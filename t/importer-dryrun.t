# t/importer-dryrun.t
#
# Runs a whole LiveJournal import, from a canned site, three ways: as a dry run
# (which must change nothing and say what it would do), for real (which must do
# exactly what the dry run said), and again (which must find everything already
# there, for real and as a dry run).
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use lib "$ENV{LJHOME}/t/lib";
use DW::Test::Importer qw( snapshot );
use DW::Test::Importer::Site;
use HTTP::Response;
use LJ::Comment;
use LJ::Entry;
use LJ::Test qw( temp_user );

use DW::External::Account;
use DW::External::Site;
use DW::Importer::Job;
use DW::Importer::Registry;
use DW::Logic::Importer;
use DW::Worker::ContentImporter::LiveJournal::Entries;
use DW::Worker::ContentImporter::Local::Comments;
use DW::Worker::ContentImporter::Local::Entries;

my $host = 'livejournal.com';
my $site = DW::Test::Importer::Site->new;

# OpenID accounts and the remote user map outlive a test run, so clear out what an earlier one left
my @identities = map { "http://$_.$host/" } qw( pal alice ext-9 );

sub forget_remote_users {
    my $dbh = LJ::get_db_writer();
    $dbh->do( q{DELETE FROM identitymap WHERE idtype = 'O' AND identity = ?}, undef, $_ )
        foreach @identities;
    $dbh->do(
        q{DELETE FROM import_usermap WHERE hostname = ? AND username IN ('pal', 'alice', 'ext_9')},
        undef, $host
    );
}
forget_remote_users();
END { forget_remote_users() }

# the account the import is into, and the one entry of it that was crossposted to the site
my $u   = temp_user();
my $dbh = LJ::get_db_writer();
$dbh->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) VALUES (?, 1, ?, ?, ?)',
    undef, $u->id, $host, 'someone', 'x'
);
my @chain = map { $_->{name} } DW::Importer::Registry->items('livejournal');
foreach my $name (@chain) {
    my $err = DW::Logic::Importer->set_import_items_for_user(
        $u,
        item => [ $name, DW::Importer::Registry->item($name)->{initial_status} ],
        id   => 1
    );
    die $err if $err;
}

my $ext = DW::External::Account->create(
    $u,
    {
        siteid         => DW::External::Site->get_site( site => $host )->{siteid},
        username       => 'someone',
        password       => 'x',
        xpostbydefault => 0,
        recordlink     => 0,
        options        => {},
    }
);
my $xposted = $u->t_post_fake_entry( subject => 'crossposted' );
LJ::set_logprop( $u, $xposted->jitemid,
    { xpost => DW::External::Account->xpost_hash_to_string( { $ext->acctid => 6 } ) } );

# the icons are fetched by the real userpic code, from a stubbed user agent
{

    package Test::IconUA;
    sub new { return bless {}, shift }

    sub get {
        my ( $self, $url ) = @_;
        my ($file) = $url =~ m{icons\.example/(.+)$}
            or return HTTP::Response->new( 404, 'Not Found' );
        open my $fh, '<:raw', "$ENV{LJHOME}/t/data/userpics/$file"
            or return HTTP::Response->new( 404, 'Not Found' );
        local $/;
        my $r = HTTP::Response->new( 200, 'OK' );
        $r->content( scalar <$fh> );
        return $r;
    }
}
{
    no warnings 'redefine';
    *LJ::get_useragent = sub { return Test::IconUA->new };
}

my %dry = ( userid => $u->id, import_data_id => 1, transport => $site );

# (a) a dry run says what it would do, and does none of it ---------------------------------------
# memcache is watched too: a dry run may read through it but must put nothing in it
my $fake_memcache = LJ::Test::FakeMemCache->new;
my $real_memcache = LJ::MemCache::get_memcache();
local @LJ::MEMCACHE_SERVERS = ('fake');

sub dry_run_chain_watching_memcache {
    my (%args) = @_;
    LJ::MemCache::set_memcache($fake_memcache);
    my $report = eval { DW::Importer::Job->dry_run_chain(%args) };
    my $error  = $@;
    LJ::MemCache::set_memcache($real_memcache);
    die $error if $error;
    return $report;
}

my $before = snapshot($u);
my $report = dry_run_chain_watching_memcache(%dry);
is_deeply( snapshot($u), $before,
    'a dry run changes nothing: not one row of what an import writes' );
is_deeply( [ sort keys %{ $fake_memcache->{data} } ], [], 'and puts nothing in memcache' );

