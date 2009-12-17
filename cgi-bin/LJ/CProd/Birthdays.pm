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

package LJ::CProd::Birthdays;
use base 'LJ::CProd';

sub applicable {
    my ($class, $u) = @_;
    return 1;
}

sub render {
    my ($class, $u, $version) = @_;
    my $user = LJ::ljuser($u);
    my $icon = "<div style=\"float: left; padding-right: 5px;\">
               <img border=\"1\" src=\"$LJ::SITEROOT/img/cake.jpg\" /></div>";
    my $link = $class->clickthru_link('cprod.birthday.link', $version);

    return "<p>$icon ". BML::ml($class->get_ml($version), { "user" => $user,
                                                            "link" => $link }) . "</p>";
}

sub ml { 'cprod.birthday.text' }
sub link { "$LJ::SITEROOT/birthdays" }
sub button_text { "Birthdays" }

1;
