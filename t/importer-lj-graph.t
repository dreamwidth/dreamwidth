# t/importer-lj-graph.t
#
# Runs the small LiveJournal jobs (verify, friend groups, tags) against a canned
# remote site to check that an import moves from one job to the next the way it
# always has: through the real workers, for a person and for a community.
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
use File::Path qw( remove_tree );
use LJ::Tags;
use LJ::Test qw( temp_user temp_comm );
use Storable qw( thaw );

use DW::Importer::Job;
use DW::Importer::Registry;
use DW::Logic::Importer;
use DW::Worker::ContentImporter::LiveJournal::FriendGroups;
use DW::Worker::ContentImporter::LiveJournal::Tags;
use DW::Worker::ContentImporter::LiveJournal::Verify;

my $reg = 'DW::Importer::Registry';
my $lj  = 'DW::Worker::ContentImporter::LiveJournal';

# the remote site: what each XML-RPC mode answers, or a fault. The jobs are given it as their
# transport, in place of the network.
my %remote;
{

    package Test::Remote;
    sub new { return bless {}, shift }

    sub xmlrpc {
        my ( $self, $mode ) = @_;
        my $answer = $remote{$mode};
        return $answer->() if ref $answer eq 'CODE';
        return $answer || { fault => 1, faultString => "no canned answer for $mode" };
    }
}
$DW::Importer::Job::TRANSPORT = Test::Remote->new;

{

    package Test::FakeJob;
    sub new { my ( $class, %args ) = @_; return bless { state => 'untouched', %args }, $class }
    sub arg               { $_[0]->{arg} }
    sub failures          { 0 }
    sub funcname          { $_[0]->{funcname} }
    sub debug             { }
    sub completed         { $_[0]->{state} = 'completed' }
    sub failed            { $_[0]->{state} = 'failed'; $_[0]->{message} = $_[1] }
    sub permanent_failure { $_[0]->{state} = 'permanent_failure'; $_[0]->{message} = $_[1] }
}

# the import as the confirm page would create it, with the verify job already queued
my @importing;
END { remove_tree( "$LJ::HOME/logs/imports/" . $_->id ) foreach @importing }

sub start_import {
    my ( $u, @items ) = @_;
    push @importing, $u;
    my $uj = $u->is_community ? $u->user : undef;
    LJ::get_db_writer()->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, usejournal, password_md5) '
            . 'VALUES (?, 1, ?, ?, ?, ?)',
        undef, $u->id, 'livejournal.com', 'someone', $uj, 'x'
    );
    foreach my $name (@items) {
        DW::Logic::Importer->set_import_items_for_user(
            $u,
            item => [ $name, $reg->item($name)->{initial_status} ],
            id   => 1
        );
    }
    set_status( $u, 'lj_verify', 'queued' );
}

sub set_status {
    my ( $u, $item, $status ) = @_;
    LJ::get_db_writer()
        ->do(
        'UPDATE import_items SET status = ? WHERE userid = ? AND import_data_id = 1 AND item = ?',
        undef, $status, $u->id, $item );
}

sub statuses {
    my ($u) = @_;
    my $rows =
        LJ::get_db_writer()
        ->selectall_arrayref(
        'SELECT item, status FROM import_items WHERE userid = ? AND import_data_id = 1',
        undef, $u->id );
    return { map { $_->[0] => $_->[1] } @$rows };
}

sub run_item {
    my ( $u, $item ) = @_;
    my $class = $reg->item($item)->{class};
    my $job   = Test::FakeJob->new(
        arg      => { userid => $u->id, import_data_id => 1 },
        funcname => $class
    );
    set_status( $u, $item, 'queued' );    # as the scheduler leaves it
    $class->work($job);
    return $job;
}

sub events {
    my ($u) = @_;
    my $rows = $u->selectall_arrayref(
        'SELECT status FROM import_status WHERE userid = ? ORDER BY import_status_id',
        undef, $u->id );
    return map { thaw( $_->[0] ) } @$rows;
}

