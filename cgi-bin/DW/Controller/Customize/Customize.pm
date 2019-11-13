#!/usr/bin/perl
#
# DW::Controller::Customize
#
# This controller is for customize handlers.
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
package DW::Controller::Customize;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Logic::MenuNav;
use JSON;
use Carp;

# This registers a static string, which is an application page.
DW::Routing->register_string( '/customize/', \&customize_handler, app => 1 );

DW::Routing->register_rpc( "themechooser",  \&themechooser_handler,  format => 'json' );
DW::Routing->register_rpc( "journaltitles", \&journaltitles_handler, format => 'html' );
DW::Routing->register_rpc( "layoutchooser", \&layoutchooser_handler, format => 'html' );
DW::Routing->register_rpc( "themefilter",   \&filter_handler,        format => 'json' );

sub customize_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $post   = $r->post_args;
    my $u      = $rv->{u};
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;

    my $vars;
    $vars->{u}            = $u;
    $vars->{remote}       = $remote;
    $vars->{is_identity}  = 1 if $u->is_identity;
    $vars->{is_community} = 1 if $u->is_community;
    $vars->{style}        = LJ::Customize->verify_and_load_style($u);
    $vars->{authas_html}  = $rv->{authas_html};

    my $queryargs = make_queryargs($GET);

    if ( $u ne $remote ) {
        $queryargs->{authas} = $u->user;
    }

    # lazy migration of style name
    LJ::Customize->migrate_current_style($u);

    # set up the keywords for basic search
    my @keywords        = LJ::Customize->get_search_keywords_for_js($u);
    my $keywords_string = join( ",", @keywords );
    $vars->{keywords_string} = $keywords_string;

    # we want to have "All" selected if we're filtering by layout or designer, or if we're searching
    $vars->{viewing_all} = $queryargs->{layoutid} || $queryargs->{designer} || $queryargs->{search};

    # sort cats by specificed order key, then alphabetical order
    my %cats = LJ::Customize->get_cats($u);
    $vars->{cats} = \%cats;
    my @cats_sorted =
        sort { $cats{$a}->{order} <=> $cats{$b}->{order} }
        sort { lc $cats{$a}->{text} cmp lc $cats{$b}->{text} } keys %cats;

    # pull the main cats out of the full list
    my @main_cats_sorted;
    for ( my $i = 0 ; $i < @cats_sorted ; $i++ ) {
        my $c = $cats_sorted[$i];

        if ( defined $cats{$c}->{main} ) {
            my $el = splice( @cats_sorted, $i, 1 );
            push @main_cats_sorted, $el;
            $i--;    # we just removed an element from @cats_sorted
        }
    }

    $vars->{main_cats_sorted} = \@main_cats_sorted;
    $vars->{cats_sorted}      = \@cats_sorted;

    my @custom_themes = LJ::S2Theme->load_by_user($u);

    # get the theme subset we're currently viewing and assign the correct title label

    my $viewing_featured = !$vars->{cat} && !$vars->{layoutid} && !$vars->{designer};

    my $style = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;

    # pass our computed values to the template
    $vars->{style}              = $style;
    $vars->{custom_themes}      = \@custom_themes;
    $vars->{help_icon}          = \&LJ::help_icon;
    $vars->{get_s2_prop_values} = sub { LJ::Customize->get_s2_prop_values(@_); };
    $vars->{qargs}              = $queryargs;

    my $url = "customize/";

    #handle post actions

    if ( $r->did_post ) {
        if ( $post->{"action_apply"} ) {

            my $themeid  = $post->{apply_themeid};
            my $layoutid = $post->{apply_layoutid};

            set_theme( apply_themeid => $themeid, apply_layout => $layoutid );

        }
        elsif ( $post->{"save"} ) {

            set_journaltitles($post);

        }
        elsif ( $post->{filter} ) {
            $queryargs->{page} = 1;
        }
        elsif ( $post->{page} ) {
            $queryargs->{page} = LJ::eurl( $post->{page} );
        }
        elsif ( $post->{show} ) {
            $queryargs->{show} = LJ::eurl( $post->{show} );
            $queryargs->{page} = 1;
        }
        elsif ( $post->{search} ) {
            $queryargs->{search} = LJ::eurl( $post->{search} );
        }
        elsif ( $post->{which_title} ) {
            my $eff_val = LJ::text_trim( $post->{title_value}, 0, LJ::std_max_length() );
            $eff_val = "" unless $eff_val;
            $u->set_prop( $post->{which_title}, $eff_val );
        }
        elsif ( $post->{apply_layout} ) {

            set_layout(
                {
                    layout_choice     => $post->{layout_choice},
                    layout_prop       => $post->{layout_prop},
                    show_sidebar_prop => $post->{show_sidebar_prop},
                    u                 => $u
                }
            );
        }
        my $redir = LJ::create_url( $url, args => $queryargs, no_blank => 1 );
        return $r->redirect($redir);

    }

    # get the current theme id - at the end because post actions may have changed it.

    $vars->{render_themechooser}  = \&render_themechooser;
    $vars->{render_journaltitles} = \&render_journaltitles;
    $vars->{render_layoutchooser} = \&render_layoutchooser;
    $vars->{render_currenttheme}  = \&render_currenttheme;
    $vars->{c_url}                = \&customize_url;

    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize/customize.tt', $vars );

}

