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

package LJ::Widget::PageNotice;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/pagenotice.css js/widgets/pagenotice.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret;
    my $remote = LJ::get_remote();
    my $content = LJ::run_hook("page_notice_content", notice_key => $opts{notice_key});

    if ($content) {
        $ret .= $class->html_hidden({ name => "notice_key", value => $opts{notice_key}, id => "notice_key" });
        $ret .= "<div class='warningbar' id='page_notice' style=\"background-image: url('$LJ::IMGPREFIX/message-warning.gif');\">";
        $ret .= $content;
        $ret .= "<img src='$LJ::IMGPREFIX/dismiss-page-notice.gif' id='dismiss_notice' alt=\"" . $class->ml('widget.pagenotice.dismiss') . "\" />"
            if $remote;
        $ret .= "</div>";
    }

    return $ret;
}

sub should_render_for_remote {
    my $class = shift;
    my %opts = @_;

    my $remote = LJ::get_remote();
    my $notice_key = $opts{notice_key};

    return 0 unless $notice_key;
    return 0 unless LJ::run_hook("page_notice_content", notice_key => $notice_key);
    return 1 unless $remote;
    return $remote->has_dismissed_page_notice($notice_key) ? 0 : 1;
}

1;
