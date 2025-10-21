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

package LJ::Widget::S2PropGroup;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;
use List::Util qw( first );

sub authas        { 1 }
sub need_res      { qw( stc/widgets/s2propgroup.css js/colorpicker.js stc/collapsible.css ) }
sub need_res_opts { ( priority => $LJ::OLD_RES_PRIORITY ) }

sub render_body {
    my $class = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $props      = $opts{props};
    my $propgroup  = $opts{propgroup};
    my $groupprops = $opts{groupprops};
    return "" unless ( $props && $propgroup && $groupprops ) || $opts{show_lang_chooser};

    my $style = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;

    my $name = LJ::Customize->propgroup_name( $propgroup, $u, $style );

    my $ret = "<fieldset><legend>$name ";
    $ret .=
"<span class='s2propgroup-outer-expandcollapse'> - <a href='' class='s2propgroup-expandcollapse' id='${propgroup}__expand'>"
        . $class->ml('widget.s2propgroup.expand')
        . "</a></span> ";
    $ret .=
"<span class='s2propgroup-outer-expandcollapse'> - <a href='' class='s2propgroup-expandcollapse' id='${propgroup}__collapse'>"
        . $class->ml('widget.s2propgroup.collapse')
        . "</a></span>";
    $ret .= "</legend></fieldset>";

    my $theme     = LJ::Customize->get_current_theme($u);
    my $row_class = "";
    my $count     = 1;

    if ( $propgroup eq "presentation" ) {
        my @basic_props   = $theme->display_option_props;
        my %is_basic_prop = map { $_ => 1 } @basic_props;

        $ret .= "<p class='detail'>" . $class->ml('widget.s2propgroup.presentation.note') . "</p>";

        $ret .=
"<div class='subheader subheader-presentation collapsible expanded' id='subheader__presentation__basic'><div class='collapse-button'>"
            . $class->ml('collapsible.expanded')
            . "</div> "
            . $class->ml('widget.s2propgroup.presentation.basic')
            . "</div>";
        $ret .=
"<table summary='' cellspacing='0' class='prop-list first' id='proplist__presentation__basic'>";
        $ret .= $class->language_chooser($u) if $opts{show_lang_chooser};
        foreach my $prop_name (@basic_props) {
            next
                if $class->skip_prop(
                $props->{$prop_name}, $prop_name,
                theme => $theme,
                user  => $u
                );

            if ( $opts{show_lang_chooser} ) {

                # start on gray, since the language chooser will be white
                $row_class = $count % 2 != 0 ? " odd" : " even";
            }
            else {
                $row_class = $count % 2 == 0 ? " even" : " odd";
            }
            $ret .= $class->output_prop( $props->{$prop_name}, $prop_name, $row_class, $u, $style,
                $theme, $props );
            $count++;
        }
        $ret .= "</table>";

        $count = 1;    # reset counter
        my $header_printed = 0;
        foreach my $prop_name (@$groupprops) {
            next
                if $class->skip_prop(
                $props->{$prop_name}, $prop_name,
                props_to_skip => \%is_basic_prop,
                theme         => $theme,
                user          => $u
                );

            # need to print the header inside the foreach because we don't want it printed if
            # there's no props in this group that are also in this subheader
            unless ($header_printed) {
                $ret .=
"<div class='subheader subheader-presentation collapsible expanded' id='subheader__presentation__additional'><div class='collapse-button'>"
                    . $class->ml('collapsible.expanded')
                    . "</div> "
                    . $class->ml('widget.s2propgroup.presentation.additional')
                    . "</div>";
                $ret .=
"<table summary='' cellspacing='0' class='prop-list' id='proplist__presentation__additional'>";
            }
            $header_printed = 1;
            $row_class      = $count % 2 == 0 ? " even" : " odd";
            $ret .= $class->output_prop( $props->{$prop_name}, $prop_name, $row_class, $u, $style,
                $theme, $props );
            $count++;
        }
        $ret .= "</table>" if $header_printed;
    }
    elsif ( $propgroup eq "modules" ) {

        my %prop_values = LJ::Customize->get_s2_prop_values( "module_layout_sections", $u, $style );
        my $layout_sections_values = $prop_values{override};
        my @layout_sections_order  = split( /\|/, $layout_sections_values );

# allow to override the default property with your own custom property definition. Created and values set in layout layers.
        my %grouped_prop_override =
            LJ::Customize->get_s2_prop_values( "grouped_property_override", $u, $style, noui => 1 );
        %grouped_prop_override = %{ $grouped_prop_override{override} }
            if %{ $grouped_prop_override{override} || {} };

        my %subheaders = @layout_sections_order;
        $subheaders{none} = "Unassigned";

        # use the module section order as defined by the layout
        my $i = 0;
        @layout_sections_order = grep { $i++ % 2 == 0; } @layout_sections_order;

        my %prop_in_subheader;
        foreach my $prop_name (@$groupprops) {
            next unless $prop_name =~ /_group$/;

            # use module_*_section for the dropdown
            my $prop_name_section = $prop_name;
            $prop_name_section =~ s/(.*)_group$/$1_section/;

            my $overriding_prop_name = $grouped_prop_override{$prop_name_section};

            # module_*_section_override overrides module_*_section;
            # for use in child layouts since they cannot redefine an existing property
            my $prop_name_section_override =
                defined $overriding_prop_name ? $props->{$overriding_prop_name}->{values} : undef;

            # put this property under the proper subheader (this is the original; may be overriden)
            my %prop_values = LJ::Customize->get_s2_prop_values( $prop_name_section, $u, $style );

            if ($prop_name_section_override) {
                $prop_name_section = $overriding_prop_name;

    # check if we have anything previously saved into the overriding property. If we don't we retain
    # the value of the original (non-overridden) property, so we don't break existing customizations
                my %overriding_prop_values =
                    LJ::Customize->get_s2_prop_values( $prop_name_section, $u, $style );
                my $contains_values = 0;

                foreach ( keys %overriding_prop_values ) {
                    if ( defined $overriding_prop_values{$_} ) {
                        $contains_values++;
                        last;
                    }
                }

                %prop_values = %overriding_prop_values if $contains_values;
                $grouped_prop_override{"${prop_name_section}_values"} = \%prop_values;
            }

 # populate section dropdown values with the layout's list of available sections, if not already set
            $props->{$prop_name_section}->{values} ||= $layout_sections_values;

            if ($prop_name_section_override) {
                my %override_sections = split( /\|/, $prop_name_section_override );

                while ( my ( $key, $value ) = each %override_sections ) {
                    unless ( $subheaders{$key} ) {
                        $subheaders{$key} = $value;
                        push @layout_sections_order, $key;
                    }
                }
            }

# see whether a cap is needed for this module and don't show the module if the user does not have that cap
            my $cap;
            $cap = $props->{$prop_name}->{requires_cap};
            next if $cap && !( $u->get_cap($cap) );

            # force it to the "none" section, if property value is not a valid subheader
            my $subheader = $subheaders{ $prop_values{override} } ? $prop_values{override} : "none";
            $prop_in_subheader{$subheader} ||= [];
            push @{ $prop_in_subheader{$subheader} }, $prop_name;
        }

        my $subheader_counter = 1;
        foreach my $subheader (@layout_sections_order) {
            my $header_printed = 0;
            foreach my $prop_name ( @{ $prop_in_subheader{$subheader} } ) {
                next
                    if $class->skip_prop(
                    $props->{$prop_name}, $prop_name,
                    theme => $theme,
                    user  => $u,
                    style => $style
                    );

                unless ($header_printed) {
                    my $prop_list_class = '';
                    $prop_list_class = " first" if $subheader_counter == 1;

                    $ret .=
"<div class='subheader subheader-modules collapsible expanded' id='subheader__modules__${subheader}'><div class='collapse-button'>"
                        . $class->ml('collapsible.expanded')
                        . "</div> $subheaders{$subheader}</div>";
                    $ret .=
"<table summary='' cellspacing='0' class='prop-list$prop_list_class' id='proplist__modules__${subheader}'>";
                    $header_printed = 1;
                    $subheader_counter++;
                    $count = 1;    # reset counter
                }

                $row_class = $count % 2 == 0 ? " even" : " odd";

                $ret .=
                    $class->output_prop( $props->{$prop_name}, $prop_name, $row_class, $u, $style,
                    $theme, $props, \%grouped_prop_override );
                $count++;
            }
            $ret .= "</table>" if $header_printed;
        }

    }
    elsif ( $propgroup eq "text" ) {
        my %subheaders = LJ::Customize->get_propgroup_subheaders;

# props under the unsorted subheader include all props in the group that aren't under any of the other subheaders
        my %unsorted_props = map { $_ => 1 } @$groupprops;
        foreach my $subheader ( keys %subheaders ) {
            my @subheader_props = eval "\$theme->${subheader}_props";
            foreach my $prop_name (@subheader_props) {
                delete $unsorted_props{$prop_name} if $unsorted_props{$prop_name};
            }
        }

        my $subheader_counter = 1;
        foreach my $subheader ( LJ::Customize->get_propgroup_subheaders_order ) {
            my $header_printed = 0;

            my @subheader_props;
            if ( $subheader eq "unsorted" ) {
                @subheader_props = keys %unsorted_props;
            }
            else {
                @subheader_props = eval "\$theme->${subheader}_props";
            }
            next unless @subheader_props;

            my %prop_is_in_subheader = map { $_ => 1 } @subheader_props;

            foreach my $prop_name (@$groupprops) {
                next
                    if $class->skip_prop(
                    $props->{$prop_name}, $prop_name,
                    theme => $theme,
                    user  => $u,
                    style => $style
                    );
                next unless $prop_is_in_subheader{$prop_name};

                # need to print the header inside the foreach because we don't want it printed if
                # there's no props in this group that are also in this subheader
                unless ($header_printed) {
                    my $prop_list_class = "";
                    $prop_list_class = " first" if $subheader_counter == 1;

                    $ret .=
"<div class='subheader subheader-$propgroup collapsible expanded' id='subheader__${propgroup}__${subheader}'><div class='collapse-button'>"
                        . $class->ml('collapsible.expanded')
                        . "</div>$subheaders{$subheader}</div>";
                    $ret .=
"<table summary='' cellspacing='0' class='prop-list$prop_list_class' id='proplist__${propgroup}__${subheader}'>";
                    $header_printed = 1;
                    $subheader_counter++;
                    $count = 1;    # reset counter
                }

                $row_class = $count % 2 == 0 ? " even" : " odd";
                $ret .=
                    $class->output_prop( $props->{$prop_name}, $prop_name, $row_class, $u, $style,
                    $theme, $props );
                $count++;
            }

            #If we're in the module subsection, we also need to render the Custom Text widget
            if ( $subheaders{$subheader} eq $class->ml('customize.propgroup_subheaders.module') ) {
                $ret .= LJ::Widget::CustomTextModule->render( count => $count );
            }
            $ret .= "</table>" if $header_printed;
        }
    }
    else {
        my %subheaders = LJ::Customize->get_propgroup_subheaders;

# props under the unsorted subheader include all props in the group that aren't under any of the other subheaders
        my %unsorted_props = map { $_ => 1 } @$groupprops;
        foreach my $subheader ( keys %subheaders ) {
            my @subheader_props = eval "\$theme->${subheader}_props";
            foreach my $prop_name (@subheader_props) {
                delete $unsorted_props{$prop_name} if $unsorted_props{$prop_name};
            }
        }

        my $subheader_counter = 1;
        foreach my $subheader ( LJ::Customize->get_propgroup_subheaders_order ) {
            my $header_printed = 0;

            my @subheader_props;
            if ( $subheader eq "unsorted" ) {
                @subheader_props = keys %unsorted_props;
            }
            else {
                @subheader_props = eval "\$theme->${subheader}_props";
            }
            next unless @subheader_props;

            my %prop_is_in_subheader = map { $_ => 1 } @subheader_props;

            foreach my $prop_name (@$groupprops) {
                next
                    if $class->skip_prop(
                    $props->{$prop_name}, $prop_name,
                    theme => $theme,
                    user  => $u,
                    style => $style
                    );
                next unless $prop_is_in_subheader{$prop_name};

                # need to print the header inside the foreach because we don't want it printed if
                # there's no props in this group that are also in this subheader
                unless ($header_printed) {
                    my $prop_list_class = "";
                    $prop_list_class = " first" if $subheader_counter == 1;

                    $ret .=
"<div class='subheader subheader-$propgroup collapsible expanded' id='subheader__${propgroup}__${subheader}'><div class='collapse-button'>"
                        . $class->ml('collapsible.expanded')
                        . "</div>$subheaders{$subheader}</div>";
                    $ret .=
"<table summary='' cellspacing='0' class='prop-list$prop_list_class' id='proplist__${propgroup}__${subheader}'>";
                    $header_printed = 1;
                    $subheader_counter++;
                    $count = 1;    # reset counter
                }

                $row_class = $count % 2 == 0 ? " even" : " odd";
                $ret .=
                    $class->output_prop( $props->{$prop_name}, $prop_name, $row_class, $u, $style,
                    $theme, $props );
                $count++;
            }
            $ret .= "</table>" if $header_printed;
        }
    }

    return $ret;
}

