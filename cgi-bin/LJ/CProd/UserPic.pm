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

package LJ::CProd::UserPic;
use base 'LJ::CProd';
use strict;

sub applicable {
    my ($class, $u) = @_;
    return 0 if $u->{defaultpicid};
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $ml_key = $class->get_ml($version);
    my $link = $class->clickthru_link('cprod.userpic.link', $version);
    my $user = LJ::ljuser($u);
    my $empty = '<div style="overflow: hidden; padding: 5px; width: 100px;
height: 100px; border: 1px solid #000000;">&nbsp;</div>';

    return BML::ml($ml_key, { "user" => $user,
                                          "link" => $link,
                                          "empty" => $empty });
}

sub ml { 'cprod.userpic.text' }
sub link { "$LJ::SITEROOT/editicons" }
sub button_text { "Userpic" }

1;
