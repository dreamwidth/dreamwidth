# t/talkpost-authenticate-user.t
#
# Test the thing that authenticates users when submitting a comment through the
# web forms.
#
# Authors:
#      Nick Fagerlund <nick.fagerlund@gmail.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 13;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );

use DW::Controller::Talk;

note("While logged in as site user:");
{
    my $remote = temp_user();
    $remote->set_password('snthueoa');
    my $journalu = temp_user();
    my $alt      = temp_user();
    $alt->set_password('aoeuhtns');

    my $authcheck = sub {    # 3 tests per
        my ( $form, $expect_ok, $expect_user, $expect_login ) = @_;
        my ( $ok, $auth ) =
            DW::Controller::Talk::authenticate_user_and_mutate_form( $form, $remote, $journalu );

        if ($expect_ok) {
            ok( $ok, "Auth succeeded" );
        }
        else {
            ok( !$ok, "Auth failed" );
        }

        if ($ok) {
            if ($expect_user) {
                ok( $expect_user->equals( $auth->{user} ),
                    "Auth user matched expected user $expect_user->user" );
            }
            else {
                ok( !defined $auth->{user}, "User is undef" );
            }

            if ($expect_login) {
                ok( $auth->{didlogin}, "Logged in" );
            }
            else {
                ok( !$auth->{didlogin}, "Didn't log in" );
            }
        }
        else {
            ok( !$expect_user,  "Auth failed, and wasn't expecting a user" );
            ok( !$expect_login, "Auth failed, and wasn't expecting a login" );
        }
    };

    note("Cookieuser, self");
    my $form = {
        usertype   => 'cookieuser',
        cookieuser => $remote->user,
    };
    $authcheck->( $form, 1, $remote, 0 );    # 3

    note("Anon");
    $form = { usertype => 'anonymous', };
    $authcheck->( $form, 1, undef, 0 );      # 6

    note("Alt, one-off");
    $form = {
        usertype => 'user',
        userpost => $alt->user,
        password => 'aoeuhtns',
    };
    $authcheck->( $form, 1, $alt, 0 );       # 9
    ok( $form->{usertype} eq 'user', "Form usertype unchanged" );    # 10

    note("Alt, wrong password");
    $form = {
        usertype => 'user',
        userpost => $alt->user,
        password => 'asdfjkl;',
    };
    $authcheck->( $form, 0, undef, 0 );                              #13

# I can't figure out how to test logins -- blows up with:
# Can't call method "header_in" on an undefined value at cgi-bin/LJ/User/Login.pm line 263.
#     note("Alt, login");
#     $form = {
#         usertype => 'user',
#         userpost => $alt->user,
#         password => 'aoeuhtns',
#         do_login => 1,
#     };
#     $authcheck->($form, 1, $alt, 1); # 16
#     ok($form->{usertype} eq 'cookieuser' && $form->{cookieuser} eq $alt->user, "Form mutated to set alt as current user"); #17

}
