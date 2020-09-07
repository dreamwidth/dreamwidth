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

DW::Routing->register_string( '/customize/',        \&customize_handler, app => 1 );
DW::Routing->register_string( '/customize/options', \&options_handler,   app => 1 );

DW::Routing->register_rpc( "themechooser",  \&themechooser_handler,  format => 'json' );
DW::Routing->register_rpc( "journaltitles", \&journaltitles_handler, format => 'html' );
DW::Routing->register_rpc( "layoutchooser", \&layoutchooser_handler, format => 'json' );
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
    $vars->{autocomplete} = \@keywords;

    # we want to have "All" selected if we're filtering by layout or designer, or if we're searching
    $vars->{viewing_all} = $queryargs->{layoutid} || $queryargs->{designer} || $queryargs->{search};

    # sort cats by specificed order key, then alphabetical order
    my %cats = LJ::Customize->get_cats($remote);
    $vars->{cats} = \%cats;
    my @cats_sorted =
        sort { $cats{$a}->{order} <=> $cats{$b}->{order} }
        sort { lc $cats{$a}->{text} cmp lc $cats{$b}->{text} } keys %cats;

    my @custom_themes = LJ::S2Theme->load_by_user($u);

    # pull the main cats out of the full list
    my @main_cats;
    my @other_cats;

    for my $cat (@cats_sorted) {
        next
            if $cat eq 'custom' && !@custom_themes;

        if ( defined $cats{$cat}->{main} ) {
            push @main_cats, $cat;
        }
        else {
            push @other_cats, $cat;
        }
    }

    $vars->{main_cats_sorted} = \@main_cats;
    $vars->{cats_sorted}      = \@other_cats;

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

    my $url = "/customize/";

    #handle post actions

    if ( $r->did_post ) {
        return error_ml('error.invalidform')
            unless LJ::check_form_auth( $post->{lj_form_auth} );

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

    $vars->{theme_data}   = get_themechooser_data($queryargs);
    $vars->{layout_data}  = get_layout_data();
    $vars->{current_data} = get_current_data(0);

    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize/index.tt', $vars );

}

## Handlers for RPC endpoints

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

    my $theme_data = get_themechooser_data($getargs);
    my $theme_html = DW::Template->template_string( 'customize/themechooser.tt',
        { theme_data => $theme_data, qargs => $getargs } );
    my $layout_data  = get_layout_data();
    my $current_data = get_current_data(0);

    $r->print(
        to_json(
            {
                theme_html   => $theme_html,
                layout_data  => $layout_data,
                current_data => $current_data
            }
        )
    );
    return $r->OK;

}

sub filter_handler {

    # gets the request and args
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $args      = $r->get_args;
    my $queryargs = make_queryargs($args);

    my $theme_data = get_themechooser_data($queryargs);
    my $theme_html = DW::Template->template_string( 'customize/themechooser.tt',
        { 'theme_data' => $theme_data, qargs => $queryargs } );
    my $current_data = get_current_data(0);

    $r->print( to_json( { theme_html => $theme_html, current_data => $current_data } ) );
    return $r->OK;
}

sub layoutchooser_handler {

    # gets the request and args
    my $r    = DW::Request->get;
    my $args = $r->post_args;

    # set the new titles

    set_layout($args);

    $r->print( to_json( get_layout_data($args) ) );
    return $r->OK;
}

sub journaltitles_handler {

    # gets the request and args
    my $r    = DW::Request->get;
    my $args = $r->post_args;

    # set the new titles

    set_journaltitles($args);

    return $r->OK;
}

sub options_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $u      = $rv->{u};
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;

    # if using s1, switch them to s2
    unless ( $u->prop('stylesys') == 2 ) {
        $u->set_prop( stylesys => 2 );
    }

    my $group = $GET->{group} ? $GET->{group} : "presentation";

    # make sure there's a style set and load it
    my $style = LJ::Customize->verify_and_load_style($u);

    # lazy migration of style name
    LJ::Customize->migrate_current_style($u);

    my $vars;
    $vars->{u}            = $u;
    $vars->{remote}       = $remote;
    $vars->{is_identity}  = 1 if $u->is_identity;
    $vars->{is_community} = 1 if $u->is_community;
    $vars->{style}        = LJ::Customize->verify_and_load_style($u);
    $vars->{authas_html}  = $rv->{authas_html};

    # pass our computed values to the template
    $vars->{help_icon} = \&LJ::help_icon;

    my $customize_theme = LJ::Widget::CustomizeTheme->new;
    my $headextra       = $customize_theme->wrapped_js( page_js_obj => "Customize" );
    my $ret             = "<div class='customize-wrapper one-percent'>";
    $ret .= $customize_theme->render(
        group     => $group,
        headextra => \$headextra,
        post      => $POST,
    );
    $ret .= "</div><!-- end .customize-wrapper -->";

    #handle post actions

    if ( LJ::did_post() ) {
        my @errors = LJ::Widget->handle_post( $POST,
            qw(CustomizeTheme CustomTextModule MoodThemeChooser NavStripChooser S2PropGroup LinksList)
        );
        $ret .= LJ::bad_input(@errors) if @errors;
    }

    $vars->{content}     = $ret;
    $vars->{layout_data} = get_layout_data();

    $vars->{current_data} = get_current_data(1);

    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize/index.tt', $vars );

}