sub language_chooser {
    my $class = shift;
    my $u     = shift;

    my $pub     = LJ::S2::get_public_layers();
    my $userlay = LJ::S2::get_layers_of_user($u);
    my %style   = LJ::S2::get_style( $u, "verify" );

    my @langs    = LJ::S2::get_layout_langs( $pub, $style{'layout'} );
    my $get_lang = sub {
        my $styleid = shift;
        foreach ( $userlay, $pub ) {
            return $_->{$styleid}->{'langcode'}
                if $_->{$styleid} && $_->{$styleid}->{'langcode'};
        }
        return undef;
    };

    my $langcode = $get_lang->( $style{'i18n'} ) || $get_lang->( $style{'i18nc'} );

    # they have set a custom i18n layer
    if ( $style{'i18n'}
        && ( $style{'i18nc'} != $style{'i18n'} || !defined $pub->{ $style{'i18n'} } ) )
    {
        push @langs, 'custom', $class->ml('widget.s2propgroup.language.custom');
        $langcode = 'custom';
    }

    my $ret = "<tr class='prop-row' width='100%'>";
    $ret .= "<td>" . $class->ml('widget.s2propgroup.language.label') . "</td><td>";
    $ret .= $class->html_select(
        {
            name     => "langcode",
            selected => $langcode,
        },
        0 => $class->ml('widget.s2propgroup.language.default'),
        @langs
    ) . "</td>";
    $ret .=
          "</tr><tr class='prop-row-note'><td colspan='100%' class='prop-note'>"
        . $class->ml('widget.s2propgroup.language.note')
        . "</td></tr>";

    return $ret;
}

