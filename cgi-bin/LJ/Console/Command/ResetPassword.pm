# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Console::Command::ResetPassword;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "reset_password" }

sub desc { "Resets the password for a given account. Requires priv: reset_password." }

sub args_desc { [
                 'user' => "The account to reset the password for.",
                 'reason' => "Reason for the password reset.",
                 ] }

sub usage { '<user> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "reset_password" );
}

sub execute {
    my ($self, $username, $reason, @args) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $username && $reason && scalar(@args) == 0;

    my $u = LJ::load_user($username);
    return $self->error("Invalid user $username")
        unless $u;

    my $newpass = LJ::rand_chars(8);
    my $oldpass = Digest::MD5::md5_hex($u->password . "change");
    my $rval = $u->infohistory_add( 'passwordreset', $oldpass );
    return $self->error("Failed to insert old password into infohistory.")
        unless $rval;

    $u->update_self( { password => $newpass, } )
        or return $self->error("Failed to set new password for $username");

    $u->kill_all_sessions;

    unless ( $LJ::T_SUPPRESS_EMAIL ) {
        my $body = "The password for your $LJ::SITENAME account '$username' has been reset to:\n\n";
        $body .= "     $newpass\n\n";
        $body .= "Please change it immediately by going to:\n\n";
        $body .= "     $LJ::SITEROOT/changepassword\n\n";
        $body .= "Regards,\n$LJ::SITENAME Team\n\n$LJ::SITEROOT/\n";

        LJ::send_mail( {
            'to' => $u->email_raw,
            'from' => $LJ::ADMIN_EMAIL,
            'subject' => "Password Reset",
            'body' => $body,
        } ) or $self->info("New password notification email could not be sent.");
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "reset_password", $reason);
    return $self->print("Password reset for '$username'.");
}

1;
