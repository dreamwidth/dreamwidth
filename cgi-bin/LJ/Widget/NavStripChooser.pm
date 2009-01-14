package LJ::Widget::NavStripChooser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Customize );

sub ajax { 1 }
sub authas { 1 }
sub need_res { qw( stc/widgets/navstripchooser.css js/colorpicker.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $preview_moodthemeid = defined $opts{preview_moodthemeid} ? $opts{preview_moodthemeid} : $u->{moodthemeid};

    my $ret = "<fieldset><legend>" . $class->ml('widget.navstripchooser.title') . "</legend>";
    $ret .= "</fieldset>" if $u->prop('stylesys') == 2;
    $ret .= "<p class='detail'>" . $class->ml('widget.navstripchooser.desc') . " " . LJ::help_icon('navstrip') . "</p>";

    # choose where to display/see it
    my $show_checked = $u->prop('show_control_strip') ? 1 : 0;
    my $view_checked = $u->prop('view_control_strip') ? 1 : 0;
    
    # If user cannot modify navstrip, the following two checkboxes should be disabled
    my $show_disabled = LJ::run_hook('user_cannot_modify_navstrip', $u);

    $ret .= "<p>" . $class->html_check(
        name => "show_control_strip",
        id => "show_control_strip",
        selected => $show_checked,
        disabled => defined $show_disabled ? $show_disabled : 0,
    );
    $ret .= " <label for='show_control_strip'>" . $class->ml('widget.navstripchooser.option.onjournal') . "</label></p>";

    $ret .= "<p>" . $class->html_check(
        name => "view_control_strip",
        id => "view_control_strip",
        selected => $view_checked,
        disabled => defined $show_disabled ? $show_disabled : 0,
    );
    $ret .= " <label for='view_control_strip'>" . $class->ml('widget.navstripchooser.option.onothers') . "</label></p>";

    # if checkbox disabled, it cannot submit it's value, even if it's checked.
    # if we want this data in submit, we must to use hidden input in this case.
    if ($show_disabled) {
        if ($view_checked) {
            $ret .= LJ::html_hidden({
                'name' => 'Widget[NavStripChooser]_view_control_strip',
                value => "1",
                'id' => "view_control_strip" });
        }

        if ($show_checked) {
            $ret .= LJ::html_hidden({
                'name' => 'Widget[NavStripChooser]_show_control_strip',
                value => "1",
                'id' => "show_control_strip" });
        }
    }

    $ret .= "<p>" . $class->ml('widget.navstripchooser.colors') . "</p>";

    # choose colors

    # note: if both props have colors, they are guaranteed to be the same color
    my $color_selected = "dark";
    if ($u->prop('view_control_strip') && $u->prop('view_control_strip') ne "off_explicit") {
        $color_selected = $u->prop('view_control_strip');
    } elsif ($u->prop('show_control_strip') && $u->prop('show_control_strip') ne "off_explicit") {
        $color_selected = $u->prop('show_control_strip');
    }

    my ($theme, @props, %prop_is_used, %colors_values, %bgcolor_values, %fgcolor_values, %bordercolor_values, %linkcolor_values);
    if ($u->prop('stylesys') == 2) {
        $theme = LJ::Customize->get_current_theme($u);
        @props = S2::get_properties($theme->layoutid);
        %prop_is_used = map { $_ => 1 } @props;

        my $style = LJ::S2::load_style($u->prop('s2_style'));
        die "Style not found." unless $style && $style->{userid} == $u->id;

        %colors_values = LJ::Customize->get_s2_prop_values("custom_control_strip_colors", $u, $style);
        %bgcolor_values = LJ::Customize->get_s2_prop_values("control_strip_bgcolor", $u, $style);
        %fgcolor_values = LJ::Customize->get_s2_prop_values("control_strip_fgcolor", $u, $style);
        %bordercolor_values = LJ::Customize->get_s2_prop_values("control_strip_bordercolor", $u, $style);
        %linkcolor_values = LJ::Customize->get_s2_prop_values("control_strip_linkcolor", $u, $style);

        unless ($colors_values{override} eq "off") {
            $color_selected = "layout_default";
            unless ($bgcolor_values{override} eq "" && $fgcolor_values{override} eq "" &&
                    $bordercolor_values{override} eq "" && $linkcolor_values{override} eq "") {
                $color_selected = "custom";
            }
        }
    }

    $ret .= "<table>";
    $ret .= "<tr><td valign='top'>" . $class->html_check(
        type => "radio",
        name => "control_strip_color",
        id => "control_strip_color_dark",
        value => "dark",
        selected => $color_selected eq "dark" ? 1 : 0,
    ) . "</td>";
    $ret .= "<td><label for='control_strip_color_dark' class='color-dark'><strong>" . $class->ml('widget.navstripchooser.option.color.dark') . "</strong></label></td></tr>";

    $ret .= "<tr><td valign='top'>" . $class->html_check(
        type => "radio",
        name => "control_strip_color",
        id => "control_strip_color_light",
        value => "light", 
        selected => $color_selected eq "light" ? 1 : 0,
    ) . "</td>";
    $ret .= "<td><label for='control_strip_color_light' class='color-light'><strong>" . $class->ml('widget.navstripchooser.option.color.light') . "</strong></label></td></tr>";

    if ($u->prop('stylesys') == 2 && $prop_is_used{custom_control_strip_colors}) {
        my $no_gradient = $colors_values{override} eq "on_no_gradient" ? 1 : 0;

        $ret .= "<tr><td valign='top'>" . $class->html_check(
            type => "radio",
            name => "control_strip_color",
            id => "control_strip_color_layout_default",
            value => "layout_default",
            selected => $color_selected eq "layout_default" ? 1 : 0,
        ) . "</td>";
        $ret .= "<td><label for='control_strip_color_layout_default'><strong>" . $class->ml('widget.navstripchooser.option.color.layout_default') . "</strong></label><br />";

        $ret .= "<div id='layout_default_subdiv'>";
        $ret .= $class->html_check(
            name => "control_strip_no_gradient_default",
            id => "control_strip_gradient_default",
            selected => $no_gradient,
        );
        $ret .= " <label for='control_strip_gradient_default'>" . $class->ml('widget.navstripchooser.option.color.no_gradient') . "</label></td></tr>";
        $ret .= "</div>";

        $ret .= "<tr><td valign='top'>" . $class->html_check(
            type => "radio",
            name => "control_strip_color",
            id => "control_strip_color_custom",
            value => "custom",
            selected => $color_selected eq "custom" ? 1 : 0,
        ) . "</td>";
        $ret .= "<td><label for='control_strip_color_custom'><strong>" . $class->ml('widget.navstripchooser.option.color.custom') . "</strong></label><br />";

        $ret .= "<div id='custom_subdiv'>";
        $ret .= $class->html_check(
            name => "control_strip_no_gradient_custom",
            id => "control_strip_gradient_custom",
            selected => $no_gradient,
        );
        $ret .= " <label for='control_strip_gradient_custom'>" . $class->ml('widget.navstripchooser.option.color.no_gradient') . "</label><br />";

        my $count = 0;
        $ret .= "<table class='color-picker'>";
        foreach my $prop (@props) {
            $prop = S2::get_property($theme->coreid, $prop)
                unless ref $prop;
            next unless ref $prop;

            my $prop_name = $prop->{name};

            next unless $prop_name eq "control_strip_bgcolor" || $prop_name eq "control_strip_fgcolor" ||
                $prop_name eq "control_strip_bordercolor" || $prop_name eq "control_strip_linkcolor";

            my $override = "";
            $override = $prop_name eq "control_strip_bgcolor" ? $bgcolor_values{override} : $override;
            $override = $prop_name eq "control_strip_fgcolor" ? $fgcolor_values{override} : $override;
            $override = $prop_name eq "control_strip_bordercolor" ? $bordercolor_values{override} : $override;
            $override = $prop_name eq "control_strip_linkcolor" ? $linkcolor_values{override} : $override;

            my $des = $class->ml("widget.navstripchooser.option.color.${prop_name}");

            $ret .= "<tr valign='top'>" if $count % 2 == 0;
            $ret .= "<td>$des</td>";
            $ret .= "<td>" . $class->html_color(
                name => $prop_name,
                default => $override,
                des => $prop->{des},
                no_btn => 1,
            ) . "</td>";
            $ret .= "</tr>" if $count % 2 == 1;
            $count++;
        }
        $ret .= "</table></td></tr>";
        $ret .= "</div>";
    }
    $ret .= "</table>";

    if ($u->prop('stylesys') != 2) {
        $ret .= "<p>" . $class->ml('widget.navstripchooser.upgradetos2', {'aopts' => "href='$LJ::SITEROOT/customize/switch_system.bml'"}) . "</p>";
        $ret .= "</fieldset>";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my %override;
    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    my ($given_control_strip_color, $given_show_control_strip, $given_view_control_strip);
    if ($post_fields_of_parent->{reset}) {
        $given_control_strip_color = "dark";
        $given_show_control_strip = 1;
        $given_view_control_strip = 1;
        $override{control_strip_bgcolor} = "";
        $override{control_strip_fgcolor} = "";
        $override{control_strip_bordercolor} = "";
        $override{control_strip_linkcolor} = "";
    } else {
        $given_control_strip_color = $post->{control_strip_color};
        $given_show_control_strip = $post->{show_control_strip};
        $given_view_control_strip = $post->{view_control_strip};
    }

    my $color = $given_control_strip_color || "dark";
    my $color_to_store = $color eq "light" ? "light" : "dark"; # we can only store dark or light in the user props

    my $props;
    $props->{show_control_strip} = $given_show_control_strip ? $color_to_store : 'off_explicit';
    $props->{view_control_strip} = $given_view_control_strip ? $color_to_store : 'off_explicit';

    ## if user can't hide control strip, then value 'off_explicit' is forbidden
    if (LJ::run_hook("user_cannot_modify_navstrip", $u)) {
        $props->{show_control_strip} = 'dark' if $props->{show_control_strip} eq 'off_explicit';
        $props->{view_control_strip} = 'dark' if $props->{view_control_strip} eq 'off_explicit';
    }
    foreach my $uprop (qw/view_control_strip show_control_strip/) {
        my $eff_val = $props->{$uprop}; # effective value, since 0 isn't stored
        $eff_val = "" unless $eff_val;
        $u->set_prop($uprop, $eff_val);
    }

    if ($color ne "layout_default" && $color ne "custom") {
        $override{custom_control_strip_colors} = "off";
    } else {
        if ($color eq "layout_default") {
            if ($post->{control_strip_no_gradient_default}) {
                $override{custom_control_strip_colors} = "on_no_gradient";
            } else {
                $override{custom_control_strip_colors} = "on_gradient";
            }

            $override{control_strip_bgcolor} = "";
            $override{control_strip_fgcolor} = "";
            $override{control_strip_bordercolor} = "";
            $override{control_strip_linkcolor} = "";
        } elsif ($color eq "custom") {
            if ($post->{control_strip_no_gradient_custom}) {
                $override{custom_control_strip_colors} = "on_no_gradient";
            } else {
                $override{custom_control_strip_colors} = "on_gradient";
            }

            $override{control_strip_bgcolor} = $post->{control_strip_bgcolor} || "";
            $override{control_strip_fgcolor} = $post->{control_strip_fgcolor} || "";
            $override{control_strip_bordercolor} = $post->{control_strip_bordercolor} || "";
            $override{control_strip_linkcolor} = $post->{control_strip_linkcolor} || "";
        }
    }

    if ($u->prop('stylesys') == 2) {
        my $style = LJ::S2::load_style($u->prop('s2_style'));
        die "Style not found." unless $style && $style->{userid} == $u->id;
        LJ::Customize->save_s2_props($u, $style, \%override);
    }

    return;
}

sub should_render {
    my $class = shift;

    return 1 if $LJ::USE_CONTROL_STRIP;
    return 0;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            if (!$('control_strip_color_layout_default')) return;

            self.hideSubDivs();
            if ($('control_strip_color_layout_default').checked) this.showSubDiv("layout_default_subdiv");
            if ($('control_strip_color_custom').checked) this.showSubDiv("custom_subdiv");

            DOM.addEventListener($('control_strip_color_dark'), "click", function (evt) { self.hideSubDivs() });
            DOM.addEventListener($('control_strip_color_light'), "click", function (evt) { self.hideSubDivs() });
            DOM.addEventListener($('control_strip_color_layout_default'), "click", function (evt) { self.showSubDiv("layout_default_subdiv") });
            DOM.addEventListener($('control_strip_color_custom'), "click", function (evt) { self.showSubDiv("custom_subdiv") });
        },
        hideSubDivs: function () {
            $('layout_default_subdiv').style.display = "none";
            $('custom_subdiv').style.display = "none";
        },
        showSubDiv: function (div) {
            this.hideSubDivs();
            $(div).style.display = "block";
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
