package LJ::Console::Command::Infohistory;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "infohistory" }

sub desc { "Retrieve info history of a given account." }

sub args_desc { [
                 'user' => "The username of the account whose infohistory to retrieve.",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "finduser", "infohistory" );
}

sub execute {
    my ($self, $user, @args) = @_;

    return $self->error("This command takes exactly one argument. Consult the reference.")
        unless $user && !@args;

    my $u = LJ::load_user($user);

    return $self->error("Invalid user $user")
        unless $u;

    my $dbh = LJ::get_db_reader();
    my $sth = $dbh->prepare("SELECT * FROM infohistory WHERE userid=?");
    $sth->execute($u->id);

    return $self->error("No matches.")
        unless $sth->rows;

    $self->info("Infohistory of user: $user");
    while (my $info = $sth->fetchrow_hashref) {
        $info->{'oldvalue'} ||= '(none)';
        $self->info("Changed $info->{'what'} at $info->{'timechange'}.");
        $self->info("Old value of $info->{'what'} was $info->{'oldvalue'}.");
        $self->info("Other information recorded: $info->{'other'}")
            if $info->{'other'};
    }

    return 1;
}

1;
