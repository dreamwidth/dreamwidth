package LJ::Console::Command::ChangeCommunityAdmin;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_community_admin" }

sub desc { "Transfer maintainership of a community to another user." }

sub args_desc { [
                 'community' => "The username of the community.",
                 'new_owner' => "The username of the new owner of the community.",
                 ] }

sub usage { '<community> <new_owner>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "communityxfer" );
}

sub execute {
    my ($self, $comm, $maint, @args) = @_;

    return $self->error("This command takes exactly two arguments. Consult the reference")
        unless $comm && $maint && scalar(@args) == 0;

    my $ucomm = LJ::load_user($comm);
    my $unew  = LJ::load_user($maint);

    return $self->error("Given community doesn't exist or isn't a community.")
        unless $ucomm && $ucomm->is_community;

    return $self->error("New owner doesn't exist or isn't a person account.")
        unless $unew && $unew->is_person;

    return $self->error("New owner's email address isn't validated.")
        unless $unew->{'status'} eq "A";

    # remove old maintainers' power over it
    LJ::clear_rel($ucomm, '*', 'A');

    # add a new sole maintainer
    LJ::set_rel($ucomm, $unew, 'A');

    # so old maintainers can't regain access
    my $dbh = LJ::get_db_writer();
    $dbh->do("DELETE FROM infohistory WHERE userid = ?", undef, $ucomm->id);

    # change password to blank and set email of community to new maintainer's email
    LJ::update_user($ucomm, { password => '', email => $unew->email_raw });
    $ucomm->update_email_alias;

    # log to statushistory
    my $remote = LJ::get_remote();
    LJ::statushistory_add($ucomm, $remote, "communityxfer", "Changed maintainer to ". $unew->user ." (". $unew->id .").");
    LJ::statushistory_add($unew, $remote, "communityxfer", "Control of '". $ucomm->user ."' (". $ucomm->id .") given.");

    return $self->print("Transferred maintainership of '" . $ucomm->user . "' to '" . $unew->user . "'.");
}

1;