my @person_items = map { $_->{name} } $reg->items('livejournal');

# a person: verify releases the first group, friend groups release friends and entries
{
    my $u = temp_user();
    start_import( $u, @person_items );

    %remote = ( getusertags => { tags => [] } );
    my $job = run_item( $u, 'lj_verify' );
    is( $job->{state},             'completed', 'verify completes' );
    is( scalar( () = events($u) ), 0,           'without telling the user' );
    my %s = %{ statuses($u) };
    is( $s{$_}, 'ready', "$_ is ready" ) foreach qw( lj_bio lj_userpics lj_friendgroups lj_tags );
    is( $s{$_}, 'init', "$_ is still waiting" ) foreach qw( lj_friends lj_entries lj_comments );

    %remote = (
        getusertags => { tags => [ { name => 'travel', display => 1 } ] },
        getfriends =>
            { friendgroups => [ { id => 3, name => 'Family', sortorder => 1, public => 0 } ] },
    );
    run_item( $u, 'lj_tags' );
    is( statuses($u)->{lj_entries}, 'init', "a person's entries do not wait for tags" );
    ok( ( grep { $_->{name} eq 'travel' } values %{ LJ::Tags::get_usertags($u) } ),
        'the tags were imported' );

    $job = run_item( $u, 'lj_friendgroups' );
    is( $job->{state},              'completed', 'friend groups completes' );
    is( statuses($u)->{lj_friends}, 'ready',     'friends are ready' );
    is( statuses($u)->{lj_entries}, 'ready',     'and entries' );

    my $map = thaw(
        LJ::get_db_writer()->selectrow_array(
            'SELECT groupmap FROM import_data WHERE userid = ? AND import_data_id = 1',
            undef, $u->id
        )
    );
    is( scalar keys %$map, 1, 'the friend group map was saved for the entries job' );
    ok( exists $map->{3}, 'keyed by the remote group id' );
}

# a rejected password ends the import at the start
{
    my $u = temp_user();
    start_import( $u, @person_items );

    %remote = ( getusertags => { fault => 1, faultString => 'Invalid password' } );
    my $job = run_item( $u, 'lj_verify' );
    is( $job->{state}, 'permanent_failure', 'a rejected password is permanent' );
    like( $job->{message}, qr/rejected by livejournal.com/, 'and says so' );
    is_deeply(
        statuses($u),
        { map { $_ => $_ eq 'lj_verify' ? 'failed' : 'aborted' } @person_items },
        'the rest of the import is aborted'
    );
}

# a community has no friend groups: tags release its entries
{
    my $c     = temp_comm();
    my @items = qw( lj_verify lj_bio lj_userpics lj_tags lj_entries lj_comments );
    start_import( $c, @items );

    %remote = (
        getusertags    => { tags    => [] },
        consolecommand => { results => [ { output => [ ['success'] ] } ] },
    );
    my $job = run_item( $c, 'lj_verify' );
    is( $job->{state},              'completed', 'verify completes for a community' );
    is( statuses($c)->{lj_tags},    'ready',     'tags are ready' );
    is( statuses($c)->{lj_entries}, 'init',      'entries wait for them' );

    run_item( $c, 'lj_tags' );
    is( statuses($c)->{lj_entries},  'ready', "tags release a community's entries" );
    is( statuses($c)->{lj_comments}, 'init',  'and comments wait for the entries' );
}

# not being an admin of the remote community stops the import too
{
    my $c = temp_comm();
    start_import( $c, qw( lj_verify lj_tags lj_entries ) );

    %remote = (
        getusertags    => { tags    => [] },
        consolecommand => { results => [ { output => [ ['error'] ] } ] },
    );
    my $job = run_item( $c, 'lj_verify' );
    is( $job->{state}, 'permanent_failure', 'not being a maintainer is permanent' );
    is( statuses($c)->{lj_entries}, 'aborted', 'and nothing that depended on verifying runs' );
}

done_testing();
