#!/usr/bin/perl
# Regression coverage for native request-note consumers replacing BML request access.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';

use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Test qw(temp_user);
use LJ::Session;
use File::Temp qw(tempfile);
require LJ::User::Login;
require LJ::User::Administration;
require LJ::Config;
require LJ::S2::FriendsPage;

sub request {
    my (%args) = @_;
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            HTTP_COOKIE       => $args{cookie} || '',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        },
    );
}

sub cookie_for_session {
    my ($session) = @_;
    return
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;
}

subtest 'login session and uncached remote use per-request notes without leakage' => sub {
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'nativereq';
    my $a = temp_user();
    my $b = temp_user();
    request();
    ok( $a->make_login_session('short'), 'real login session is created' );
    my $session_a = $a->{_session};
    is( DW::Request->get->note('ljuser'), $a->user, 'real login writes the request ljuser note' );
    like( join( ' ', DW::Request->get->{res}->headers->header('Set-Cookie') || () ),
        qr/ljmastersession=/, 'real login session writes a master session cookie' );
    ok( $b->make_fake_login_session,
        'second real session is created for sequential-cookie coverage' );
    my $session_b = $b->{_session};

    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE  = undef;
    my $r      = request( cookie => cookie_for_session($session_a) );
    my $remote = LJ::get_remote();
    is( $remote->id, $a->id, 'uncached get_remote resolves the first real session cookie' );
    is( $r->note('ljuser'), $a->user,
        'uncached get_remote records the first actor in its request note' );

    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE  = undef;
    $r                 = request();
    is( LJ::get_remote(), undef, 'no-cookie request between sessions remains anonymous' );
    ok( !defined $r->note('ljuser'), 'no-cookie request does not inherit the first actor note' );

    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE  = undef;
    $r                 = request( cookie => cookie_for_session($session_b) );
    $remote            = LJ::get_remote();
    is( $remote->id,        $b->id,   'sequential uncached get_remote resolves the second cookie' );
    is( $r->note('ljuser'), $b->user, 'second request does not inherit the first actor note' );

    DW::Request->reset;
    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE  = undef;
    is( LJ::get_remote(), undef, 'get_remote remains safely anonymous outside a request' );
    ok( $a->make_fake_login_session(), 'fake login session remains usable outside a request' );
};

{

    package NativeRequestContext::Remote;
    sub userid { $_[0]{userid} }
}