is_deeply(
    [ map { $_->{outcome}->status } $report->outcomes ],
    [ ('ok') x scalar @chain ],
    'every job of the dry run succeeded'
) or diag( $report->as_text );

my $counts = $report->counts;
is( $counts->{entry},       5, 'five entries would be posted' );
is( $counts->{comment},     6, 'six comments would be posted' );
is( $counts->{tag},         2, 'two tags' );
is( $counts->{trust_group}, 1, 'one trust group' );
is( $counts->{userpic},     2, 'two icons' );
ok( $counts->{identity} >= 3, 'OpenID accounts would be made for who is not here yet' );
ok( $counts->{bio} && $counts->{interests} && $counts->{trust},
    'the bio, interests and friends too' );

my %entry = map { $_->{target} => $_->{record} } $report->actions_of('entry');
is_deeply(
    [ sort keys %entry ],
    [
        sort map { "$host/someone/" . ( $_->{itemid} * 256 + $_->{anum} ) }
            @{ $site->data->{events} }[ 0 .. 4 ]
    ],
    'the entries are keyed as always'
);

my %security = map { ( $_->{subject} => $_ ) } values %entry;
is( $security{'A public entry'}->{security},  'public',  'public stays public' );
is( $security{'A private entry'}->{security}, 'private', 'private stays private' );
is( $security{'Friends only'}->{security},    'usemask', 'friends only stays limited' );
is( $security{'Friends only'}->{allowmask},   1,         'to friends' );
is( $security{'Family only'}->{security},     'usemask', 'a group-locked entry stays limited' );
my $family = ( $report->actions_of('trust_group') )[0]->{record}->{local_id};
is( $security{'Family only'}->{allowmask}, 1 << $family, 'to the group it was mapped to' );
is( $security{'A group that is gone'}->{security},
    'private', 'an entry locked to a group that is gone is private' );
is( $security{'A group that is gone'}->{allowmask}, 0, 'with no mask' );
ok( ( grep { $_->{text} eq 'Could not determine groups to post to.' } $report->warnings ),
    'and the user would be told' );
ok( !$entry{ "$host/someone/" . ( 6 * 256 + 17 ) }, 'the crossposted entry is not posted back' );
ok(
    ( grep { $_->{type} eq 'entry' && $_->{count} } $report->skips ),
    'and is counted among the entries that are not fetched'
);

my @comments = $report->actions_of('comment');
my %comment  = map { ( $_->{record}->{orig_id} => $_->{record} ) } @comments;
is_deeply(
    [ sort { $a <=> $b } keys %comment ],
    [ 1, 2, 3, 4, 5, 8 ],
    'six comments would be posted'
);
is( $comment{2}->{parentid}, $comment{1}->{local_id}, 'a reply is threaded under its parent' );
is( $comment{4}->{parentid}, $comment{2}->{local_id}, 'and so is one under a reply' );
is( $comment{2}->{state},    'S',                     'a screened comment stays screened' );
is( $comment{3}->{state},    'D',                     'and a deleted one deleted' );
is( $comment{5}->{posterid}, 0,                       'an anonymous comment stays anonymous' );
like(
    $comment{8}->{entry_source},
    qr/^CROSSPOSTER livejournal\.com someone 6 $/,
    'a comment on the crosspost is keyed from the crosspost'
);
is_deeply( [ map { $_->{remote_id} } $report->orphans ],
    [6], 'the reply to a comment we do not have is an orphan' );
is_deeply( [ map { $_->{remote_id} } $report->unmapped ],
    [7], 'the comment on an entry we do not have is reported' );

like( $report->as_text, qr/Would write:\n.*entry\s+5/s, 'the report reads as text' );

# (b) a real run does exactly what the dry run said -----------------------------------------------
sub fake_job {
    my ($class) = @_;
    return DW::Test::Importer::Job->new(
        arg      => { userid => $u->id, import_data_id => 1 },
        funcname => $class
    );
}
{

    package DW::Test::Importer::Job;
    sub new { my ( $class, %a ) = @_; return bless { state => 'untouched', %a }, $class }
    sub arg               { $_[0]->{arg} }
    sub failures          { 0 }
    sub funcname          { $_[0]->{funcname} }
    sub debug             { }
    sub grabbed_until     { }
    sub save              { }
    sub run_after         { }
    sub declined          { }
    sub completed         { $_[0]->{state} = 'completed' }
    sub failed            { $_[0]->{state} = 'failed'; $_[0]->{message} = $_[1] }
    sub permanent_failure { $_[0]->{state} = 'permanent_failure'; $_[0]->{message} = $_[1] }
}

