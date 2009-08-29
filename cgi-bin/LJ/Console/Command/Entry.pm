package LJ::Console::Command::Entry;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "entry" }

sub desc { "Manage entries in an account" }

sub args_desc { [
                 'action' => "Currently only 'delete'",
                 'url' => 'The URL to the entry',
                 'reason' => 'Reason this action is being taken',
                 ] }

sub usage { '<action> <url> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "deletetalk" );
}

sub execute {
    my ($self, $action, $uri, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $action && $uri && $reason && scalar(@args) == 0;

    return $self->error("Invalid action")
        unless $action eq "delete";

    return $self->error("You must provide a reason to action an entry.")
        unless $reason;

    my $entry = LJ::Entry->new_from_url($uri);
    return $self->error("URL provided does not appear to link to a valid entry.")
        unless $entry && $entry->valid;

    if ($action eq "delete") {
        LJ::delete_entry($entry->journal, $entry->jitemid)
            or return $self->error("There was a problem deleting this entry.");
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add($entry->journal, $remote, 'entry_action', "$action (entry " . $entry->ditemid . "): $reason");

    return $self->print("Entry action taken.");
}

1;
