# t/tags-deleted-trust-group.t
#
# Test that deleting an access filter keeps the tag counts of the entries that
# were shared with it (#2934).
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Protocol;
use LJ::S2;
use LJ::Test qw( temp_user );

my $u      = temp_user();
my $viewer = temp_user();

my $one   = $u->create_trust_group( groupname => 'one' );
my $two   = $u->create_trust_group( groupname => 'two' );
my $sixty = $u->create_trust_group( groupname => 'sixty', id => 60 );
is_deeply( [ $one, $two, $sixty ], [ 1, 2, 60 ], 'created three access filters' );

# the viewer is only in filter two
$u->add_edge( $viewer, trust => { mask => 1 | ( 1 << $two ), nonotify => 1 } );

my $posted = 0;

sub post {
    my ( $tags, %sec ) = @_;
    my $journal = delete $sec{journal} // $u;
    $posted++;
    my $err = 0;
    my $res = LJ::Protocol::do_request(
        'postevent',
        {
            ver      => $LJ::PROTOCOL_VER,
            username => $journal->user,
            tz       => 'guess',
            event    => "entry $posted",
            props    => { taglist => $tags },
            %sec,
        },
        \$err,
        { noauth => 1 }
    );
    is( $err, 0, "posted entry tagged '$tags'" );
    return $res->{itemid};
}

sub usemask { return ( security => 'usemask', allowmask => $_[0] ) }

my $only_one = post( 'solo', usemask( 1 << $one ) );
post( 'solo, shared', usemask( ( 1 << $one ) | ( 1 << $two ) ) );
post( 'shared',       usemask( ( 1 << $one ) | ( 1 << $sixty ) ) );
post( 'solo',   security => 'private' );
post( 'shared', security => 'public' );
post( 'shared', usemask( 1 << $two ) );

sub fresh_tags {
    my $journal = shift // $u;
    LJ::start_request();
    LJ::MemCache::delete( [ $journal->id, "tags:" . $journal->id ] );
    my $tags = LJ::Tags::get_usertags($journal);
    return { map { $tags->{$_}->{name} => { %{ $tags->{$_} }, kwid => $_ } } keys %$tags };
}

# tag counts as the owner and as other viewers see them on the tags page
sub shown_count {
    my ( $tag, $remote ) = @_;
    my $t = fresh_tags()->{$tag};    # starts a new request, so set the remote after
    LJ::set_remote($remote);
    my $ctx = LJ::S2::tag_viewer_context($u);
    LJ::set_remote(undef);
    return LJ::S2::TagDetail( $u, $t->{kwid}, $t, $ctx )->{use_count};
}

# the summary counts should always match the entries' actual security
sub check_summary {
    my ($name) = @_;
    my %expected;
    my $rows = $u->selectall_arrayref(
        q{SELECT t.kwid, l.security, l.allowmask FROM logtags t, log2 l
          WHERE t.journalid = ? AND l.journalid = t.journalid AND l.jitemid = t.jitemid},
        undef, $u->id
    );
    foreach my $row (@$rows) {
        my ( $kwid, $security, $allowmask ) = @$row;
        $expected{ "$kwid:" . LJ::Tags::get_security_level( $security, $allowmask ) }++;
    }

    my $sums =
        $u->selectall_arrayref( q{SELECT kwid, security, entryct FROM logkwsum WHERE journalid = ?},
        undef, $u->id );
    my %actual = map { ( "$_->[0]:$_->[1]" => $_->[2] ) } @$sums;

    is_deeply( \%actual, \%expected, "$name: tag summary matches the entries" );
}

# the reported case: a journal whose only filtered entries use one filter
my $simple = temp_user();
my $only   = $simple->create_trust_group( groupname => 'only' );
post( 'diary', journal => $simple, usemask( 1 << $only ) );
post( 'diary', journal => $simple, usemask( 1 << $only ) );
post( 'diary', journal => $simple, security => 'public' );
is( fresh_tags($simple)->{diary}->{uses}, 3, 'diary is used three times' );
ok( $simple->delete_trust_group( id => $only ), 'deleted the only filter' );
is( fresh_tags($simple)->{diary}->{uses}, 3, 'diary is still used three times' );
is_deeply(
    fresh_tags($simple)->{diary}->{security},
    { public => 1, private => 2, protected => 0, groups => {} },
    'entries only shared with the deleted filter are still counted, as private'
);

my $tags = fresh_tags();
is( $tags->{solo}->{uses},   3, 'solo is used three times' );
is( $tags->{shared}->{uses}, 4, 'shared is used four times' );
check_summary('before deleting a filter');

ok( $u->delete_trust_group( id => $one ), 'deleted filter one' );

$tags = fresh_tags();
is( $tags->{solo}->{uses}, 3, 'solo is still used three times' );
is_deeply(
    $tags->{solo}->{security},
    { public => 0, private => 2, protected => 0, groups => { $two => 1 } },
    'solo entries only shared with filter one are now counted as private'
);
is( $tags->{shared}->{uses}, 4, 'shared is still used four times' );
is_deeply(
    $tags->{shared}->{security},
    { public => 1, private => 0, protected => 0, groups => { $two => 2, $sixty => 1 } },
    'shared entries keep their remaining filters'
);
check_summary('after deleting filter one');

is( shown_count( 'solo',   $u ),      3, 'owner still sees three solo entries' );
is( shown_count( 'solo',   $viewer ), 1, 'filter two member sees one solo entry' );
is( shown_count( 'solo',   undef ),   0, 'logged-out viewer sees no solo entries' );
is( shown_count( 'shared', $viewer ), 3, 'filter two member sees three shared entries' );
is( shown_count( 'shared', undef ),   1, 'logged-out viewer sees one shared entry' );

ok( $u->delete_trust_group( id => $sixty ), 'deleted filter sixty' );

$tags = fresh_tags();
is( $tags->{shared}->{uses}, 4, 'shared is still used four times after deleting filter sixty' );
is_deeply(
    $tags->{shared}->{security},
    { public => 1, private => 1, protected => 0, groups => { $two => 2 } },
    'shared entry only left with filter sixty is now counted as private'
);
check_summary('after deleting filter sixty');

# editing an entry afterwards should move its count, not add a second one
my $err = 0;
LJ::Protocol::do_request(
    'editevent',
    {
        ver      => $LJ::PROTOCOL_VER,
        username => $u->user,
        itemid   => $only_one,
        event    => 'now public',
        security => 'public',
        props    => { taglist => 'solo' },
    },
    \$err,
    { noauth => 1 }
);
is( $err, 0, 'made the first entry public' );

$tags = fresh_tags();
is( $tags->{solo}->{uses}, 3, 'solo is still used three times after the edit' );
is_deeply(
    $tags->{solo}->{security},
    { public => 1, private => 1, protected => 0, groups => { $two => 1 } },
    'edited entry moved from private to public'
);
check_summary('after editing an entry');
is( shown_count( 'solo', undef ), 1, 'logged-out viewer now sees one solo entry' );

ok( $u->delete_trust_group( id => $two ), 'deleted filter two' );
is_deeply(
    fresh_tags()->{solo}->{security},
    { public => 1, private => 2, protected => 0, groups => {} },
    'deleting the last filter leaves only public and private counts'
);
check_summary('after deleting filter two');

done_testing();
