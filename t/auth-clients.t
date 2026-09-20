#!/usr/bin/perl
#
# t/auth-clients.t
#
# Regression tests for crossposting and backup API-key clients.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use LJ::Test qw(temp_user);
use DW::API::Key;
use DW::Auth::TOTP;
use DW::Auth::Challenge;
use DW::External::XPostProtocol::LJXMLRPC;
use LJ::Protocol;
use Digest::MD5 qw(md5_hex);
use File::Temp qw(tempfile);
use Plack::Test::Server;
use IPC::Open3;
use Symbol qw(gensym);
use GDBM_File;

local $LJ::ADMIN_EMAIL = 'test@example.invalid';
my $u = temp_user();
$u->update_self( { status => 'A' } );
$u->set_password('client-password');
DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
my $key      = DW::API::Key->new_for_user($u);
my $protocol = DW::External::XPostProtocol::LJXMLRPC->new;
no warnings 'redefine';
ok( $protocol->uses_api_key('https://www.dreamwidth.org/interface/xmlrpc'),
    'Dreamwidth uses API keys' );
ok( !$protocol->uses_api_key('https://www.livejournal.com/interface/xmlrpc'),
    'Other hosts retain legacy auth' );
ok(
    !$protocol->do_auth( undef,
        { ljsession => 'old', auth_challenge => 'old', auth_response => 'old' }, 1 )->{success},
    'Old browser session or one-use response cannot replace an API key'
);
{
    my @methods;
    my @challenges;
    local *DW::External::XPostProtocol::LJXMLRPC::_call_xmlrpc = sub {
        my ( $self, $client, $mode, $req ) = @_;
        push @methods, $mode;
        return { success => 1, result => { challenge => DW::Auth::Challenge->generate } }
            if $mode eq 'getchallenge';
        die 'API key must not mint browser cookies' if $mode eq 'sessiongenerate';
        my ( $error, %flags );
        ok(
            LJ::Protocol::authenticate( $req, \$error, \%flags ),
            "Crossposter authenticates $mode with API key"
        );
        push @challenges, $req->{auth_challenge};
        return { success => 1, result => {} };
    };
    my $auth = {
        username           => $u->user,
        encrypted_password => md5_hex( $key->hash ),
        auth_challenge     => 'stale',
        auth_response      => 'stale',
        ljsession          => 'obsolete'
    };
    for my $mode (qw(getfriendgroups postevent editevent)) {
        ok(
            $protocol->call_xmlrpc( 'https://www.dreamwidth.org/interface/xmlrpc',
                $mode, {}, $auth )->{success},
            "$mode uses API authentication despite stale session data"
        );
    }
    is( scalar @challenges, 3, 'Every operation has a challenge' );
    isnt( $challenges[0], $challenges[1], 'Second operation uses a fresh challenge' );
    isnt( $challenges[1], $challenges[2], 'Third operation uses a fresh challenge' );
    is_deeply(
        \@methods,
        [qw(getchallenge getfriendgroups getchallenge postevent getchallenge editevent)],
        'Crossposting never calls sessiongenerate for Dreamwidth'
    );
}
{
    my @methods;
    local *DW::External::XPostProtocol::LJXMLRPC::_call_xmlrpc = sub {
        push @methods, $_[2];
        return { success => 1, result => { ljsession => 'legacy-session' } };
    };
    my $auth = $protocol->do_auth( undef,
        { username => 'legacy', auth_challenge => 'challenge', auth_response => 'response' }, 0 );
    is( $auth->{ljsession}, 'legacy-session',
        'Other services retain their existing session authentication' );
    is_deeply( \@methods, ['sessiongenerate'], 'Legacy authentication flow remains available' );
}

{
    require DW::Controller::Interface::S2;
    no warnings 'once';
    local *DW::Request::HTTP_UNAUTHORIZED = sub { 401 };
    local *DW::Request::OK                = sub { 0 };
    my $response = '';
    my $status;
    local *DW::Request::get         = sub { bless {}, 'DW::Request' };
    local *DW::Request::method      = sub { 'GET' };
    local *DW::Request::status_line = sub { $status = $_[1] };
    local *DW::Request::print       = sub { $response .= $_[1] };
    local *LJ::S2::load_layer       = sub { { userid => $u->id } };
    local *DW::Auth::authenticate   = sub { undef };
    DW::Controller::Interface::S2::interface_handler( {}, 123 );
    like( $status, qr/^401/, 'Unauthenticated S2 request is rejected' );
    like( $response, qr/username and API key/, 'S2 failure explains API-key authentication' );
    unlike( $response, qr/username and password/, 'S2 does not suggest obsolete password login' );
}