sub skip_prop {
    my $class     = shift;
    my $prop      = shift;
    my $prop_name = shift;
    my %opts      = @_;

    my $props_to_skip = $opts{props_to_skip};
    my $theme         = $opts{theme};

    if ( !$prop ) {
        return 1 unless $prop_name eq "linklist_support" && $theme && $theme->linklist_support_tab;
    }

    return 1 if $prop->{noui};
    return 1 if $prop->{grouped};

    return 1 if $props_to_skip && $props_to_skip->{$prop_name};

    if ($theme) {
        return 1 if $prop_name eq $theme->layout_prop;
        return 1 if $prop_name eq $theme->show_sidebar_prop;
    }

    if ( $opts{user}->is_community ) {
        return 1 if $prop_name eq "text_view_network";
        return 1 if $prop_name eq "text_view_friends";
        return 1 if $prop_name eq "text_view_friends_filter";
        return 1 if $prop_name eq "module_subscriptionfilters_group";
    }
    else {
        return 1 if $prop_name eq "text_view_friends_comm";
    }

    return 1 if $prop_name eq "custom_control_strip_colors";
    return 1 if $prop_name eq "control_strip_bgcolor";
    return 1 if $prop_name eq "control_strip_fgcolor";
    return 1 if $prop_name eq "control_strip_bordercolor";
    return 1 if $prop_name eq "control_strip_linkcolor";

    my $hook_rv = LJ::Hooks::run_hook(
        "skip_prop_override", $prop_name,
        user  => $opts{user},
        theme => $theme,
        style => $opts{style}
    );
    return $hook_rv if $hook_rv;

    return 0;
}

