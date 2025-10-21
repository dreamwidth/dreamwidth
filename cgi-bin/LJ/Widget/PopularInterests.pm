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

package LJ::Widget::PopularInterests;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Stats;

sub need_res { qw( stc/widgets/popularinterests.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $remote = LJ::get_remote();
    my $get    = $class->get_args;
    my $body;

    my $rows = LJ::Stats::get_popular_interests();
    @$rows = grep { !$LJ::INTERESTS_KW_FILTER{ $_->[0] } } @$rows;
    my @rand = BML::randlist(@$rows);

    my $num_interests = 20;
    my $max           = ( ( scalar @rand ) < $num_interests ) ? ( scalar @rand ) : $num_interests;

    my %interests;
    foreach my $int_array ( @rand[ 0 .. $max - 1 ] ) {
        my ( $int, $count ) = @$int_array;
        $interests{$int} = {
            int   => $int,
            eint  => LJ::ehtml($int),
            url   => "/interests?int=" . LJ::eurl($int),
            value => $count,
        };
    }

    $body .= "<p>" . LJ::tag_cloud( \%interests, { 'font_size_range' => 16 } ) . "</p>";

    $body .=
          "<p class='viewall'>&raquo; <a href='$LJ::SITEROOT/interests?view=popular'>"
        . $class->ml('widget.popularinterests.viewall')
        . "</a></p>";

    return $body;
}

1;
