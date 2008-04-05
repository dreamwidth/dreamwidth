package LJ::SMS::MessageHandler::Friends;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $text   = $msg->body_text;
    my $u      = $msg->from_u;
    my $maxlen = $u->max_sms_bytes;

    my ($group) = $text =~ /
        ^\s*
        f(?:riends)?              # post full or short

        (?:\.                     # optional friends group setting
         (
          (?:\"|\').+?(?:\"|\')   # single or double quoted friends group
          |
          \S+)                    # single word friends group
         )?

         \s*$/ix;

    # for quoted strings, the 'group' segment will still have single or double quotes
    if ($group) {
        $group =~ s/^(?:\"|\')//;
        $group =~ s/(?:\"|\')$//;
    }

    # if no group specified, see if they have a default friend group prop set
    $group ||= $u->prop('sms_friend_group');

    # try to find the requested friends group and construct a filter mask
    my $filter;
    if ($group) {
        my $groups = LJ::get_friend_group($u);
        while (my ($bit, $grp) = each %$groups) {
            next unless $grp->{groupname} =~ /^$group$/i;

            # found the security group the user is asking for
            $filter = 1 << $grp->{groupnum};

            last;
        }
    } else {
        # we should return the default view friends group
        my $grp = LJ::get_friend_group($u, { 'name'=> 'Default View' });
        my $bit = $grp ? $grp->{'groupnum'} : 0;
        $filter = $bit ? (1 << $bit) : undef;
    }

    my @entries = LJ::get_friend_items({
        remoteid   => $u->id,
        itemshow   => 5,
        skip       => 0,
        showtypes  => 'PYC',
        u          => $u,
        userid     => $u->id,
        filter     => $filter,
    });

    my $resp = "";

    foreach my $item (@entries) {

        # each $item is just a magical hashref.  from that we'll
        # need to construct actual LJ::Entry objects to process
        # and eventually return via SMS

        my $entry = LJ::Entry->new_from_item_hash($item)
            or die "unable to construct entry object";

        my $seg = $entry->as_sms(for_u => $u, maxlen => 20);

        # could we append this segment without violating the
        # SMS message length boundary?
        last unless LJ::SMS->can_append($u, $resp, $seg);

        # still more buffer room, append another
        $resp .= $seg;

        # now try to append "\n\n" if that won't throw us over the limit
        # -- if successful, loop again to try to add a new message, 
        #    the finally strip off any \n\n ... 
        last unless LJ::SMS->can_append($u, $resp, "\n");

        $resp .= "\n";
    }

    # trim trailing newlines
    $resp =~ s/\n+$//;

    # ... but what if there actually were no entries?
    unless ($resp) {
        $resp = "Sorry, you currently have no friends page entries";
        $resp .= " for group '$group'" if $group;
        $resp .= ")";
    }

    my $resp_msg = eval { $msg->respond($resp) };

    # FIXME: do we set error status on $resp?

    # mark the requesting (source) message as processed
    $msg->status($@ ? ('error' => $@) : 'success');

    return 1;
}

sub owns {
    my ($class, $msg) = @_;
    croak "invalid message passed to MessageHandler"
        unless $msg && $msg->isa("LJ::SMS::Message");

    return $msg->body_text =~ /^\s*f(?:riends)?\.?\s*$/i ? 1 : 0;
}

1;
