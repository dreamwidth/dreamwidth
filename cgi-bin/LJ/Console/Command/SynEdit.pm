package LJ::Console::Command::SynEdit;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_editurl" }

sub desc { "Changes the source feed URL for a syndicated account." }

sub args_desc { [
                 'user' => "The username of the syndicated account.",
                 'newurl' => "The new source feed URL.",
                 ] }

sub usage { '<user> <newurl>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "syn_edit" );
}

sub execute {
    my ($self, $user, $newurl, @args) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $user && $newurl && scalar(@args) == 0;

    my $u = LJ::load_user($user);

    return $self->error("Invalid user $user")
        unless $u;
    return $self->error("Not a syndicated account")
        unless $u->is_syndicated;
    return $self->error("Invalid URL")
        unless $newurl =~ m!^http://(.+?)/!;

    my $dbh = LJ::get_db_writer();
    my $oldurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?",
                                       undef, $u->id);
    $dbh->do("UPDATE syndicated SET synurl=?, checknext=NOW() WHERE userid=?",
             undef, $newurl, $u->id);

    if ($dbh->err) {
        my $acct = $dbh->selectrow_array("SELECT userid FROM syndicated WHERE synurl=?",
                                         undef, $newurl);
        my $oldu = LJ::load_userid($acct);
        return $self->error("URL for account $user not changed: URL in use by " . $oldu->user);
    } else {
        my $remote = LJ::get_remote();
        LJ::statushistory_add($u, $remote, 'synd_edit', "URL changed: $oldurl => $newurl");
        return $self->print("URL for account $user changed: $oldurl => $newurl");
    }
}

1;
