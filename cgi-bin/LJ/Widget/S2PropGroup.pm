package LJ::Widget::S2PropGroup;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Customize );

sub authas { 1 }
sub need_res { qw( stc/widgets/s2propgroup.css js/colorpicker.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $props = $opts{props};
    my $propgroup = $opts{propgroup};
    my $groupprops = $opts{groupprops};
    return "" unless ($props && $propgroup && $groupprops) || $opts{show_lang_chooser};

    my $style = LJ::S2::load_style($u->prop('s2_style'));
    die "Style not found." unless $style && $style->{userid} == $u->id;

    my $name = LJ::Customize->propgroup_name($propgroup, $u, $style);

    my $ret = "<fieldset><legend>$name ";
    $ret .= "<span class='s2propgroup-outer-expandcollapse'> - <a href='' class='s2propgroup-expandcollapse' id='${propgroup}__expand'>" . $class->ml('widget.s2propgroup.expand') . "</a></span> ";
    $ret .= "<span class='s2propgroup-outer-expandcollapse'> - <a href='' class='s2propgroup-expandcollapse' id='${propgroup}__collapse'>" . $class->ml('widget.s2propgroup.collapse') . "</a></span>";
    $ret .= "</legend></fieldset>";

    my $theme = LJ::Customize->get_current_theme($u);
    my $row_class = "";
    my $count = 1;

    if ($propgroup eq "presentation") {
        my @basic_props = $theme->display_option_props;
        my %is_basic_prop = map { $_ => 1 } @basic_props;

        $ret .= "<p class='detail'>" . $class->ml('widget.s2propgroup.presentation.note') . "</p>";

        $ret .= "<div class='subheader subheader-presentation on' id='subheader__presentation__basic'>" . $class->ml('widget.s2propgroup.presentation.basic') . "</div>";
        $ret .= "<table cellspacing='0' class='prop-list first' id='proplist__presentation__basic'>";
        $ret .= $class->language_chooser($u) if $opts{show_lang_chooser};
        foreach my $prop_name (@basic_props) {
            next if $class->skip_prop($props->{$prop_name}, $prop_name, theme => $theme);

            if ($opts{show_lang_chooser}) {
                # start on gray, since the language chooser will be white
                $row_class = $count % 2 != 0 ? " graybg" : "";
            } else {
                $row_class = $count % 2 == 0 ? " graybg" : "";
            }
            $ret .= $class->output_prop($props->{$prop_name}, $prop_name, $row_class, $u, $style, $theme);
            $count++;
        }
        $ret .= "</table>";

        $count = 1; # reset counter
        my $header_printed = 0;
        foreach my $prop_name (@$groupprops) {
            next if $class->skip_prop($props->{$prop_name}, $prop_name, props_to_skip => \%is_basic_prop, theme => $theme);

            # need to print the header inside the foreach because we don't want it printed if
            # there's no props in this group that are also in this subheader
            unless ($header_printed) {
                $ret .= "<div class='subheader subheader-presentation on' id='subheader__presentation__additional'>" . $class->ml('widget.s2propgroup.presentation.additional') . "</div>";
                $ret .= "<table cellspacing='0' class='prop-list' id='proplist__presentation__additional'>";
            }
            $header_printed = 1;
            $row_class = $count % 2 == 0 ? " graybg" : "";
            $ret .= $class->output_prop($props->{$prop_name}, $prop_name, $row_class, $u, $style, $theme);
            $count++;
        }
        $ret .= "</table>" if $header_printed;
    } else {
        my %subheaders = LJ::Customize->get_propgroup_subheaders;

        # props under the "Page" subheader include all props in the group that aren't under any of the other subheaders
        my %page_props = map { $_ => 1 } @$groupprops;
        foreach my $subheader (keys %subheaders) {
            my @subheader_props = eval "\$theme->${subheader}_props";
            foreach my $prop_name (@subheader_props) {
                delete $page_props{$prop_name} if $page_props{$prop_name};
            }
        }

        my $subheader_counter = 1;
        foreach my $subheader (LJ::Customize->get_propgroup_subheaders_order) {
            my $header_printed = 0;

            my @subheader_props;
            if ($subheader eq "page") {
                @subheader_props = keys %page_props;
            } else {
                @subheader_props = eval "\$theme->${subheader}_props";
            }
            next unless @subheader_props;

            my %prop_is_in_subheader = map { $_ => 1 } @subheader_props;

            foreach my $prop_name (@$groupprops) {
                next if $class->skip_prop($props->{$prop_name}, $prop_name, theme => $theme, user => $u, style => $style);
                next unless $prop_is_in_subheader{$prop_name};

                # need to print the header inside the foreach because we don't want it printed if
                # there's no props in this group that are also in this subheader
                unless ($header_printed) {
                    my $prop_list_class = " first" if $subheader_counter == 1;

                    $ret .= "<div class='subheader subheader-$propgroup on' id='subheader__${propgroup}__${subheader}'>$subheaders{$subheader}</div>";
                    $ret .= "<table cellspacing='0' class='prop-list$prop_list_class' id='proplist__${propgroup}__${subheader}'>";
                    $header_printed = 1;
                    $subheader_counter++;
                    $count = 1; # reset counter
                }

                $row_class = $count % 2 == 0 ? " graybg" : "";
                $ret .= $class->output_prop($props->{$prop_name}, $prop_name, $row_class, $u, $style, $theme);
                $count++;
            }
            $ret .= "</table>" if $header_printed;
        }
    }

    return $ret;
}

sub language_chooser {
    my $class = shift;
    my $u = shift;

    my $pub = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);
    my %style = LJ::S2::get_style($u, "verify");

    my @langs = LJ::S2::get_layout_langs($pub, $style{'layout'});
    my $get_lang = sub {
        my $styleid = shift;
        foreach ($userlay, $pub) {
            return $_->{$styleid}->{'langcode'} if
                $_->{$styleid} && $_->{$styleid}->{'langcode'};
        }
        return undef;
    };

    my $langcode = $get_lang->($style{'i18n'}) || $get_lang->($style{'i18nc'});
    # they have set a custom i18n layer
    if ($style{'i18n'} &&
        ($style{'i18nc'} != $style{'i18n'} || ! defined $pub->{$style{'i18n'}})) {
        push @langs, 'custom', $class->ml('widget.s2propgroup.language.custom');
        $langcode = 'custom';
    }

    my $ret = "<tr class='prop-row' width='100%'>";
    $ret .= "<td>" . $class->ml('widget.s2propgroup.language.label') . "</td><td>";
    $ret .= $class->html_select(
        { name => "langcode",
          selected => $langcode, },
        0 => $class->ml('widget.s2propgroup.language.default'), @langs) . "</td>";
    $ret .= "</tr><tr class='prop-row-note'><td colspan='100%' class='prop-note'>" . $class->ml('widget.s2propgroup.language.note') . "</td></tr>";

    return $ret;
}

