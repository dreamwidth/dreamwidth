# t/sitescheme.t
#
# Test separate account and anonymous site scheme preferences.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::SiteScheme;
use LJ::Session;
use LJ::Test qw(temp_user);

package SiteSchemeRequest;

sub new { bless { jar => {}, sent => [], notes => {}, args => {} }, $_[0] }
sub cookie { $_[0]->{jar}{ $_[1] } }
sub get_args { $_[0]->{args} }
sub get_remote_ip { '127.0.0.1' }
sub header_in { '' }

sub note {
    my ( $self, $name, $value ) = @_;
    $self->{notes}{$name} = $value if @_ > 2;
    return $self->{notes}{$name};
}

sub add_cookie {
    my ( $self, %cookie ) = @_;
    push @{ $self->{sent} }, \%cookie;
}

sub delete_cookie {
    my ( $self, %cookie ) = @_;
    $self->add_cookie( %cookie, value => '', expires => '-1d' );
}

sub last_cookie {
    my ( $self, $name ) = @_;
    my @sent = grep { $_->{name} eq $name } @{ $self->{sent} };
    return $sent[-1];
}

# Apply the response cookies as a browser would before the next request.
sub next_request {
    my $self = shift;
    for my $cookie ( @{ $self->{sent} } ) {
        if ( length( $cookie->{value} // '' ) ) {
            $self->{jar}{ $cookie->{name} } = $cookie->{value};
        }
        else {
            delete $self->{jar}{ $cookie->{name} };
        }
    }
    $self->{sent} = [];
    $self->{notes} = {};
    $self->{args} = {};
}

package main;

my $request = SiteSchemeRequest->new;
no warnings 'redefine';
local *DW::Request::get = sub { $request };
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'sitescheme12345';
local $LJ::SAVE_SCHEME_EXPLICITLY = 0;

my $default = DW::SiteScheme->default;
my @other = grep { $_ ne $default } qw(celerity lynx blueshift);
my ( $anonymous, $account ) = @other;

subtest 'legacy cookie remains readable' => sub {
    $request->{jar}{BMLschemepref} = $account;
    is( DW::SiteScheme->current, $account, 'existing preference still applies' );
};

subtest 'anonymous selection has its own session cookie' => sub {
    $request->{jar}{BMLschemepref} = $account;
    ok( DW::SiteScheme->set_for_user( $anonymous, undef ), 'anonymous scheme saved' );
    my $cookie = $request->last_cookie('BMLschemeprefanon');
    ok( $cookie, 'anonymous cookie issued' );
    is( $cookie->{value}, $anonymous, 'anonymous choice stored' ) if $cookie;
    ok( !defined $cookie->{expires}, 'anonymous cookie lasts for the browser session' )
        if $cookie;
    $request->next_request;
    ok( !$request->cookie('BMLschemepref'), 'legacy preference cannot mask the new choice' );
    is( DW::SiteScheme->current, $anonymous, 'anonymous selection is used' );
};

my $u = temp_user();
my $v = temp_user();
$u->set_prop( schemepref => $account );
$v->set_prop( schemepref => $default );
my @sessions;

subtest 'login and account changes preserve the anonymous preference' => sub {
    for my $row ( [ $u, $account ], [ $v, $default ], [ $u, $account ] ) {
        my ( $user, $scheme ) = @$row;
        my $session = LJ::Session->create( $user, exptype => 'long' );
        ok( $session, 'session created' );
        push @sessions, $session;
        $session->update_master_cookie;
        ok( !$request->last_cookie('BMLschemeprefanon'), 'login leaves anonymous cookie alone' );
        my $cookie = $request->last_cookie('BMLschemepref');
        is( $cookie->{value}, $scheme, 'account preference issued' );
        is( $cookie->{expires}, LJ::time_to_cookie( $session->expiration_time ),
            'account preference expires with the login cookies' );
        $request->next_request;
        is( DW::SiteScheme->current, $scheme, 'account preference takes precedence' );
        is( $request->cookie('BMLschemeprefanon'), $anonymous, 'anonymous preference retained' );
    }
};

subtest 'an account with no saved choice uses the anonymous preference' => sub {
    $v->set_prop( schemepref => '' );
    $sessions[1]->update_master_cookie;
    ok( !$request->last_cookie('BMLschemeprefanon'), 'login does not replace anonymous preference' );
    $request->next_request;
    ok( !$request->cookie('BMLschemepref'), 'no account preference cookie remains' );
    is( DW::SiteScheme->current, $anonymous, 'anonymous preference supplies the fallback' );
};

subtest 'account selection of the default overrides an anonymous choice' => sub {
    $u->{_session} = $sessions[0];
    ok( DW::SiteScheme->set_for_user( $default, $u ), 'account default saved' );
    my $cookie = $request->last_cookie('BMLschemepref');
    ok( $cookie, 'explicit account default has a cookie' );
    is( $cookie->{value}, $default, 'cookie stores the account default' ) if $cookie;
    ok( !$request->last_cookie('BMLschemeprefanon'), 'account save leaves anonymous cookie alone' );
    $request->next_request;
    is( DW::SiteScheme->current, $default, 'anonymous choice does not override account default' );
    is( $u->prop('schemepref'), $default, 'account userprop saved' );
};

subtest 'logout clears authentication and restores the anonymous choice' => sub {
    $u->_logout_common;
    ok( !$request->last_cookie('BMLschemeprefanon'), 'logout leaves anonymous cookie alone' );
    for my $name (qw(ljmastersession ljloggedin BMLschemepref)) {
        my $cookie = $request->last_cookie($name);
        ok( $cookie && !$cookie->{value}, "$name cleared" );
    }
    $request->next_request;
    is( DW::SiteScheme->current, $anonymous, 'anonymous choice returns after logout' );
};

subtest 'browser expiration falls back to the anonymous cookie' => sub {
    $request->{jar}{BMLschemepref} = $account;
    is( DW::SiteScheme->current, $account, 'account cookie wins before expiration' );
    delete $request->{jar}{BMLschemepref};
    is( DW::SiteScheme->current, $anonymous, 'anonymous cookie wins after account cookie expires' );
};

subtest 'anonymous default does not change the account preference' => sub {
    ok( DW::SiteScheme->set_for_user( $default, undef ), 'anonymous default selected' );
    $request->next_request;
    ok( !$request->cookie('BMLschemeprefanon'), 'implicit anonymous default has no cookie' );
    is( DW::SiteScheme->current, $default, 'site default used' );
    is( $u->prop('schemepref'), $default, 'anonymous choice does not change account preference' );
    local $LJ::SAVE_SCHEME_EXPLICITLY = 1;
    ok( DW::SiteScheme->set_for_user( $default, undef ), 'explicit anonymous default saved' );
    $request->next_request;
    is( $request->cookie('BMLschemeprefanon'), $default, 'explicit anonymous default retained' );
};

subtest 'request overrides still take precedence' => sub {
    $request->{jar}{BMLschemeprefanon} = $anonymous;
    $request->{args}{usescheme} = $account;
    is( DW::SiteScheme->current, $account, 'usescheme overrides cookie' );
    $request->{args}{skin} = $default;
    is( DW::SiteScheme->current, $default, 'skin overrides usescheme' );
    $request->note( bml_use_scheme => $anonymous );
    is( DW::SiteScheme->current, $anonymous, 'request note overrides query arguments' );
    $request->next_request;
    ok( !DW::SiteScheme->set_for_user( 'not-a-scheme', undef ), 'invalid selection rejected' );
    ok( !@{ $request->{sent} }, 'invalid selection does not change cookies' );
};

$_->destroy for @sessions;
delete $u->{_session};
done_testing();