sub output_prop {
    my ( $class, $prop, $prop_name, $row_class, $u, $style, $theme, $props, $grouped_prop_override )
        = @_;

    # for themes that don't use the linklist_support prop
    my $linklist_tab;
    if ( !$prop && $prop_name eq "linklist_support" ) {
        $linklist_tab = $theme->linklist_support_tab;
    }

    my $ret;
    $ret .= "<tr class='prop-row$row_class' width='100%' valign='top'>";

    if ($linklist_tab) {
        $ret .=
              "<td colspan='100%'>"
            . $class->ml( 'widget.s2propgroup.linkslisttab', { 'name' => $linklist_tab } )
            . "</td>";
        $ret .= "</tr>";
        return $ret;
    }

    $ret .=
          "<td class='prop-header' valign='top'>"
        . LJ::eall( $prop->{des} ) . " "
        . LJ::help_icon("s2opt_$prop->{name}") . "</td>"
        unless $prop->{type} eq "Color" || $prop->{type} eq "string[]";

    $ret .= $class->output_prop_element( $prop, $prop_name, $u, $style, $theme, $props, 0,
        $grouped_prop_override );

    my $note = "";
    $note .= LJ::eall( $prop->{note} ) if $prop->{note};
    $ret .=
        "</tr><tr class='prop-row-note$row_class'><td colspan='100%' class='prop-note'>$note</td>"
        if $note;

    $ret .= "</tr>";
    return $ret;
}