## Functions to handle edits for both RPC and main endpoints

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

sub set_journaltitles {
    my $post = shift;

    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $eff_val = LJ::text_trim( $post->{title_value}, 0, LJ::std_max_length() );
    $eff_val = "" unless $eff_val;
    $u->set_prop( $post->{which_title}, $eff_val );
}

# Functions to render backend data in a format that is simpler to process in our templates/JS

sub get_themechooser_data {
    my $queryargs = shift;
    my @themes;
    my $u      = LJ::get_effective_remote();
    my $remote = LJ::get_remote();
    my %cats   = LJ::Customize->get_cats($u);

    if ( $u ne $remote ) {
        $queryargs->{authas} = $u->user;
    }

    my $cat_title;

    my $current = LJ::Customize->get_current_theme($u);

    if ( $queryargs->{cat} eq "all" ) {
        @themes    = LJ::S2Theme->load_all($u);
        $cat_title = LJ::Lang::ml('widget.themechooser.header.all');
    }
    elsif ( $queryargs->{cat} eq "custom" ) {
        @themes    = LJ::S2Theme->load_by_user($u);
        $cat_title = LJ::Lang::ml('widget.themechooser.header.custom');
    }
    elsif ( $queryargs->{cat} eq "base" ) {
        @themes    = LJ::S2Theme->load_default_themes();
        $cat_title = $cats{'base'}->{text};
    }
    elsif ( $queryargs->{cat} ) {
        @themes = LJ::S2Theme->load_by_cat( $queryargs->{cat} );
        my $cat = $queryargs->{cat};
        $cat_title = $cats{$cat}->{text};
    }
    elsif ( $queryargs->{layoutid} ) {
        @themes    = LJ::S2Theme->load_by_layoutid( $queryargs->{layoutid}, $u );
        $cat_title = LJ::Lang::ml('widget.themechooser.header.all');
    }
    elsif ( $queryargs->{designer} ) {
        @themes    = LJ::S2Theme->load_by_designer( $queryargs->{designer} );
        $cat_title = LJ::ehtml( $queryargs->{designer} );
    }
    elsif ( $queryargs->{search} ) {
        @themes    = LJ::S2Theme->load_by_search( $queryargs->{search}, $u );
        $cat_title = LJ::Lang::ml( 'widget.themechooser.header.search',
            { 'term' => ehtml( $queryargs->{search} ) } );
    }
    else {    # category is "featured"
        @themes    = LJ::S2Theme->load_by_cat("featured");
        $cat_title = $cats{'featured'}->{text};
    }

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

    @themes = LJ::Customize->remove_duplicate_themes(@themes);
    my $max_page =
        $queryargs->{show} ne "all" ? POSIX::ceil( scalar(@themes) / $queryargs->{show} ) || 1 : 1;

    if ( $queryargs->{show} ne "all" ) {
        my $i_first = $queryargs->{show} * ( $queryargs->{page} - 1 );
        my $i_last  = ( $queryargs->{show} * $queryargs->{page} ) - 1;
        @themes = splice( @themes, $i_first, $queryargs->{show} );
    }

    my @theme_data = ();
    for my $theme (@themes) {
        my $current = ( $theme->themeid && ( $theme->themeid == $current->themeid ) )
            || ( ( $theme->layoutid == $current->layoutid )
            && !$theme->themeid
            && !$current->themeid ) ? 1 : 0;
        my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );

        push @theme_data, get_theme_data( $theme, $current, $no_layer_edit );

    }

    return {
        cat_title => $cat_title,
        max_page  => $max_page,
        themes    => \@theme_data
    };

}

