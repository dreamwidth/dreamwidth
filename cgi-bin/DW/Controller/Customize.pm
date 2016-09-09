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

sub customize_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

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

    # create all our widgets
    my $current_theme = LJ::Widget::CurrentTheme->new;
    $vars->{current_theme} = $current_theme;
    $vars->{headextra} .= $current_theme->wrapped_js( page_js_obj => "Customize" );
    my $journal_titles = LJ::Widget::JournalTitles->new;
    $vars->{journal_titles} = $journal_titles;
    $vars->{headextra} = $journal_titles->wrapped_js;
    my $layout_chooser = LJ::Widget::LayoutChooser->new;
    $vars->{layout_chooser} = $layout_chooser;
    $vars->{headextra} .= $layout_chooser->wrapped_js( page_js_obj => "Customize" );


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


    my @getargs;
    my @themes;
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
    
    # pass our computed values to the template
    $vars->{custom_themes} = \@custom_themes;
    $vars->{special_themes_exist} = $special_themes_exist;
    $vars->{max_page} = $vars->{show} ne "all" ? POSIX::ceil(scalar(@themes) / $vars->{show}) || 1 : 1;
    $vars->{themes} = \@themes;
    $vars->{getargs} = \@getargs;
    $vars->{run_hook} = \&LJ::Hooks::run_hook;
    $vars->{get_layout_name} = sub { LJ::Customize->get_layout_name(@_); };

    my $q_string = BML::get_query_string();
    $q_string =~ s/&?page=\d+//g;

    my $url = "$LJ::SITEROOT/customize/";

    if ($r->did_post) {
        if ($post->{"action:apply"}) {
            die "Invalid user." unless LJ::isu($u);

            my $themeid = $post->{apply_themeid}+0;
            my $layoutid = $post->{apply_layoutid}+0;
            my $key;
            
            # we need to load sponsor's themes for sponsored users
            my $substitute_user = LJ::Hooks::run_hook("substitute_s2_layers_user", $u);
            my $effective_u = defined $substitute_user ? $substitute_user : $u;
            my $theme;
            if ($themeid) {
                $theme = LJ::S2Theme->load_by_themeid($themeid, $effective_u);
            } elsif ($layoutid) {
                $theme = LJ::S2Theme->load_custom_layoutid($layoutid, $effective_u);
            } else {
                die "No theme id or layout id specified.";
            }

            LJ::Customize->apply_theme($u, $theme);
            LJ::Hooks::run_hooks('apply_theme', $u);
        } elsif ($post->{filter}) {
            $q_string = "?$q_string" if $q_string;
            my $q_sep = $q_string ? "&" : "?";
            $url .= $q_string;

        } elsif ($post->{page}) {
            $q_string = "?$q_string" if $q_string;
            my $q_sep = $q_string ? "&" : "?";

            $post->{page} = LJ::eurl($post->{page});
            if ($post->{page} != 1) {
                $url .= "$q_string${q_sep}page=$post->{page}";
            } else {
                $url .= $q_string;
            }
        } elsif ($post->{show}) {
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
        }
    }
        

    # get the current theme id - at the end because post actions may have changed it.
    $vars->{current_theme_id} = LJ::Customize->get_current_theme($u);
    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize.tt', $vars );

}


1;
