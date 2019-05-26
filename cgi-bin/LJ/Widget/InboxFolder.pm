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

package LJ::Widget::InboxFolder;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

# DO NOT COPY
# This widget is not a good example of how to use JS and AJAX.
# This widget's render_body outputs HTML similar to the HTML
# output originally by the Notifications Inbox page. This was
# done so that the existing JS, CSS and Endpoints could be used.

sub need_res {
    return qw(
        js/6alib/core.js
        js/6alib/dom.js
        js/6alib/view.js
        js/6alib/datasource.js
        js/6alib/checkallbutton.js
        js/6alib/selectable_table.js
        js/6alib/httpreq.js
        js/6alib/hourglass.js
        js/esn_inbox.js
        stc/esn.css
        stc/lj_base.css
    );
}

# args
#   folder: the view or subset of notification items to display
#   reply_btn: should we show a reply button or link
#   expand: display a specified in expanded view
#   inbox: NotificationInbox object
#   items: list of notification items
sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $name           = $opts{folder};
    my $show_reply_btn = $opts{reply_btn} || 0;
    my $expand         = $opts{expand} || 0;
    my $inbox          = $opts{inbox};
    my $nitems         = $opts{items};
    my $page           = $opts{page} || 1;
    my $view           = $opts{view} || "all";
    my $itemid         = int( $opts{itemid} || 0 );
    my $remote         = LJ::get_remote();

    my $unread_count = 1;                                 #TODO get real number
    my $disabled     = $unread_count ? '' : 'disabled';

    # print form
    my $msgs_body .= qq {
        <form action="$LJ::SITEROOT/inbox/" method="POST" id="${name}Form" onsubmit="return false;">
        };

    $msgs_body .= LJ::html_hidden(
        {
            name  => "view",
            value => "$view",
            id    => "inbox_view",
        }
    );

    $msgs_body .= LJ::html_hidden(
        {
            name  => "itemid",
            value => "$itemid",
            id    => "inbox_itemid",
        }
    );

    # pagination
    my $page_limit = 15;
    $page = 1 if $page < 1;
    my $last_page = POSIX::ceil( ( scalar @$nitems ) / $page_limit );
    $last_page ||= 1;
    $page = $last_page if $page > $last_page;
    my $starting_index = ( $page - 1 ) * $page_limit;

    my $prev_disabled = ( $page <= 1 )          ? 'disabled' : '';
    my $next_disabled = ( $page >= $last_page ) ? 'disabled' : '';

    my $actionsrow = sub {
        my $sfx = shift;    # suffix

        # check all checkbox
        my $checkall = LJ::html_check(
            {
                id    => "${name}_CheckAll_$sfx",
                class => "InboxItem_Check",
            }
        );

        return qq {
             <tr class="header" id="ActionRow$sfx">
                    <td class="checkbox">$checkall</td>
                    <td class="actions" colspan="2">
                        <span class="Pages">
                            Page $page of $last_page
                            <input type="button" id="Page_Prev_$sfx" value="<?_ml widget.inbox.menu.previous_page.btn _ml?>" $prev_disabled />
                            <input type="button" id="Page_Next_$sfx" value="<?_ml widget.inbox.menu.next_page.btn _ml?>" $next_disabled />
                        </span>
                        <input type="submit" name="markRead_$sfx" value="<?_ml widget.inbox.menu.mark_read.btn _ml?>" $disabled id="${name}_MarkRead_$sfx" />
                        <input type="submit" name="markUnread_$sfx" value="<?_ml widget.inbox.menu.mark_unread.btn _ml?>" id="${name}_MarkUnread_$sfx" />
                        <input type="submit" name="delete_$sfx" value="<?_ml widget.inbox.menu.delete.btn _ml?>" id="${name}_Delete_$sfx" />
                    </td>
            </tr>
        };
    };

    my $markdeleteall = sub {
        my $sfx = shift;

        # choose button text depending on whether user is viewing all emssages or only a subfolder
        # to avoid any confusion as to what deleting and marking read will do
        my $mark_all_text   = "";
        my $delete_all_text = "";
        if ( $view eq "all" ) {
            $mark_all_text   = "widget.inbox.menu.mark_all_read.btn";
            $delete_all_text = "widget.inbox.menu.delete_all.btn";
        }
        elsif ( $view eq "singleentry" ) {
            $mark_all_text   = "widget.inbox.menu.mark_all_read.entry.btn";
            $delete_all_text = "widget.inbox.menu.delete_all.entry.btn";
        }
        else {
            $mark_all_text   = "widget.inbox.menu.mark_all_read.subfolder.btn";
            $delete_all_text = "widget.inbox.menu.delete_all.subfolder.btn";
        }

        return qq {
            <div style="text-align: center; margin-bottom: 20px; margin-top: 20px;">
            <input type="submit" name="markAllRead_$sfx" value="<?_ml $mark_all_text _ml?>" $disabled 
                id="${name}_MarkAllRead_$sfx" style="margin-right: 5em; width: 15em;" />
            <input type="submit" name="deleteAll_$sfx" value="<?_ml $delete_all_text _ml?>" 
                $disabled id="${name}_DeleteAll_$sfx" style="width: 15em;" />
            </div>
        };
    };

    # create table of messages
    my $messagetable = $markdeleteall->(1);

    $messagetable .= qq {
        <div id="${name}_Table" class="NotificationTable">
        <table summary='' id="${name}" class="inbox" cellspacing="0" border="0" cellpadding="0">
    };
    $messagetable .= $actionsrow->(1);
    $messagetable .= "<tbody id='${name}_Body'>";

    unless (@$nitems) {
        $messagetable .= qq {
            <tr><td class="NoItems status-hint" colspan="3" id="NoMessageTD"><?_ml inbox.nomessages _ml?></td></tr>
            };
    }

    @$nitems = sort { $b->when_unixtime <=> $a->when_unixtime } @$nitems;

    # print out messages
    my $rownum = 0;

    for ( my $i = $starting_index ; $i < $starting_index + $page_limit ; $i++ ) {
        my $inbox_item = $nitems->[$i];
        last unless $inbox_item;

        my $qid = $inbox_item->qid;

        my $read_class = $inbox_item->read ? "InboxItem_Read read" : "InboxItem_Unread";

        my $title = $inbox_item->title( mode => $opts{mode} );

        my $checkbox_name = "${name}_Check-$qid";
        my $checkbox      = LJ::html_check(
            {
                id    => $checkbox_name,
                class => "InboxItem_Check",
                name  => $checkbox_name,
            }
        );

        # HTML for displaying bookmark flag
        my $bookmark = 'bookmark_' . ( $inbox->is_bookmark($qid) ? "on" : "off" );
        $bookmark = "<a href='$LJ::SITEROOT/inbox/?page=$page&$bookmark=$qid'>"
            . LJ::img( $bookmark, "", { class => 'InboxItem_Bookmark' } ) . "</a>";

        # For clarity, we display both a relative time (e.g. "5 days ago")
        # and an absolute time (e.g. "2019-05-11 14:34 UTC") in the
        # notification list.
        my $event_time    = $inbox_item->when_unixtime;
        my $relative_time = LJ::diff_ago_text($event_time);
        my $absolute_time = LJ::S2::sitescheme_secs_to_iso( $event_time, { tz => "UTC" } );

        my $contents = $inbox_item->as_html || '';

        my $row_class = ( $rownum++ % 2 == 0 ) ? "InboxItem_Meta odd" : "InboxItem_Meta even";

        my $expandbtn   = '';
        my $content_div = '';

        if ($contents) {
            BML::ebml( \$contents );

            my $expanded = $expand && $expand == $qid;
            $expanded ||= $remote->prop('esn_inbox_default_expand');
            $expanded = 0 if $inbox_item->read;

            $expanded = 1 if ( $view eq "usermsg_sent_last" && $i == $starting_index );

            my $expand_img = $expanded ? "inbox_expand" : "inbox_collapse";

            $expandbtn .= qq { <a href="$LJ::SITEROOT/inbox/?page=$page&expand=$qid"> };
            $expandbtn .= LJ::img( $expand_img, '', { class => 'InboxItem_Expand' } );
            $expandbtn .= "</a>\n";

            my $display = $expanded ? "block" : "none";

            $content_div = qq {
                <div class="InboxItem_Content usercontent" style="display: $display;">$contents</div>
                };
        }

        $messagetable .= qq {
            <tr class="InboxItem_Row $row_class" lj_qid="$qid" id="${name}_Row_$qid">
                <td class="checkbox">$checkbox</td>
                <td class="item">
                    <div class="InboxItem_Controls">$bookmark $expandbtn</div>
                    <span class="$read_class" id="${name}_Title_$qid">$title</span>
                    $content_div
                    </td>
                    <td class="time detail">$absolute_time<br>$relative_time</td>
                </tr>
        };
    }

    my $actionnumber = 2;
    $messagetable .= $actionsrow->($actionnumber);

    $messagetable .= '</tbody></table></div>';

    $messagetable .= $markdeleteall->(2);

    $msgs_body .= $messagetable;

    $msgs_body .= LJ::html_hidden(
        {
            name  => "page",
            id    => "pageNum",
            value => $page,
        }
    );

    $msgs_body .= qq {
        </form>
        };

    # JS confirm dialog that appears when a user tries to delete a bookmarked item
    $msgs_body .=
          "<script>ESN_Inbox.confirmDelete = '"
        . $class->ml('widget.inboxfolder.confirm.delete')
        . "';</script>";

    return $msgs_body;
}

1;
