package LJ::Console::Command::ResetEmail;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "reset_email" }

sub desc { "Resets the email address of a given account." }

sub args_desc { [
                 'user' => "The account to reset the email address for.",
                 'value' => "Email address to set the account to.",
                 'reason' => "Reason for the reset",
                 ] }

sub usage { '<user> <value> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "reset_email");
}

sub execute {
    my ($self, $username, $newemail, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $username && $newemail && $reason && scalar(@args) == 0;

    my $u = LJ::load_user($username);
    return $self->error("Invalid user $username")
        unless $u;

    my $aa = LJ::register_authaction($u->id, "validateemail", $newemail);

    LJ::infohistory_add($u, 'emailreset', $u->email_raw, $u->email_status)
        if $u->email_raw ne $newemail;

    LJ::update_user($u, { email => $newemail, status => 'T' })
        or return $self->error("Unable to set new email address for $username");

    my $body = "The email address for your $LJ::SITENAME account '$username' has been reset. To\n";
    $body .= "validate the change, please go to this address:\n\n";
    $body .= "     $LJ::SITEROOT/confirm/$aa->{'aaid'}.$aa->{'authcode'}\n\n";
    $body .= "Regards,\n$LJ::SITENAME Team\n\n$LJ::SITEROOT/\n";

    LJ::send_mail({
        'to' => $newemail,
        'from' => $LJ::ADMIN_EMAIL,
        'subject' => "Email Address Reset",
        'body' => $body,
    }) or $self->info("Confirmation email could not be sent.");

    my $dbh = LJ::get_db_writer();
    $dbh->do("UPDATE infohistory SET what='emailreset' WHERE userid=? AND what='email'",
             undef, $u->id) or return $self->error("Database error: " . $dbh->errstr);

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "reset_email", $reason);

    return $self->print("Email address for '$username' reset.");
}

1;
