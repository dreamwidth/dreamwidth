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

use Test::More tests => 11;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
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
    $u->update_self( { email => 'unconfirmed@example.com', status => 'N' } );
    $u->set_password('Original-pass-42');
    @mail = ();

    my $res = reset_password( $u, 'unconfirmed@example.com' );
    is( $res->code, 200, 'reset form submits' );
    like( $res->content, qr/password has been changed/, 'reset reports success' );

    $u = reloaded($u);
    ok( $u->check_password($newpass), 'new password is set' );
    ok( $u->is_validated,             'using the reset link confirms the address it was sent to' );
    is( scalar @mail, 1, 'password change notice is mailed' );
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