sub skip_prop {
    my $class = shift;
    my $prop = shift;
    my $prop_name = shift;
    my %opts = @_;

    my $props_to_skip = $opts{props_to_skip};
    my $theme = $opts{theme};

    if (!$prop) {
        return 1 unless $prop_name eq "linklist_support" && $theme && $theme->linklist_support_tab;
    }

    return 1 if $prop->{noui};

    return 1 if $props_to_skip && $props_to_skip->{$prop_name};

    if ($theme) {
        return 1 if $prop_name eq $theme->layout_prop;
        return 1 if $prop_name eq $theme->show_sidebar_prop;
    }

    return 1 if $prop_name eq "custom_control_strip_colors";
    return 1 if $prop_name eq "control_strip_bgcolor";
    return 1 if $prop_name eq "control_strip_fgcolor";
    return 1 if $prop_name eq "control_strip_bordercolor";
    return 1 if $prop_name eq "control_strip_linkcolor";

    my $hook_rv = LJ::run_hook("skip_prop_override", $prop_name, user => $opts{user}, theme => $theme, style => $opts{style});
    return $hook_rv if $hook_rv;

    return 0;
}

sub output_prop {
    my $class = shift;
    my $prop = shift;
    my $prop_name = shift;
    my $row_class = shift;
    my $u = shift;
    my $style = shift;
    my $theme = shift;

    # for themes that don't use the linklist_support prop
    my $linklist_tab;
    if (!$prop && $prop_name eq "linklist_support") {
        $linklist_tab = $theme->linklist_support_tab;
    }

    my $name = $prop->{name};
    my $type = $prop->{type};

    my $can_use = LJ::S2::can_use_prop($u, $theme->layout_uniq, $name);

    my %prop_values = LJ::Customize->get_s2_prop_values($name, $u, $style);
    my $existing = $prop_values{existing};
    my $override = $prop_values{override};

    my %values = split(/\|/, $prop->{values});
    my $existing_display = defined $values{$existing} ? $values{$existing} : $existing;

    $existing_display = LJ::eall($existing_display);

    my $ret;
    $ret .= "<tr class='prop-row$row_class' width='100%'>";

    if ($linklist_tab) {
        $ret .= "<td colspan='100%'>" . $class->ml('widget.s2propgroup.linkslisttab', {'name' => $linklist_tab}) . "</td>";
        $ret .= "</tr>";
        return $ret;
    }

    $ret .= "<td class='prop-header'>" . LJ::eall($prop->{des}) . " " . LJ::help_icon("s2opt_$name") . "</td>"
        unless $type eq "Color";

    if ($prop->{values}) {
        $ret .= "<td class='prop-input'>";
        $ret .= $class->html_select(
            { name => $name,
              disabled => ! $can_use,
              selected => $override, },
            split(/\|/, $prop->{values})
        );
        $ret .= "</td>";
    } elsif ($type eq "int") {
        $ret .= "<td class='prop-input'>";
        $ret .= $class->html_text(
            name => $name,
            disabled => ! $can_use,
            value => $override,
            maxlength => 5,
            size => 7,
        );
        $ret .= "</td>";
    } elsif ($type eq "bool") {
        $ret .= "<td class='prop-check'>";
        $ret .= $class->html_check(
            name => $name,
            disabled => ! $can_use,
            selected => $override,
            
        );
        
        # force the checkbox to be submitted, if the user unchecked it
        # so that it can be processed (disabled) when handling the post
        $ret .= $class->html_hidden(
            "${name}",
            "0",
            { disabled => ! $can_use }
        );

        $ret .= "</td>";
    } elsif ($type eq "string") {
        my ($rows, $cols, $full) = ($prop->{rows}+0,
                                    $prop->{cols}+0,
                                    $prop->{full}+0);

        $ret .= "<td class='prop-input'>";
        if ($full > 0) {
            $ret .= $class->html_textarea(
                name => $name,
                disabled => ! $can_use,
                value => $override,
                rows => "40",
                cols => "40",
                style => "width: 97%; height: 350px; ",
            );
        } elsif ($rows > 0 && $cols > 0) {
            $ret .= $class->html_textarea(
                name => $name,
                disabled => ! $can_use,
                value => $override,
                rows => $rows,
                cols => $cols,
            );
        } else {
            my ($size, $maxlength) = ($prop->{size} || 30,
                                      $prop->{maxlength} || 255);

            $ret .= $class->html_text(
                name => $name,
                disabled => ! $can_use,
                value => $override,
                maxlength => $maxlength,
                size => $size,
            );
        }
        $ret .= "</td>";
    } elsif ($type eq "Color") {
        $ret .= "<td class='prop-color'>";
        $ret .= $class->html_color(
            name => $name,
            disabled => ! $can_use,
            default => $override,
            des => $prop->{des},
            onchange => "Customize.CustomizeTheme.form_change();",
            no_btn => 1,
        );
        $ret .= "</td>";
        $ret .= "<td>" . LJ::eall($prop->{des}) . " " . LJ::help_icon("s2opt_$name") . "</td>";
    }

    my $offhelp = ! $can_use ? LJ::help_icon('s2propoff', ' ') : "";
    $ret .= " $offhelp";

    my $note = "";
    $note .= LJ::eall($prop->{note}) if $prop->{note};
    $ret .= "</tr><tr class='prop-row-note$row_class'><td colspan='100%' class='prop-note'>$note</td>" if $note;

    $ret .= "</tr>";
    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless $u;

    my $style = LJ::S2::load_style($u->prop('s2_style'));
    die "Style not found." unless $style && $style->{userid} == $u->id;

    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    if ($post_fields_of_parent->{reset}) {
        # reset all props except the layout props
        my $current_theme = LJ::Customize->get_current_theme($u);
        my $layout_prop = $current_theme->layout_prop;
        my $show_sidebar_prop = $current_theme->show_sidebar_prop;

        my %override = %$post;
        delete $override{$layout_prop};
        delete $override{$show_sidebar_prop};

        LJ::Customize->save_s2_props($u, $style, \%override, reset => 1);
        LJ::Customize->save_language($u, $post->{langcode}, reset => 1) if defined $post->{langcode};
    } else {
        my %override = map { $_ => 0 } keys %$post;
        
        # ignore all values after the first true $value
        # only checkboxes have multiple values (forced post of 0, 
        # so we don't ignore checkboxes that the user just unchecked)
        foreach my $key ( keys %$post ) {
            foreach my $value ( split ( /\0/, $post->{$key} ) ) {
                $override{$key} ||= $value;
            }
        }
        LJ::Customize->save_s2_props($u, $style, \%override);
        LJ::Customize->save_language($u, $post->{langcode}) if defined $post->{langcode};
    }

    return;
}

