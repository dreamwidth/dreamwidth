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

package LJ::Widget::Feeds;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/feeds.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $r      = DW::Request->get;
    my $remote = LJ::get_remote();
    my $get    = $class->get_args;
    my $body;
    $body .= "<h2 class='solid-neutral'>" . $class->ml('widget.feeds.title') . "</h2>";
    $body .= "<a href='$LJ::SITEROOT/feeds/list' class='more-link'>"
        . $class->ml('widget.feeds.viewall') . "</a>";

    # get user IDs of most popular feeds
    my $popsyn = LJ::Feed::get_popular_feed_ids();
    my @rand   = BML::randlist(@$popsyn);

    my $feednum = 10;
    my $max     = ( ( scalar @rand ) < $feednum ) ? ( scalar @rand ) : $feednum;
    $body .= "<div class='feeds-content'>";
    $body .= "<table summary='' class='feeds-table' cellpadding='0' cellspacing='0'>";
    my $odd = 1;
    foreach my $userid ( @rand[ 0 .. $max - 1 ] ) {
        my $u = LJ::load_userid($userid);
        $body .= "<tr>" if ($odd);
        $body .= "<td valign='top' width='50%'>" . $u->ljuser_display . "<br />";
        $body .= "<span class='feeds-title'>" . $u->name_html . "</span></td>";
        $body .= "</tr>" unless ($odd);
        $odd = $odd ? 0 : 1;
    }
    $body .= "<td>&nbsp;</td></tr>" unless ($odd);

    $body .= "</table>";

    # Form to add or find feeds
    if ($remote) {
        $body .= "<form method='post' action='$LJ::SITEROOT/feeds/'>";
        $body .= LJ::html_hidden( 'userid', $remote->userid );
        $body .= "<b>" . $class->ml('widget.feeds.find') . "</b> ";
        my $prompt = $class->ml('widget.feeds.enterRSS');
        $body .= LJ::html_text(
            {
                name      => 'synurl',
                size      => '40',
                maxlength => '255',
                value     => "$prompt",
                onfocus   => "if(this.value=='$prompt')this.value='';",
                onblur    => "if(this.value=='')this.value='$prompt';"
            }
        );
        $body .= " " . LJ::html_submit( "action:addcustom", $class->ml('widget.feeds.btn.add') );
        $body .= "</form>";
    }

    $body .= "</div>";

    return $body;
}

1;
