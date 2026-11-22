# t/importer-local-entries.t
#
# Characterizes Local::Entries::post_event, the writer the importers use to
# create an entry from normalized data: idempotency by key, provenance,
# the backdating rule and the stored logtime.
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
use LJ::Entry;
use LJ::Test qw( temp_user temp_comm );
use DW::Worker::ContentImporter::Local::Entries;

my $class = 'DW::Worker::ContentImporter::Local::Entries';

sub evt {
    my ( $key, %over ) = @_;
    return {
        key       => $key,
        subject   => "importer test $key",
        event     => "body for $key",
        security  => 'public',
        allowmask => 0,
        eventtime => '2009-03-04 05:06:07',
        logtime   => '2009-03-04 05:06:08',
        props     => {},
        %over,
    };
}

sub row_count {
    my ($u) = @_;
    return $u->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid = ?', undef, $u->id );
}

my $u = temp_user();

# personal journal: backdated, keyed, logtime preserved
{
    my %map;
    my @errors;
    my ( $ok, $res ) =
        $class->post_event( {}, \%map, $u, undef, evt('example.com/user/256'), \@errors );

    ok( $ok, 'post_event succeeds' ) or diag( $res->{errmsg} );
    is( $map{'example.com/user/256'}, $res->{itemid}, 'the key is recorded in the caller map' );
    is( scalar @errors, 0, 'no item errors' );

    my $entry = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    is( $entry->prop('import_source'), 'example.com/user/256', 'import_source stores the key' );
    ok( $entry->prop('opt_backdated'), 'imports into a personal journal are backdated' );

    my $logtime =
        $u->selectrow_array( 'SELECT logtime FROM log2 WHERE journalid = ? AND jitemid = ?',
        undef, $u->id, $res->{itemid} );
    is( $logtime, '2009-03-04 05:06:08', 'logtime is overwritten with the remote value' );
    is(
        $entry->eventtime_mysql,
        '2009-03-04 05:06:00',
        'eventtime comes from the event, at minute precision (postevent has no seconds)'
    );
}

# the same key never posts a second entry
{
    my %map;
    my @errors;
    my $before = row_count($u);

    my ( $ok1, $res1 ) =
        $class->post_event( {}, \%map, $u, undef, evt('example.com/user/512'), \@errors );
    ok( $ok1, 'first post succeeds' );
    is( row_count($u), $before + 1, 'one entry created' );

    my @second = $class->post_event( {}, \%map, $u, undef, evt('example.com/user/512'), \@errors );
    is( scalar @second, 0,           'a key already in the map returns nothing' );
    is( row_count($u),  $before + 1, 'no second entry was created' );

    # the map is the only guard: a fresh map for the same key posts again, which is why the
    # importers load get_entry_map before posting
    my $map = $class->get_entry_map($u);
    is( $map->{'example.com/user/512'},
        $res1->{itemid}, 'get_entry_map reads back import_source keys' );
}

# posting as a user into a community is not backdated
{
    my $comm   = temp_comm();
    my $poster = temp_user();
    my %map;
    my @errors;

    my ( $ok, $res ) =
        $class->post_event( {}, \%map, $comm, $poster, evt('example.com/comm/768'), \@errors );
    ok( $ok, 'posting into a community as another user succeeds' ) or diag( $res->{errmsg} );

    my $entry = LJ::Entry->new( $comm, jitemid => $res->{itemid} );
    is( $entry->poster->userid,  $poster->userid, 'the entry is attributed to the poster' );
    is( $entry->journal->userid, $comm->userid,   'and lives in the community' );
    ok( !$entry->prop('opt_backdated'), 'community imports are not backdated' );
    is( $entry->prop('import_source'), 'example.com/comm/768', 'import_source is stored' );
}

# a source-supplied import_source prop cannot override the key
{
    my %map;
    my @errors;
    my ( $ok, $res ) = $class->post_event( {}, \%map, $u, undef,
        evt( 'example.com/user/1024', props => { import_source => 'forged/1' } ), \@errors );
    ok( $ok, 'post succeeds' );
    is(
        LJ::Entry->new( $u, jitemid => $res->{itemid} )->prop('import_source'),
        'example.com/user/1024',
        'the key wins over a prop of the same name'
    );
}

# protocol failures are reported to the caller rather than thrown
{
    my %map;
    my @errors;
    my ( $ok, $res ) = $class->post_event( {}, \%map, $u, undef,
        evt( 'example.com/user/2048', event => '' ), \@errors );
    ok( !$ok, 'an invalid event does not post' );
    is( scalar @errors, 1, 'the failure is added to the item errors' );
    like( $errors[0], qr/^Failed to post:/, 'with the protocol error' );
    ok( !exists $map{'example.com/user/2048'}, 'and the key is not recorded' );
}

done_testing();
