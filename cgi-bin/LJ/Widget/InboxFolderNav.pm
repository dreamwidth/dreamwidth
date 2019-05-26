# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Widget::InboxFolderNav;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw(
        js/6alib/core.js
        js/6alib/dom.js
        js/6alib/hourglass.js
        stc/esn.css
        stc/lj_base.css
    );
}

sub render_body {
    my $class = shift;
    my %opts  = @_;
    my @errors;

    my $body;

    my $unread_html = sub {
        my $count = shift || 0;
        return $count
            ? " <span class='unread_count'>($count)</span>"
            : " <span class='unread_count'></span>";
    };

    my $subfolder_link = sub {
        my $link_view  = shift;
        my $link_label = shift;
        my $class      = shift || "";
        my $unread     = shift || "";
        my $img        = shift || 0;

        $class .= " selected" if $opts{view} && $opts{view} eq $link_view;

        my $link = qq{<a href=".?view=$link_view" class="$class" id="esn_folder_$link_view">};
        $link .= BML::ml($link_label);
        $link .= $unread if $unread;
        $link .= " $img" if $img;
        $link .= qq{</a>\n};
        return $link;
    };

    my $remote = LJ::get_remote()
        or return "<?needlogin?>";

    my $inbox = $remote->notification_inbox
        or return LJ::error_list(
        BML::ml( 'inbox.error.couldnt_retrieve_inbox', { 'user' => $remote->{user} } ) );

    # print number of new alerts
    my $unread_count = $inbox->all_event_count;
    my $alert_plural = $unread_count == 1 ? 'inbox.message' : 'inbox.messages';
    $alert_plural .= $unread_count ? '!' : '.';
    my $message_button = "";
    $message_button = qq{
        <form action="./compose" method="GET">
        <input type="submit" value="<?_ml inbox.menu.new_message.btn _ml?>" style="width: 100%">
        </form>} if LJ::is_enabled('user_messaging');

    $body .= qq{
            $message_button
            <div class="folders"><p>
    };

    my $unread_all_html = $unread_html->($unread_count);
    $body .= '<a href="." id="esn_folder_all"';
    $body .= ' class="selected"' unless $opts{view};
    $body .= "><?_ml inbox.menu.all _ml?>$unread_all_html</a>";
    $body .= $subfolder_link->(
        "usermsg_recvd", "inbox.menu.messages", "subs",
        $unread_html->( $inbox->usermsg_recvd_event_count )
    ) if LJ::is_enabled('user_messaging');
    $body .= $subfolder_link->(
        "circle", "inbox.menu.circle_updates", "subs", $unread_html->( $inbox->circle_event_count )
    );
    $body .= $subfolder_link->( "birthday",  "inbox.menu.birthdays", "subsubs" );
    $body .= $subfolder_link->( "encircled", "inbox.menu.encircled", "subsubs" );
    $body .= $subfolder_link->(
        "entrycomment", "inbox.menu.entries_and_comments",
        "subs", $unread_html->( $inbox->entrycomment_event_count )
    );
    $body .= $subfolder_link->(
        "pollvote", "inbox.menu.poll_votes", "subs", $unread_html->( $inbox->pollvote_event_count )
    );
    $body .= $subfolder_link->(
        "communitymembership", "inbox.menu.community_membership",
        "subs", $unread_html->( $inbox->communitymembership_event_count )
    );
    $body .= $subfolder_link->(
        "sitenotices", "inbox.menu.site_notices", "subs",
        $unread_html->( $inbox->sitenotices_event_count )
    );
    $body .= qq{<span class="subs">&nbsp;</span>\n};
    $body .= $subfolder_link->( "unread", "inbox.menu.unread", "subs", $unread_all_html );
    $body .= $subfolder_link->(
        "usermsg_sent", "inbox.menu.sent", "subs",
        $unread_html->( $inbox->usermsg_sent_event_count )
    ) if LJ::is_enabled('user_messaging');
    $body .= qq{<span class="subs">&nbsp;</span>\n};
    $body .= $subfolder_link->(
        "bookmark", "inbox.menu.bookmarks", "subs",
        $unread_html->( $inbox->bookmark_count ),
        LJ::img( 'flag', '' )
    );
    $body .= $subfolder_link->( "archived", "inbox.menu.archive", "subs" )
        if LJ::is_enabled('esn_archive');
    $body .= qq{
            </p></div>&nbsp;<br />
    };

    return $body;
}

1;