sub get_theme_data {
    my ( $theme, $current, $no_layer_edit ) = shift;
    my $tmp = {
        imgurl   => $theme->preview_imgurl,
        layoutid => $theme->layoutid,
        themeid  => $theme->themeid,
        name     => $theme->{'name'},
        designer => $theme->designer,
        layout   => $theme->{'layout_name'},
    };

    $tmp->{'designer_link'} = LJ::create_url(
        "/customize",
        keep_args => [ 'show', 'authas' ],
        args      => { designer => $theme->designer }
    ) if $theme->designer;
    $tmp->{'layout_link'} = LJ::create_url(
        "/customize",
        keep_args => [ 'show', 'authas' ],
        args      => { layoutid => $theme->layoutid }
    );
    $tmp->{'current'} = $current;

    if ( $current && !$no_layer_edit && $theme->is_custom ) {
        $tmp->{can_edit_layout} = $theme->layoutid && !$theme->{layout_uniq} ? 1 : 0;
        $tmp->{can_edit_theme}  = $theme->themeid  && !$theme->{uniq}        ? 1 : 0;
    }

    if ( $theme->themeid ) {
        $tmp->{preview_url} = LJ::create_url( "/customize/preview_redirect",
            args => { 'themeid' => $theme->themeid } );
    }
    else {
        $tmp->{preview_url} = LJ::create_url( "/customize/preview_redirect",
            args => { 'layoutid' => $theme->layoutid } );
    }
    return $tmp;
}

sub get_current_data {
    my $no_themechooser = shift;
    my $u               = LJ::get_effective_remote();
    my $remote          = LJ::get_remote();

    my $current       = LJ::Customize->get_current_theme($u);
    my $no_layer_edit = LJ::Hooks::run_hook( "no_theme_or_layer_edit", $u );
    my $theme_data    = get_theme_data( $current, 1, $no_layer_edit );

    my @current_options = ();
    if ($no_themechooser) {
        push @current_options,
            {
            url   => LJ::create_url( "/customize", keep_args => ['authas'] ),
            title => LJ::Lang::ml('widget.currenttheme.options.newtheme')
            };
    }
    else {
        push @current_options,
            {
            url   => LJ::create_url( "/customize/options", keep_args => ['authas'] ),
            title => LJ::Lang::ml('widget.currenttheme.options.change')
            };
    }

    if ( !$no_layer_edit ) {
        push @current_options,
            {
            url   => LJ::create_url("/customize/advanced/"),
            title => LJ::Lang::ml('widget.currenttheme.options.advancedcust')
            };
        push @current_options,
            {
            url =>
                LJ::create_url( "/customize/advanced/", args => { id => $theme_data->{layoutid} } ),
            title => LJ::Lang::ml('widget.currenttheme.options.editlayoutlayer')
            }
            if $theme_data->{can_edit_layout};
        push @current_options,
            {
            url =>
                LJ::create_url( "/customize/advanced/", args => { id => $theme_data->{themeid} } ),
            title => LJ::Lang::ml('widget.currenttheme.options.editthemelayer')
            }
            if $theme_data->{can_edit_theme};
    }

    push @current_options,
        { url => "#layout", title => LJ::Lang::ml('widget.currenttheme.options.layout') };

    return { 'current' => $theme_data, 'current_options' => \@current_options };
}

sub get_layout_data {
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $current           = LJ::Customize->get_current_theme($u);
    my %layouts           = $current->layouts;
    my $show_sidebar_prop = $current->show_sidebar_prop;
    my %layout_names      = LJ::Customize->get_layouts;

    my $layout_prop = $current->layout_prop;

    my $prop_value;
    if ( $layout_prop || $show_sidebar_prop ) {
        my $style = LJ::S2::load_style( $u->prop('s2_style') );
        die "Style not found." unless $style && $style->{userid} == $u->id;

        if ($layout_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values( $layout_prop, $u, $style );
            $prop_value = $prop_values{override};
        }

        # for layouts that have a separate prop that turns off the sidebar, use the value of that
        # prop instead if the sidebar is set to be off (false/0).
        if ($show_sidebar_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values( $show_sidebar_prop, $u, $style );
            $prop_value = $prop_values{override} if $prop_values{override} == 0;
        }
    }

    my @layout_data = ();
    for my $layout ( sort keys %layouts ) {
        my $tmp = {
            layout => $layout,
            name   => $layout_names{$layout},
        };
        $tmp->{current} =
            ( !$layout_prop ) || ( $layout_prop && $layouts{$layout} eq $prop_value ) ? 1 : 0;

        push @layout_data, $tmp;
    }

    my $is_system = $current->is_system_layout;

    return {
        is_system         => $current->is_system_layout,
        show_sidebar_prop => $show_sidebar_prop,
        layout_prop       => $layout_prop,
        layouts           => \@layout_data
    };

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

1;
