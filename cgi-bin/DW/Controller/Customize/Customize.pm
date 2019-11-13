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
DW::Routing->register_string( '/customize/', \&customize_handler, 
    app => 1 );


DW::Routing->register_rpc( "themechooser", \&themechooser_handler, format => 'json' );
DW::Routing->register_rpc( "journaltitles", \&journaltitles_handler, format => 'html' );
DW::Routing->register_rpc( "layoutchooser", \&layoutchooser_handler, format => 'html' );
DW::Routing->register_rpc( "themefilter", \&filter_handler, format => 'json' );

sub customize_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $post = $r->post_args;
    my $u = $rv->{u};
    my $remote = $rv->{remote};
    my $GET = $r->get_args;
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";


    my $vars;
    $vars->{u} = $u;
    $vars->{remote} = $remote;
    $vars->{getextra} = ( $u ne $remote) ? ( "?authas=" . $u->user ) : '';
    $vars->{getsep} = $getsep;
    $vars->{is_identity} = 1 if $u->is_identity;
    $vars->{is_community} = 1 if $u->is_community;
    $vars->{style} = LJ::Customize->verify_and_load_style($u);
    $vars->{authas_html} = $rv->{authas_html};



    $vars->{cat} = defined $GET->{cat} ? $GET->{cat} : "";
    $vars->{layoutid} = defined $GET->{layoutid} ? $GET->{layoutid} : 0;
    $vars->{designer} = defined $GET->{designer} ? $GET->{designer} : "";
    $vars->{search} = defined $GET->{search} ? $GET->{search} : "";
    $vars->{page} = defined $GET->{page} ? $GET->{page} : 1;
    $vars->{show} = defined $GET->{show} ? $GET->{show} : 12;

    my $showarg = $vars->{show} != 12 ? "show=$vars->{show}" : "";
    my $show = $vars->{show};

    # lazy migration of style name
    LJ::Customize->migrate_current_style($u);

    # set up the keywords for basic search
    my @keywords = LJ::Customize->get_search_keywords_for_js($u);
    my $keywords_string = join(",", @keywords);
    $vars->{keywords_string} =  $keywords_string;


    # we want to have "All" selected if we're filtering by layout or designer, or if we're searching
    $vars->{viewing_all} = $vars->{layoutid} || $vars->{designer}|| $vars->{search};

    # sort cats by specificed order key, then alphabetical order
    my %cats = LJ::Customize->get_cats($u);
    $vars->{cats} = \%cats;
    my @cats_sorted =
        sort { $cats{$a}->{order} <=> $cats{$b}->{order} }
        sort { lc $cats{$a}->{text} cmp lc $cats{$b}->{text} } keys %cats;

    # pull the main cats out of the full list
    my @main_cats_sorted;
    for (my $i = 0; $i < @cats_sorted; $i++) {
        my $c = $cats_sorted[$i];

        if (defined $cats{$c}->{main}) {
            my $el = splice(@cats_sorted, $i, 1);
            push @main_cats_sorted, $el;
            $i--; # we just removed an element from @cats_sorted
        }
    }

    $vars->{main_cats_sorted} = \@main_cats_sorted;
    $vars->{cats_sorted} = \@cats_sorted;

    my @special_themes = LJ::S2Theme->load_by_cat("special");
    my $special_themes_exist = 0;
    foreach my $special_theme (@special_themes) {
        my $layout_is_active = LJ::Hooks::run_hook("layer_is_active", $special_theme->layout_uniq);
        my $theme_is_active = LJ::Hooks::run_hook("layer_is_active", $special_theme->uniq);

        if ($layout_is_active && $theme_is_active) {
            $special_themes_exist = 1;
            last;
        }
    }

    my @custom_themes = LJ::S2Theme->load_by_user($u);

    # get the theme subset we're currently viewing and assign the correct title label

    my $viewing_featured = !$vars->{cat} && !$vars->{layoutid} && !$vars->{designer};





        my $style = LJ::S2::load_style($u->prop('s2_style'));
        die "Style not found." unless $style && $style->{userid} == $u->id;


    # pass our computed values to the template
    $vars->{style} = $style;
    $vars->{custom_themes} = \@custom_themes;
    $vars->{special_themes_exist} = $special_themes_exist;
    $vars->{eurl} = \&LJ::eurl;
    $vars->{maxlength} = LJ::std_max_length();
    $vars->{help_icon} = \&LJ::help_icon;
    $vars->{get_s2_prop_values} = sub { LJ::Customize->get_s2_prop_values(@_); };

    my $q_string = $r->query_string;
    my $url = "$LJ::SITEROOT/customize/";
    #handle post actions

    if ($r->did_post) {
        if ($post->{"action_apply"}) {

            my $themeid = $post->{apply_themeid};
            my $layoutid = $post->{apply_layoutid};
            
            set_theme(apply_themeid => $themeid, apply_layout => $layoutid);
            $url .= "?" . $q_string;

        } elsif ($post->{"save"}) {
       
            set_journaltitles($post);
            $url .= "?" . $q_string;

        } elsif ($post->{filter}) {
            $q_string =~ s/&?page=\d+//g;
            $q_string = "?$q_string" if $q_string;
            my $q_sep = $q_string ? "&" : "?";
            $url .= $q_string;

        } elsif ($post->{page}) {
            $q_string =~ s/&?page=\d+//g;
            $q_string = "?$q_string" if $q_string;
            my $q_sep = $q_string ? "&" : "?";

            $post->{page} = LJ::eurl($post->{page});
            if ($post->{page} != 1) {
                $url .= "$q_string${q_sep}page=$post->{page}";
            } else {
                $url .= $q_string;
            }
        } elsif ($post->{show}) {
            $q_string =~ s/&?page=\d+//g;
            $q_string =~ s/&?show=\w+//g;
            $q_string = "?$q_string" if $q_string;
            my $q_sep = $q_string ? "&" : "?";

            $post->{show} = LJ::eurl($post->{show});
            if ($post->{show} != 12) {
                $url .= "$q_string${q_sep}show=$post->{show}";
            } else {
                $url .= $q_string;
            }
        } elsif ($post->{search}) {
            my $show = ($q_string =~ /&?show=(\w+)/) ? "&show=$1" : "";
            my $authas = ($q_string =~ /&?authas=(\w+)/) ? "&authas=$1" : "";
            $q_string = "";

            $post->{search} = LJ::eurl($post->{search});
            $url .= "?search=$post->{search}$authas$show";
        } elsif ($post->{which_title}) {
            my $eff_val = LJ::text_trim($post->{title_value}, 0, LJ::std_max_length());
            $eff_val = "" unless $eff_val;
            $u->set_prop($post->{which_title}, $eff_val);
            $url .= "?" . $q_string;
        } elsif ($post->{apply_layout})  {

            set_layout( { layout_choice => $post->{layout_choice},
                       layout_prop => $post->{layout_prop},
                        show_sidebar_prop => $post->{show_sidebar_prop},
                        u => $u });
            $url .= "?" . $q_string;
        }
        return $r->redirect($url);

    }
        

    # get the current theme id - at the end because post actions may have changed it.

    $vars->{render_themechooser} = \&render_themechooser;
    $vars->{render_journaltitles} = \&render_journaltitles;
    $vars->{render_layoutchooser} = \&render_layoutchooser;
    $vars->{render_currenttheme} = \&render_currenttheme;

    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize/customize.tt', $vars );

}

