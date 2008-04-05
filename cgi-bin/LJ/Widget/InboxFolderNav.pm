package LJ::Widget::InboxFolderNav;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw(
            js/core.js
            js/dom.js
            js/hourglass.js
            stc/esn.css
            stc/lj_base.css
            );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $body;

    my $unread_html = sub {
        my $count = shift || 0;
        return $count ? " <span class='unread_count'>($count)</span>"
                      : " <span class='unread_count'></span>";
    };

    my $remote = LJ::get_remote();
    my $inbox = $remote->notification_inbox
        or die "Could not retrieve inbox for user $remote->{user}";

    # print number of new alerts
    my $unread_count = $inbox->unread_count;
    my $alert_plural = $unread_count == 1 ? 'message' : 'messages';
    $alert_plural .= $unread_count ? '!' : '.';
    my $unread_all = $unread_html->($unread_count);
    my $unread_usermsg_recvd = $unread_html->($inbox->usermsg_recvd_event_count);
    my $unread_friend = $unread_html->($inbox->friendplus_event_count);
    my $unread_entrycomment = $unread_html->($inbox->entrycomment_event_count);
    my $message_button = "";
    $message_button = qq{
        <form action="$LJ::SITEROOT/inbox/compose.bml" method="GET">
        <input type="submit" value="New Message" style="width: 100%">
        </form>} unless $LJ::DISABLED{user_messaging};

    $body .= qq{
            $message_button
            <div class="folders"><p>
            <a href="$LJ::SITEROOT/inbox/" id="esn_folder_all">All$unread_all</a>};
    $body .= qq{<a href="$LJ::SITEROOT/inbox/?view=usermsg_recvd" id="esn_folder_usermsg_recvd">Messages$unread_usermsg_recvd</a>} unless $LJ::DISABLED{user_messaging};
    $body .= qq{<a href="$LJ::SITEROOT/inbox/?view=friendplus" id="esn_folder_friendplus">Friend Updates$unread_friend</a>
              <a href="$LJ::SITEROOT/inbox/?view=birthday" class="subs" id="esn_folder_birthday">Birthdays</a>
              <a href="$LJ::SITEROOT/inbox/?view=befriended" class="subs" id="esn_folder_befriended">New Friends</a><a href=".?view=entrycomment" id="esn_folder_entrycomment">Entries &amp; Comments$unread_entrycomment</a>
            ---
            <a href="$LJ::SITEROOT/inbox/?view=bookmark" id="esn_folder_bookmark">Flagged <img src="$LJ::IMGPREFIX/flag_on.gif" width="12" height="14" border="0" /></a>};
    $body .= qq{<a href="$LJ::SITEROOT/inbox/?view=usermsg_sent" id="esn_folder_usermsg_sent">Sent</a>\n} unless $LJ::DISABLED{user_messaging};
    $body .= qq{<a href="$LJ::SITEROOT/inbox/?view=archived" id="esn_folder_archived">Archive</a>\n} unless $LJ::DISABLED{esn_archive};
    $body .= qq{
            </p></div>&nbsp;<br />
    };

    return $body;
}

1;