# Persisted pre-upgrade password digests must never masquerade as API keys.
{
    require DW::External::Account;
    for my $host ( 'www.dreamwidth.org', 'www.livejournal.com' ) {
        my $account = DW::External::Account->create(
            $u,
            {
                siteid      => 0,
                username    => 'crosspost',
                password    => 'saved-credential',
                servicename => $host,
                servicetype => 'lj',
                serviceurl  => "https://$host/interface/xmlrpc",
                options     => {},
            }
        );
        $account = DW::External::Account->get_external_account( $u, $account->acctid );
        is( $account->password, md5_hex('saved-credential'), 'New saved credential is usable' );
        $u->do(
            'UPDATE externalaccount SET options=? WHERE userid=? AND acctid=?',
            undef, DW::External::Account->xpost_hash_to_string( {} ),
            $u->id, $account->acctid
        );
        $account->_remove_from_memcache( $account->_memcache_id );
        $account = DW::External::Account->get_external_account( $u, $account->acctid );
        if ( $host eq 'www.livejournal.com' ) {
            ok( !$account->needs_api_key_upgrade, 'Other hosts need no credential migration' );
            is( $account->password, md5_hex('saved-credential'),
                'Other hosts keep saved password' );
            next;
        }
        ok( $account->needs_api_key_upgrade, 'Old Dreamwidth credential requires replacement' );
        is( $account->password, '', 'Old password digest is unavailable to editors and workers' );
        $account->set_options( { _credential_type => 'api_key', comments => 'disable' } );
        ok( $account->needs_api_key_upgrade, 'Protocol options cannot reclassify old credentials' );
        my $entry = $u->t_post_fake_entry;
        local *DW::External::XPostProtocol::LJXMLRPC::crosspost = sub {
            is(
                $_[2]->{encrypted_password},
                md5_hex( $key->hash ),
                'One-off API key overrides obsolete saved password'
            );
            return { success => 0, error => 'test transport', code => 'test' };
        };
        $account->crosspost( { password => $key->hash }, $entry );
        $account->set_password('saved-credential');
        ok( !$account->needs_api_key_upgrade,
            'Explicit replacement marks even an unchanged digest' );
        is(
            $account->password,
            md5_hex('saved-credential'),
            'In-memory saved credential is hashed'
        );
        $account->set_password( $key->hash );
        $account->set_options( { comments => 'enable' } );
        $account = DW::External::Account->get_external_account( $u, $account->acctid );
        is(
            $account->password,
            md5_hex( $key->hash ),
            'Saved API key survives options update and reload'
        );
        ok( !$account->needs_api_key_upgrade, 'Reload retains credential type' );
        $account->set_password('');
        is( $account->password, '', 'Clearing credential removes saved key' );
        ok( !$account->options->{_credential_type}, 'Clearing key removes its type marker' );
    }
}

# Run the shipped backup CLI against a real local HTTP server and MFA account.
my $entry = $u->t_post_fake_entry(
    subject  => 'API backup regression',
    body     => 'Private backup body',
    security => 'private'
);
$entry->t_enter_comment( u => $u, body => 'Private backup comment' );
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless $app;
my ( $trace, $trace_path ) = tempfile();
close $trace;
my $server = Plack::Test::Server->new(
    sub {
        my ($env) = @_;
        my $method = $env->{PATH_INFO};
        if ( $env->{PATH_INFO} eq '/interface/xmlrpc' ) {
            my $body = '';
            $env->{'psgi.input'}->read( $body, $env->{CONTENT_LENGTH} );
            ($method) = $body =~ m{<methodName>([^<]+)</methodName>};
            open my $input, '<', \$body;
            $env->{'psgi.input'} = $input;
        }
        open my $fh, '>>', $trace_path or die $!;
        print $fh "$env->{REQUEST_METHOD} $method\n";
        close $fh;
        return $app->($env);
    }
);
my $backup = "$ENV{HOME}/" . $u->user . '.jbak';
BAIL_OUT('Refusing to overwrite an existing backup') if -e $backup;

# Seed a prior sync date: the legacy server's zero-date default is rejected by
# strict MySQL, independently of authentication. Exercise an incremental backup.
{
    my %seed;
    tie %seed, 'GDBM_File', $backup, &GDBM_NEWDB, 0600 or die $!;
    $seed{'event:lastsync'} = '2000-01-01 00:00:00';
    $seed{'event:lastgrab'} = '2000-01-01 00:00:00';
    untie %seed;
}
my $stderr = gensym;
my $pid    = open3(
    undef,                                 my $stdout,
    $stderr,                               $^X,
    "$ENV{LJHOME}/src/jbackup/jbackup.pl", '--sync',
    '--quiet',                             '--protocol=http',
    '--server=127.0.0.1',                  '--port=' . $server->port,
    '--user=' . $u->user,                  '--api-key=' . $key->hash
);
my ( $output, $errors );
{
    local $SIG{ALRM} = sub { kill 'KILL', $pid; die 'Backup client timeout' };
    alarm 60;
    $output = do { local $/; <$stdout> };
    $errors = do { local $/; <$stderr> };
    waitpid( $pid, 0 );
    alarm 0;
}
is( $?, 0, 'jbackup completes API-key entry and comment backup' ) or diag($errors);
if ( -e $backup ) {
    my %saved;
    tie %saved, 'GDBM_File', $backup, &GDBM_READER, 0600 or die $!;
    ok(
        grep( /Private backup body/, values %saved ),
        'Backup contains authenticated private entry'
    ) or diag( $output, $errors );
    ok( grep( /Private backup comment/, values %saved ), 'Backup includes authenticated comments' );
    untie %saved;
    unlink $backup;
}
open my $fh, '<', $trace_path or die $!;
my $requests = do { local $/; <$fh> };
close $fh;
unlink $trace_path;
unlike( $requests, qr/sessiongenerate/, 'Backup never requests a browser session' );
like(
    $requests,
    qr{POST /export_comments\.bml},
    'Backup posts challenge credentials to comment export'
);
done_testing();
