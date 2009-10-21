package LJ::Console::Command::MoodthemeCreate;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_create" }

sub desc { "Create a new moodtheme. Returns the mood theme ID that you'll need to define moods for this theme." }

sub args_desc { [
                 'name' => "Name of this theme.",
                 'desc' => "A description of the theme",
                 ] }

sub usage { '<name> <desc>' }

sub can_execute { 1 }

sub execute {
    my ($self, $name, $desc, @args) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $name && $desc && scalar(@args) == 0;

    my $remote = LJ::get_remote();
    return $self->error("Sorry, your account type doesn't let you create new mood themes")
        unless $remote->can_create_moodthemes;

    my $dbh = LJ::get_db_writer();
    my $sth = $dbh->prepare("INSERT INTO moodthemes (ownerid, name, des, is_public) VALUES (?, ?, ?, 'N')");
    $sth->execute($remote->id, $name, $desc);

    my $mtid = $dbh->{'mysql_insertid'};
    return $self->print("Success. Your new mood theme ID is $mtid");
}

1;