subtest 'administration logs preserve explicit and request uniq precedence' => sub {
    my $user   = temp_user();
    my $remote = bless { userid => 8 }, 'NativeRequestContext::Remote';
    my @bound;
    no warnings 'redefine';
    local *LJ::User::do      = sub { @bound = @_[ 1 .. $#_ ]; return 1 };
    local *LJ::get_remote_ip = sub { '192.0.2.9' };
    local *LJ::get_remote    = sub { $remote };

    my $r = request();
    $r->note( uniq => 'request-uniq' );
    ok( $user->log_event( 'change', { actiontarget => 5, alpha => 'one' } ),
        'request-context log inserts' );
    is( $bound[7], 'request-uniq', 'log_event binds the request uniq when none was supplied' );
    is( $bound[6], '192.0.2.9',    'log_event preserves remote IP lookup' );
    is( $bound[5], 8,              'log_event preserves remote actor lookup' );
    is( $bound[4], 5,              'log_event preserves action target extraction' );
    is( $bound[8], 'alpha=one', 'log_event preserves destructive info extraction into extra data' );

    ok( $user->log_event( 'change', { uniq => 'explicit-uniq' } ), 'explicit-uniq log inserts' );
    is( $bound[7], 'explicit-uniq', 'explicit uniq still takes precedence over the request note' );

    DW::Request->reset;
    ok( $user->log_event( 'change', {} ), 'nonweb log inserts' );
    is( $bound[7], undef, 'nonweb log has no leaked request uniq' );
};

subtest 'Config reload diagnostic is limited to native web context' => sub {
    my ( $fh, $filename ) = tempfile();
    print {$fh} "# native request context fixture\n";
    close $fh;
    utime time, time, $filename;
    my $reloads = 0;
    no warnings 'redefine';
    local @LJ::CONFIG_FILES                   = ($filename);
    local $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = 0;
    local $LJ::CACHE_CONFIG_MODTIME           = 0;
    local $LJ::LOCKER_OBJ;
    local *LJ::Config::reload = sub { $reloads++ };
    local $LJ::DEBUG_HOOK{pre_save_bak_stats};

    DW::Request->reset;
    my $stderr = '';
    open my $capture, '>', \$stderr or die $!;
    local *STDERR = $capture;
    LJ::Config->start_request_reload;
    is( $reloads, 1, 'Config reload still runs outside a request' );
    unlike( $stderr, qr/Configuration file\(s\) reloaded/,
        'nonweb reload emits no web diagnostic' );

    local $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = 0;
    local $LJ::CACHE_CONFIG_MODTIME           = 0;
    request();
    $stderr = '';
    LJ::Config->start_request_reload;
    is( $reloads, 2, 'Config reload still runs in a request' );
    like(
        $stderr,
        qr/Configuration file\(s\) reloaded/,
        'native request context enables only the existing web diagnostic'
    );
    unlink $filename;
};

{

    package NativeRequestContext::S2Journal;

    sub new {
        bless { user => 'journal', friendspagetitle => '', friendspagesubtitle => '' }, shift;
    }
    sub content_filters { return }
    sub watch_items     { return }
}

subtest 'FriendsPage reads the native uniq note for 304 suppression' => sub {
    my @keys;
    my %loginout = ( A => 1, B => 0 );
    no warnings 'redefine';
    local *LJ::S2::Page                         = sub { return { head_content => '' } };
    local *LJ::S2::tracking_popup_js            = sub { return () };
    local *LJ::need_res                         = sub { return };
    local *LJ::Talk::init_s2journal_js          = sub { return };
    local *LJ::Talk::init_s2journal_shortcut_js = sub { return };
    local *LJ::Capabilities::get_cap_min        = sub { return 1 };
    local *LJ::Lang::ml                         = sub { return $_[0] };
    local *LJ::http_to_time                     = sub { return time + 60 };
    local *LJ::MemCache::get = sub {
        my ($key) = @_;
        push @keys, $key;
        return $key =~ /loginout:(.+)\z/ ? $loginout{$1} : 0;
    };
    my $opts = sub {
        return {
            header  => { 'If-Modified-Since' => 'future' },
            headers => {},
            getargs => {},
            view    => 'read'
        };
    };
    my $journal = NativeRequestContext::S2Journal->new;

    my $r = request();
    $r->note( uniq => 'A' );
    my $one = $opts->();
    LJ::S2::FriendsPage( $journal, undef, $one );
    isnt( $one->{handler_return},
        304, 'true loginout marker suppresses the conditional 304 response' );
    is( $keys[-1], 'loginout:A',
        'FriendsPage uses the first request uniq note for loginout suppression' );

    $r = request();
    $r->note( uniq => 'B' );
    my $two = $opts->();
    is( LJ::S2::FriendsPage( $journal, undef, $two ),
        1, 'false loginout marker permits the conditional 304 response' );
    is( $two->{handler_return}, 304, 'false marker sets the existing 304 handler result' );
    is( $keys[-1], 'loginout:B',
        'sequential FriendsPage request does not leak the prior uniq note' );

    DW::Request->reset;
    my $three = $opts->();
    LJ::S2::FriendsPage( $journal, undef, $three );
    is( $three->{handler_return},
        304, 'FriendsPage retains no-request conditional behavior without a BML request' );
    is( scalar @keys, 2, 'no-request FriendsPage does not consult a synthetic uniq cache key' );
};

done_testing;