sub themechooser_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    # gets the request and args

    my $r = DW::Request->get;
    my $args = $r->post_args;
    my $getargs;
    my $themeid = $args->{apply_themeid};
    my $layoutid = $args->{apply_layoutid};


    $getargs->{cat} = defined $args->{cat} ? $args->{cat} : "";
    $getargs->{layoutid} = defined $args->{layoutid} ? $args->{layoutid} : 0;
    $getargs->{designer} = defined $args->{designer} ? $args->{designer} : "";
    $getargs->{search} = defined $args->{search} ? $args->{search} : "";
    $getargs->{page} = defined $args->{page} ? $args->{page} : 1;
    $getargs->{show} = defined $args->{show} ? $args->{show} : 12;

    # apply the new theme selected


    set_theme(apply_themeid => $themeid, apply_layoutid => $layoutid);

    my $themechooser_html = render_themechooser($getargs);
    my $layoutchooser_html = render_layoutchooser();
    my $currenttheme_html = render_currenttheme('show', $getargs->{show});

    $r->print( to_json( { themechooser => $themechooser_html, layoutchooser => $layoutchooser_html, currenttheme => $currenttheme_html } ) );
    return $r->OK;


}

sub set_theme {
    my %opts = @_;
    my $u = LJ::get_effective_remote();
        warn "Trying to set theme";

            die "Invalid user." unless LJ::isu($u);

            my $themeid = $opts{apply_themeid}+0;
            my $layoutid = $opts{apply_layoutid}+0;
            
            my $theme;
            if ($themeid) {
                $theme = LJ::S2Theme->load_by_themeid($themeid, $u);
            } elsif ($layoutid) {
                $theme = LJ::S2Theme->load_custom_layoutid($layoutid, $u);
            } else {
                die "No theme id or layout id specified.";
            }

            LJ::Customize->apply_theme($u, $theme) or croak("Couldn't apply theme");
            LJ::Hooks::run_hooks('apply_theme', $u);
}

