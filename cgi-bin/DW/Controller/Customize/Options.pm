#!/usr/bin/perl
#
# DW::Controller::Customize::Options
#
# This controller is for /customize/options and the helper functions for that view.
#
# Authors:
#      R Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Controller::Customize::Options;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Logic::MenuNav;
use JSON;

# This registers a static string, which is an application page.
DW::Routing->register_string( '/customize/options', \&options_handler, app => 1 );

DW::Routing->register_rpc( "moodtheme", \&moodtheme_handler, format => 'json' );

sub options_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r        = $rv->{r};
    my $POST     = $r->post_args;
    my $u        = $rv->{u};
    my $remote   = $rv->{remote};
    my $GET      = $r->get_args;
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";
    my $style    = LJ::Customize->verify_and_load_style($u);

    my $vars;

    # variables holding information about the user and their style
    $vars->{u}            = $u;
    $vars->{remote}       = $remote;
    $vars->{getextra}     = $getextra;
    $vars->{getsep}       = $getsep;
    $vars->{is_identity}  = 1 if $u->is_identity;
    $vars->{is_community} = 1 if $u->is_community;
    $vars->{style}        = $style;
    $vars->{authas_html}  = $rv->{authas_html};

    # variables holding subroutine references for building other elements of the view
    $vars->{render_journaltitles}  = \&DW::Controller::Customize::render_journaltitles;
    $vars->{render_layoutchooser}  = \&DW::Controller::Customize::render_layoutchooser;
    $vars->{render_customizetheme} = \&render_customizetheme;
    $vars->{render_currenttheme}   = \&DW::Controller::Customize::render_currenttheme;

    $vars->{show} = defined $GET->{show} ? $GET->{show} : 12;
    my $show = $vars->{show};

    LJ::Customize->migrate_current_style($u);

    $vars->{group} = $GET->{group} ? $GET->{group} : "presentation";

    #handle post actions

    my ( $given_moodthemeid, $given_forcemoodtheme );

    if ( $r->did_post ) {
        return error_ml('error.invalidform')
            unless LJ::check_form_auth( $POST->{lj_form_auth} );

        if ( $POST->{'action:morelinks'} ) {
            $vars->{morelinks} = 1;
            $vars->{numlinks}  = $POST->{numlinks};
        }

        # this is handled in render_body
        elsif ( $POST->{'reset'} ) {

            # reset all props except the layout props
            my $current_theme     = LJ::Customize->get_current_theme($u);
            my $layout_prop       = $current_theme->layout_prop;
            my $show_sidebar_prop = $current_theme->show_sidebar_prop;

            my %override = %$POST;
            delete $override{$layout_prop};
            delete $override{$show_sidebar_prop};

            foreach my $val ( keys %$POST ) {
                next unless $val =~ /^link_\d+_title$/ || $val =~ /^link_\d+_url$/;

                $POST->{$val} = "";
            }

            $given_moodthemeid    = 1;
            $given_forcemoodtheme = 0;

            LJ::Customize->save_s2_props( $u, $style, \%override, reset => 1 );
            LJ::Customize->save_language( $u, $POST->{langcode}, reset => 1 )
                if defined $POST->{langcode};

            # clear the custom-text values if we're on the text group page
            if ( $vars->{group} eq 'text' ) {
                $u->set_prop( 'customtext_title', "Custom Text" );
                $u->clear_prop('customtext_url');
                $u->clear_prop('customtext_content');
            }
        }
        else {
            my %override = map { $_ => "" } keys %$POST;

            # we need to remove properties that are set in userprops and
            # handle checkboxes, which can have multiple values, so we can
            # 'see' checkboxes the user has unchecked. If there are mutiple
            # values, we know the box has been checked.
            foreach my $key ( keys %$POST ) {
                next
                    if $key eq 'module_customtext_title'
                    || $key eq 'module_customtext_url'
                    || $key eq 'module_customtext_content'
                    ;    # don't add customtext fields, we save these in userprops instead

                my @value = $POST->get_all($key);
                $override{$key} = $#value > 0 ? 'on' : $value[0];

            }

            $given_moodthemeid    = $POST->{moodthemeid};
            $given_forcemoodtheme = $POST->{opt_forcemoodtheme};

            my $given_control_strip_color  = $POST->{control_strip_color};
            my $given_control_strip_custom = $POST->{control_strip_custom};

            if ( $given_control_strip_custom ne "custom" ) {
                $override{custom_control_strip_colors} = "off";
            }
            else {
                if ( $given_control_strip_custom eq "custom" ) {
                    if ( $POST->{control_strip_no_gradient_custom} ) {
                        $override{custom_control_strip_colors} = "on_no_gradient";
                    }
                    else {
                        $override{custom_control_strip_colors} = "on_gradient";
                    }

                    $override{control_strip_bgcolor}     = $POST->{control_strip_bgcolor}     || "";
                    $override{control_strip_fgcolor}     = $POST->{control_strip_fgcolor}     || "";
                    $override{control_strip_bordercolor} = $POST->{control_strip_bordercolor} || "";
                    $override{control_strip_linkcolor}   = $POST->{control_strip_linkcolor}   || "";
                }
            }

            $u->set_prop( 'control_strip_color', $given_control_strip_color );

            LJ::Customize->save_s2_props( $u, $style, \%override );
            LJ::Customize->save_language( $u, $POST->{langcode} ) if defined $POST->{langcode};

            # try and set custom-text values only if we're on the text group page
            # otherwise we'll clobber them with blank fields
            if ( $vars->{group} eq 'text' ) {
                $u->set_prop( 'customtext_title',   $POST->{module_customtext_title} );
                $u->set_prop( 'customtext_url',     $POST->{module_customtext_url} );
                $u->set_prop( 'customtext_content', $POST->{module_customtext_content} );
            }

            # if we're on the linklist page, process the form into a link object
            # and save it for the user
            if ( $vars->{group} eq 'linkslist' ) {
                my $linkobj = LJ::Links::make_linkobj_from_form( $u, $POST->as_hashref );
                LJ::Links::save_linkobj( $u, $linkobj );

            }
        }

        #handle mood theme updates
        my %update;
        my $moodthemeid = LJ::Customize->validate_moodthemeid( $u, $given_moodthemeid );
        $update{moodthemeid}        = $moodthemeid;
        $update{opt_forcemoodtheme} = $given_forcemoodtheme ? "Y" : "N";

        # update 'user' table
        foreach ( keys %update ) {
            delete $update{$_} if $u->{$_} eq $update{$_};
        }
        $u->update_self( \%update ) if %update;

        # reload the user object to force the display of these changes
        $u = LJ::load_user( $u->user, 'force' );

    }

    return DW::Template->render_template( 'customize/options.tt', $vars );

}

