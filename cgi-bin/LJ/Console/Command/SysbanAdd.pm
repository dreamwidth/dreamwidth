package LJ::Console::Command::SysbanAdd;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "sysban_add" }

sub desc { "Block an action based on certain criteria" }

sub args_desc { [
                 'what' => "The criterion you're blocking",
                 'value' => "The value you're blocking",
                 'days' => "Length of the ban, in days (or 0 for forever)",
                 'note' => "Reason why you're setting this ban",
                 ] }

sub usage { '<what> <value> [ <days> ] [ <note> ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "sysban");
}

sub execute {
    my ($self, $what, $value, $days, $note, @args) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $what && $value && scalar(@args) == 0;

    my $remote = LJ::get_remote();
    return $self->error("You cannot create these ban types")
        unless LJ::check_priv($remote, "sysban", $what);

    my $err = LJ::sysban_validate($what, $value);
    return $self->error($err) if $err;

    $days ||= 0;
    return $self->error("You must specify a numeric value for the length of the ban")
        unless $days =~ /^\d+$/;

    my $banid = LJ::sysban_create(
                                  'what'    => $what,
                                  'value'   => $value,
                                  'bandays' => $days,
                                  'note'    => $note,
                                  );

    return $self->error("There was a problem creating the ban.")
        unless $banid;

    return $self->print("Successfully created ban #$banid");
}

1;
