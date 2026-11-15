# t/importer-dryrun-files.t
#
# A dry run must not fill the comment export cache: the real import that follows
# trusts it. This drives the production transport (with the HTTP agent stubbed)
# and checks what the cache holds, for a dry run and for a real run, and that a
# failure reaches the job's log.
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
use HTTP::Response;
use LJ::Test qw( temp_user );

use DW::Importer::Job;
use DW::Importer::LogStore;
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

# an import for a user
my $u = temp_user();
LJ::get_db_writer()->do(
'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) VALUES (?, 1, ?, ?, ?)',
    undef, $u->id, 'livejournal.com', 'someone', 'x'
);
DW::Logic::Importer->set_import_items_for_user( $u, item => [ $item, 'queued' ], id => 1 );

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
    my $logger  = DW::Importer::Logger->in_memory;
    my $outcome = DW::Importer::Job->dry_run(
        item           => $item,
        userid         => $u->id,
        import_data_id => 1,
        logger         => $logger
    );
    return ( $outcome, $logger );
}

sub live_run {
    my $job =
        Test::FakeJob->new( arg => { userid => $u->id, import_data_id => 1 }, funcname => $class );
    $class->work($job);
    return $job;
}

# a dry run fetches the export but caches nothing: a second dry run has to fetch again
{
    my ( $outcome, $logger ) = dry_run();
    is( $outcome->status, 'ok', 'the comments job of a dry run succeeds' )
        or diag( $outcome->message );
    ok( $requests >= 2, 'having fetched the export through the production transport' );
    ok( ( grep { /^Not writing cache file/ } $logger->messages ), 'it says it did not cache it' );

    my $first = $requests;
    ( $outcome, $logger ) = dry_run();
    is( $outcome->status, 'ok',       'a second dry run succeeds' );
    is( $requests,        $first * 2, 'and fetched everything again, as nothing was cached' );
    ok( !( grep { /^Using cached file/ } $logger->messages ), 'it did not use a cache' );
}

# a failure in a dry run still reaches its log
{
    $explode = 1;
    my ( $outcome, $logger ) = dry_run();
    $explode = 0;
    is( $outcome->status, 'temp_fail', 'a failure is still a failure in a dry run' );
    ok( ( grep { /^ERROR: the network went away/ } $logger->messages ),
        'its reason goes to the log' );
}

# a real run that fails is retried, and its reason is in the stored log
{
    $explode = 1;
    my $job = live_run();
    $explode = 0;
    is( $job->{state}, 'failed', 'a real run that fails is retried' );

    my ($log) = grep { $_->{item} eq $item } @{ DW::Importer::LogStore->logs_for( $u->id, 1 ) };
    ok( $log, 'it left a log' );
    my ($text) = DW::Importer::LogStore->content($log);
    like( $text, qr/ERROR: the network went away/, 'whose text has the reason' );
}

# a real run caches the export, and a dry run after it may read that cache
{
    $requests = 0;
    my $job = live_run();
    is( $job->{state}, 'completed', 'the real run completes' ) or diag( $job->{message} );
    ok( $requests >= 2, 'having fetched the two export windows' );

    my $before = $requests;
    my ( $outcome, $logger ) = dry_run();
    is( $outcome->status, 'ok',    'a dry run after it succeeds' );
    is( $requests,        $before, 'from the cache, without asking the remote again' );
    ok( ( grep { /^Using cached file/ } $logger->messages ), 'and says so' );
}

done_testing();
