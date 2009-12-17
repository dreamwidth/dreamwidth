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

package LJ::Widget::SiteMessages;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::SiteMessages;

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    my @messages = LJ::SiteMessages->get_messages;

    $ret .= "<h2>" . $class->ml( "widget.sitemessages.title", { sitename => $LJ::SITENAMESHORT } ) . "</h2>";
    $ret .= "<ul class='nostyle'>";
    foreach my $message (@messages) {
        my $ml_key = $class->ml_key("$message->{mid}.text");
        $ret .= "<li>" . $class->ml($ml_key) . "</li>";
    }
    $ret .= "</ul>";

    return $ret;
}

sub should_render {
    my $class = shift;

    my @messages = LJ::SiteMessages->get_messages;

    return 1 if @messages;
    return 0;
}

1;
