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

package LJ::Widget::Browse;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/browse.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    my $ret;

    $ret .= "<h2>" . $class->ml('widget.browse.title', { sitenameabbrev => $LJ::SITENAMEABBREV }) . "</h2>";
    $ret .= "<div class='browse-content'>";
    $ret .= LJ::Widget::Search->render( stylesheet_override => "stc/widgets/search-interestonly.css", single_search => "interest" );

    $ret .= LJ::Widget::PopularInterests->render;

    $ret .= "<div class='browse-findlinks'>";

    $ret .= "<div class='browse-findby'>";
    $ret .= "<p><strong>" . $class->ml('widget.browse.findusers') . "</strong><br />";
    $ret .= "&raquo; <a href='$LJ::SITEROOT/directory'>" . $class->ml('widget.browse.findusers.location') . "</a></p>";
    $ret .= "</div>";

    $ret .= "<div class='browse-directorysearch'>";
    $ret .= "<p><strong>" . $class->ml('widget.browse.directorysearch') . "</strong><br />";
    $ret .= "&raquo; <a href='$LJ::SITEROOT/directorysearch'>" . $class->ml('widget.browse.directorysearch.users') . "</a><br />";
    $ret .= "&raquo; <a href='$LJ::SITEROOT/community/search'>" . $class->ml('widget.browse.directorysearch.communities') . "</a></p>";
    $ret .= "</div>";

    $ret .= "</div>";

    $ret .= "<div style='clear: both;'></div>";
    $ret .= "<div class='browse-extras'>";
    $ret .= "<div class='browse-randomuser'>";
    $ret .= "<img src='$LJ::IMGPREFIX/explore/randomuser.jpg' alt='' />";
    $ret .= "<p><a href='$LJ::SITEROOT/random'><strong>" . $class->ml('widget.browse.extras.random') . "</strong></a><br />";
    $ret .= $class->ml('widget.browse.extras.random.desc') . "</p>";
    $ret .= "</div>";
    $ret .= LJ::Hooks::run_hook('browse_widget_extras');
    $ret .= "</div>";

    $ret .= "</div>";
    return $ret;
}

1;
