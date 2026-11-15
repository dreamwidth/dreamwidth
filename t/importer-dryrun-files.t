# t/importer-dryrun-files.t
#
# A dry run must not write files either: the comment export cache it would fill
# is trusted by the real import that follows, and the failure note is for real
# failures. This drives the production transport (with the HTTP agent stubbed)
# and checks what lands on disk, for a dry run and for a real run.
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
use File::Find;
use File::Path qw( make_path );
use File::Temp qw( tempdir );
use HTTP::Response;
use LJ::Test qw( temp_user );

use DW::Importer::Job;
use DW::Importer::Logger;
use DW::Importer::Registry;
use DW::Importer::Source::LiveJournal::Transport;
use DW::Logic::Importer;
use DW::Worker::ContentImporter::LiveJournal::Comments;

my $item  = 'lj_comments';
my $class = DW::Importer::Registry->item($item)->{class};

sub slurp {
    open my $fh, '<', "$ENV{LJHOME}/t/data/importer/$_[0]" or die $!;
    local $/;
    return scalar <$fh>;
}
my %export =
    ( comment_meta => slurp('comments-meta.xml'), comment_body => slurp('comments-body.xml') );

# the remote's HTTP side, through the production transport: the export is served by a stubbed
# agent, and the profile pages the identity lookups ask for are not found
my ( $requests, $explode ) = ( 0, 0 );
{
    no warnings qw( redefine once );
    *DW::Importer::Source::LiveJournal::Transport::session = sub { 'session' };
    *LWP::UserAgent::request                               = sub {
        my ( $self, $request ) = @_;
        $requests++;
        die "the network went away\n" if $explode;
        my ($mode) = $request->uri =~ /get=(comment_\w+)/;
        my $r = HTTP::Response->new( 200, 'OK' );
        $r->content( $export{$mode} );
        return $r;
    };
    *LJ::get_useragent = sub {
        return bless {}, 'Test::NotFound';
    };
    *Test::NotFound::get = sub { HTTP::Response->new( 404, 'Not Found' ) };
}

# an import for a user, with a scratch directory standing in for $LJ::HOME/logs
my $u = temp_user();
LJ::get_db_writer()->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) VALUES (?, 1, ?, ?, ?)',
    undef, $u->id, 'livejournal.com', 'someone', 'x'
);
DW::Logic::Importer->set_import_items_for_user( $u, item => [ $item, 'queued' ], id => 1 );

my $home = tempdir( CLEANUP => 1 );
make_path( "$home/logs/imports/" . $u->id );

sub files {
    my @found;
    find( { wanted => sub { push @found, $File::Find::name if -f }, no_chdir => 1 }, $home );
    return map { s/^\Q$home\E\///r } sort @found;
}

{

    package Test::FakeJob;
    sub new { my ( $c, %a ) = @_; return bless { state => 'untouched', %a }, $c }
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

sub dry_run {
    my $logger = DW::Importer::Logger->in_memory;
    local $LJ::HOME = $home;
    my $outcome = DW::Importer::Job->dry_run(
        item           => $item,
        userid         => $u->id,
        import_data_id => 1,
        logger         => $logger
    );
    return ( $outcome, $logger );
}

sub live_run {
    local $LJ::HOME = $home;
    my $job =
        Test::FakeJob->new( arg => { userid => $u->id, import_data_id => 1 }, funcname => $class );
    $class->work($job);
    return $job;
}

# a dry run fetches the export but leaves no cache file behind
{
    my ( $outcome, $logger ) = dry_run();
    is( $outcome->status, 'ok', 'the comments job of a dry run succeeds' )
        or diag( $outcome->message );
    ok( $requests >= 2, 'having fetched the export through the production transport' );
    is_deeply( [ files() ], [], 'and wrote no file' );
    ok( ( grep { /^Not writing cache file/ } $logger->messages ), 'it says it did not' );
}

# a failure in a dry run leaves no failure note
{
    $explode = 1;
    my ( $outcome, $logger ) = dry_run();
    $explode = 0;
    is( $outcome->status, 'temp_fail', 'a failure is still a failure in a dry run' );
    is_deeply( [ files() ], [], 'but writes no .failure file' );
    ok( ( grep { /^FAILURE: the network went away/ } $logger->messages ),
        'its reason goes to the log' );
}

# a real run caches the export and keeps failure notes
{
    $requests = 0;
    my $job = live_run();
    is( $job->{state}, 'completed', 'the real run completes' ) or diag( $job->{message} );
    my @cached = grep { m{/[0-9a-f]{32}\.xml$} } files();
    is( scalar @cached, 2, 'and caches the two export windows' );

    # a dry run after it may read the cache, and still writes nothing
    my $before = $requests;
    my ($outcome) = dry_run();
    is( $outcome->status, 'ok',    'a dry run after it succeeds' );
    is( $requests,        $before, 'from the cache, without asking the remote again' );
    is( scalar( () = grep { m{\.xml$} } files() ), 2, 'and adds no file' );

    unlink map { "$home/$_" } @cached;
    $explode = 1;
    $job     = live_run();
    $explode = 0;
    is( $job->{state}, 'failed', 'a real run that fails is retried' );
    ok( ( grep { m{\.lj_comments\.\d+\.failure$} } files() ), 'and leaves its failure note' );
}

done_testing();
