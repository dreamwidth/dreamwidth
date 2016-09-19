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
use Data::Dumper;

# This registers a static string, which is an application page.
DW::Routing->register_string( '/customize/', \&customize_handler, 
    app => 1 );
DW::Routing->register_string( '/customize/options/', \&options_handler, 
    app => 1 );

DW::Routing->register_rpc( "themechooser", \&themechooser_handler, format => 'html' );

sub customize_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    warn "Hit the handler";


    my $r = $rv->{r};
    my $post = $r->post_args;
    my $u = $rv->{u};
    my $remote = $rv->{remote};
    my $GET = DW::Request->get;
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



    $vars->{cat} = defined $GET->get_args->{cat} ? $GET->get_args->{cat} : "";
    $vars->{layoutid} = defined $GET->get_args->{layoutid} ? $GET->get_args->{layoutid} : 0;
    $vars->{designer} = defined $GET->get_args->{designer} ? $GET->get_args->{designer} : "";
    $vars->{search} = defined $GET->get_args->{search} ? $GET->get_args->{search} : "";
    $vars->{page} = defined $GET->get_args->{page} ? $GET->get_args->{page} : 1;
    $vars->{show} = defined $GET->get_args->{show} ? $GET->get_args->{show} : 12;

    my $showarg = $vars->{show} != 12 ? "show=$vars->{show}" : "";
    my $show = $vars->{show};

    # create all our widgets
    my $current_theme = LJ::Widget::CurrentTheme->new;
    $vars->{current_theme} = $current_theme->render(show => $show);
    $vars->{headextra} .= $current_theme->wrapped_js( page_js_obj => "Customize" );

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
        my %layout_names = LJ::Customize->get_layouts; 

    # pass our computed values to the template
    $vars->{style} = $style;
    $vars->{custom_themes} = \@custom_themes;
    $vars->{special_themes_exist} = $special_themes_exist;
    $vars->{get_layout_name} = sub { LJ::Customize->get_layout_name(@_); };
    $vars->{eurl} = \&LJ::eurl;
    $vars->{ehtml} = \&LJ::ehtml;
    $vars->{img_prefix} = $LJ::IMGPREFIX;
    $vars->{maxlength} = LJ::std_max_length();
    $vars->{help_icon} = \&LJ::help_icon;
    $vars->{layout_names} = \%layout_names;
    $vars->{get_s2_prop_values} = sub { LJ::Customize->get_s2_prop_values(@_); };

    my $q_string = $r->query_string;
    my $url = "$LJ::SITEROOT/customize/";
    #handle post actions

    if ($r->did_post) {
        warn "Hit post handler";
        if ($post->{"action_apply"}) {

            my $themeid = $post->{apply_themeid};
            my $layoutid = $post->{apply_layoutid};
            
            set_theme(apply_themeid => $themeid, apply_layout => $layoutid);
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
            $url .= "?" . $q_string;
        }
        return $r->redirect($url);

    }
        

    # get the current theme id - at the end because post actions may have changed it.
    my $current_theme_id = LJ::Customize->get_current_theme($u);
    $vars->{current_theme_id} = $current_theme_id;
    my %layouts = $current_theme_id->layouts;
    $vars->{layouts} = \%layouts;
    my $show_sidebar_prop = $current_theme_id->show_sidebar_prop;

    my $layout_prop = $current_theme_id->layout_prop;

    my $prop_value;
    if ($layout_prop || $show_sidebar_prop) {
        my $style = LJ::S2::load_style($u->prop('s2_style'));
        die "Style not found." unless $style && $style->{userid} == $u->id;

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

    $vars->{prop_value} = $prop_value;
    $vars->{render_themechooser} = \&render_themechooser;

    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize/customize.tt', $vars );

}

sub themechooser_handler {
    warn "Hit the themechooser handler";

    # gets the request and args
    my $r = DW::Request->get;
    my $args = $r->post_args;
    my %getargs;
    my $themeid = $args->{apply_themeid};
    my $layoutid = $args->{apply_layoutid};

    $getargs{cat} = defined $args->{cat} ? $args->{cat} : "";
    $getargs{layoutid} = defined $args->{layoutid} ? $args->{layoutid} : 0;
    $getargs{designer} = defined $args->{designer} ? $args->{designer} : "";
    $getargs{search} = defined $args->{search} ? $args->{search} : "";
    $getargs{page} = defined $args->{page} ? $args->{page} : 1;
    $getargs{show} = defined $args->{show} ? $args->{show} : 12;

    # apply the new theme selected

    set_theme(apply_themeid => $themeid, apply_layoutid => $layoutid);

    $r->print( render_themechooser(%getargs) );
    return $r->OK;


}

sub set_theme {
    warn "Hit set_theme";
    my %opts = @_;
    my $u = LJ::get_effective_remote();

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

            LJ::Customize->apply_theme($u, $theme);
            LJ::Hooks::run_hooks('apply_theme', $u);
}

sub render_themechooser {
    my %args = @_;
    my $vars;   
    my @getargs;
    my @themes;
    my $u = LJ::get_effective_remote();
    warn Dumper(%args);
    warn Dumper($u);
    

    $vars->{cat} = defined $args{cat} ? $args{cat} : "";
    $vars->{layoutid} = defined $args{layoutid} ? $args{layoutid} : 0;
    $vars->{designer} = defined $args{designer} ? $args{designer} : "";
    $vars->{search} = defined $args{search} ? $args{search} : "";
    $vars->{page} = defined $args{page} ? $args{page} : 1;
    $vars->{show} = defined $args{show} ? $args{show} : 12;

    my $showarg = $vars->{show} != 12 ? "show=$vars->{show}" : "";

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

        push @getargs, $showarg;
    
    @themes = LJ::Customize->remove_duplicate_themes(@themes);

    $vars->{max_page} = $vars->{show} ne "all" ? POSIX::ceil(scalar(@themes) / $vars->{show}) || 1 : 1;
    $vars->{themes} = \@themes;
    $vars->{getargs} = \@getargs;
    $vars->{run_hook} = \&LJ::Hooks::run_hook;

return DW::Template->template_string( 'customize/themechooser.tt', $vars );

}

1;