sub run_for_real {
    my @states;
    local $DW::Importer::Job::TRANSPORT = $site;
    foreach my $name (@chain) {
        my $class = DW::Importer::Registry->item($name)->{class};
        my $job   = fake_job($class);
        $class->work($job);
        push @states, "$name: $job->{state}" . ( $job->{message} ? " ($job->{message})" : '' );
    }
    return @states;
}

my @states = run_for_real();
is_deeply( [ grep { !/: completed$/ } @states ], [], 'every job of the real run completed' )
    or diag("@states");

$u = LJ::load_userid( $u->id, 'force' );
my $entry_map = DW::Worker::ContentImporter::Local::Entries->get_entry_map($u);
is_deeply(
    [ sort grep { m{^\Q$host\E/someone/} } keys %$entry_map ],
    [ sort keys %entry ],
    'the entries it posted are the ones the dry run listed'
);

foreach my $key ( sort keys %entry ) {
    my $e = LJ::Entry->new( $u, jitemid => $entry_map->{$key} );
    my ( $dry_security, $dry_mask ) = ( $entry{$key}->{security}, $entry{$key}->{allowmask} );
    is(
        $e->security,
        $dry_security eq 'usemask' ? 'usemask' : $dry_security,
        "$key has the security the dry run said"
    );
    is( $e->allowmask, $dry_mask, "$key has the access mask the dry run said" )
        if $dry_security eq 'usemask';
    is( $e->subject_raw, $entry{$key}->{subject}, "$key has its subject" );
}

my $comment_map = DW::Worker::ContentImporter::Local::Comments->get_comment_map($u);
is_deeply(
    [ sort keys %$comment_map ],
    [ sort map { $_->{target} } @comments ],
    'the comments are the ones the dry run listed'
);

my %by_id = reverse %$comment_map;
foreach my $c (@comments) {
    my $rec = $c->{record};
    my $row = LJ::Comment->instance( $u, jtalkid => $comment_map->{ $c->{target} } );
    is( $row->state, $rec->{state}, "comment $rec->{orig_id} has the state the dry run said" );
    my $parent       = $row->parent;
    my $parent_key   = $parent ? $by_id{ $parent->jtalkid } : undef;
    my ($dry_parent) = grep { $_->{record}->{local_id} == ( $rec->{parentid} || -1 ) } @comments;
    is(
        $parent_key,
        $dry_parent ? $dry_parent->{target} : undef,
        "comment $rec->{orig_id} is under the comment the dry run said"
    );
}
is(
    $u->selectrow_array(
        'SELECT COUNT(*) FROM talk2 WHERE journalid = ? AND nodeid = 0',
        undef, $u->id
    ),
    0,
    'and no comment is attached to entry 0'
);

my $groups = $u->trust_groups;
is( scalar keys %$groups, 1,       'one trust group was made' );
is( ( keys %$groups )[0], $family, 'with the id the dry run said' );
is( scalar( () = grep { $_->{name} } values %{ LJ::Tags::get_usertags($u) } ), 2, 'and two tags' );

# (c) a second real run, and a dry run after it, find it all there --------------------------------
my @content     = grep { !/import_status|import_items_state/ } sort keys %{ snapshot($u) };
my $after_first = snapshot($u);
@states = run_for_real();
my $after_second = snapshot($u);
is_deeply( [ grep { !/: completed$/ } @states ], [], 'the second run completes' )
    or diag("@states");
is_deeply(
    { map { $_ => $after_second->{$_} } @content },
    { map { $_ => $after_first->{$_} } @content },
    'and adds nothing: no new entries, comments, tags, groups, accounts or icons'
);

my $again =
    dry_run_chain_watching_memcache( %dry, items => [ grep { $_ ne 'lj_userpics' } @chain ] );
$counts = $again->counts;
is( $counts->{entry}       // 0, 0, 'a dry run after it would post no entry' );
is( $counts->{comment}     // 0, 0, 'no comment' );
is( $counts->{tag}         // 0, 0, 'no tag' );
is( $counts->{trust_group} // 0, 0, 'no group' );
is( $counts->{identity}    // 0, 0, 'no account' );
my $skipped = 0;
$skipped += $_->{count} // 1 foreach grep { $_->{type} eq 'entry' } $again->skips;
ok( $skipped >= 5, 'and reports the entries as already imported' ) or diag( $again->as_text );
ok( ( grep { $_->{type} eq 'comment' } $again->skips ), 'and the comments' );
ok( ( grep { $_->{type} eq 'tag' } $again->skips ),     'and the tags' );

done_testing();
