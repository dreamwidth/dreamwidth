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

package LJ::CProd::FriendsFriends;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 0 unless $u->can_use_network_page;
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);

    my $icon = "<img border=\"0\" src=\"$LJ::SITEROOT/img/friendgroup.gif\" class='cprod-image'  />";
    my $link = $class->clickthru_link('cprod.friendsfriends.link2', $version);

    return "$icon ".BML::ml($class->get_ml($version), { "user" => $user, "link" => $link });

}

sub ml { 'cprod.friendsfriends.text2' }
sub link {
    my $remote = LJ::get_remote()
        or return "$LJ::SITEROOT/login";
    return $remote->friendsfriends_url . "/";
}
sub button_text { "Friends of Friends" }

1;
