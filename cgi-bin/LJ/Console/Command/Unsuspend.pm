package LJ::Console::Command::Unsuspend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "unsuspend" }

sub desc { "Unsuspend an account." }

sub args_desc { [
                 'username or email address' => "The username of the account to unsuspend, or an email address to unsuspend all accounts at that address.",
                 'reason' => "Why you're unsuspending the account.",
                 ] }

sub usage { '<username or email address> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "suspend");
}

sub execute {
    my ($self, $user, $reason, $confirmed, @args) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $user && $reason && scalar(@args) == 0;

    my @users;
    if ($user !~ /@/) {
        push @users, $user;

    } else {
        $self->info("Acting on users matching email $user");

        my $dbr = LJ::get_db_reader();
        my $userids = $dbr->selectcol_arrayref('SELECT userid FROM email WHERE email = ?', undef, $user);
        return $self->error("Database error: " . $dbr->errstr)
            if $dbr->err;

        return $self->error("No users found matching the email address $user.")
            unless $userids && @$userids;

        my $us = LJ::load_userids(@$userids);

        foreach my $u (values %$us) {
            push @users, $u->user;
        }

        unless ($confirmed eq "confirm") {
            $self->info("   $_") foreach @users;
            $self->info("To actually confirm this action, please do this again:");
            $self->info("   unsuspend $user \"$reason\" confirm");
            return 1;
        }
    }

    foreach my $username (@users) {
        my $u = LJ::load_user($username);

        unless ($u) {
            $self->error("Unable to load '$username'");
            next;
        }

        unless ($u->is_suspended) {
            $self->error("$username is not currently suspended; skipping.");
            next;
        }

        LJ::update_user($u->{'userid'}, { statusvis => 'V', raw => 'statusvisdate=NOW()' });
        $u->{statusvis} = 'V';

        my $remote = LJ::get_remote();
        LJ::statushistory_add($u, $remote, "unsuspend", $reason);
        eval { $u->fb_push };
        warn "Error running fb_push: $@\n" if $@ && $LJ::IS_DEV_SERVER;

        $self->info("User '$username' unsuspended.");
    }

    return 1;
}

1;
