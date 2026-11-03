#!/usr/bin/perl
#
# t/login-controller.t
#
# Tests login controller error selection without rendering templates.
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
use DW::Controller::Login;

{

    package LoginErrorRequest;
    sub get_args  { {} }
    sub post_args { $_[0]->{post} }
    sub did_post  { 1 }

    sub note {
        my ( $self, $key, $value ) = @_;
        $self->{notes}{$key} = $value if @_ > 2;
        return $self->{notes}{$key};
    }
}

{

    package LoginErrorUser;
    sub readonly     { $_[0]->{readonly} }
    sub is_readonly  { $_[0]->{readonly} }
    sub is_expunged  { 0 }
    sub is_memorial  { 0 }
    sub is_community { 0 }
    sub is_locked    { 0 }
    sub session      { undef }
}

my ( $request, $remote, $user, $banned );
my ( @lookups, @auth_calls );

no warnings 'redefine';
local *DW::Request::get                  = sub { $request };
local *DW::Controller::Login::controller = sub {
    return ( 1, { r => $request, remote => $remote } );
};
local *DW::Template::render_template = sub { $_[2] };
local *LJ::Lang::ml                  = sub { $_[0] };
local *LJ::check_form_auth           = sub { 1 };
local *DW::Stats::increment          = sub { };
local *LJ::load_user                 = sub {
    push @lookups, $_[0];
    return $user;
};
local *LJ::auth_okay = sub {
    my ( $u, $password, %opts ) = @_;
    push @auth_calls, $u;
    ${ $opts{is_ip_banned} } = $banned;
    return 0;
};

sub login_result {
    my (%opts) = @_;
    $request =
        bless { post => { user => $opts{input} // 'someuser', password => 'incorrect-password' } },
        'LoginErrorRequest';
    $user    = $opts{user};
    $remote  = $opts{remote};
    $banned  = $opts{banned} // 0;
    @lookups = @auth_calls = ();
    return DW::Controller::Login::login_handler();
}

my $result = login_result( input => 'reader@example.com' );
is( $result->{errors}[0][0], 'email_as_username', 'Email input has a distinct error reason' );
is( $result->{errors}[0][1], '/login.tt.error.email', 'Email error uses an absolute ML key' );
is( scalar @lookups, 0, 'Email input is not looked up as an account name' );
ok( !grep( { defined $_ } @auth_calls ), 'Email input does not authenticate an account' );

$result = login_result( input => 'missinguser' );
is( $result->{errors}[0][0], 'unknown_user', 'Unknown username retains its error reason' );
is( $result->{errors}[0][1],
    '/login.tt.error.notuser',
    'Unknown-user lookup does not depend on the current translation scope' );

my $ordinary = bless {}, 'LoginErrorUser';
$result = login_result( user => $ordinary );
is( $result->{errors}[0][0], 'bad_password',       'Wrong password retains its error reason' );
is( $result->{errors}[0][1], 'error.badpassword2', 'Wrong password uses the global ML key' );

my $readonly = bless { readonly => 1 }, 'LoginErrorUser';
for my $opts ( { user => $readonly }, { remote => $readonly } ) {
    $result = login_result(%$opts);
    is( $result->{message}, '/login.tt.login.dbreadonly',
        'Read-only error uses the existing page-local ML key' );
    is( scalar @auth_calls, 0, 'Read-only account does not reach password authentication' );
}

$result = login_result( user => $ordinary, banned => 1 );
is( $result->{message}, '/login.tt.login.tempfailban',
    'IP ban uses the existing page-local ML key' );

done_testing();
