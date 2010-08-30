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

package LJ::CProd::ControlStrip;
use base 'LJ::CProd';
use strict;

sub applicable {
    my ($class, $u) = @_;
    return 0 if defined $u->control_strip_display;

    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $link = $class->clickthru_link('cprod.controlstrip.link', $version);

    return "<p>".BML::ml($class->get_ml($version), { "link" => $link }) . "</p>";

}

sub ml { 'cprod.controlstrip.text' }
sub link { "$LJ::SITEROOT/manage/settings/" }
sub button_text { "Navigation strip" }

1;
