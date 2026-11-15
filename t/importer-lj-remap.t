# t/importer-lj-remap.t
#
# Characterizes the pieces the LiveJournal importer reuses when mapping remote
# data onto a local account: trust group and tag merging, remote-to-local
# groupmask translation and <lj user> markup rewriting.
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
use LJ::Tags;
use LJ::Test qw( temp_user );
use Storable qw( nfreeze );

use DW::Importer::Context;
use DW::Worker::ContentImporter::LiveJournal;
use DW::Worker::ContentImporter::Local::Tags;
use DW::Worker::ContentImporter::Local::TrustGroups;

my $lj = 'DW::Worker::ContentImporter::LiveJournal';

# trust groups: matched by name, so a repeated import updates instead of duplicating
{
    my $u      = temp_user();
    my $groups = 'DW::Worker::ContentImporter::Local::TrustGroups';

    my $map1 = $groups->merge_trust_groups(
        $u,
        [
            { id => 3, name => 'Family',   sortorder => 10, public => 1 },
            { id => 9, name => 'Coworker', sortorder => 20, public => 0 },
        ]
    );
    is( scalar keys %$map1, 2, 'both remote groups are mapped' );
    ok( $map1->{3} && $map1->{9} && $map1->{3} != $map1->{9}, 'to distinct local ids' );

    my $cur = $u->trust_groups;
    is( scalar keys %$cur,                 2,        'two local groups exist' );
    is( $cur->{ $map1->{3} }->{groupname}, 'Family', 'the group carries the remote name' );
    ok( $cur->{ $map1->{3} }->{is_public},  'and its visibility' );
    ok( !$cur->{ $map1->{9} }->{is_public}, 'including private groups' );

    # same names, different remote ids and an edited sort order
    my $map2 = $groups->merge_trust_groups(
        $u,
        [
            { id => 1, name => 'Family',  sortorder => 15, public => 1 },
            { id => 2, name => 'Reading', sortorder => 30, public => 0 },
        ]
    );
    is( $map2->{1}, $map1->{3}, 'an existing local group is reused when the name matches' );
    ok( $map2->{2} && $map2->{2} != $map1->{3} && $map2->{2} != $map1->{9},
        'a new name gets a new local id' );
    $cur = $u->trust_groups;
    is( scalar keys %$cur,                 3,  'only the unmatched name created a group' );
    is( $cur->{ $map1->{3} }->{sortorder}, 15, 'the matched group was updated' );

    is_deeply( $groups->merge_trust_groups( $u, undef ), {}, 'no remote groups map to nothing' );
}

# tags: created once, with display names
{
    my $u    = temp_user();
    my $tags = 'DW::Worker::ContentImporter::Local::Tags';

    $tags->merge_tags( $u,
        [ { name => 'books', display => 1 }, { name => 'tv shows', display => 0 } ] );
    $tags->merge_tags( $u, [ { name => 'books', display => 1 } ] );
    $tags->merge_tags( $u, undef );

    my %names = map { $_->{name} => $_ } values %{ LJ::Tags::get_usertags($u) || {} };
    is_deeply(
        [ sort keys %names ],
        [ 'books', 'tv shows' ],
        'each tag exists once, repeat merges add nothing'
    );
    ok( $names{books}->{display},       'display flag is kept' );
    ok( !$names{'tv shows'}->{display}, 'including when off' );
}

# groupmask: remote group bits are rewritten through the groupmap saved by the friend groups job
{
    my $u     = temp_user();
    my $dbh   = LJ::get_db_writer();
    my $impid = 1;
    $dbh->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5, groupmap) '
            . 'VALUES (?, ?, ?, ?, ?, ?)',
        undef, $u->id, $impid, 'remote.example', 'someone', 'x', nfreeze( { 1 => 3, 2 => 5 } )
    );
    die $dbh->errstr if $dbh->err;
    my $data = { userid => $u->id, import_data_id => $impid };

    # the map is read once per job and kept in its context, so each call here is a new job
    sub remap {
        my ( $data, $mask ) = @_;
        return $lj->remap_groupmask( DW::Importer::Context->new( data => $data ), $mask );
    }

    is( remap( $data, 0 ), 0,      'no access stays no access' );
    is( remap( $data, 1 ), 1,      'the trust bit is carried over unchanged' );
    is( remap( $data, 2 ), 1 << 3, 'remote group 1 becomes local group 3' );
    is( remap( $data, 4 ), 1 << 5, 'remote group 2 becomes local group 5' );
    is(
        remap( $data, 1 | 2 | 4 ),
        1 | ( 1 << 3 ) | ( 1 << 5 ),
        'masks with several groups map each bit'
    );
    is( remap( $data, 8 ),     0,      'a group missing from the map grants nothing' );
    is( remap( $data, 1 | 8 ), 1,      'a missing group is dropped but the trust bit stays' );
    is( remap( $data, 2 | 8 ), 1 << 3, 'known groups survive next to an unknown one' );

    # with no groupmap at all (the friend groups job did not run) only trust survives
    $dbh->do( 'UPDATE import_data SET groupmap = NULL WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $impid );
    is( remap( $data, 1 | 2 ), 1, 'without a groupmap, group bits are lost and trust remains' );
    is( remap( $data, 2 ),     0, 'and a group-only mask grants nothing' );
}

done_testing();
