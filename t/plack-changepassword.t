# t/plack-changepassword.t
#
# Tests for resetting a password with an emailed /changepassword link: using a
# link sent to the account's current address also confirms that address.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 22;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Session;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# Form auth binds to the browser's uniq cookie; fix it so GET and POST agree.
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'changepassTest';

my @mail;
no warnings 'redefine';
local *LJ::send_mail = sub { push @mail, $_[0]; 1 };
use warnings 'redefine';

my $newpass = 'Replacement-pass-73';

# Follow a reset link mailed to $email, then submit a new password from it.
sub reset_password {
    my ( $u, $email ) = @_;
    my $aa  = LJ::register_authaction( $u->id, 'reset_password', $email );
    my $url = "http://localhost/changepassword?auth=$aa->{aaid}.$aa->{authcode}";

    my $res;
    test_psgi $app, sub {
        my $cb          = shift;
        my $form        = $cb->( GET $url );
        my ($form_auth) = $form->content =~ /name="lj_form_auth" value="([^"]+)"/;
        $res = $cb->(
            POST $url,
            Content => [
                lj_form_auth => $form_auth,
                mode         => 'submit',
                newpass1     => $newpass,
                newpass2     => $newpass,
            ]
        );
    };
    return $res;
}

sub reloaded {
    my $u = shift;
    LJ::start_request();
    return LJ::load_userid( $u->id, 'force' );
}

# An account whose only address was never confirmed.
{
    my $u = temp_user();
    $u->update_self( { email => 'Unconfirmed@example.com', status => 'N' } );
    $u->set_password('Original-pass-42');
    @mail = ();

    my $res = reset_password( $u, 'Unconfirmed@example.com' );
    is( $res->code, 200, 'reset form submits' );
    like( $res->content, qr/password has been changed/, 'reset reports success' );

    $u = reloaded($u);
    ok( $u->check_password($newpass), 'new password is set' );
    ok( $u->is_validated,             'using the reset link confirms the address it was sent to' );
    is( scalar @mail, 1, 'password change notice is mailed' );
}

{
    my $u = temp_user();
    $u->update_self( { email => 'mixed@example.com', status => 'N' } );
    $u->set_password('Original-pass-42');

    my $res = reset_password( $u, 'Mixed@example.com' );
    like( $res->content, qr/password has been changed/, 'mixed-case address can reset' );
    $u = reloaded($u);
    ok( $u->check_password($newpass), 'reset sets the password from a mixed-case address' );
    ok( $u->is_validated,             'mixed-case reset link confirms the stored address' );
    is( $u->email_raw, 'mixed@example.com', 'reset preserves the stored address casing' );
}

{
    my $u = temp_user();
    $u->update_self( { email => 'before@example.com', status => 'N' } );
    $u->set_password('Original-pass-42');

    my $mark_used = \&LJ::mark_authaction_used;
    no warnings 'redefine';
    local *LJ::mark_authaction_used = sub {
        my $result = $mark_used->(@_);
        my $dbh    = LJ::get_db_writer();
        $dbh->do( 'UPDATE email SET email = ? WHERE userid = ?',
            undef, 'after@example.com', $u->id )
            or die $dbh->errstr;
        LJ::memcache_kill( $u->id, 'email' );
        return $result;
    };

    my $res = reset_password( $u, 'before@example.com' );
    like(
        $res->content,
        qr/password has been changed/,
        'reset finishes after an overlapping change'
    );
    $u = reloaded($u);
    ok( $u->check_password($newpass), 'reset sets the password after the address changes' );
    is( $u->email_raw, 'after@example.com', 'the overlapping email change persists' );
    is( $u->email_status, 'N', 'the changed address is not confirmed by the reset' );
}

{
    my $u = temp_user();
    $u->update_self( { email => 'in-flight@example.com', status => 'N' } );
    $u->set_password('Original-pass-42');

    my $session = LJ::Session->create( $u, nolog => 1 );
    my $cookie =
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;
    my $url = 'http://localhost/changeemail';

    local $LJ::HOOKS{post_email_change} = [
        sub {
            my $dbh = LJ::get_db_writer();
            $dbh->do( "UPDATE user SET status = 'A' WHERE userid = ?", undef, $u->id )
                or die $dbh->errstr;
            LJ::memcache_kill( $u->id, 'userid' );
        }
    ];

    test_psgi $app, sub {
        my $cb          = shift;
        my $form        = $cb->( GET $url, Cookie => $cookie );
        my ($form_auth) = $form->content =~ /name="lj_form_auth" value="([^"]+)"/;
        my $res         = $cb->(
            POST $url,
            Cookie  => $cookie,
            Content => [
                lj_form_auth   => $form_auth,
                email          => 'replacement@example.com',
                force_spelling => 1,
                password       => 'Original-pass-42',
            ]
        );
        like( $res->content, qr/Email address changed successfully/,
            'overlapping change finishes' );
    };

    $u = reloaded($u);
    is( $u->email_raw, 'replacement@example.com', 'the change stores the replacement address' );
    is( $u->email_status, 'T', 'validation of the old address does not carry over' );
}

# An account that changed to a new, unconfirmed address. A reset link sent to
# the old, previously confirmed address doesn't prove the new one.
{
    my $u = temp_user();
    $u->update_self( { email => 'old@example.com', status => 'A' } );
    $u->infohistory_add( 'email', 'old@example.com', 'A' );
    $u->update_self( { email => 'new@example.com', status => 'T' } );
    $u->set_password('Original-pass-42');
    $u = reloaded($u);

    my $res = reset_password( $u, 'old@example.com' );
    like( $res->content, qr/password has been changed/, 'old address can still reset' );

    $u = reloaded($u);
    ok( $u->check_password($newpass), 'new password is set from the old address' );
    is( $u->email_status, 'T', 'new address stays unconfirmed' );

    $res = reset_password( $u, 'new@example.com' );
    like( $res->content, qr/password has been changed/, 'new address can reset' );
    $u = reloaded($u);
    ok( $u->is_validated, 'reset link to the new address confirms it' );
    is( $u->email_raw, 'new@example.com', 'address is unchanged' );
}