sub customize_url {
    my ( $cur_args, $args, $path, $frag ) = @_;
    my %opts = (
        keep_args => 1,
        no_blank  => 1
    );

    my $url = defined $path ? "/customize/" . $path : "/customize/";
    $opts{args}     = defined $args     ? $args     : {};
    $opts{cur_args} = defined $cur_args ? $cur_args : {};
    $opts{fragment} = defined $frag     ? $frag     : undef;

    return LJ::create_url( $url, %opts );
}

sub themechooser_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    # gets the request and args

    my $r        = DW::Request->get;
    my $args     = $r->post_args;
    my $themeid  = $args->{apply_themeid};
    my $layoutid = $args->{apply_layoutid};
    my $getargs  = make_queryargs($args);

    # apply the new theme selected

    set_theme( apply_themeid => $themeid, apply_layoutid => $layoutid );

    my $themechooser_html  = render_themechooser($getargs);
    my $layoutchooser_html = render_layoutchooser();
    my $currenttheme_html  = render_currenttheme( 'show', $getargs->{show} );

    $r->print(
        to_json(
            {
                themechooser  => $themechooser_html,
                layoutchooser => $layoutchooser_html,
                currenttheme  => $currenttheme_html
            }
        )
    );
    return $r->OK;

}

sub set_theme {
    my %opts = @_;
    my $u    = LJ::get_effective_remote();

    die "Invalid user." unless LJ::isu($u);

    my $themeid  = $opts{apply_themeid} + 0;
    my $layoutid = $opts{apply_layoutid} + 0;

    my $theme;
    if ($themeid) {
        $theme = LJ::S2Theme->load_by_themeid( $themeid, $u );
    }
    elsif ($layoutid) {
        $theme = LJ::S2Theme->load_custom_layoutid( $layoutid, $u );
    }
    else {
        die "No theme id or layout id specified.";
    }

    LJ::Customize->apply_theme( $u, $theme ) or croak("Couldn't apply theme");
    LJ::Hooks::run_hooks( 'apply_theme', $u );
}

