package LJ::SMS::MessageHandler::Add;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $u = $msg->from_u
        or die "no from_u for Add message";

    my ($fgroup, $text) = $msg->body_text
        =~ /^\s*a(?:dd)?(?:\.(\w+))?\s+(\S+)\s*/i;

    my $fr_user = LJ::canonical_username($text)
        or die "Invalid format for username: $text";

    my $fr_u = LJ::load_user($fr_user)
        or die "Invalid user: $fr_user";

    my $groupmask = 1;

    if ($fgroup) {
        my $group = LJ::get_friend_group($u->id, { name => $fgroup })
            or die "Invalid friend group: $fgroup";

        my $grp = $group ? $group->{groupnum}+0 : 0;
        $groupmask |= (1 << $grp) if $grp;
    }

    my $err;
    unless ($u->is_friend($fr_u) || $u->can_add_friends(\$err)) {
        die "Unable to add friend: $err";
    }

    $u->add_friend($fr_u, { groupmask => $groupmask })
        or die "Unable to add friend for 'Add' request";

    # mark the requesting (source) message as processed
    # -- we'd die before now if there was an error
    $msg->status('success');
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*a(?:dd)?(\.(\w+))?\s+\S+\s*$/i ? 1 : 0;
}

1;
