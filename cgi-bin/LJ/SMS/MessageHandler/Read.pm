package LJ::SMS::MessageHandler::Read;

use base qw(LJ::SMS::MessageHandler);

use strict;
use Carp qw(croak);

sub handle {
    my ($class, $msg) = @_;

    my $text   = $msg->body_text;
    my $remote = $msg->from_u;
    my $maxlen = $remote->max_sms_bytes;

    my ($page, $user) = $text =~ /
        ^\s*
        r(?:ead)?                 # read full or short

        (?:\.                     # optional page number
         (\d+)                    # numeric page to retrieve
         )?

        \s+

        (\S{1,15})                # optional friends group setting

         \s*$/ix;

    $page ||= 1;
    $page = 1 if $page > 100;

    my $u = LJ::load_user($user)
        or die "nonexistant user: $user";

    my $err;
    my ($item) = LJ::get_recent_items({
        clusterid     => $u->{clusterid},
        clustersource => 'slave',
        userid        => $u->id,
        remote        => $remote,
        itemshow      => 1,
        order         => 'logtime',
        err           => \$err,
    });

    my $resp = "";

    # no entries for this user?
    unless ($item) {
        $resp = "Sorry, user '$user' has posted no entries";
        # now fall through to sending phase
    }

    # have an entry, try to process it
    if ($item) {
        my $entry = LJ::Entry->new_from_item_hash($u, $item)
            or die "unable to construct entry object";

        # $item is just a magical hashref.  from that we'll need to 
        # construct an actual LJ::Entry object to process and 
        # eventually return via SMS

        $resp = $entry->as_paged_sms(for_u => $remote, page => $page);

        # trim trailing newlines
        $resp =~ s/\n+$//;
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

    return $msg->body_text =~ /^\s*r(?:ead)?/i ? 1 : 0;
}

1;