sub render_themechooser {
    my $args = shift;
    my $vars;   
    my @getargs;
    my @themes;
    my $u = LJ::get_effective_remote();
    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";
    my %cats = LJ::Customize->get_cats($u);

    $vars->{u} = $u;
    $vars->{cat} = defined $args->{cat} ? $args->{cat} : "";
    $vars->{layoutid} = defined $args->{layoutid} ? $args->{layoutid} : 0;
    $vars->{designer} = defined $args->{designer} ? $args->{designer} : "";
    $vars->{search} = defined $args->{search} ? $args->{search} : "";
    $vars->{page} = defined $args->{page} ? $args->{page} : 1;
    $vars->{show} = defined $args->{show} ? $args->{show} : 12;
    $vars->{cats} = \%cats;

    my $showarg = $vars->{show} != 12 ? "show=$vars->{show}" : "";

    my $current_theme_id = LJ::Customize->get_current_theme($u);
    $vars->{current_theme_id} = $current_theme_id;

    if ( $vars->{cat} eq "base" ) {
        # sort alphabetically by layout
        @themes = sort { lc $a->layout_name cmp lc $b->layout_name } @themes;
    } else {
        # sort themes with custom at the end, then alphabetically by theme
        @themes =
            sort { $a->is_custom <=> $b->is_custom }
            sort { lc $a->name cmp lc $b->name } @themes;
    }

    # remove any themes from the array that are not defined or whose layout or theme is not active
    for (my $i = 0; $i < @themes; $i++) {
        my $layout_is_active = LJ::Hooks::run_hook("layer_is_active", $themes[$i]->layout_uniq);
        my $theme_is_active = LJ::Hooks::run_hook("layer_is_active", $themes[$i]->uniq);

        unless ((defined $themes[$i]) &&
            (!defined $layout_is_active || $layout_is_active) &&
            (!defined $theme_is_active || $theme_is_active)) {

            splice(@themes, $i, 1);
            $i--; # we just removed an element from @themes
        }
    }

    if ($vars->{cat} eq "all") {
        push @getargs, "cat=all";
        @themes = LJ::S2Theme->load_all($u);
    } elsif ($vars->{cat} eq "custom") {
        push @getargs, "cat=custom";
        @themes = LJ::S2Theme->load_by_user($u);
    } elsif ($vars->{cat} eq "base") {
        push @getargs, "cat=base";
        @themes = LJ::S2Theme->load_default_themes();
    } elsif ($vars->{cat}) {
        push @getargs, "cat=$vars->{cat}";
        @themes = LJ::S2Theme->load_by_cat($vars->{cat});
    } elsif ($vars->{layoutid}) {
        push @getargs, "layoutid=$vars->{layoutid}";
        @themes = LJ::S2Theme->load_by_layoutid($vars->{layoutid}, $u);
    } elsif ($vars->{designer}) {
        push @getargs, "designer=" . LJ::eurl($vars->{designer});
        @themes = LJ::S2Theme->load_by_designer($vars->{designer});
    } elsif ($vars->{search}) {
        push @getargs, "search=" . LJ::eurl($vars->{search});
        @themes = LJ::S2Theme->load_by_search($vars->{search}, $u);
    } else { # category is "featured"
        @themes = LJ::S2Theme->load_by_cat("featured");
    }
    push @getargs, $showarg unless $showarg eq "";
    
    @themes = LJ::Customize->remove_duplicate_themes(@themes);

    $vars->{max_page} = $vars->{show} ne "all" ? POSIX::ceil(scalar(@themes) / $vars->{show}) || 1 : 1;
    $vars->{themes} = \@themes;
    $vars->{getargs} = \@getargs;
    $vars->{run_hook} = \&LJ::Hooks::run_hook;
    $vars->{img_prefix} = $LJ::IMGPREFIX;
    $vars->{eurl} = \&LJ::eurl;
    $vars->{getextra} = $getextra;
    $vars->{getsep} = $getsep;
    $vars->{get_layout_name} = sub { LJ::Customize->get_layout_name(@_); };


return DW::Template->template_string( 'customize/themechooser.tt', $vars );

}