sub render_themechooser {
    my $queryargs = shift;
    my $vars;
    my @themes;
    my $u      = LJ::get_effective_remote();
    my $remote = LJ::get_remote();
    my %cats   = LJ::Customize->get_cats($u);

    if ( $u ne $remote ) {
        $queryargs->{authas} = $u->user;
    }

    $vars->{u}    = $u;
    $vars->{cats} = \%cats;

    my $current_theme_id = LJ::Customize->get_current_theme($u);
    $vars->{current_theme_id} = $current_theme_id;

    if ( $queryargs->{cat} eq "base" ) {

        # sort alphabetically by layout
        @themes = sort { lc $a->layout_name cmp lc $b->layout_name } @themes;
    }
    else {
        # sort themes with custom at the end, then alphabetically by theme
        @themes =
            sort { $a->is_custom <=> $b->is_custom }
            sort { lc $a->name cmp lc $b->name } @themes;
    }

    # remove any themes from the array that are not defined or whose layout or theme is not active
    for ( my $i = 0 ; $i < @themes ; $i++ ) {
        my $layout_is_active = LJ::Hooks::run_hook( "layer_is_active", $themes[$i]->layout_uniq );
        my $theme_is_active  = LJ::Hooks::run_hook( "layer_is_active", $themes[$i]->uniq );

        unless ( ( defined $themes[$i] )
            && ( !defined $layout_is_active || $layout_is_active )
            && ( !defined $theme_is_active  || $theme_is_active ) )
        {

            splice( @themes, $i, 1 );
            $i--;    # we just removed an element from @themes
        }
    }

    if ( $queryargs->{cat} eq "all" ) {
        @themes = LJ::S2Theme->load_all($u);
    }
    elsif ( $queryargs->{cat} eq "custom" ) {
        @themes = LJ::S2Theme->load_by_user($u);
    }
    elsif ( $queryargs->{cat} eq "base" ) {
        @themes = LJ::S2Theme->load_default_themes();
    }
    elsif ( $queryargs->{cat} ) {
        @themes = LJ::S2Theme->load_by_cat( $queryargs->{cat} );
    }
    elsif ( $queryargs->{layoutid} ) {
        @themes = LJ::S2Theme->load_by_layoutid( $queryargs->{layoutid}, $u );
    }
    elsif ( $queryargs->{designer} ) {
        @themes = LJ::S2Theme->load_by_designer( $queryargs->{designer} );
    }
    elsif ( $queryargs->{search} ) {
        @themes = LJ::S2Theme->load_by_search( $queryargs->{search}, $u );
    }
    else {    # category is "featured"
        @themes = LJ::S2Theme->load_by_cat("featured");
    }

    @themes = LJ::Customize->remove_duplicate_themes(@themes);

    $vars->{max_page} =
        $queryargs->{show} ne "all" ? POSIX::ceil( scalar(@themes) / $queryargs->{show} ) || 1 : 1;
    $vars->{themes}          = \@themes;
    $vars->{qargs}           = $queryargs;
    $vars->{run_hook}        = \&LJ::Hooks::run_hook;
    $vars->{img_prefix}      = $LJ::IMGPREFIX;
    $vars->{get_layout_name} = sub { LJ::Customize->get_layout_name(@_); };
    $vars->{c_url}           = \&customize_url;

    return DW::Template->template_string( 'customize/themechooser.tt', $vars );

}

sub filter_handler {

    # gets the request and args
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $args      = $r->get_args;
    my $queryargs = make_queryargs($args);

    my $themechooser_html = render_themechooser($queryargs);
    my $currenttheme_html = render_currenttheme( 'show', $queryargs->{show} );

    $r->print(
        to_json( { themechooser => $themechooser_html, currenttheme => $currenttheme_html } ) );
    return $r->OK;
}

sub render_currenttheme {
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);
    my $remote = LJ::get_remote();

    my $queryargs;
    $queryargs->{show}   = $opts{show} || 12;
    $queryargs->{authas} = $u->user ne $remote->user ? $u->user : "";

    my $no_themechooser = defined $opts{no_themechooser} ? $opts{no_themechooser} : 0;
    my $no_layer_edit   = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

    my $theme   = LJ::Customize->get_current_theme($u);
    my $userlay = LJ::S2::get_layers_of_user($u);

    my $vars;
    $vars->{u}               = $u;
    $vars->{theme}           = $theme;
    $vars->{qargs}           = $queryargs;
    $vars->{no_themechooser} = $no_themechooser;
    $vars->{userlay}         = $userlay;
    $vars->{no_layer_edit}   = $no_layer_edit;
    $vars->{is_special}      = LJ::Hooks::run_hook( "layer_is_special", $theme->uniq );
    $vars->{c_url}           = \&customize_url;

    return DW::Template->template_string( 'customize/currenttheme.tt', $vars );
}

