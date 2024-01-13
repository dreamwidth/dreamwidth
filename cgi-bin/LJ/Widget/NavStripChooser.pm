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

package LJ::Widget::NavStripChooser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;

sub ajax     { 1 }
sub authas   { 1 }
sub need_res { qw( stc/widgets/navstripchooser.css stc/coloris.css js/vendor/coloris.js  ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $chosen_color   = $u->prop('control_strip_color') // '';
    my $color_selected = $chosen_color ne '' ? $chosen_color : "dark";

    my $theme        = LJ::Customize->get_current_theme($u);
    my @props        = S2::get_properties( $theme->layoutid );
    my %prop_is_used = map { $_ => 1 } @props;

    my $style = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;

    my %colors_values =
        LJ::Customize->get_s2_prop_values( "custom_control_strip_colors", $u, $style );
    my %bgcolor_values = LJ::Customize->get_s2_prop_values( "control_strip_bgcolor", $u, $style );
    my %fgcolor_values = LJ::Customize->get_s2_prop_values( "control_strip_fgcolor", $u, $style );
    my %bordercolor_values =
        LJ::Customize->get_s2_prop_values( "control_strip_bordercolor", $u, $style );
    my %linkcolor_values =
        LJ::Customize->get_s2_prop_values( "control_strip_linkcolor", $u, $style );

    my $color_custom = 0;

    unless ( $colors_values{override} eq "off" ) {
        $color_custom = 1;
    }

    my $vars = {
        color_selected => $color_selected,
        color_custom   => $color_custom,
        help_icon      => \&LJ::help_icon
    };

    if ( $prop_is_used{custom_control_strip_colors} ) {
        my $no_gradient = $colors_values{override} eq "on_no_gradient" ? 1 : 0;

        my $custom_colors = [];
        foreach my $prop (@props) {
            $prop = S2::get_property( $theme->coreid, $prop )
                unless ref $prop;
            next unless ref $prop;

            my $prop_name = $prop->{name};

            next
                unless $prop_name eq "control_strip_bgcolor"
                || $prop_name eq "control_strip_fgcolor"
                || $prop_name eq "control_strip_bordercolor"
                || $prop_name eq "control_strip_linkcolor";

            my $override = "";
            $override =
                $prop_name eq "control_strip_bgcolor" ? $bgcolor_values{override} : $override;
            $override =
                $prop_name eq "control_strip_fgcolor" ? $fgcolor_values{override} : $override;
            $override =
                  $prop_name eq "control_strip_bordercolor"
                ? $bordercolor_values{override}
                : $override;
            $override =
                $prop_name eq "control_strip_linkcolor" ? $linkcolor_values{override} : $override;

            my $des = $class->ml("widget.navstripchooser.option.color.${prop_name}");

            my $custom_color = {
                name    => $prop_name,
                default => $override,
                des     => $des,
            };
            push $custom_colors, $custom_color;
        }
        $vars->{no_gradient}   = $no_gradient;
        $vars->{custom_colors} = $custom_colors;
    }

    return DW::Template->template_string( 'widget/navstripchooser.tt', $vars );
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my %override;
    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    my ( $given_control_strip_color, $props, $given_control_strip_custom );

    if ( $post_fields_of_parent->{reset} ) {

        my $style = LJ::S2::load_style( $u->prop('s2_style') );
        die "Style not found." unless $style && $style->{userid} == $u->id;
        LJ::Customize->save_s2_props( $u, $style, \%$post, reset => 1 );

    }
    else {
        $given_control_strip_color  = $post->{control_strip_color};
        $given_control_strip_custom = $post->{control_strip_custom};
    }

    # we only want to store dark or light in the user props
    $props->{control_strip_color} = $given_control_strip_color;

    $u->set_prop( 'control_strip_color', $props->{control_strip_color} );

    if ( $given_control_strip_custom ne "custom" ) {
        $override{custom_control_strip_colors} = "off";
    }
    else {
        if ( $given_control_strip_custom eq "custom" ) {
            if ( $post->{control_strip_no_gradient_custom} ) {
                $override{custom_control_strip_colors} = "on_no_gradient";
            }
            else {
                $override{custom_control_strip_colors} = "on_gradient";
            }

            $override{control_strip_bgcolor}     = $post->{control_strip_bgcolor}     || "";
            $override{control_strip_fgcolor}     = $post->{control_strip_fgcolor}     || "";
            $override{control_strip_bordercolor} = $post->{control_strip_bordercolor} || "";
            $override{control_strip_linkcolor}   = $post->{control_strip_linkcolor}   || "";
        }
    }

    if ( $u->prop('stylesys') == 2 ) {
        my $style = LJ::S2::load_style( $u->prop('s2_style') );
        die "Style not found." unless $style && $style->{userid} == $u->id;
        LJ::Customize->save_s2_props( $u, $style, \%override );
    }

    return;
}

sub should_render { 1 }

sub js {
    q [
        initWidget: function () {
            var self = this;

            if (!$('control_strip_color_custom')) return;

            self.hideSubDivs();
            if ($('control_strip_color_custom').checked) this.showSubDiv("custom_subdiv");

            DOM.addEventListener($('control_strip_color_dark'), "click", function (evt) { self.hideSubDivs() });
            DOM.addEventListener($('control_strip_color_light'), "click", function (evt) { self.hideSubDivs() });
            DOM.addEventListener($('control_strip_color_custom'), "click", function (evt) { self.showSubDiv() });
        },
        hideSubDivs: function () {
            $('custom_subdiv').style.display = "none";
        },
        showSubDiv: function () {
            $('custom_subdiv').style.display = "block";
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