# renders the part of the view that holds the option groups and their nav
sub render_customizetheme {
    my $vars;
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);
    my %opts = @_;

    my $remote   = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";
    my $style    = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;
    my %groups      = LJ::Customize->get_propgroups( $u, $style );
    my $group_names = $groups{groups};

    my $group = $opts{group} ? $opts{group} : "display";

    $vars->{u}              = $u;
    $vars->{remote}         = $remote;
    $vars->{getextra}       = ( $u ne $remote ) ? ( "?authas=" . $u->user ) : '';
    $vars->{getsep}         = $getsep;
    $vars->{style}          = $style;
    $vars->{groups}         = \%groups;
    $vars->{group_names}    = $group_names;
    $vars->{propgroup_name} = sub { LJ::Customize->propgroup_name(@_); };
    $vars->{has_customcss} = 1;        #FIXME (map { customcss => 1 } @$group_names);
    $vars->{group}         = $group;

    $vars->{help_icon} = \&LJ::help_icon;
    my @moodthemes = LJ::Customize->get_moodtheme_select_list($u);
    $vars->{moodthemes} = \@moodthemes;
    my $preview_moodthemeid =
        defined $opts{preview_moodthemeid} ? $opts{preview_moodthemeid} : $u->moodtheme;
    my $forcemoodtheme =
        defined $opts{forcemoodtheme} ? $opts{forcemoodtheme} : $u->{opt_forcemoodtheme} eq 'Y';
    $vars->{preview_moodthemeid} = $preview_moodthemeid;
    $vars->{forcemoodtheme}      = $forcemoodtheme;
    my $mood_previews = $preview_moodthemeid ? moodtheme_preview($preview_moodthemeid) : undef;
    $vars->{mood_previews} = $mood_previews;

    my $theme        = LJ::Customize->get_current_theme($u);
    my @props        = S2::get_properties( $theme->layoutid );
    my %prop_is_used = map { $_ => 1 } @props;

    my %navstrip_custom_colors;
    my %navstrip_options =
        LJ::Customize->get_s2_prop_values( "custom_control_strip_colors", $u, $style );
    $navstrip_custom_colors{control_strip_bgcolor} =
        LJ::Customize->get_s2_prop_values( "control_strip_bgcolor", $u, $style );
    $navstrip_custom_colors{control_strip_fgcolor} =
        LJ::Customize->get_s2_prop_values( "control_strip_fgcolor", $u, $style );
    $navstrip_custom_colors{control_strip_bordercolor} =
        LJ::Customize->get_s2_prop_values( "control_strip_bordercolor", $u, $style );
    $navstrip_custom_colors{control_strip_linkcolor} =
        LJ::Customize->get_s2_prop_values( "control_strip_linkcolor", $u, $style );

    $vars->{props}                  = \@props;
    $vars->{navstrip_options}       = \%navstrip_options;
    $vars->{navstrip_custom_colors} = \%navstrip_custom_colors;
    $vars->{get_property}           = sub { S2::get_property( $theme->coreid, $_ ); };
    $vars->{prop_is_used}           = \%prop_is_used;
    $vars->{isref}                  = sub { return ref $_; };
    $vars->{nav_class}              = sub {
        my $g       = shift;
        my $classes = "";

        if ( $g eq $group ) {
            $classes .= " class='on";
            $classes .= "'";
        }

        return $classes;
    };
    $vars->{render_s2propgroup}  = \&render_s2propgroup;
    $vars->{render_linkslist}    = \&render_linkslist;
    $vars->{render_currenttheme} = \&DW::Controller::Customize::render_currenttheme;

    return DW::Template->template_string( 'customize/customizetheme.tt', $vars );

}

