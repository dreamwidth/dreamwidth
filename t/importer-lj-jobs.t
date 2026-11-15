# t/importer-lj-jobs.t
#
# Runs the LiveJournal entries and comments jobs from end to end against a
# canned remote site: what gets posted, what the jobs hand on to each other,
# and how they fail.
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
use HTTP::Response;
use LJ::Comment;
use LJ::Test qw( temp_user );
use Storable qw( thaw );

use DW::Importer::Job;
use DW::Logic::Importer;
use DW::Worker::ContentImporter::LiveJournal::Comments;
use DW::Worker::ContentImporter::LiveJournal::Entries;
use DW::Worker::ContentImporter::Local::Comments;
use DW::Worker::ContentImporter::Local::Entries;

my $entries_class  = 'DW::Worker::ContentImporter::LiveJournal::Entries';
my $comments_class = 'DW::Worker::ContentImporter::LiveJournal::Comments';
my $host           = 'livejournal.com';

# the remote site's profile pages are never found, so commenters become guessed OpenID users
{

    package Test::NotFoundUA;
    sub new { return bless {}, shift }
    sub get { return HTTP::Response->new( 404, 'Not Found' ) }
}
{
    no warnings 'redefine';
    *LJ::get_useragent = sub { return Test::NotFoundUA->new };
}

{

    package Test::FakeJob;
    sub new { my ( $class, %args ) = @_; return bless { state => 'untouched', %args }, $class }
    sub arg               { $_[0]->{arg} }
    sub failures          { 0 }
    sub funcname          { $_[0]->{funcname} }
    sub debug             { }
    sub grabbed_until     { }
    sub save              { }
    sub completed         { $_[0]->{state} = 'completed' }
    sub failed            { $_[0]->{state} = 'failed'; $_[0]->{message} = $_[1] }
    sub permanent_failure { $_[0]->{state} = 'permanent_failure'; $_[0]->{message} = $_[1] }
}

# the remote: journal entries 1 and 2 (itemid 1 has anum 7, so its key id is 1*256+7)
my @remote_events = (
    {
        itemid    => 1,
        anum      => 7,
        subject   => 'first',
        event     => 'hello from <lj user="friend">',
        security  => 'public',
        allowmask => 0,
        eventtime => '2009-03-04 05:06:07',
        logtime   => '2009-03-04 05:06:08',
        props     => {},
    },
    {
        itemid    => 2,
        anum      => 9,
        subject   => 'second',
        event     => 'more',
        security  => 'public',
        allowmask => 0,
        eventtime => '2009-03-05 05:06:07',
        logtime   => '2009-03-05 05:06:08',
        props     => {},
    },
);

my $xmlrpc_fault;    # set to make the remote fail
my @xmlrpc_calls;

# comments: 1 and 2 are on imported entries (2 replies to 1), 3 is on an entry that wasn't
my $meta_xml = q{<?xml version="1.0" encoding="utf-8"?>
<livejournal>
<maxid>3</maxid>
<comments>
<comment id="1" posterid="10" state="A"/>
<comment id="2" posterid="10" state="A"/>
<comment id="3" posterid="10" state="A"/>
</comments>
<usermaps><usermap id="10" user="commenter"/></usermaps>
</livejournal>};

my $body_xml = q{<?xml version="1.0" encoding="utf-8"?>
<livejournal>
<comments>
<comment id="1" jitemid="1" parentid="0"><body>top level</body><subject>one</subject><date>2009-03-06T01:00:00Z</date></comment>
<comment id="2" jitemid="1" parentid="1"><body>a reply</body><subject>two</subject><date>2009-03-06T02:00:00Z</date></comment>
<comment id="3" jitemid="99" parentid="0"><body>nowhere to go</body><subject>three</subject><date>2009-03-06T03:00:00Z</date></comment>
</comments>
</livejournal>};

# the remote site, which the jobs are given in place of the network
{

    package Test::Remote;
    sub new { return bless {}, shift }

    sub xmlrpc {
        my ( $self, $mode, $hash ) = @_;
        push @xmlrpc_calls, $hash->{selecttype} // $mode;
        return $self->{answer}->( $mode, $hash ) if $self->{answer};

        return { fault => 1, faultString => $xmlrpc_fault } if $xmlrpc_fault;
        return { events => [ $remote_events[1] ] } if $hash->{selecttype} eq 'lastn';

        my %wanted = map { $_ => 1 } split /,/, $hash->{itemids};
        return { events => [ grep { $wanted{ $_->{itemid} } } @remote_events ] };
    }

    sub comment_export { return $_[1] eq 'comment_meta' ? $meta_xml : $body_xml }

    # profile pages (the comments job looks up the journal's FOAF); a missing page is
    # handled as best effort
    sub get { return HTTP::Response->new( 404, 'Not Found' ) }
}
my $remote = Test::Remote->new;
$DW::Importer::Job::TRANSPORT = $remote;

my $u   = temp_user();
my $dbh = LJ::get_db_writer();
$dbh->do(
    'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) '
        . 'VALUES (?, 1, ?, ?, ?)',
    undef, $u->id, $host, 'someone', 'x'
);
foreach my $name (qw( lj_entries lj_comments )) {
    DW::Logic::Importer->set_import_items_for_user( $u, item => [ $name, 'init' ], id => 1 );
}
$dbh->do( "UPDATE import_items SET status = 'queued' WHERE userid = ? AND item = 'lj_entries'",
    undef, $u->id );

