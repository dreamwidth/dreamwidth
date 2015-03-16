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

package LJ::Widget::CurrentTheme;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;

sub ajax { 1 }
sub authas { 1 }
sub need_res { qw( stc/widgets/currenttheme.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;
    $opts{show} ||= 0;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";

    my $showarg = $opts{show} != 12 ? "&show=$opts{show}" : "";
    my $no_theme_chooser = defined $opts{no_theme_chooser} ? $opts{no_theme_chooser} : 0;
    my $no_layer_edit = LJ::Hooks::run_hook("no_theme_or_layer_edit", $u);

    my $theme = LJ::Customize->get_current_theme($u);
    my $userlay = LJ::S2::get_layers_of_user($u);
    my $layout_name = $theme->layout_name;
    my $designer = $theme->designer;

    my $ret;
    $ret .= "<div class='highlight-box'><h2 class='widget-header'><span>" . $class->ml('widget.currenttheme.title', {'user' => $u->ljuser_display}) . "</span></h2>";
    $ret .= "<div class='theme-current-content pkg'>";
    $ret .= "<img src='" . $theme->preview_imgurl . "' class='theme-current-image preview-image' />";
    $ret .= "<h3>" . $theme->name . "</h3>";

    my $layout_link = "<a href='$LJ::SITEROOT/customize/$getextra${getsep}layoutid=" . $theme->layoutid . "$showarg' class='theme-current-layout'><em>$layout_name</em></a>";
    my $special_link_opts = "href='$LJ::SITEROOT/customize/$getextra${getsep}cat=special$showarg' class='theme-current-cat'";
    $ret .= "<p class='theme-current-desc'>";
    if ($designer) {
        my $designer_link = "<a href='$LJ::SITEROOT/customize/$getextra${getsep}designer=" . LJ::eurl($designer) . "$showarg' class='theme-current-designer'>$designer</a>";
        $ret .= $class->ml('widget.currenttheme.designer', {'designer' => $designer_link});
        if (LJ::Hooks::run_hook("layer_is_special", $theme->uniq)) {
            $ret .= " " . $class->ml('widget.currenttheme.specialdesc2', {'aopts' => $special_link_opts});
        } else {
            $ret .= " " . $class->ml('widget.currenttheme.desc2', {'style' => $layout_link});
        }
    } elsif ($layout_name) {
        $ret .= $class->ml('widget.currenttheme.desc2', {'style' => $layout_link});
    }
    $ret .= "</p>";

    $ret .= "<div class='theme-current-links inset-box'>";
    $ret .= $class->ml('widget.currenttheme.options');
    $ret .= "<ul class='nostyle'>";
    if ($no_theme_chooser) {
        $ret .= "<li><a href='$LJ::SITEROOT/customize/$getextra'>" . $class->ml('widget.currenttheme.options.newtheme') . "</a></li>";
    } else {
        $ret .= "<li><a href='$LJ::SITEROOT/customize/options$getextra'>" . $class->ml('widget.currenttheme.options.change') . "</a></li>";
    }
    if (! $no_layer_edit ) {
        $ret .= "<li><a href='$LJ::SITEROOT/customize/advanced/'>" . $class->ml( 'widget.currenttheme.options.advancedcust' ) . "</a></li>";
        if ($theme->layoutid && !$theme->layout_uniq) {
            $ret .= "<li><a href='$LJ::SITEROOT/customize/advanced/layeredit?id=" . $theme->layoutid . "'>" . $class->ml('widget.currenttheme.options.editlayoutlayer') . "</a></li>";
        }
        if ($theme->themeid && !$theme->uniq) {
            $ret .= "<li><a href='$LJ::SITEROOT/customize/advanced/layeredit?id=" . $theme->themeid . "'>" . $class->ml('widget.currenttheme.options.editthemelayer') . "</a></li>";
        }
    }
    if ($no_theme_chooser) {
        $ret .= "<li><a href='$LJ::SITEROOT/customize/options$getextra#layout'>" . $class->ml('widget.currenttheme.options.layout') . "</a></li>";
    } else {
        $ret .= "<li><a href='$LJ::SITEROOT/customize/$getextra#layout'>" . $class->ml('widget.currenttheme.options.layout') . "</a></li>";
    }

    $ret .= "</ul>";
    $ret .= "</div><!-- end .theme-current-links -->";
    $ret .= "</div><!-- end .theme-current-content -->";
    $ret .= "</div>";

    return $ret;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            var filter_links = DOM.getElementsByClassName(document, "theme-current-cat");
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-current-layout"));
            filter_links = filter_links.concat(DOM.getElementsByClassName(document, "theme-current-designer"));

            // add event listeners to all of the category, layout, and designer links
            filter_links.forEach(function (filter_link) {
                var getArgs = LiveJournal.parseGetArgs(filter_link.href);
                for (var arg in getArgs) {
                    if (!getArgs.hasOwnProperty(arg)) continue;
                    if (arg == "authas" || arg == "show") continue;
                    DOM.addEventListener(filter_link, "click", function (evt) { Customize.ThemeNav.filterThemes(evt, arg, getArgs[arg]) });
                    break;
                }
            });
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
