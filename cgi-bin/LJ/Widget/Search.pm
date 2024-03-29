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

package LJ::Widget::Search;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/search.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;
    my $ret;

    my ( $select_box, $search_btn );

    my @search_opts = (
        int          => $class->ml('widget.search.interest'),
        region       => $class->ml('widget.search.region'),
        nav_and_user => $class->ml('widget.search.siteuser'),
        faq          => $class->ml('widget.search.faq'),
        email        => $class->ml('widget.search.email'),
    );

    {
        $select_box =
            LJ::html_select( { name => 'type', selected => 'int', class => 'select' },
            @search_opts )
            . " ";
        $search_btn = LJ::html_submit( $class->ml('widget.search.btn.go') );
    }

    $ret .= "<form action='$LJ::SITEROOT/multisearch' method='post'>\n";
    $ret .= LJ::html_text(
        {
            name  => 'q',
            id    => 'search',
            class => 'text',
            title => $class->ml('widget.search.title'),
            size  => 20
        }
    ) . " ";
    $ret .= $select_box;
    $ret .= $search_btn;
    $ret .= "</form>";

    return $ret;
}

1;