# renders the options lists within customizetheme.
sub render_s2propgroup {
    my $vars;
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $style = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;

    my $remote   = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep   = $getextra ? "&" : "?";
    my %opts     = @_;

    $vars->{u}        = $u;
    $vars->{remote}   = $remote;
    $vars->{getextra} = $getextra;
    $vars->{getsep}   = $getsep;
    $vars->{style}    = $style;

    my $props      = $opts{props};
    my $propgroup  = $opts{propgroup};
    my $groupprops = $opts{groupprops};
    return "DIED" unless ( $props && $propgroup && $groupprops ) || $opts{show_lang_chooser};

    my $theme = LJ::Customize->get_current_theme($u);

    # get the custom text settings from the S2 layers, in case the userprops are empty.
    my %module_custom_text_title =
        LJ::Customize->get_s2_prop_values( "text_module_customtext", $u, $style );
    my %module_custom_text_url =
        LJ::Customize->get_s2_prop_values( "text_module_customtext_url", $u, $style );
    my %module_custom_text_content =
        LJ::Customize->get_s2_prop_values( "text_module_customtext_content", $u, $style );

    # go for userprop values first, layer values second.
    my $custom_text_title =
          $u->prop('customtext_title') ne ''
        ? $u->prop('customtext_title')
        : "Custom Text";
    my $custom_text_url = $u->prop('customtext_url') || $module_custom_text_url{override};
    my $custom_text_content =
        $u->prop('customtext_content') || $module_custom_text_content{override};

    $vars->{custom_text_title}    = $custom_text_title;
    $vars->{custom_text_url}      = $custom_text_url;
    $vars->{custom_text_content}  = $custom_text_content;
    $vars->{theme}                = $theme;
    $vars->{props}                = $props;
    $vars->{propgroup}            = $propgroup;
    $vars->{groupprops}           = $groupprops;
    $vars->{propgroup_name}       = sub { LJ::Customize->propgroup_name(@_); };
    $vars->{skip_prop}            = \&skip_prop;
    $vars->{help_icon}            = \&LJ::help_icon;
    $vars->{output_prop}          = \&output_prop;
    $vars->{get_subheaders}       = sub { LJ::Customize->get_propgroup_subheaders; };
    $vars->{get_subheaders_order} = sub { LJ::Customize->get_propgroup_subheaders_order; };
    $vars->{output_prop_element}  = \&output_prop_element;

    if ( $propgroup eq "presentation" ) {
        my @basic_props   = $theme->display_option_props;
        my %is_basic_prop = map { $_ => 1 } @basic_props;

        $vars->{basic_props}   = \@basic_props;
        $vars->{is_basic_prop} = \%is_basic_prop;

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
        $vars->{layout_sections_order} = \@layout_sections_order;
        $vars->{prop_in_subheader}     = \%prop_in_subheader;
        $vars->{subheaders}            = \%subheaders;
        $vars->{grouped_prop_override} = \%grouped_prop_override;

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
        $vars->{unsorted_props} = \%unsorted_props;
        $vars->{subheaders}     = \%subheaders;
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

        $vars->{unsorted_props} = \%unsorted_props;
        $vars->{subheaders}     = \%subheaders;

    }

    if ( $opts{show_lang_chooser} ) {

        my $pub     = LJ::S2::get_public_layers();
        my $userlay = LJ::S2::get_layers_of_user($u);

        my @langs    = LJ::S2::get_layout_langs( $pub, $style->{'layout'} );
        my $get_lang = sub {
            my $styleid = shift;
            foreach ( $userlay, $pub ) {
                return $_->{$styleid}->{'langcode'}
                    if $_->{$styleid} && $_->{$styleid}->{'langcode'};
            }
            return undef;
        };

        my $langcode = $get_lang->( $style->{'i18n'} ) || $get_lang->( $style->{'i18nc'} );

        # they have set a custom i18n layer
        if ( $style->{'i18n'}
            && ( $style->{'i18nc'} != $style->{'i18n'} || !defined $pub->{ $style->{'i18n'} } ) )
        {
            push @langs, 'custom', DW::ml('widget.s2propgroup.language.custom');
            $langcode = 'custom';
        }
        $vars->{show_lang_chooser} = 1;
        $vars->{langcode}          = $langcode;
        $vars->{langs}             = \@langs;
    }

    return DW::Template->template_string( 'customize/s2propgroup.tt', $vars );
}

