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

package LJ::Widget::LayoutChooser;

use strict;
use warnings;
use base qw(LJ::Widget);
use Carp qw(croak carp);
use LJ::Customize;

sub ajax { 1 }
sub authas { 1 }
sub need_res { qw( stc/widgets/layoutchooser.css ) }
sub need_res_opts { priority => $LJ::OLD_RES_PRIORITY }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $no_theme_chooser = defined $opts{no_theme_chooser} ? $opts{no_theme_chooser} : 0;

    my $headextra = $opts{headextra};

    my $ret;
    $ret .= "<h2 class='widget-header'>";
    $ret .= $no_theme_chooser ? $class->ml('widget.layoutchooser.title_nonum') : $class->ml('widget.layoutchooser.title');
    $ret .= "</h2>";
    $ret .= "<ul class='layout-content select-list'>";

    my $styleid = $opts{styleid} && $opts{styleid} =~ /[0-9]+/ ? $opts{styleid} : $u->prop( 's2_style' );

    # Column option
    my $current_theme = LJ::Customize->get_current_theme( $u, $styleid );
    my %layouts = $current_theme->layouts;
    my $layout_prop = $current_theme->layout_prop;
    my $show_sidebar_prop = $current_theme->show_sidebar_prop;
    my %layout_names = LJ::Customize->get_layouts;

    my $prop_value;
    if ($layout_prop || $show_sidebar_prop) {
        my $style = LJ::S2::load_style( $styleid );

        if ($layout_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values($layout_prop, $u, $style);
            $prop_value = $prop_values{override};
        }

        # for layouts that have a separate prop that turns off the sidebar, use the value of that
        # prop instead if the sidebar is set to be off (false/0).
        if ($show_sidebar_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values($show_sidebar_prop, $u, $style);
            $prop_value = $prop_values{override} if $prop_values{override} == 0;
        }
    }

    unless (!$current_theme->is_system_layout) {
        foreach my $layout (sort keys %layouts) {
            my $current = (!$layout_prop) || ($layout_prop && $layouts{$layout} eq $prop_value) ? 1 : 0;
            my $current_class = $current ? " selected" : "";

            $ret .= "<li class='layout-item$current_class'>";
            $ret .= "<img src='$LJ::IMGPREFIX/customize/layouts/$layout.png' class='layout-preview' />";
            $ret .= "<p class='layout-desc'>$layout_names{$layout}</p>";
            unless ($current) {
                $ret .= $class->start_form( class => "layout-form" );
                $ret .= $class->html_hidden(
                    layout_choice => $layout,
                    layout_prop => $layout_prop,
                    show_sidebar_prop => $show_sidebar_prop,
                    styleid => $styleid,
                );
                $ret .= $class->html_submit(
                    apply => $class->ml('widget.layoutchooser.layout.apply'),
                    { raw => "class='layout-button' id='layout_btn_$layout'" },
                );
                $ret .= $class->end_form;
            }
            $ret .= "</li><!-- end .theme-item -->";
        }
    }

    $ret .= "</ul>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my %override;
    my $layout_choice = $post->{layout_choice};
    my $layout_prop = $post->{layout_prop};
    my $show_sidebar_prop = $post->{show_sidebar_prop};
    my $current_theme = LJ::Customize->get_current_theme($u);
    my %layouts = $current_theme->layouts;

    # show_sidebar prop is set to false/0 if the 1 column layout was chosen,
    # otherwise it's set to true/1 and the layout prop is set appropriately.
    if ($show_sidebar_prop && $layout_choice eq "1") {
        $override{$show_sidebar_prop} = 0;
    } else {
        $override{$show_sidebar_prop} = 1 if $show_sidebar_prop;
        $override{$layout_prop} = $layouts{$layout_choice} if $layout_prop;
    }

    my $styleid = $post->{styleid} && $post->{styleid} =~ /[0-9]+/ ? $post->{styleid} : undef;
    my $style = LJ::S2::load_style( $styleid );

    die "Style not found." unless $style && $style->{userid} == $u->id;

    LJ::Customize->save_s2_props($u, $style, \%override);

    return;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            var apply_forms = DOM.getElementsByClassName(document, "layout-form");

            // add event listeners to all of the apply layout forms
            apply_forms.forEach(function (form) {
                DOM.addEventListener(form, "submit", function (evt) { self.applyLayout(evt, form) });
            });

            if ( ! self._init ) {
                LiveJournal.register_hook( "update_other_widgets", function( updated ) { self.refreshLayoutChoices.apply( self, [ updated ] ) } )
                self._init = true;
            }
        },
        applyLayout: function (evt, form) {
            var given_layout_choice = form["Widget[LayoutChooser]_layout_choice"].value + "";
            $("layout_btn_" + given_layout_choice).disabled = true;
            DOM.addClassName($("layout_btn_" + given_layout_choice), "layout-button-disabled disabled");

            this.doPostAndUpdateContent({
                layout_choice: given_layout_choice,
                layout_prop: form["Widget[LayoutChooser]_layout_prop"].value + "",
                styleid: form["Widget[LayoutChooser]_styleid"].value,
                show_sidebar_prop: form["Widget[LayoutChooser]_show_sidebar_prop"].value
            });

            Event.stop(evt);
        },
        onData: function (data) {
            LiveJournal.run_hook("update_other_widgets", "LayoutChooser");
        },
        onRefresh: function (data) {
            this.initWidget();
        },
        refreshLayoutChoices: function( updatedWidget ) {
            if ( updatedWidget == "ThemeChooser" ) {
                this.updateContent();
            }
        }
    ];
}

1;