sub output_prop_element {
    my ( $class, $prop, $prop_name, $u, $style, $theme, $props, $is_group, $grouped_prop_override,
        $overriding_values )
        = @_;
    $grouped_prop_override ||= {};
    $overriding_values     ||= {};

    my $name = $prop->{name};
    my $type = $prop->{type};

    my $can_use = LJ::S2::can_use_prop( $u, $theme->layout_uniq, $name );

    my %prop_values =
          %$overriding_values
        ? %$overriding_values
        : LJ::Customize->get_s2_prop_values( $name, $u, $style );

    my $existing = $prop_values{existing};
    my $override = $prop_values{override};

    my %values = split( /\|/, $prop->{values} || '' );
    my $existing_display =
        defined $existing && defined $values{$existing} ? $values{$existing} : $existing;

    $existing_display = LJ::eall($existing_display);

    my $ret;

    # visually grouped properties. Allow nesting to only two levels
    if ( $type eq "string[]" && $is_group < 2 ) {

        if ( $prop->{grouptype} eq "module" ) {
            my $has_opts;
            $ret .= "<td class='prop-grouped prop-$prop->{grouptype}' colspan=2>";
            foreach my $prop_in_group (@$override) {

                my $overriding_values;
                if ( $grouped_prop_override->{$prop_in_group} ) {
                    $prop_in_group     = $grouped_prop_override->{$prop_in_group};
                    $overriding_values = $grouped_prop_override->{"${prop_in_group}_values"};
                }

                if ( $prop_in_group =~ /opts_group$/ ) {
                    $has_opts = 1;
                    next;
                }
                $ret .= $class->output_prop_element(
                    $props->{$prop_in_group},
                    $prop_in_group, $u, $style, $theme, $props, $is_group + 1,
                    $grouped_prop_override, $overriding_values
                );
            }

            my $modulename = $prop->{name};
            $modulename =~ s/_group$//;

            $ret .= "<label for='${modulename}_show'>" . LJ::eall( $prop->{des} ) . "</label>";

            $ret .= $class->output_prop_element( $props->{"${modulename}_opts_group"},
                "${modulename}_opts_group", $u, $style, $theme, $props, $is_group + 1 )
                if $has_opts;

            $ret .= "</td>";
        }
        elsif ( $prop->{grouptype} eq "moduleopts" ) {
            $ret .= "<ul class='prop-moduleopts'>";
            foreach my $prop_in_group (@$override) {
                $ret .= "<li>"
                    . $class->output_prop_element( $props->{$prop_in_group},
                    $prop_in_group, $u, $style, $theme, $props, $is_group + 1 );
            }
            $ret .= "</ul>";
        }
        else {
            $ret .=
"<td class='prop-grouped prop-$prop->{grouptype}' colspan=2><label class='prop-header'>"
                . LJ::eall( $prop->{des} ) . " "
                . LJ::help_icon("s2opt_$prop->{name}")
                . "</label>";

            foreach my $prop_in_group (@$override) {
                $ret .= $class->output_prop_element( $props->{$prop_in_group},
                    $prop_in_group, $u, $style, $theme, $props, $is_group + 1 );
            }
            my $note = "";
            $note .= LJ::eall( $prop->{note} )          if $prop->{note};
            $ret  .= "<ul class=''><li>$note</li></ul>" if $note;
            $ret  .= "</td>";
        }
    }
    elsif ( $prop->{values} ) {
        $ret .= "<td class='prop-input'>" unless $is_group;

        # take the list of allowed values, determine whether we allow custom values
        # and whether we have a value not in the list (possibly set through the layer editor)
        # if so, prepend custom values
        my @values = split( /\|/, $prop->{values} );
        unshift @values, $override, "Custom: $override"
            if $prop->{allow_other} && defined $override && !first { $_ eq $override } @values;

        $ret .= $class->html_select(
            {
                name     => $name,
                disabled => !$can_use,
                selected => $override,
            },
            @values,
        );
        $ret .= " <label>" . LJ::eall( $prop->{des} ) . "</label>" if $is_group && $prop->{des};
        $ret .= "</td>" unless $is_group;
    }
    elsif ( $type eq "int" ) {
        $ret .= "<td class='prop-input'>" unless $is_group;
        $ret .= $class->html_text(
            name      => $name,
            disabled  => !$can_use,
            value     => $override,
            maxlength => 5,
            size      => 7,
        );
        $ret .= " <label>" . LJ::eall( $prop->{des} ) . "</label>" if $is_group && $prop->{des};
        $ret .= "</td>" unless $is_group;
    }
    elsif ( $type eq "bool" ) {
        $ret .= "<td class='prop-check'>" unless $is_group;
        unless ( $prop->{obsolete} ) {    # can't be changed, so don't print
            $ret .= $class->html_check(
                name     => $name,
                disabled => !$can_use,
                selected => $override,
                label    => $prop->{label},
                id       => $name,
            );

            # force the checkbox to be submitted, if the user unchecked it
            # so that it can be processed (disabled) when handling the post
            $ret .= $class->html_hidden( "${name}", "0", { disabled => !$can_use } );
        }

        $ret .= "</td>" unless $is_group;
    }
    elsif ( $type eq "string" ) {
        my $rows = $prop->{rows} ? $prop->{rows} + 0 : 0;
        my $cols = $prop->{cols} ? $prop->{cols} + 0 : 0;
        my $full = $prop->{full} ? $prop->{full} + 0 : 0;

        $ret .= "<td class='prop-input'>" unless $is_group;
        if ( $full > 0 ) {
            $ret .= $class->html_textarea(
                name     => $name,
                disabled => !$can_use,
                value    => $override,
                rows     => "40",
                cols     => "40",
                style    => "width: 97%; height: 350px; ",
            );
        }
        elsif ( $rows > 0 && $cols > 0 ) {
            $ret .= $class->html_textarea(
                name     => $name,
                disabled => !$can_use,
                value    => $override,
                rows     => $rows,
                cols     => $cols,
            );
        }
        else {
            my ( $size, $maxlength ) = ( $prop->{size} || 30, $prop->{maxlength} || 255 );

            $ret .= $class->html_text(
                name      => $name,
                disabled  => !$can_use,
                value     => $override,
                maxlength => $maxlength,
                size      => $size,
            );
        }
        $ret .= "</td>" unless $is_group;
    }
    elsif ( $type eq "Color" ) {
        $ret .= "<td class='prop-color'>" unless $is_group;
        $ret .= $class->html_color(
            name     => $name,
            disabled => !$can_use,
            default  => $override,
            des      => $prop->{des},
            onchange => "Customize.CustomizeTheme.form_change();",
            no_btn   => 1,
        );
        $ret .= "</td>" unless $is_group;
        $ret .= "<td>" . LJ::eall( $prop->{des} ) . " " . LJ::help_icon("s2opt_$name") . "</td>";
    }

    my $offhelp = !$can_use ? LJ::help_icon( 's2propoff', ' ' ) : "";
    $ret .= " $offhelp";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless $u;

    my $style = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;

    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    if ( $post_fields_of_parent->{reset} ) {

        # reset all props except the layout props
        my $current_theme     = LJ::Customize->get_current_theme($u);
        my $layout_prop       = $current_theme->layout_prop;
        my $show_sidebar_prop = $current_theme->show_sidebar_prop;

        my %override = %$post;
        delete $override{$layout_prop};
        delete $override{$show_sidebar_prop};

        LJ::Customize->save_s2_props( $u, $style, \%override, reset => 1 );
        LJ::Customize->save_language( $u, $post->{langcode}, reset => 1 )
            if defined $post->{langcode};
    }
    else {
        my %override = map { $_ => "" } keys %$post;

        # ignore all values after the first true $value
        # only checkboxes have multiple values (forced post of 0,
        # so we don't ignore checkboxes that the user just unchecked)
        foreach my $key ( keys %$post ) {
            foreach my $value ( split( /\0/, $post->{$key} ) ) {
                $override{$key} ||= $value;
            }
        }

        LJ::Customize->save_s2_props( $u, $style, \%override );
        LJ::Customize->save_language( $u, $post->{langcode} ) if defined $post->{langcode};
    }

    return;
}

