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
    $vars->{themes} = @themes;
    $vars->{getargs} = \@getargs;

    #information for pagination of results
    my $current_theme_id = LJ::Customize->get_current_theme($u);
    my $index_of_first_theme = $vars->{show} ne "all" ? $vars->{show} * ($vars->{page} - 1) : 0;
    my $index_of_last_theme = $vars->{show} ne "all" ? ($vars->{show} * $vars->{page}) - 1 : scalar @themes - 1;
    my @themes_this_page = @themes[$index_of_first_theme..$index_of_last_theme];
    my $ret;

foreach my $theme (@themes_this_page) {
        next unless defined $theme;

        # figure out the type(s) of theme this is so we can modify the output accordingly
        my %theme_types;
        if ($theme->themeid) {
            $theme_types{current} = 1 if $theme->themeid == $current_theme_id->themeid;
        } elsif (!$theme->themeid && !$current_theme_id->themeid) {
            $theme_types{current} = 1 if $theme->layoutid == $current_theme_id->layoutid;
        }
        $theme_types{upgrade} = 1 if !$theme->available_to($u);
        $theme_types{special} = 1 if LJ::Hooks::run_hook("layer_is_special", $theme->uniq);

        
        my ($theme_class, $theme_options, $theme_icons) = ("", "", "");
        
        $theme_icons .= "<div class='theme-icons'>" if $theme_types{upgrade} || $theme_types{special};
        if ($theme_types{current}) {
            my $no_layer_edit = LJ::Hooks::run_hook("no_theme_or_layer_edit", $u);

            $theme_class .= " selected";
            $theme_options .= "<strong><a href='$LJ::SITEROOT/customize/options$getextra'>" . LJ::Lang::ml('widget.themechooser.theme.customize') . "</a></strong>";
            if (! $no_layer_edit && $theme->is_custom && !$theme_types{upgrade}) {
                if ($theme->layoutid && !$theme->layout_uniq) {
                    $theme_options .= "<br /><strong><a href='$LJ::SITEROOT/customize/advanced/layeredit?id=" . $theme->layoutid . "'>" . LJ::Lang::ml('widget.themechooser.theme.editlayoutlayer') . "</a></strong>";
                }
                if ($theme->themeid && !$theme->uniq) {
                    $theme_options .= "<br /><strong><a href='$LJ::SITEROOT/customize/advanced/layeredit?id=" . $theme->themeid . "'>" . LJ::Lang::ml('widget.themechooser.theme.editthemelayer') . "</a></strong>";
                }
            }
        }
        if ($theme_types{upgrade}) {
            $theme_class .= " upgrade";
            $theme_options .= "<br />" if $theme_options;
            $theme_options .= LJ::Hooks::run_hook("customize_special_options", $u, $theme);
            $theme_icons .= LJ::Hooks::run_hook("customize_special_icons", $u, $theme);
        }
        if ($theme_types{special}) {
            $theme_class .= " special" if $viewing_featured && LJ::Hooks::run_hook("should_see_special_content", $u);
            $theme_icons .= LJ::Hooks::run_hook("customize_available_until", $theme);
        }
        $theme_icons .= "</div><!-- end .theme-icons -->" if $theme_icons;

        my $theme_layout_name = $theme->layout_name;
        my $theme_designer = $theme->designer;

        $ret .= "<li class='theme-item$theme_class'>";
        $ret .= "<img src='" . $theme->preview_imgurl . "' class='theme-preview' />";

        $ret .= "<h4>" . $theme->name . "</h4><div class='theme-action'><span class='theme-desc'>";

        if ($theme_designer) {
            my $designer_link = "<a href='$LJ::SITEROOT/customize/$getextra${getsep}designer=" . LJ::eurl($theme_designer) . "$showarg' class='theme-designer'>$theme_designer</a> ";
            $ret .= LJ::Lang::ml('widget.themechooser.theme.designer', {'designer' => $designer_link});
        }

        my $preview_redirect_url;
        if ($theme->themeid) {
            $preview_redirect_url = "$LJ::SITEROOT/customize/preview_redirect$getextra${getsep}themeid=" . $theme->themeid;
        } else {
            $preview_redirect_url = "$LJ::SITEROOT/customize/preview_redirect$getextra${getsep}layoutid=" . $theme->layoutid;
        }
        $ret .= "<a href='$preview_redirect_url' target='_blank' class='theme-preview-link' title='" . LJ::Lang::ml('widget.themechooser.theme.preview') . "'>";

        $ret .= "<img src='$LJ::IMGPREFIX/customize/preview-theme.gif' class='theme-preview-image' /></a>";
        $ret .= $theme_icons;

        my $layout_link = "<a href='$LJ::SITEROOT/customize/$getextra${getsep}layoutid=" . $theme->layoutid . "$showarg' class='theme-layout'><em>$theme_layout_name</em></a>";
        my $special_link_opts = "href='$LJ::SITEROOT/customize/$getextra${getsep}cat=special$showarg' class='theme-cat'";
        if ($theme_types{special}) {
            $ret .= LJ::Lang::ml('widget.themechooser.theme.specialdesc2', {'aopts' => $special_link_opts});
        } else {
            $ret .= LJ::Lang::ml('widget.themechooser.theme.desc2', {'style' => $layout_link});
        }
        $ret .= "</span>";

        if ($theme_options) {
            $ret .= $theme_options;
        } else { # apply theme form
           # $ret .= $class->start_form( class => "theme-form" );
          #  $ret .= $class->html_hidden(
         #       apply_themeid => $theme->themeid,
        #        apply_layoutid => $theme->layoutid,
       #     );
        #    $ret .= $class->html_submit(
        #        apply => LJ::Lang::ml('widget.themechooser.theme.apply'),
       #         { raw => "class='theme-button' id='theme_btn_" . $theme->layoutid . $theme->themeid . "'" },
       #     );
        #    $ret .= $class->end_form;
        }
        $ret .= "</div><!-- end .theme-action --></li><!-- end .theme-item -->";
    }

    $vars->{theme_area} = $ret;
    $vars->{run_hook} = \&LJ::Hooks::run_hook;
        
    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize.tt', $vars );

}


1;
