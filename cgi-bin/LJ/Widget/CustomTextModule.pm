#!/usr/bin/perl
#
# LJ::Widget::CustomTextModule
#
# This file is the display widget for Custom Text module options, which allows
# users to set and clear custom text saved in their user properties.
#
# Authors:
#      Momiji <momijizukamori@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

#
package LJ::Widget::CustomTextModule;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::Customize;

sub ajax   { 1 }
sub authas { 1 }

sub render_body {
    my $class = shift;
    my %opts  = @_;
    my $count = $opts{count};

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $ret;

    # if userprops are blank, populate with S2 layer data instead
    my ( $theme, @props, %prop_is_used, %module_custom_text_title, %module_custom_text_url,
        %module_custom_text_content );
    if ( $u->prop('stylesys') == 2 ) {
        $theme        = LJ::Customize->get_current_theme($u);
        @props        = S2::get_properties( $theme->layoutid );
        %prop_is_used = map { $_ => 1 } @props;

        my $style = LJ::S2::load_style( $u->prop('s2_style') );
        die "Style not found." unless $style && $style->{userid} == $u->id;

        %module_custom_text_title =
            LJ::Customize->get_s2_prop_values( "text_module_customtext", $u, $style );
        %module_custom_text_url =
            LJ::Customize->get_s2_prop_values( "text_module_customtext_url", $u, $style );
        %module_custom_text_content =
            LJ::Customize->get_s2_prop_values( "text_module_customtext_content", $u, $style );

    }

    # fill text if it's totally empty.
    my $custom_text_title =
          $u->prop('customtext_title') ne ''
        ? $u->prop('customtext_title')
        : "Custom Text";
    my $custom_text_url = $u->prop('customtext_url') || $module_custom_text_url{override};
    my $custom_text_content =
        $u->prop('customtext_content') || $module_custom_text_content{override};

    my $row_class = $count % 2 == 0 ? " even" : " odd";

    $ret .=
          "<tr class='prop-row "
        . $row_class
        . "' valign='top' width='100%'><td class='prop-header' valign='top'>"
        . $class->ml('widget.customtext.title') . "</td>";
    $ret .= "<td valign='top'>"
        . $class->html_text(
        name  => "module_customtext_title",
        size  => 20,
        value => $custom_text_title,
        ) . "</td></tr>";

    $count++;
    $row_class = $count % 2 == 0 ? " even" : " odd";

    $ret .=
          "<tr class='prop-row "
        . $row_class
        . "' valign='top' width='100%'><td class='prop-header' valign='top'>"
        . $class->ml('widget.customtext.url') . "</td>";
    $ret .= "<td valign='top'>"
        . $class->html_text(
        name  => "module_customtext_url",
        size  => 20,
        value => $custom_text_url,
        ) . "</td></tr>";

    $count++;
    $row_class = $count % 2 == 0 ? " even" : " odd";

    $ret .=
          "<tr class='prop-row "
        . $row_class
        . "' valign='top' width='100%'><td class='prop-header' valign='top'>"
        . $class->ml('widget.customtext.content')
        . "<br />";
    $ret .= "<td valign='top'>"
        . $class->html_textarea(
        name  => "module_customtext_content",
        rows  => 10,
        cols  => 50,
        wrap  => 'soft',
        value => $custom_text_content,
        ) . "</td></tr>";
    $ret .= "</div>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post  = shift;
    my %opts  = @_;

    my $u = $class->get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my %override;
    my $post_fields_of_parent = LJ::Widget->post_fields_of_widget("CustomizeTheme");
    my ( $given_control_strip_color, $props );
    if ( $post_fields_of_parent->{reset} ) {
        $u->set_prop( 'customtext_title', "Custom Text" );
        $u->clear_prop('customtext_url');
        $u->clear_prop('customtext_content');
    }
    else {
        $u->set_prop( 'customtext_title',   $post->{module_customtext_title} );
        $u->set_prop( 'customtext_url',     $post->{module_customtext_url} );
        $u->set_prop( 'customtext_content', $post->{module_customtext_content} );
    }

    return;
}

sub should_render {
    my $class = shift;

    return 1;
}

1;