# return if the propgroup has props to display or not
sub group_exists_with_props {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{user};
    my $props = $opts{props};
    my $groupprops = $opts{groupprops};

    my $theme = LJ::Customize->get_current_theme($u);
    foreach my $prop_name (@$groupprops) {
        return 1 unless $class->skip_prop($props->{$prop_name}, $prop_name, theme => $theme);
    }

    return 0;
}

sub js {
    q [
        initWidget: function () {
            var self = this;

            var maxPropsToShow = 15;
            var numPropsOnPage = DOM.getElementsByClassName(document, "prop-row").length;

            // hide all prop lists except the first one if there are too many props
            if (numPropsOnPage > maxPropsToShow) {
                var lists = DOM.getElementsByClassName(document, "prop-list");
                lists.forEach(function (list) {
                    var listid = list.id;
                    var subheaderid = listid.replace(/proplist/, 'subheader');
                    if (!DOM.hasClassName(list, 'first')) {
                        self.alterSubheader(subheaderid);
                    }
                });
            }

            // add event listeners to all of the subheaders
            var subheaders = DOM.getElementsByClassName(document, "subheader");
            subheaders.forEach(function (subheader) {
                DOM.addEventListener(subheader, "click", function (evt) { self.alterSubheader(subheader.id) });
            });

            // show the expand/collapse links
            var ec_spans = DOM.getElementsByClassName(document, "s2propgroup-outer-expandcollapse");
            ec_spans.forEach(function (ec_span) {
                ec_span.style.display = "inline";
            });

            // add event listeners to all of the expand/collapse links
            var ec_links = DOM.getElementsByClassName(document, "s2propgroup-expandcollapse");
            ec_links.forEach(function (ec_link) {
                DOM.addEventListener(ec_link, "click", function (evt) { self.expandCollapseAll(evt, ec_link.id) });
            });
        },
        alterSubheader: function (subheaderid, override) {
            var self = this;
            var proplistid = subheaderid.replace(/subheader/, 'proplist');

            // figure out whether to expand or collapse
            var expand = !DOM.hasClassName($(subheaderid), 'on');
            if (override) {
                if (override == "expand") {
                    expand = 1;
                } else {
                    expand = 0;
                }
            }

            if (expand) {
                // expand
                DOM.addClassName($(subheaderid), 'on');
                $(proplistid).style.display = "block";
            } else {
                // collapse
                DOM.removeClassName($(subheaderid), 'on');
                $(proplistid).style.display = "none";
            }
        },
        expandCollapseAll: function (evt, ec_linkid) {
            var self = this;
            var action = ec_linkid.replace(/.+__(.+)/, '$1');
            var propgroup = ec_linkid.replace(/(.+)__.+/, '$1');

            var propgroupSubheaders = DOM.getElementsByClassName(document, "subheader-" + propgroup);
            propgroupSubheaders.forEach(function (subheader) {
                self.alterSubheader(subheader.id, action);
            });
            Event.stop(evt);
        },
        onRefresh: function (data) {
            this.initWidget();
        }
    ];
}

1;
