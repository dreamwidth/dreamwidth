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

package LJ::CProd::Polls;
use base 'LJ::CProd';
use strict;

sub applicable {
    my ($class, $u) = @_;
    return 0 unless $u->can_create_polls;
    my $dbcr = LJ::get_cluster_reader( $u )
        or return 0;
    my $used_polls = $dbcr->selectrow_array( "SELECT pollid FROM poll2 WHERE posterid=?",
                                             undef, $u->userid );
    return $used_polls ? 0 : 1;
}

sub link { "$LJ::SITEROOT/poll/create" }
sub button_text { "Poll wizard" }
sub ml { 'cprod.polls.text' }

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $link = $class->clickthru_link('cprod.polls.link', $version);
    my $lbar = LJ::img( 'poll_left',  '', { style => 'vertical-align:middle' } );
    my $rbar = LJ::img( 'poll_right', '', { style => 'vertical-align:middle' } );

    my $poll = "
<div style='margin: 2px'>
<div>That's crazy!</div><div style='white-space: nowrap'>
$lbar <img src='$LJ::IMGPREFIX/poll/mainbar.gif'
 style='vertical-align:middle' height='14' width='174' alt='' />
$rbar <b>283</b> (58.0%)</div>
<div>I can't wait to try.</div><div style='white-space: nowrap'>
$lbar <img src='$LJ::IMGPREFIX/poll/mainbar.gif'
 style='vertical-align:middle' height='14' width='81' alt='' />
$rbar <b>132</b> (27.0%)</div>
<div>What type of poll am I?</div><div style='white-space: nowrap'>
$lbar <img src='$LJ::IMGPREFIX/poll/mainbar.gif'
 style='vertical-align:middle' height='14' width='45' alt='' />
$rbar <b>73</b> (15.0%)</div>
</div>";

    return BML::ml($class->get_ml($version), { "user" => $user, "link" => $link, "poll" => $poll });
}

1;