# return if the propgroup has props to display or not
sub group_exists_with_props {
    my $class = shift;
    my %opts  = @_;

    my $u          = $opts{user};
    my $props      = $opts{props};
    my $groupprops = $opts{groupprops};

    my $theme = LJ::Customize->get_current_theme($u);
    foreach my $prop_name (@$groupprops) {
        return 1
            unless $class->skip_prop(
            $props->{$prop_name}, $prop_name,
            theme => $theme,
            user  => $u
            );
    }

    return 0;
}

sub js {
    my $collapsed = LJ::ejs_string( LJ::Lang::ml('collapsible.collapsed') );
    my $expanded  = LJ::ejs_string( LJ::Lang::ml('collapsible.expanded') );

    qq [
        ml: {
            collapsed: $collapsed,
            expanded: $expanded
        },
    ]
        . q [
        initWidget: function () {
            var self = this;

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
            var expand = !DOM.hasClassName($(subheaderid), 'expanded');
            if (override) {
                if (override == "expand") {
                    expand = 1;
                } else {
                    expand = 0;
                }
            }

            if (expand) {
                // expand
                DOM.removeClassName($(subheaderid), 'collapsed');
                DOM.addClassName($(subheaderid), 'expanded');

                DOM.getElementsByClassName($(subheaderid), 'collapse-button')
                    .forEach( function(button) {
                        button.innerText = self.ml.expanded;
                    } );

                $(proplistid).style.display = "block";
            } else {
                // collapse
                DOM.removeClassName($(subheaderid), 'expanded');
                DOM.addClassName($(subheaderid), 'collapsed');

                DOM.getElementsByClassName($(subheaderid), 'collapse-button')
                    .forEach( function(button) {
                        button.innerText = self.ml.collapsed;
                    } );

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
