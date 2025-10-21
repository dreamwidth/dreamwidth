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

package LJ::Widget::FriendBirthdays;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( stc/widgets/friendbirthdays.css );
}

# args
#   user: optional $u whose friend birthdays we should get (remote is default)
#   limit: optional max number of birthdays to show; default is 5
sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $opts{user} && LJ::isu( $opts{user} ) ? $opts{user} : LJ::get_remote();
    return "" unless $u;

    my $limit = defined $opts{limit} ? $opts{limit} : 5;

    my @bdays = $u->get_birthdays( months_ahead => 1 );
    @bdays = @bdays[ 0 .. $limit - 1 ]
        if @bdays > $limit;

    return "" unless @bdays;

    my $ret;
    $ret .= "<h2><span>" . $class->ml('widget.friendbirthdays.title') . "</span></h2>";
    $ret .=
          "<a href='$LJ::SITEROOT/birthdays' class='more-link'>"
        . $class->ml('widget.friendbirthdays.viewall')
        . "</a></p>";
    $ret .= "<div class='indent_sm'><table summary=''>";

    foreach my $bday (@bdays) {
        my $u     = LJ::load_user( $bday->[2] );
        my $month = $bday->[0];
        my $day   = $bday->[1];
        next unless $u && $month && $day;

        # remove leading zero on day
        $day =~ s/^0//;

        $ret .= "<tr>";
        $ret .= "<td>" . $u->ljuser_display . "</td>";
        $ret .= "<td>"
            . $class->ml( 'widget.friendbirthdays.userbirthday',
            { 'month' => LJ::Lang::month_short($month), 'day' => $day } )
            . "</td>";
        $ret .= "<td><a href='" . $u->gift_url . "' class='gift-link'>";
        $ret .= $class->ml('widget.friendbirthdays.gift') . "</a></td>";
        $ret .= "</tr>";
    }

    $ret .= "</table></div>";

    $ret .=
          "<p class='indent_sm'>&raquo; <a href='$LJ::SITEROOT/birthdays'>"
        . $class->ml('widget.friendbirthdays.friends_link')
        . "</a></p>"
        if $opts{friends_link};

    return $ret;
}

1;
