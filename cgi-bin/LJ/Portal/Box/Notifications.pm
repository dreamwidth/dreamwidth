package LJ::Portal::Box::Notifications; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "Notifications";
our $_box_name = "Message Center";
our $_box_description = "See a preview of what's in your Message Center";
our $_prop_keys = {
    'maxnotices' => 2,
    'daysold'    => 1,
};
our $_config_props = {
    'maxnotices'  => {
        'type'    => 'integer',
        'desc'    => 'Maximum number of messages to display',
        'default' => 15,
        'min'     => 1,
        'max'     => 60,
    },
    'daysold'  => {
        'type'    => 'integer',
        'desc'    => 'How many days to save messages',
        'default' => 60,
        'min'     => 1,
        'max'     => 365,
    },
};

sub handle_request {
    my ($self, $GET, $POST) = @_;

    # process any deletions
    if ($GET->{'delete_note'} || $POST->{'delete_note'}) {
        my $qid = int($GET->{'del_note_qid'} || $POST->{'del_note_qid'});
        my $qitem = LJ::NotificationItem->new($self->{u}, $qid) or return undef;
        $qitem->delete;
    }

    return undef;
}

sub queue {
    my $self = shift;
    return $self->{u}->notification_inbox;
}

sub generate_content {
    my $self = shift;

    my $pboxid = $self->pboxid;
    my $u = $self->{u};

    my $content = '';
    my $maxnotices = $self->get_prop('maxnotices');
    my $daysold    = $self->get_prop('daysold');

    my $q = $self->queue;
    return "Could not retreive inbox." unless $q;

    $content .= qq {
        <div class="ESN_Links"><a href="$LJ::SITEROOT/inbox/">Message Center</a> |
            <a href="$LJ::SITEROOT/manage/subscriptions/">Manage Settings</a></div>

        <table style="width: 100%;">
            <tr class="PortalTableHeader"><td>Notification</td><td>Date</td><td>Delete</td></tr>
        };

    my $noticecount = 0;

    foreach my $item ($q->items) {
        my $evt = $item->event;
        my $qid = $item->qid;

        my $desc = $item->title;
        my $delrequest = "portalboxaction=$pboxid&delete_note=1&del_note_qid=$qid";

        my $delicon = "<img src=\"$LJ::IMGPREFIX/portal/btn_del.gif\" align=\"center\" />";

        my $cutoff_date = time() - $daysold * 24 * 60 * 60;

        next if $item->when_unixtime < $cutoff_date;

        my $timeago = $item->when_unixtime ?
            LJ::ago_text(time() - $item->when_unixtime) :
            "(?)";

        my $rowmod = $noticecount % 2 + 1;
        $content .= qq {
            <tr class="PortalRow$rowmod">
                <td>$desc</td>
                <td>$timeago</td>
                <td align="center"><a href="/portal/index.bml?$delrequest" onclick="return evalXrequest('$delrequest', null);">$delicon</a></td>
            </tr>
            };

        $noticecount++;
        last if $noticecount >= $maxnotices;
    }

    $content .= qq {
        <tr><td colspan="3">(No new notices)</td></tr>
        } unless $noticecount;

    $content .= '</table>';

    return $content;
}


#######################################

sub can_refresh { 1; }
sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }

# caching options
sub cache_global { 0; } # cache per-user
sub cache_time { 1 * 60; } # check etag every minute
sub etag {
    my $self = shift;

    my $daysold = $self->get_prop('daysold');
    my $maxnotices = $self->get_prop('maxnotices');

    my $q = $self->queue or return undef;

    my @items = $q->items;
    my @qids = map { $_->qid } @items;

    return "$daysold-" . join('-', @qids);
}

1;