# Helper subroutine to determine which properties not to show in the normal
# flow. These include hiding user-only properties if we're working as
# a community, navstrip color blocks, because they're handled seperately,
# and layout props, which have their own UI already.

sub skip_prop {

    my ( $prop, $prop_name, %opts ) = @_;

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

# Helper function to pull out the necessary bits of data
# for formatting property form elements.

sub output_prop_element {
    my ( $prop, $prop_name, $u, $style, $theme, $props, $is_group, $grouped_prop_override,
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

    my $vars;
    my @values;
    @values = split( /\|/, $prop->{values} ) if $prop->{values};
    $vars->{name}                  = $name;
    $vars->{type}                  = $type;
    $vars->{can_use}               = $can_use;
    $vars->{existing_display}      = $existing_display;
    $vars->{grouped_prop_override} = $grouped_prop_override;
    $vars->{theme}                 = $theme;
    $vars->{u}                     = $u;
    $vars->{style}                 = $style;
    $vars->{is_group}              = $is_group;
    $vars->{props}                 = $props;
    $vars->{prop}                  = $prop;
    $vars->{overriding_values}     = $overriding_values;
    $vars->{help_icon}             = \&LJ::help_icon;
    $vars->{output_prop_element}   = \&output_prop_element;
    $vars->{override}              = $override;
    $vars->{value_list}            = \@values;

    return DW::Template->template_string( 'customize/output_prop_element.tt', $vars );

}

sub render_linkslist {
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $linkobj  = LJ::Links::load_linkobj( $u, "master" );
    my $link_min = 5;                                         # how many do they start with ?
    my $link_more  = 5;     # how many do they get when they click "more"
    my $order_step = 10;    # step order numbers by

    # how many link inputs to show?
    my $showlinks = $opts{numlinks} || @$linkobj;
    my $caplinks  = $u->count_max_userlinks;
    $showlinks += $link_more if $opts{morelinks};
    $showlinks = $link_min if $showlinks < $link_min;
    $showlinks = $caplinks if $showlinks > $caplinks;

    my $vars;
    $vars->{linkobj}    = $linkobj;
    $vars->{link_min}   = $link_min;
    $vars->{link_more}  = $link_more;
    $vars->{order_step} = $order_step;
    $vars->{showlinks}  = $showlinks;
    $vars->{caplinks}   = $caplinks;

    return DW::Template->template_string( 'customize/linkslist.tt', $vars );
}

sub moodtheme_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r                 = DW::Request->get;
    my $args              = $r->post_args;
    my $u                 = LJ::get_effective_remote();
    my $given_moodthemeid = $args->{preview_moodthemeid};
    die "Invalid user." unless LJ::isu($u);

    my $moodthemeid = LJ::Customize->validate_moodthemeid( $u, $given_moodthemeid );

    $r->print( moodtheme_preview($moodthemeid) );
    return $r->OK;

}

sub moodtheme_preview {
    my $moodtheme_id = $_[0];
    my $moodtheme    = DW::Mood->new($moodtheme_id);
    my $previews     = {};

    foreach my $mood ( 'happy', 'sad', 'angry', 'tired' ) {
        my %pic;
        if ( $moodtheme->get_picture( $moodtheme->mood_id($mood), \%pic ) ) {
            $previews->{$mood} = {
                src => $pic{pic},
                w   => $pic{w},
                h   => $pic{h},
            };
        }
    }

    my $vars;
    $vars->{mood_previews} = $previews;
    $vars->{desc}          = $moodtheme->des;
    return DW::Template->template_string( 'customize/moodtheme_preview.tt', $vars );
}

1;
