# t/importer-sink.t
#
# Tests the sinks every import writes through: the live one writes, the dry-run
# one only records, and both give the job what it needs to carry on (ids to
# thread comments with, group ids that work as access mask bits).
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
use LJ::Comment;
use LJ::Entry;
use LJ::Tags;
use LJ::Test qw( temp_user );

use DW::Importer::Report;
use DW::Importer::Sink;
use DW::Importer::Sink::DryRun;
use DW::Importer::Sink::Live;

my $host = 'remote.example';

sub entry {
    my ( $key, %over ) = @_;
    return {
        key       => $key,
        subject   => "subject of $key",
        event     => "body of $key",
        security  => 'public',
        allowmask => 0,
        eventtime => '2009-03-04 05:06:07',
        logtime   => '2009-03-04 05:06:08',
        props     => {},
        %over,
    };
}

sub comment {
    my (%over) = @_;
    return {
        orig_id      => 5,
        jitemid      => 1,
        parentid     => 0,
        posterid     => 0,
        entry_source => "$host/someone/256",
        subject      => 's',
        body         => 'b',
        date         => '2009-03-06T01:00:00Z',
        state        => 'A',
        props        => {},
        %over,
    };
}

# both sinks answer everything the interface lists
{
    my @methods = qw(
        post_entry update_entry_icon insert_comment update_comment merge_tags merge_trust_groups
        save_groupmap merge_trust merge_interests merge_bio import_userpics identity_user
        save_usermap dispatch_search_copy entry_map comment_map xpost_map groupmap usermap_lookup
        precache note
    );
    foreach my $class (qw( DW::Importer::Sink::Live DW::Importer::Sink::DryRun )) {
        my @missing =
            grep { $class->can($_) == DW::Importer::Sink->can($_) } grep { $_ ne 'note' } @methods;
        is_deeply( \@missing, [], "$class implements the whole interface" );
    }
}

# the live sink writes, and remembers what it wrote
{
    my $u = temp_user();
    my $sink =
        DW::Importer::Sink::Live->new( u => $u, data => { userid => $u->id, import_data_id => 1 } );
    LJ::get_db_writer()->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) VALUES (?, 1, ?, ?, ?)',
        undef, $u->id, $host, 'someone', 'x'
    );

    my @errors;
    my ( $ok, $res ) = $sink->post_entry( entry("$host/someone/256"), errors => \@errors );
    ok( $ok, 'an entry is posted' ) or diag( $res->{errmsg} );
    is( $sink->entry_map->{"$host/someone/256"},
        $res->{itemid}, 'and is in the entry map the job reads' );
    is_deeply( [ $sink->post_entry( entry("$host/someone/256"), errors => \@errors ) ],
        [], 'posting its key again does nothing' );

    my $err = '';
    my $id  = $sink->insert_comment( comment( jitemid => $res->{itemid} ), \$err );
    ok( $id, 'a comment is inserted' ) or diag($err);
    is( $sink->comment_map->{"$host/someone/256/1280"}, $id, 'and is in the comment map' );

    $sink->merge_tags( [ { name => 'travel', display => 1 } ] );
    ok( ( grep { $_->{name} eq 'travel' } values %{ LJ::Tags::get_usertags($u) } ),
        'tags are created' );

    my $map =
        $sink->merge_trust_groups( [ { id => 4, name => 'Family', sortorder => 1, public => 0 } ] );
    $sink->save_groupmap($map);
    is_deeply( $sink->groupmap, $map, 'the group map is saved for the import' );
}

