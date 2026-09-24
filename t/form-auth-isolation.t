# Explicit form-auth arguments must not inherit stale BML request state.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
my $user = temp_user();
LJ::set_remote($user);
my $html = LJ::form_auth();
my ($token) = $html =~ /value=["']([^"']+)/;
ok( $token, 'generated a real form-auth token' );
local $BMLCodeBlock::POST{lj_form_auth} = $token;
ok( LJ::check_form_auth(),       'legacy no-argument lookup accepts the BML token' );
ok( LJ::check_form_auth($token), 'explicit valid token succeeds' );
is( LJ::check_form_auth(''),        0, 'explicit empty token cannot inherit BML token' );
is( LJ::check_form_auth(undef),     0, 'explicit undefined token cannot inherit BML token' );
is( LJ::check_form_auth('invalid'), 0, 'explicit invalid token fails' );
LJ::unset_remote();
done_testing;
