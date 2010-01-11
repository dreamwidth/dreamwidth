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

package LJ::Widget::RecentComments;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( stc/widgets/recentcomments.css );
}

# args
#   user: optional $u whose recent received comments we should get (remote is default)
#   limit: number of recent comments to show, or 3
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    return "" unless $u;

    my $limit = defined $opts{limit} ? $opts{limit} : 3;

    my @comments = $u->get_recent_talkitems($limit, memcache => 1);

    my $ret;

    $ret .= "<h2><span>" . $class->ml('widget.recentcomments.title') . "</span></h2>";
    $ret .= "<a href='$LJ::SITEROOT/tools/recent_comments' class='more-link'>" . $class->ml('widget.recentcomments.viewall') . "</a>";

    # return if no comments
    return "<h2><span>" . $class->ml('widget.recentcomments.title') . "</span></h2><?warningbar " . $class->ml('widget.recentcomments.nocomments', {'aopts' => "href='$LJ::SITEROOT/update'"}) . " warningbar?>"
        unless @comments && defined $comments[0];

    # there are comments, print them
    @comments = reverse @comments; # reverse the comments so newest is printed first
    $ret .= "<div class='appwidget-recentcomments-content'>";
    my $ct = 0;
    foreach my $row (@comments) {
        next unless $row->{nodetype} eq 'L';

        # load the comment
        my $comment = LJ::Comment->new($u, jtalkid => $row->{jtalkid});
        next if $comment->is_deleted;

        # load the comment poster
        my $posteru = $comment->poster;
        next if $posteru && ($posteru->is_suspended || $posteru->is_expunged);
        my $poster = $posteru ? $posteru->ljuser_display : $class->ml('widget.recentcomments.anon');

        # load the entry the comment was posted to
        my $entry = $comment->entry;
        my $class_name = ($ct == scalar(@comments) - 1) ? "last" : "";

        # print the comment
        $ret .= "<p class='pkg $class_name'>";
        # FIXME: this widget is only used in the portal, I believe.
        # If this code is ever used in the future, uncomment the
        # following line to replace the line that follows it, and then test.
        #$ret .= $entry->imgtag;
        $ret .= $comment->poster_userpic;
        $ret .= $class->ml('widget.recentcomments.commentheading', {'poster' => $poster, 'entry' => "<a href='" . $entry->url . "'>"});
        $ret .= $entry->subject_text ? $entry->subject_text : $class->ml('widget.recentcomments.nosubject');
        $ret .= "</a><br />";
        $ret .= substr($comment->body_text, 0, 250) . "&nbsp;";
        $ret .= "<span class='detail'>(<a href='" . $comment->url . "'>" . $class->ml('widget.recentcomments.link') . "</a>)</span> ";
        $ret .= "<span class='detail'>(<a href='" . $comment->reply_url . "'>" . $class->ml('widget.recentcomments.reply') . "</a>)</span> ";
        $ret .= "</p>";
        $ct++;
    }
    $ret .= "</div>";

    return $ret;
}

1;