# a dry run records writes, leaves the database alone, and hands out usable ids
{
    my $u = temp_user();
    my $live =
        DW::Importer::Sink::Live->new( u => $u, data => { userid => $u->id, import_data_id => 1 } );
    my $report = DW::Importer::Report->new;
    my $sink   = DW::Importer::Sink::DryRun->new( live => $live, report => $report );
    my $before = snapshot($u);

    my @errors;
    my ( $ok, $res ) = $sink->post_entry( entry("$host/someone/256"), errors => \@errors );
    ok( $ok && $res->{itemid} > 1_000_000_000,
        'an entry is "posted" with an id that cannot be a real one' );
    is( $sink->entry_map->{"$host/someone/256"},
        $res->{itemid}, 'and is in the entry map, so jobs skip it' );
    is_deeply( [ $sink->post_entry( entry("$host/someone/256"), errors => \@errors ) ],
        [], 'posting its key again does nothing' );

    my $parent = $sink->insert_comment( comment( jitemid => $res->{itemid} ) );
    my $reply  = $sink->insert_comment(
        comment( orig_id => 6, jitemid => $res->{itemid}, parentid => $parent ) );
    ok( $parent && $reply && $parent != $reply, 'comments get distinct ids to thread with' );
    is( $sink->comment_map->{"$host/someone/256/1536"}, $reply, 'and are in the comment map' );

    $sink->merge_tags( [ { name => 'travel', display => 1 }, { name => 'travel', display => 1 } ] );
    my $map = $sink->merge_trust_groups(
        [
            { id => 4, name => 'Family', sortorder => 1, public => 0 },
            { id => 9, name => 'Work',   sortorder => 2, public => 0 }
        ]
    );
    ok(
        ( !grep { $_ < 1 || $_ > 60 } values %$map ) && $map->{4} != $map->{9},
        'groups get distinct ids that can be bits of an access mask'
    );
    is_deeply(
        $sink->merge_trust_groups( [ { id => 4, name => 'Family', sortorder => 1, public => 0 } ] ),
        { 4 => $map->{4} },
        'the same group again is the same id'
    );
    $sink->save_groupmap($map);
    is_deeply( $sink->groupmap, $map, 'later jobs of the run read the group map it saved' );

    my $oid = $sink->identity_user('http://newcomer.remote.example/');
    ok( $oid > 1_000_000_000,
        'an identity that does not exist is given an id that can not be real' );
    is( $sink->identity_user('http://newcomer.remote.example/'), $oid, 'and the same one again' );
    $sink->save_usermap( $host, 'newcomer', $oid, undef );
    is_deeply(
        [ $sink->usermap_lookup( $host, 'newcomer' ) ],
        [ $oid, undef ],
        'and is in the user map'
    );

    $sink->merge_trust( [ { userid => $oid, groupmask => 1 } ] );
    $sink->merge_interests( ['knitting'] );
    $sink->merge_bio( { bio => 'about', jabber => undef } );
    $sink->import_userpics(
        [],
        { id => 1, src => 'http://p/1.png', keywords => ['a'] },
        [
            { id => 1, src => 'http://p/1.png', keywords => ['a'] },
            { id => 2, src => 'http://p/2.png', keywords => ['b'] }
        ],
        sub { }
    );
    $sink->update_entry_icon( 5, 'happy' );
    $sink->dispatch_search_copy('importen');
    $sink->update_comment( { id => 7, props => {} } );

    is_deeply( snapshot($u), $before, 'none of it changed anything' );

    my $counts = $report->counts;
    is_deeply(
        $counts,
        {
            entry          => 1,
            comment        => 2,
            tag            => 1,
            trust_group    => 2,
            groupmap       => 1,
            identity       => 1,
            usermap        => 1,
            trust          => 1,
            interests      => 1,
            bio            => 1,
            userpic        => 2,
            entry_icon     => 1,
            search_copy    => 1,
            comment_update => 1,
        },
        'and each was recorded once, repeats not at all'
    );
    like(
        ( $report->actions_of('entry') )[0]->{summary},
        qr/^public entry "subject of remote.example\/someone\/256"/,
        'with a summary'
    );
    is( ( $report->actions_of('comment') )[1]->{record}->{parentid},
        $parent, 'and the record that would be written' );

    # the world can be shared, so the next job of a chain finds what this one wrote
    my $world = $sink->{world};
    my $next  = DW::Importer::Sink::DryRun->new(
        live   => $live,
        report => DW::Importer::Report->new,
        world  => $world
    );
    ok( $next->entry_map->{"$host/someone/256"},
        'a later job given the same world sees the entry' );
    is_deeply( $next->groupmap, $map, 'and the group map' );
}

# a dry run reads what is really there
{
    my $u = temp_user();
    my $live =
        DW::Importer::Sink::Live->new( u => $u, data => { userid => $u->id, import_data_id => 1 } );
    my ( $ok, $res ) = $live->post_entry( entry("$host/someone/256"), errors => [] );
    $live->merge_tags( [ { name => 'travel', display => 1 } ] );

    my $report = DW::Importer::Report->new;
    my $sink   = DW::Importer::Sink::DryRun->new(
        live   => DW::Importer::Sink::Live->new( u => $u, data => {} ),
        report => $report
    );

    is( $sink->entry_map->{"$host/someone/256"}, $res->{itemid}, 'entries that exist are known' );
    is_deeply( [ $sink->post_entry( entry("$host/someone/256"), errors => [] ) ],
        [], 'and are not "posted" again' );

    $sink->merge_tags( [ { name => 'travel', display => 1 }, { name => 'food', display => 0 } ] );
    is_deeply( [ map { $_->{target} } $report->actions_of('tag') ],
        ['food'], 'only the tag that is missing would be created' );
    is_deeply( [ map { $_->{target} } $report->skips ],
        ['travel'], 'and the other is reported as skipped' );

    $sink->note( skip => type => 'entry', count => 3, reason => 'already imported' );
    $sink->note( warning  => target    => 'x', text      => 'careful' );
    $sink->note( orphan   => remote_id => 4,   parent_id => 3 );
    $sink->note( unmapped => remote_id => 5,   entry_id  => 9 );
    is( scalar( () = $report->skips ), 2, 'notes of what was skipped are kept' );
    is( ( $report->warnings )[0]->{text},     'careful', 'and warnings' );
    is( ( $report->orphans )[0]->{parent_id}, 3,         'and orphans' );
    is( ( $report->unmapped )[0]->{entry_id}, 9, 'and comments on entries that are not imported' );
}

done_testing();
