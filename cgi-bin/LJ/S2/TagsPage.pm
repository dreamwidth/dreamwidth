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

use strict;

package LJ::S2;

sub TagsPage {
    my ( $u, $remote, $opts ) = @_;

    my $p = Page( $u, $opts );
    $p->{'_type'} = "TagsPage";
    $p->{'view'}  = "tags";
    $p->{'tags'}  = [];

    my $user        = $u->user;
    my $journalbase = $u->journal_base( vhost => $opts->{'vhost'} );

    if ( $opts->{'pathextra'} ) {
        $opts->{'badargs'} = 1;
        return 1;
    }

    $p->{'head_content'} .= $u->openid_tags;

    if ( $u->should_block_robots ) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    # get tags for the page to display
    my @taglist;
    my $tags = LJ::Tags::get_usertags( $u, { remote => $remote } );
    foreach my $kwid ( keys %{$tags} ) {

        # only show tags for display
        next unless $tags->{$kwid}->{display};
        push @taglist, LJ::S2::TagDetail( $u, $kwid => $tags->{$kwid} );
    }
    @taglist = sort { $a->{name} cmp $b->{name} } @taglist;
    $p->{'_visible_tag_list'} = $p->{'tags'} = \@taglist;

    return $p;
}

1;
