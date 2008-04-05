package LJ::Console::Command::MoodthemeList;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "moodtheme_list" }

sub desc { "List mood themes, or data about a mood theme." }

sub args_desc { [
                 'themeid' => 'Optional; mood theme ID to view data for. If not given, lists all available mood themes.'
                 ] }

sub usage { '[ <themeid> ]' }

sub requires_remote { 0 }

sub can_execute { 1 }

sub execute {
    my ($self, $themeid, @args) = @_;

    return $self->error("This command takes at most one argument. Consult the reference.")
        unless scalar(@args) == 0;

    my $dbh = LJ::get_db_reader();
    my $sth;

    if ($themeid) {
        $sth = $dbh->prepare("SELECT m.mood, md.moodid, md.picurl, md.width, md.height FROM moodthemedata md, moods m "
                             . "WHERE md.moodid=m.moodid AND md.moodthemeid = ? ORDER BY m.mood");
        $sth->execute($themeid);
        while (my ($mood, $moodid, $picurl, $w, $h) = $sth->fetchrow_array) {
            $self->info(sprintf("%-20s %2dx%2d %s", "$mood ($moodid)", $w, $h, $picurl));
        }
        return 1;
    }


    $self->info(sprintf("%3s %4s %-15s %-25s %s", "pub", "id# ", "owner", "theme name", "des"));
    $self->info( "-" x 80);

    $self->info("Public themes:");
    $sth = $dbh->prepare("SELECT mt.moodthemeid, u.user, mt.is_public, mt.name, mt.des FROM moodthemes mt, user u "
                         . "WHERE mt.ownerid=u.userid AND mt.is_public='Y' ORDER BY mt.moodthemeid");
    $sth->execute;
    $self->error("Database error: " . $dbh->errstr)
        if $dbh->err;

    while (my ($id, $user, $pub, $name, $des) = $sth->fetchrow_array) {
        $self->info(sprintf("%3s %4s %-15s %-25s %s", $pub, $id, $user, $name, $des));
    }

    my $remote = LJ::get_remote();
    if ($remote) {
        $sth = $dbh->prepare("SELECT mt.moodthemeid, u.user, mt.is_public, mt.name, mt.des FROM moodthemes mt, user u "
                             . "WHERE mt.ownerid=u.userid AND mt.ownerid = ? ORDER BY mt.moodthemeid");
        $sth->execute($remote->id);

        $self->error("Database error: " . $dbh->errstr)
            if $dbh->err;

        $self->info("Your themes:");

        while (my ($id, $user, $pub, $name, $des) = $sth->fetchrow_array) {
            $self->info(sprintf("%3s %4s %-15s %-25s %s", $pub, $id, $user, $name, $des));
        }
    }

    return 1;
}

1;
