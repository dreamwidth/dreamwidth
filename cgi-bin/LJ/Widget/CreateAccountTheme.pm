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

package LJ::Widget::CreateAccountTheme;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;

sub need_res { qw( stc/widgets/createaccounttheme.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u             = LJ::get_effective_remote();
    my $current_theme = LJ::Customize->get_current_theme($u);

    my $ret;
    $ret .= "<h2>" . $class->ml('widget.createaccounttheme.title') . "</h2>";
    $ret .= "<p>" . $class->ml('widget.createaccounttheme.info') . "</p>";

    my $count = 0;
    $ret .= "<table summary='' cellspacing='3' cellpadding='0' align='center'>\n";
    foreach my $uniq (@LJ::CREATE_ACCOUNT_THEMES) {
        my $theme       = LJ::S2Theme->load_by_uniq($uniq);
        my $image_class = $theme->uniq;
        $image_class =~ s/\//_/;
        my $name = $theme->name . ", " . $theme->layout_name;

        my @checked;
        @checked = ( checked => "checked" ) if $current_theme->uniq eq $uniq;

        $ret .= "<tr>" if $count % 3 == 0;
        $ret .= "<td class='theme-box'>";
        $ret .= "<div class='theme-box-inner'>";
        $ret .=
              "<label for='theme_$image_class'><img src='"
            . $theme->preview_imgurl
            . "' width='90' height='68' class='theme-image' alt='$name' title='$name' /></label><br />";
        $ret .=
              "<a href='$LJ::SITEROOT/customize/preview_redirect?themeid="
            . $theme->themeid
            . "' target='_blank' onclick='window.open(href, \"theme_preview\", \"resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes\"); return false;' class='theme-preview-link' title='"
            . $class->ml('widget.createaccounttheme.preview') . "'>";
        $ret .=
"<img src='$LJ::IMGPREFIX/customize/preview-theme.gif' class='theme-preview-image' /></a>";
        $ret .= $class->html_check(
            name  => 'theme',
            id    => "theme_$image_class",
            type  => 'radio',
            value => $uniq,
            style => "margin-bottom: 5px;",
            @checked,
        );
        $ret .= "</div>";
        $ret .= "</td>";
        $ret .= "</tr>" if $count % 3 == 2;

        $count++;
    }
    $ret .= "</table>\n";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $u = LJ::get_effective_remote();

    if ( $post->{theme} ) {
        my $theme = LJ::S2Theme->load_by_uniq( $post->{theme} );
        die "Invalid theme selection" unless $theme;

        LJ::Customize->apply_theme( $u, $theme );
    }

    return;
}

1;