sub run_job {
    my ($class) = @_;
    my $job = Test::FakeJob->new(
        arg      => { userid => $u->id, import_data_id => 1 },
        funcname => $class
    );
    DW::Importer::Job->reset_exit_request;
    $class->work($job);
    return $job;
}

sub status_of {
    my ($item) = @_;
    return $dbh->selectrow_array(
        'SELECT status FROM import_items WHERE userid = ? AND import_data_id = 1 AND item = ?',
        undef, $u->id, $item );
}

sub events {
    my $rows = $u->selectall_arrayref(
        'SELECT status FROM import_status WHERE userid = ? ORDER BY import_status_id',
        undef, $u->id );
    return map { thaw( $_->[0] ) } @$rows;
}

# the remote failing while we ask for the newest entry is retried
{
    $xmlrpc_fault = 'Server is busy';
    my $job = run_job($entries_class);
    $xmlrpc_fault = undef;

    is( $job->{state}, 'failed', 'a remote error is a temporary failure' );
    is( $job->{message}, 'XMLRPC failure: Server is busy', 'with the remote\'s message' );
    is( status_of('lj_entries'),  'queued', 'the item stays queued for the retry' );
    is( status_of('lj_comments'), 'init',   'comments keep waiting' );
    ok( DW::Importer::Job->exit_requested, 'the entries worker asks to be replaced even so' );
    is_deeply( [ keys %{ DW::Worker::ContentImporter::Local::Entries->get_entry_map($u) } ],
        [], 'nothing was posted' );
}

# the remote failing part way through is too
{
    my $calls  = 0;
    my $normal = Test::Remote->new;
    local $remote->{answer} = sub {
        return $_[0] eq 'getevents' && ++$calls == 1
            ? $normal->xmlrpc(@_)
            : { fault => 1, faultString => 'Gone away' };
    };
    my $job = run_job($entries_class);
    is( $job->{state}, 'failed', 'a failure while fetching entries is a temporary failure' );
    is( $job->{message}, 'XMLRPC failure: Gone away', 'with the remote\'s message' );
    is( status_of('lj_comments'), 'init', 'comments keep waiting' );
}

# a successful run posts the entries and releases comments
{
    @xmlrpc_calls = ();
    my $job = run_job($entries_class);
    is( $job->{state}, 'completed', 'the entries job completes' ) or diag( $job->{message} );

    my $map = DW::Worker::ContentImporter::Local::Entries->get_entry_map($u);
    is_deeply(
        [ sort keys %$map ],
        [ "$host/someone/" . ( 1 * 256 + 7 ), "$host/someone/" . ( 2 * 256 + 9 ) ],
        'each remote entry is keyed by site, user and remote id'
    );

    my $first = LJ::Entry->new( $u, jitemid => $map->{"$host/someone/263"} );
    is( $first->subject_raw, 'first', 'the subject is kept' );
    is(
        $first->event_raw,
        'hello from <user site="livejournal.com" user="friend">',
        '<lj user> is rewritten to point at the remote site'
    );
    ok( $first->prop('opt_backdated'), 'entries are backdated into a personal journal' );

    is( status_of('lj_entries'),  'succeeded', 'the item succeeded' );
    is( status_of('lj_comments'), 'ready',     'comments are ready to run' );
    ok( DW::Importer::Job->exit_requested, 'the worker asks to be replaced' );

    my @events = grep { $_->{type} ne 'temp_fail' } events();
    is( scalar @events,     1,    'one notification, besides the retries' );
    is( $events[0]->{type}, 'ok', 'that entries were imported' );
}

# running it again finds everything already there
{
    my $before = scalar keys %{ DW::Worker::ContentImporter::Local::Entries->get_entry_map($u) };
    $dbh->do( "UPDATE import_items SET status = 'queued' WHERE userid = ? AND item = 'lj_entries'",
        undef, $u->id );
    my $job = run_job($entries_class);
    is( $job->{state}, 'completed', 'a repeat run completes' );
    is( scalar keys %{ DW::Worker::ContentImporter::Local::Entries->get_entry_map($u) },
        $before, 'and posts nothing new' );
}

# comments: threaded under their entries, and skipped if their entry isn't there
{
    $dbh->do( "UPDATE import_items SET status = 'queued' WHERE userid = ? AND item = 'lj_comments'",
        undef, $u->id );
    my $job = run_job($comments_class);
    is( $job->{state}, 'completed', 'the comments job completes' ) or diag( $job->{message} );

    my $map = DW::Worker::ContentImporter::Local::Comments->get_comment_map($u);
    is( scalar keys %$map, 2, 'two comments were imported' );

    my $entry_key = "$host/someone/263";
    my $top       = $map->{ "$entry_key/" . ( 1 << 8 ) };
    my $reply     = $map->{ "$entry_key/" . ( 2 << 8 ) };
    ok( $top && $reply, 'each is keyed by its entry and remote comment id' );
    is( LJ::Comment->instance( $u, jtalkid => $reply )->parent->jtalkid,
        $top, 'the reply is threaded' );

    my $on_nothing =
        $u->selectrow_array( 'SELECT COUNT(*) FROM talk2 WHERE journalid = ? AND nodeid = 0',
        undef, $u->id );
    is( $on_nothing, 0, 'nothing was posted against entry 0' );

    my ($status) = grep { $_->{type} eq 'status' } events();
    like( $status->{text}, qr/^1 comments were not imported/, 'the user is told one was skipped' );
    is( status_of('lj_comments'), 'succeeded', 'the item succeeded' );
}

done_testing();