sub journaltitles_handler {

    # gets the request and args
    my $r = DW::Request->get;
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

    my $eff_val = LJ::text_trim($post->{title_value}, 0, LJ::std_max_length());
    $eff_val = "" unless $eff_val;
    $u->set_prop($post->{which_title}, $eff_val);
}

sub render_journaltitles {
    my %opts = @_;
    my $vars;
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    $vars->{u} = $u;
    $vars->{no_themechooser} = $opts{no_themechooser};
    return DW::Template->template_string( 'customize/journaltitles.tt', $vars );
}

sub layoutchooser_handler {

    # gets the request and args
    my $r = DW::Request->get;
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
            my $layout_choice = $post->{layout_choice};
            my $layout_prop = $post->{layout_prop};
            my $show_sidebar_prop = $post->{show_sidebar_prop};
            my $current_theme_id = LJ::Customize->get_current_theme($u);
            my %layouts = $current_theme_id->layouts;

            # show_sidebar prop is set to false/0 if the 1 column layout was chosen,
            # otherwise it's set to true/1 and the layout prop is set appropriately.
            if ($show_sidebar_prop && $layout_choice eq "1") {
                $override{$show_sidebar_prop} = 0;
            } else {
                $override{$show_sidebar_prop} = 1 if $show_sidebar_prop;
                $override{$layout_prop} = $layouts{$layout_choice} if $layout_prop;
            }

            my $style = LJ::S2::load_style($u->prop('s2_style'));
            die "Style not found." unless $style && $style->{userid} == $u->id;

            LJ::Customize->save_s2_props($u, $style, \%override);
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
    $vars->{layout_names} = \%layout_names;
    $vars->{img_prefix} = $LJ::IMGPREFIX;
    $vars->{no_themechooser} = $opts{no_themechooser};

    my $layout_prop = $current_theme_id->layout_prop;

    my $prop_value;
    if ($layout_prop || $show_sidebar_prop) {
        my $style = LJ::S2::load_style($u->prop('s2_style'));
        die "Style not found." unless $style && $style->{userid} == $u->id;

        if ($layout_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values($layout_prop, $u, $style);
            carp;
            $prop_value = $prop_values{override};
        }

        # for layouts that have a separate prop that turns off the sidebar, use the value of that
        # prop instead if the sidebar is set to be off (false/0).
        if ($show_sidebar_prop) {
            my %prop_values = LJ::Customize->get_s2_prop_values($show_sidebar_prop, $u, $style);
            $prop_value = $prop_values{override} if $prop_values{override} == 0;
        }
    }

    $vars->{prop_value} = $prop_value;

    $vars->{u} = $u;
    return DW::Template->template_string( 'customize/layoutchooser.tt', $vars );
}

sub filter_handler {

    # gets the request and args
    my ( $ok, $rv ) = controller( authas => 1,  form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $args = $r->get_args;

    # set the new titles

    my $themechooser_html = render_themechooser($args);
    my $currenttheme_html = render_currenttheme('show', $args->{show});

    $r->print( to_json( { themechooser => $themechooser_html, currenttheme => $currenttheme_html } ) );
    return $r->OK;
}


sub render_currenttheme{
    my %opts = @_;
    $opts{show} ||= 12;

    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";

    my $showarg = $opts{show} != 12 ? "&show=$opts{show}" : "";
    my $no_themechooser = defined $opts{no_themechooser} ? $opts{no_themechooser} : 0;
    my $no_layer_edit = LJ::Hooks::run_hook("no_theme_or_layer_edit", $u);

    my $theme = LJ::Customize->get_current_theme($u);
    my $userlay = LJ::S2::get_layers_of_user($u);


    my $vars;
    $vars->{u} = $u;
    $vars->{getextra} = $getextra;
    $vars->{theme} = $theme;
    $vars->{getsep} = $getsep;
    $vars->{showarg} = $showarg;
    $vars->{no_themechooser} = $no_themechooser;
    $vars->{userlay} = $userlay;
    $vars->{no_layer_edit} = $no_layer_edit;
    $vars->{eurl} = \&LJ::eurl;
    $vars->{is_special} = LJ::Hooks::run_hook("layer_is_special", $theme->uniq);

    return DW::Template->template_string( 'customize/currenttheme.tt', $vars );
}

1;
