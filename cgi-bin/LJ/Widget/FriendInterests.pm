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

package LJ::Widget::FriendInterests;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( js/widgets/friendinterests.js );
}

sub handle_post {
    my ( $class, $fields ) = @_;

    return unless $fields->{user};
    return unless $fields->{from};

    my $u = LJ::isu($fields->{user}) ? $fields->{user} : LJ::load_user($fields->{user});
    return unless $u;
    my $fromu = LJ::isu($fields->{from}) ? $fields->{from} : LJ::load_user($fields->{from});
    return unless $fromu;

    my $fromints = $fromu->interests;
    return unless keys %$fromints;
    my $sync = $u->sync_interests( $fields, values %$fromints );

    if ( $sync->{toomany} ) {
        my $toomany = $sync->{deleted} ? 'del_and_toomany' : 'toomany';
        die LJ::Lang::ml( "interests.results.$toomany",
                          { intcount => $sync->{toomany} } );
    }

    return;
}

sub render_body {
    my ( $class, %opts ) = @_;
    my $ret;

    return "" unless $opts{user};
    return "" unless $opts{from};

    my $u = LJ::isu($opts{user}) ? $opts{user} : LJ::load_user($opts{user});
    return "" unless $u;
    my $fromu = LJ::isu($opts{from}) ? $opts{from} : LJ::load_user($opts{from});
    return "" unless $fromu;

    my $uints = $u->interests;
    my $fromints = $fromu->interests;

    return "" unless keys %$fromints;
    return "" if $u->id == $fromu->id;

    $ret .= "<div id='friend_interests' class='pkg' style='display: none;'>";
    $ret .= $class->ml('widget.friendinterests.intro', {user => $fromu->ljuser_display});

    $ret .= "<table summary=''>";
    my @fromintsorted = sort keys %$fromints;
    my $cols = 4;
    my $rows = int((scalar(@fromintsorted) + $cols - 1) / $cols);
    for (my $i = 0; $i < $rows; $i++) {
        $ret .= "<tr valign='middle'>";
        for (my $j = 0; $j < $cols; $j++) {
            my $index = $rows * $j + $i;
            if ($index < scalar @fromintsorted) {
                my $friend_interest = $fromintsorted[$index];
                my $checked = $uints->{$friend_interest} ? 1 : undef;
                my $friend_interest_id = $fromints->{$friend_interest};
                $ret .= "<td align='left' nowrap='nowrap'>";
                $ret .= $class->html_check(
                    name     => "int_$friend_interest_id",
                    class    => "check",
                    id       => "int_$friend_interest_id",
                    selected => $checked,
                    value    => 1,
                );
                $ret .= "<label class='right' for='int_$friend_interest_id'>$friend_interest</label></td>";
            } else {
                $ret .= "<td></td>";
            }
        }
        $ret .= "</tr>";
    }
    $ret .= "</table>";
    $ret .= $class->html_hidden( user => $u->user );
    $ret .= $class->html_hidden({ name => "from", id => "from_user", value => $fromu->user });
    $ret .= "</div>";

    return $ret;
}

1;
