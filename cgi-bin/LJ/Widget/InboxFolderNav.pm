package LJ::Widget::InboxFolderNav;

use strict;
use vars qw(%GET %POST);
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
    my @errors;

    my $body;

    my $unread_html = sub {
        my $count = shift || 0;
        return $count ? " <span class='unread_count'>($count)</span>"
                      : " <span class='unread_count'></span>";
    };

    my $remote = LJ::get_remote()
        or return "<?needlogin?>";

    my $inbox = $remote->notification_inbox
        or return LJ::error_list( BML::ml('inbox.error.couldnt_retrieve_inbox', { 'user' => $remote->{user} }) );

    # print number of new alerts
    my $unread_count = $inbox->all_event_count;
    my $alert_plural = $unread_count == 1 ? 'inbox.message' : 'inbox.messages';
    $alert_plural .= $unread_count ? '!' : '.';
    my $unread_all = $unread_html->($unread_count);
    my $unread_usermsg_recvd = $unread_html->($inbox->usermsg_recvd_event_count);
    my $unread_friend = $unread_html->($inbox->friendplus_event_count);
    my $unread_entrycomment = $unread_html->($inbox->entrycomment_event_count);
    my $unread_usermsg_sent = $unread_html->($inbox->usermsg_sent_event_count);
    my $message_button = "";
    $message_button = qq{
        <form action="./compose.bml" method="GET">
        <input type="submit" value="<?_ml inbox.menu.new_message.btn _ml?>" style="width: 100%">
        </form>} if LJ::is_enabled('user_messaging');


    $body .= qq{
            $message_button
            <div class="folders"><p>
            <a href="." id="esn_folder_all"><?_ml inbox.menu.all _ml?>$unread_all</a>};
    $body .= qq{<a href=".?view=usermsg_recvd" class="subs" id="esn_folder_usermsg_recvd"><?_ml inbox.menu.messages _ml?>$unread_usermsg_recvd</a>} if LJ::is_enabled('user_messaging');
    $body .= qq{<a href=".?view=friendplus" class="subs" id="esn_folder_friendplus"><?_ml inbox.menu.friend_updates _ml?>$unread_friend</a>
            <a href=".?view=birthday" class="subsubs" id="esn_folder_birthday"><?_ml inbox.menu.birthdays _ml?></a>
            <a href=".?view=befriended" class="subsubs" id="esn_folder_befriended"><?_ml inbox.menu.new_friends _ml?></a><a href=".?view=entrycomment" class="subs" id="esn_folder_entrycomment"><?_ml inbox.menu.entries_and_comments _ml?>$unread_entrycomment</a>
            <span class="subs">---</span>
            <a href=".?view=bookmark" class="subs" id="esn_folder_bookmark"><?_ml inbox.menu.bookmarks _ml?> <img src="$LJ::IMGPREFIX/flag_on.gif" width="12" height="14" border="0" /></a>};
    $body .= qq{<a href=".?view=usermsg_sent" class="subs" id="esn_folder_usermsg_sent"><?_ml inbox.menu.sent _ml?>$unread_usermsg_sent</a>\n} if LJ::is_enabled('user_messaging');
    $body .= qq{<a href=".?view=archived" class="subs" id="esn_folder_archived"><?_ml inbox.menu.archive _ml?></a>\n} if LJ::is_enabled('esn_archive');
    $body .= qq{
            </p></div>&nbsp;<br />
    };

    return $body;
}

1;
