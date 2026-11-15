# t/importer-items.t
#
# Tests how the items of an import move along as jobs finish: finishing an item
# makes exactly the items waiting for it ready, and a permanent failure aborts
# everything that could only have run after it.
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
use LJ::Test qw( temp_user temp_comm );

use DW::Importer::Items;
use DW::Importer::Registry;
use DW::Logic::Importer;

my $reg = 'DW::Importer::Registry';

# create an import for a user with these items, as the controller would
sub start_import {
    my ( $u, $impid, @items ) = @_;
    foreach my $name (@items) {
        my $item = $reg->item($name);
        my $err  = DW::Logic::Importer->set_import_items_for_user(
            $u,
            item => [ $name, $item->{initial_status} ],
            id   => $impid
        );
        die $err if $err;
    }
}

sub statuses {
    my ( $u, $impid ) = @_;
    my $rows =
        LJ::get_db_writer()
        ->selectall_arrayref(
        'SELECT item, status FROM import_items WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $impid );
    return { map { $_->[0] => $_->[1] } @$rows };
}

# set an item to a status as if the scheduler and a worker had got there
sub set_status {
    my ( $u, $impid, $item, $status ) = @_;
    LJ::get_db_writer()
        ->do(
        'UPDATE import_items SET status = ? WHERE userid = ? AND import_data_id = ? AND item = ?',
        undef, $status, $u->id, $impid, $item );
}

sub finish {
    my ( $u, $impid, $item ) = @_;
    set_status( $u, $impid, $item, 'succeeded' );
    return [ sort @{ DW::Importer::Items->advance( $u, $impid, $item, 'success' )->{ready} } ];
}

my @everything = map { $_->{name} } $reg->items('livejournal');

# a personal import walks the graph the workers used to encode by hand
{
    my $u = temp_user();
    start_import( $u, 1, @everything );

    is_deeply(
        statuses( $u, 1 ),
        { map { $_ => $_ eq 'lj_verify' ? 'ready' : 'init' } @everything },
        'only verify starts ready'
    );

    is_deeply(
        finish( $u, 1, 'lj_verify' ),
        [qw( lj_bio lj_friendgroups lj_tags lj_userpics )],
        'verifying readies bio, userpics, friend groups and tags'
    );
    is_deeply( finish( $u, 1, 'lj_tags' ), [], 'for a person, tags readies nothing' );
    is( statuses( $u, 1 )->{lj_entries}, 'init', 'so entries are still waiting' );

    is_deeply(
        finish( $u, 1, 'lj_friendgroups' ),
        [qw( lj_entries lj_friends )],
        'friend groups ready friends and entries'
    );
    is_deeply( finish( $u, 1, 'lj_bio' ),      [],              'bio readies nothing' );
    is_deeply( finish( $u, 1, 'lj_userpics' ), [],              'nor do userpics' );
    is_deeply( finish( $u, 1, 'lj_friends' ),  [],              'nor do friends' );
    is_deeply( finish( $u, 1, 'lj_entries' ),  ['lj_comments'], 'entries ready comments' );

    is_deeply( statuses( $u, 1 )->{lj_comments}, 'ready', 'and they are marked ready' );

    # nothing that is already past waiting is touched again
    is_deeply( finish( $u, 1, 'lj_verify' ), [], 'finishing again readies nothing new' );
}

# a community has no friend groups: tags are what entries wait for
{
    my $c = temp_comm();
    start_import( $c, 1, qw( lj_verify lj_bio lj_userpics lj_tags lj_entries lj_comments ) );

    is_deeply(
        finish( $c, 1, 'lj_verify' ),
        [qw( lj_bio lj_tags lj_userpics )],
        'a community import readies the same first group, minus friend groups'
    );
    is( statuses( $c, 1 )->{lj_entries}, 'init', 'entries are not ready yet' );
    is_deeply( finish( $c, 1, 'lj_tags' ),    ['lj_entries'],  'tags ready entries' );
    is_deeply( finish( $c, 1, 'lj_entries' ), ['lj_comments'], 'and entries ready comments' );
}

# an import only moves its own items
{
    my $u = temp_user();
    start_import( $u, 1, qw( lj_verify lj_bio ) );
    start_import( $u, 2, qw( lj_verify lj_bio ) );

    is_deeply( finish( $u, 1, 'lj_verify' ), ['lj_bio'], 'import 1 moves on' );
    is( statuses( $u, 2 )->{lj_bio}, 'init', 'import 2 is untouched' );

    my $other = temp_user();
    start_import( $other, 1, qw( lj_verify lj_bio ) );
    is( statuses( $other, 1 )->{lj_bio}, 'init', "another user's import 1 is untouched" );
}

# a permanent failure aborts what could only have run afterwards
{
    my $u = temp_user();
    start_import( $u, 1, @everything );
    finish( $u, 1, 'lj_verify' );
    set_status( $u, 1, 'lj_bio',      'queued' );
    set_status( $u, 1, 'lj_userpics', 'succeeded' );

    set_status( $u, 1, 'lj_friendgroups', 'failed' );
    my $res = DW::Importer::Items->advance( $u, 1, 'lj_friendgroups', 'failure' );

    is_deeply(
        [ sort @{ $res->{aborted} } ],
        [qw( lj_comments lj_entries lj_friends )],
        'friends, entries and, through them, comments are aborted'
    );
    my $s = statuses( $u, 1 );
    is( $s->{$_},     'aborted', "$_ is aborted" ) foreach qw( lj_friends lj_entries lj_comments );
    is( $s->{lj_bio}, 'queued',  'a queued sibling is left alone' );
    is( $s->{lj_userpics}, 'succeeded', 'a finished sibling is left alone' );
    is( $s->{lj_tags},     'ready',     'a ready sibling is left alone' );
}

# verify failing (a bad password, say) takes the whole import with it
{
    my $u = temp_user();
    start_import( $u, 1, @everything );
    set_status( $u, 1, 'lj_verify', 'failed' );
    DW::Importer::Items->advance( $u, 1, 'lj_verify', 'failure' );

    is_deeply(
        statuses( $u, 1 ),
        { map { $_ => $_ eq 'lj_verify' ? 'failed' : 'aborted' } @everything },
        'everything else is aborted'
    );
}

# an item can wait for several others, and for ones that are not part of the import
{
    $reg->register_source( name => 'chain', kind => 'file' );
    $reg->register_item(
        name           => 'c_a',
        source         => 'chain',
        class          => 'Chain::A',
        typeid         => 9301,
        initial_status => 'ready'
    );
    $reg->register_item(
        name           => 'c_b',
        source         => 'chain',
        class          => 'Chain::B',
        typeid         => 9302,
        initial_status => 'ready'
    );
    $reg->register_item(
        name       => 'c_both',
        source     => 'chain',
        class      => 'Chain::Both',
        typeid     => 9303,
        depends_on => [ 'c_a', 'c_b' ]
    );
    $reg->register_item(
        name       => 'c_absent',
        source     => 'chain',
        class      => 'Chain::Absent',
        typeid     => 9304,
        depends_on => [ 'c_a', 'c_not_selected' ]
    );
    $reg->register_item(
        name   => 'c_not_selected',
        source => 'chain',
        class  => 'Chain::NotSelected',
        typeid => 9305
    );

    my $u = temp_user();
    start_import( $u, 1, qw( c_a c_b c_both c_absent ) );

    is_deeply( finish( $u, 1, 'c_a' ),
        ['c_absent'], 'an item waiting only for absent items and a finished one is ready' );
    is( statuses( $u, 1 )->{c_both},
        'init', 'an item waiting for two keeps waiting for the second' );
    is_deeply( finish( $u, 1, 'c_b' ), ['c_both'], 'and starts when the second finishes' );

    my $v = temp_user();
    start_import( $v, 1, qw( c_a c_b c_both ) );
    set_status( $v, 1, 'c_a', 'failed' );
    DW::Importer::Items->advance( $v, 1, 'c_a', 'failure' );
    is( statuses( $v, 1 )->{c_both}, 'aborted', 'failure of either dependency aborts it' );

    $reg->unregister_source('chain');
}

done_testing();
