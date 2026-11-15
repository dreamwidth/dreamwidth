# t/importer-registry.t
#
# Tests the importer registry: the contracts stored outside the code, what a
# user's choices expand to, and that the dependency rules can't leave an import
# stuck.
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
use DW::Importer::Registry;

my $reg = 'DW::Importer::Registry';

# item names, worker classes and typeids are stored in import_items, queued TheSchwartz jobs
# and notifications, so existing ones must keep their values
{
    my %expected = (
        lj_entries      => [ 0, 'Entries' ],
        lj_tags         => [ 1, 'Tags' ],
        lj_bio          => [ 2, 'Bio' ],
        lj_comments     => [ 3, 'Comments' ],
        lj_friends      => [ 4, 'Friends' ],
        lj_friendgroups => [ 5, 'FriendGroups' ],
        lj_userpics     => [ 6, 'Userpics' ],
        lj_verify       => [ 7, 'Verify' ],
    );
    foreach my $name ( sort keys %expected ) {
        my ( $typeid, $suffix ) = @{ $expected{$name} };
        my $item = $reg->item($name);
        is( $item->{typeid}, $typeid, "$name keeps typeid $typeid" );
        is(
            $item->{class},
            "DW::Worker::ContentImporter::LiveJournal::$suffix",
            "$name is still run by the $suffix worker class"
        );
        is( $reg->item_for_typeid($typeid)->{name}, $name, "typeid $typeid maps back to $name" );
        is( $reg->item_for_class( $item->{class} )->{name}, $name, "$suffix maps back to $name" );
    }
    is( scalar( () = $reg->items('livejournal') ), 8, 'and there are no other livejournal items' );
}

# which items follow from what the user ticked
{
    my @comments_person = $reg->expand_selection( 'livejournal', ['lj_comments'], 'person' );
    is_deeply(
        \@comments_person,
        [qw( lj_verify lj_tags lj_friendgroups lj_entries lj_comments )],
        'comments bring entries, which bring tags and friend groups, and every import verifies'
    );

    is_deeply(
        [ $reg->expand_selection( 'livejournal', ['lj_comments'], 'community' ) ],
        [qw( lj_verify lj_tags lj_entries lj_comments )],
        'communities have no friend groups'
    );

    is_deeply( [ $reg->expand_selection( 'livejournal', ['lj_friends'], 'community' ) ],
        ['lj_verify'], 'items that make no sense for a community are dropped' );

    is_deeply(
        [ $reg->expand_selection( 'livejournal', ['lj_entries_remap_icon'], 'person' ) ],
        [qw( lj_verify lj_tags lj_friendgroups lj_entries )],
        'an option selects the item it belongs to'
    );

    is_deeply( [ $reg->expand_selection( 'livejournal', [ 'lj_bio', 'not_an_item' ], 'person' ) ],
        [qw( lj_verify lj_bio )], 'unknown names are ignored' );
}

# what the browser is told to apply must be the rules the server applies
is_deeply(
    $reg->dependency_map('livejournal'),
    {
        lj_friends            => ['lj_friendgroups'],
        lj_entries            => [ 'lj_tags', 'lj_friendgroups' ],
        lj_entries_remap_icon => ['lj_entries'],
        lj_comments           => ['lj_entries'],
    },
    'the choose-data page gets the same implications'
);

# an item that waits for something its selection does not import would wait forever
is_deeply( [ $reg->validate ], [], 'the registered items are consistent' );

{
    $reg->register_source( name => 'broken', kind => 'file' );
    $reg->register_item(
        name   => 'b_one',
        source => 'broken',
        class  => 'Broken::One',
        typeid => 9101
    );
    $reg->register_item(
        name       => 'b_two',
        source     => 'broken',
        class      => 'Broken::Two',
        typeid     => 9102,
        depends_on => ['b_one']
    );
    $reg->register_item(
        name       => 'b_loop_a',
        source     => 'broken',
        class      => 'Broken::LoopA',
        typeid     => 9103,
        depends_on => ['b_loop_b'],
        implies    => ['b_loop_b'],
    );
    $reg->register_item(
        name       => 'b_loop_b',
        source     => 'broken',
        class      => 'Broken::LoopB',
        typeid     => 9104,
        depends_on => ['b_loop_a'],
        implies    => ['b_loop_a'],
    );
    $reg->register_item(
        name       => 'b_ghost',
        source     => 'broken',
        class      => 'Broken::Ghost',
        typeid     => 9105,
        depends_on => ['nobody'],
    );

    my @problems = $reg->validate;
    like(
        "@problems",
        qr/b_two depends on b_one, which is not imported with it/,
        'a dependency that is not implied is reported'
    );
    like( "@problems", qr/b_loop_a has a circular dependency/, 'a dependency circle is reported' );
    like(
        "@problems",
        qr/b_ghost refers to unknown items: nobody/,
        'an unknown dependency is reported'
    );

    $reg->unregister_source('broken');
    is_deeply( [ $reg->validate ], [], 'unregistering removes the source and its items' );
    ok( !$reg->item('b_one') && !$reg->item_for_typeid(9101), 'including lookups' );
}

# a class or typeid can't be registered twice, since both are stored elsewhere
{
    $reg->register_source( name => 'dupe', kind => 'file' );
    ok(
        !eval {
            $reg->register_item( name => 'x', source => 'dupe', class => 'X', typeid => 7 );
            1;
        },
        'typeid 7 is taken'
    );
    ok(
        !eval {
            $reg->register_item(
                name   => 'y',
                source => 'dupe',
                class  => 'DW::Worker::ContentImporter::LiveJournal::Bio',
                typeid => 9201
            );
            1;
        },
        'the Bio worker class is taken'
    );
    $reg->unregister_source('dupe');
}

# which worker process runs what
{
    my %want = (
        'content-importer'      => [qw( Bio Comments Entries FriendGroups Friends Tags Userpics )],
        'content-importer-lite' => [qw( Bio FriendGroups Friends Tags Userpics )],
        'content-importer-verify' => ['Verify'],
    );
    foreach my $process ( sort keys %want ) {
        my @got = sort map { s/^.*:://r } $reg->classes_for_process($process);
        is_deeply( \@got, $want{$process}, "$process runs the expected workers" );
    }
}

done_testing();
