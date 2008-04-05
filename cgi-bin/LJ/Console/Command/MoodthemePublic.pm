package LJ::Console::Command::MoodthemePublic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_public" }

sub desc { "Mark a mood theme as public or not." }

sub args_desc { [
                 'themeid' => "Mood theme ID number.",
                 'setting' => "Either 'Y' or 'N' to make it public or not public, respectively.",
                 ] }

sub usage { '<themeid> <setting>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "moodthememanager");
}

sub execute {
    my ($self, $themeid, $public, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $themeid && $public && scalar(@args) == 0;

    return $self->error("Setting must be either 'Y' or 'N'")
        unless $public =~ /^[YN]$/;
    my $msg = ($public eq "Y") ? "public" : "not public";

    my $dbh = LJ::get_db_writer();
    my $sth = $dbh->prepare("SELECT is_public FROM moodthemes WHERE moodthemeid = ?");
    $sth->execute($themeid);
    my $old_value = $sth->fetchrow_array;

    return $self->error("This theme doesn't seem to exist.")
        unless $old_value;

    return $self->error("This theme is already marked as $msg.")
        if $old_value eq $public;

    $dbh->do("UPDATE moodthemes SET is_public = ? WHERE moodthemeid = ?", undef, $public, $themeid);
    return $self->print("Theme #$themeid marked as $msg.");
}

1;