sub make_queryargs {
    my $args = shift;
    my $ret_args;

    $ret_args->{cat}      = defined $args->{cat}      ? $args->{cat}      : "";
    $ret_args->{layoutid} = defined $args->{layoutid} ? $args->{layoutid} : 0;
    $ret_args->{designer} = defined $args->{designer} ? $args->{designer} : "";
    $ret_args->{search}   = defined $args->{search}   ? $args->{search}   : "";
    $ret_args->{page}     = defined $args->{page}     ? $args->{page}     : 1;
    $ret_args->{show}     = defined $args->{show}     ? $args->{show}     : 12;

    return $ret_args;
}

sub layoutchooser_handler {

    # gets the request and args
    my $r    = DW::Request->get;
    my $args = $r->post_args;

    # set the new titles

    set_layout($args);

    $r->print( render_layoutchooser($args) );
    return $r->OK;
}

sub set_layout {
    my $post = shift;

    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my %override;
    my $layout_choice     = $post->{layout_choice};
    my $layout_prop       = $post->{layout_prop};
    my $show_sidebar_prop = $post->{show_sidebar_prop};
    my $current_theme_id  = LJ::Customize->get_current_theme($u);
    my %layouts           = $current_theme_id->layouts;

    # show_sidebar prop is set to false/0 if the 1 column layout was chosen,
    # otherwise it's set to true/1 and the layout prop is set appropriately.
    if ( $show_sidebar_prop && $layout_choice eq "1" ) {
        $override{$show_sidebar_prop} = 0;
    }
    else {
        $override{$show_sidebar_prop} = 1 if $show_sidebar_prop;
        $override{$layout_prop} = $layouts{$layout_choice} if $layout_prop;
    }

    my $style = LJ::S2::load_style( $u->prop('s2_style') );
    die "Style not found." unless $style && $style->{userid} == $u->id;

    LJ::Customize->save_s2_props( $u, $style, \%override );
}

sub render_layoutchooser {
    my %opts = @_;
    my $vars;
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $current_theme_id = LJ::Customize->get_current_theme($u);
    $vars->{current_theme_id} = $current_theme_id;
    my %layouts = $current_theme_id->layouts;
    $vars->{layouts} = \%layouts;
    my $show_sidebar_prop = $current_theme_id->show_sidebar_prop;
    $vars->{get_layout_name} = sub { LJ::Customize->get_layout_name(@_); };
    my %layout_names = LJ::Customize->get_layouts;
    $vars->{layout_names}    = \%layout_names;
    $vars->{img_prefix}      = $LJ::IMGPREFIX;
    $vars->{no_themechooser} = $opts{no_themechooser};

    my $layout_prop = $current_theme_id->layout_prop;

    my $prop_value;
    if ( $layout_prop || $show_sidebar_prop ) {
        my $style = LJ::S2::load_style( $u->prop('s2_style') );
        die "Style not found." unless $style && $style->{userid} == $u->id;

        if ($layout_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values( $layout_prop, $u, $style );
            carp;
            $prop_value = $prop_values{override};
        }

        # for layouts that have a separate prop that turns off the sidebar, use the value of that
        # prop instead if the sidebar is set to be off (false/0).
        if ($show_sidebar_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values( $show_sidebar_prop, $u, $style );
            $prop_value = $prop_values{override} if $prop_values{override} == 0;
        }
    }

    $vars->{prop_value} = $prop_value;

    $vars->{u} = $u;
    return DW::Template->template_string( 'customize/layoutchooser.tt', $vars );
}

sub journaltitles_handler {

    # gets the request and args
    my $r    = DW::Request->get;
    my $args = $r->post_args;

    # set the new titles

    set_journaltitles($args);

    $r->print( render_journaltitles() );
    return $r->OK;
}

sub set_journaltitles {
    my $post = shift;

    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $eff_val = LJ::text_trim( $post->{title_value}, 0, LJ::std_max_length() );
    $eff_val = "" unless $eff_val;
    $u->set_prop( $post->{which_title}, $eff_val );
}

sub render_journaltitles {
    my %opts = @_;
    my $vars;
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    $vars->{u}               = $u;
    $vars->{no_themechooser} = $opts{no_themechooser};
    return DW::Template->template_string( 'customize/journaltitles.tt', $vars );
}

1;
