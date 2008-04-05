package LJ::Console::Command::ExpungeUserpic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "expunge_userpic" }

sub desc { "Expunge a userpic from the site." }

sub args_desc { [
                 'url' => "URL of the userpic to expunge",
                 ] }

sub usage { '<url>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "siteadmin", "userpics");
}

sub execute {
    my ($self, $url, @args) = @_;

    return $self->error("This command takes one argument. Consult the reference.")
        unless $url && scalar(@args) == 0;

    my ($userid, $picid);
    if ($url =~ m!(\d+)/(\d+)/?$!) {
        $picid = $1;
        $userid = $2;
    }

    my $u = LJ::load_userid($userid);
    return $self->error("Invalid userpic URL.")
        unless $u;

    # the actual expunging happens in ljlib
    my ($rval, @hookval) = LJ::expunge_userpic($u, $picid);

    return $self->error("Error expunging userpic.") unless $rval;

    foreach my $hv (@hookval) {
        my ($type, $msg) = @$hv;
        $self->$type($msg);
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, 'expunge_userpic', "expunged userpic; id=$picid");

    return $self->print("Userpic '$picid' for '" . $u->user . "' expunged.");
}

1;
