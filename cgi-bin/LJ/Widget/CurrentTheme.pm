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
use DW::Template;

sub ajax     { 1 }
sub authas   { 1 }
sub need_res { qw( stc/widgets/currenttheme.css ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;
    $opts{show} ||= 0;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote   = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";

    my $showarg = $opts{show} != 12 ? "&show=$opts{show}" : "";
    my $no_theme_chooser = defined $opts{no_theme_chooser} ? $opts{no_theme_chooser} : 0;
    my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

    my $theme = LJ::Customize->get_current_theme($u);

    my $vars = {
        theme            => $theme,
        layout_name      => $theme->layout_name,
        designer         => $theme->designer,
        getextra         => $getextra,
        no_theme_chooser => $no_theme_chooser,
        no_layer_edit    => $no_layer_edit,
        getsep           => $getsep,
        showarg          => $showarg,
        u                => $u
    };

    return DW::Template->template_string( 'widget/currenttheme.tt', $vars );
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
