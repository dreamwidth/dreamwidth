package LJ::Widget::FriendUpdates;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( stc/widgets/friendupdates.css );
}

# args
#   user: optional $u whose friend updates we should get (remote is default)
#   limit: optional max number of updates to show; default is 5
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    return "" unless $u;

    my $limit = defined $opts{limit} ? $opts{limit} : 5;

    my $inbox = $u->notification_inbox;
    my @notifications = ();
    if ($inbox) {
        @notifications = $inbox->friend_items;
        @notifications = sort { $b->when_unixtime <=> $a->when_unixtime } @notifications;
        @notifications = @notifications[0..$limit-1] if @notifications > $limit;
    }

    my $ret;
    $ret .= "<h2><span>" . $class->ml('widget.friendupdates.title') . "</span></h2>";
    $ret .= "<a href='$LJ::SITEROOT/inbox/' class='more-link'>" . $class->ml('widget.friendupdates.viewall') . "</a>";

    unless (@notifications) {
        $ret .= $class->ml('widget.friendupdates.noupdates');
        $ret .= "<p class='detail'>" . $class->ml('widget.friendupdates.noupdates.setup', {'aopts' => "href='$LJ::SITEROOT/manage/subscriptions/'"}) . "</p>";
        return $ret;
    }

    $ret .= "<ul class='nostyle'>";
    foreach my $item (@notifications) {
        $ret .= "<li>" . $item->title . "</li>";
    }
    $ret .= "</ul>";

    return $ret;
}

1;
