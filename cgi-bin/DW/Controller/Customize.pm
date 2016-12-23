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
use Carp;

# This registers a static string, which is an application page.
DW::Routing->register_string( '/customize/', \&customize_handler, 
    app => 1 );
DW::Routing->register_string( '/customize/options', \&options_handler, 
    app => 1 );

DW::Routing->register_rpc( "themechooser", \&themechooser_handler, format => 'json' );
DW::Routing->register_rpc( "journaltitles", \&journaltitles_handler, format => 'html' );
DW::Routing->register_rpc( "layoutchooser", \&layoutchooser_handler, format => 'html' );
DW::Routing->register_rpc( "themefilter", \&filter_handler, format => 'json' );

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
    $vars->{authas_html} = $rv->{authas_html};



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
    my $headextra = $current_theme->wrapped_js( page_js_obj => "Customize" );

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
    $vars->{ehtml} = \&LJ::ehtml;
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
    return DW::Template->render_template( 'customize/customize.tt', $vars, { head => $headextra } );

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
    $vars->{ehtml} = \&LJ::ehtml;
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
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $args = $r->get_args;

    # set the new titles

    my $themechooser_html = render_themechooser($args);
    my $currenttheme_html = render_currenttheme('show', $args->{show});

    $r->print( to_json( { themechooser => $themechooser_html, currenttheme => $currenttheme_html } ) );
    return $r->OK;
}

sub options_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $post = $r->post_args;
    my $u = $rv->{u};
    my $remote = $rv->{remote};
    my $GET = DW::Request->get;
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";
    my $style = LJ::Customize->verify_and_load_style($u);


    my $vars;
    $vars->{u} = $u;
    $vars->{remote} = $remote;
    $vars->{getextra} = ( $u ne $remote) ? ( "?authas=" . $u->user ) : '';
    $vars->{getsep} = $getsep;
    $vars->{is_identity} = 1 if $u->is_identity;
    $vars->{is_community} = 1 if $u->is_community;
    $vars->{style} = $style;
    $vars->{authas_html} = $rv->{authas_html};
    $vars->{render_journaltitles} = \&render_journaltitles;
    $vars->{render_layoutchooser} = \&render_layoutchooser;
    $vars->{render_customizetheme} = \&render_customizetheme;

    $vars->{render_currenttheme} = \&render_currenttheme;

    $vars->{show} = defined $GET->get_args->{show} ? $GET->get_args->{show} : 12;
    my $show = $vars->{show};
    
    LJ::Customize->migrate_current_style($u);

    $vars->{group} = $GET->get_args->{group} ? $GET->get_args->{group} : "presentation";

    #handle post actions

    if ($r->did_post) {
        next if $post->{'action:morelinks'}; # this is handled in render_body
         my ($given_moodthemeid, $given_forcemoodtheme);
    warn Dumper($post);
        if ($post->{'reset'}) {
            # reset all props except the layout props
            my $current_theme = LJ::Customize->get_current_theme($u);
            my $layout_prop = $current_theme->layout_prop;
            my $show_sidebar_prop = $current_theme->show_sidebar_prop;

            my %override = %$post;
            delete $override{$layout_prop};
            delete $override{$show_sidebar_prop};

            foreach my $val (keys %$post) {
            next unless $val =~ /^link_\d+_title$/ || $val =~ /^link_\d+_url$/;

            $post->{$val} = "";
            }

            $given_moodthemeid = 1;
            $given_forcemoodtheme = 0;

            LJ::Customize->save_s2_props($u, $style, \%override, reset => 1);
            LJ::Customize->save_language($u, $post->{langcode}, reset => 1) if defined $post->{langcode};
        } else {
            my %override = map { $_ => "" } keys %$post;



            # ignore all values after the first true $value
            # only checkboxes have multiple values (forced post of 0,
            # so we don't ignore checkboxes that the user just unchecked)
            foreach my $key ( keys %$post ) {
                foreach my $value ( split ( /\0/, $post->{$key} ) ) {
                    $override{$key} ||= $value;
                }
            }

            $given_moodthemeid = $post->{moodthemeid};
            $given_forcemoodtheme = $post->{opt_forcemoodtheme};
            
            LJ::Customize->save_s2_props($u, $style, \%override);
            LJ::Customize->save_language($u, $post->{langcode}) if defined $post->{langcode};
        }

        #handle mood theme updates
            my %update;
            my $moodthemeid = LJ::Customize->validate_moodthemeid($u, $given_moodthemeid);
            $update{moodthemeid} = $moodthemeid;
            $update{opt_forcemoodtheme} = $given_forcemoodtheme ? "Y" : "N";

            # update 'user' table
            foreach (keys %update) {
                delete $update{$_} if $u->{$_} eq $update{$_};
            }
            $u->update_self( \%update ) if %update;

            # reload the user object to force the display of these changes
        $u = LJ::load_user($u->user, 'force');

    }

    return DW::Template->render_template( 'customize/options.tt', $vars );

}

sub render_customizetheme {
    my $vars;
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);
    my %opts = @_;
    
    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";
    my $style = LJ::S2::load_style($u->prop('s2_style'));
    die "Style not found." unless $style && $style->{userid} == $u->id;
    my %groups = LJ::Customize->get_propgroups($u, $style);
    my $group_names = $groups{groups};

    my $group = $opts{group} ? $opts{group} : "display";


    $vars->{u} = $u;
    $vars->{remote} = $remote;
    $vars->{getextra} = ( $u ne $remote) ? ( "?authas=" . $u->user ) : '';
    $vars->{getsep} = $getsep;
    $vars->{style} = $style;
    $vars->{groups} = \%groups;
    $vars->{group_names} = $group_names;
    $vars->{propgroup_name} = sub { LJ::Customize->propgroup_name(@_); }; 
    $vars->{has_customcss} =  1; #FIXME (map { customcss => 1 } @$group_names);
    $vars->{group} = $group;

    $vars->{help_icon} = \&LJ::help_icon;
    my @moodthemes = LJ::Customize->get_moodtheme_select_list($u);
    $vars->{moodthemes} = \@moodthemes;
    my $preview_moodthemeid = defined $opts{preview_moodthemeid} ? $opts{preview_moodthemeid} : $u->moodtheme;
    my $forcemoodtheme = defined $opts{forcemoodtheme} ? $opts{forcemoodtheme} : $u->{opt_forcemoodtheme} eq 'Y';
    $vars->{preview_moodthemeid} = $preview_moodthemeid;
    $vars->{forcemoodtheme} = $forcemoodtheme;
    my $mobj = DW::Mood->new( $preview_moodthemeid );
    $vars->{mobj} = $mobj;
    $vars->{eall} = \&LJ::eall;


    my $theme = LJ::Customize->get_current_theme($u);
    my @props = S2::get_properties($theme->layoutid);
    my %prop_is_used = map { $_ => 1 } @props;
    my %colors_values = LJ::Customize->get_s2_prop_values("custom_control_strip_colors", $u, $style);
    my %bgcolor_values = LJ::Customize->get_s2_prop_values("control_strip_bgcolor", $u, $style);
    my %fgcolor_values = LJ::Customize->get_s2_prop_values("control_strip_fgcolor", $u, $style);
    my %bordercolor_values = LJ::Customize->get_s2_prop_values("control_strip_bordercolor", $u, $style);
    my %linkcolor_values = LJ::Customize->get_s2_prop_values("control_strip_linkcolor", $u, $style);
    $vars->{props} = \@props;
    $vars->{colors_values} = \%colors_values;
    $vars->{bgcolor_values} = \%bgcolor_values;
    $vars->{fgcolor_values} = \%fgcolor_values;
    $vars->{bordercolor_values} = \%bordercolor_values;
    $vars->{linkcolor_values} = \%linkcolor_values;
    $vars->{get_property} = sub { S2::get_property($theme->coreid, $_); };
    $vars->{prop_is_used} = \%prop_is_used;
    $vars->{isref} = sub { return ref $_; };
    $vars->{nav_class} = sub {
        my $g = shift;
        my $classes = "";

        if ($g eq $group) {
            $classes .= " class='on";
            $classes .= "'";
        }

        return $classes;
    };
    $vars->{render_s2propgroup} = \&render_s2propgroup;
    $vars->{render_linkslist} = \&render_linkslist;
    $vars->{render_currenttheme} = \&render_currenttheme;



return DW::Template->template_string( 'customize/customizetheme.tt', $vars );

}

sub render_s2propgroup {
    my $vars;
    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $style = LJ::S2::load_style($u->prop('s2_style'));
    die "Style not found." unless $style && $style->{userid} == $u->id;
    
    my $remote = LJ::get_remote();
    my $getextra = $u->user ne $remote->user ? "?authas=" . $u->user : "";
    my $getsep = $getextra ? "&" : "?";
    my %opts = @_;

    $vars->{u} = $u;
    $vars->{remote} = $remote;
    $vars->{getextra} = ( $u ne $remote) ? ( "?authas=" . $u->user ) : '';
    $vars->{getsep} = $getsep;
    $vars->{style} = $style;

    my $props = $opts{props};
    my $propgroup = $opts{propgroup};
    my $groupprops = $opts{groupprops};
    return "DIED" unless ($props && $propgroup && $groupprops) || $opts{show_lang_chooser};

    my $theme = LJ::Customize->get_current_theme($u);

    $vars->{theme} = $theme;
    $vars->{props} = $props;
    $vars->{propgroup} = $propgroup;
    $vars->{groupprops} = $groupprops;
    $vars->{propgroup_name} = sub { LJ::Customize->propgroup_name(@_); };
    $vars->{skip_prop} = \&skip_prop;
    $vars->{help_icon} = \&LJ::help_icon;
    $vars->{eall} = \&LJ::eall;
    $vars->{can_use_prop} = \&LJ::S2::can_use_prop;
    $vars->{get_s2_prop_values} = sub { LJ::Customize->get_s2_prop_values(@_); };
    $vars->{output_prop} = \&output_prop;
    $vars->{get_subheaders} =  sub {LJ::Customize->get_propgroup_subheaders; };
    $vars->{get_subheaders_order} =  sub {LJ::Customize->get_propgroup_subheaders_order; };
    $vars->{eval} = sub { eval $_ };
    $vars->{output_prop_element} = \&output_prop_element;

    if ($propgroup eq "presentation") {
        my @basic_props = $theme->display_option_props;
        my %is_basic_prop = map { $_ => 1 } @basic_props;

        $vars->{basic_props} =\@basic_props;
        $vars->{is_basic_prop} = \%is_basic_prop;

        
    } elsif ( $propgroup eq "modules" ) {

        my %prop_values = LJ::Customize->get_s2_prop_values( "module_layout_sections", $u, $style );
        my $layout_sections_values = $prop_values{override};
        my @layout_sections_order = split( /\|/, $layout_sections_values );

        # allow to override the default property with your own custom property definition. Created and values set in layout layers.
        my %grouped_prop_override = LJ::Customize->get_s2_prop_values( "grouped_property_override", $u, $style, noui => 1 );
        %grouped_prop_override = %{$grouped_prop_override{override}} if %{$grouped_prop_override{override} || {}};

        my %subheaders = @layout_sections_order;
        $subheaders{none} = "Unassigned";

        # use the module section order as defined by the layout
        my $i=0;
        @layout_sections_order = grep { $i++ % 2 == 0; } @layout_sections_order;

        my %prop_in_subheader;
        foreach my $prop_name ( @$groupprops ) {
            next unless $prop_name =~ /_group$/;

            # use module_*_section for the dropdown
            my $prop_name_section = $prop_name;
            $prop_name_section =~ s/(.*)_group$/$1_section/;

            my $overriding_prop_name = $grouped_prop_override{$prop_name_section};

            # module_*_section_override overrides module_*_section;
            # for use in child layouts since they cannot redefine an existing property
            my $prop_name_section_override = defined $overriding_prop_name
                ? $props->{$overriding_prop_name}->{values} : undef;

            # put this property under the proper subheader (this is the original; may be overriden)
            my %prop_values = LJ::Customize->get_s2_prop_values( $prop_name_section, $u, $style );

            if ( $prop_name_section_override ) {
                $prop_name_section = $overriding_prop_name;

                # check if we have anything previously saved into the overriding property. If we don't we retain
                # the value of the original (non-overridden) property, so we don't break existing customizations
                my %overriding_prop_values = LJ::Customize->get_s2_prop_values( $prop_name_section, $u, $style );
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

            if ( $prop_name_section_override ) {
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
            next if $cap && !( $u->get_cap( $cap ) );

            # force it to the "none" section, if property value is not a valid subheader
            my $subheader = $subheaders{$prop_values{override}} ? $prop_values{override} : "none";
            $prop_in_subheader{$subheader} ||= [];
            push @{$prop_in_subheader{$subheader}}, $prop_name;
        }
            $vars->{layout_sections_order} = \@layout_sections_order;
            $vars->{prop_in_subheader} = \%prop_in_subheader;
            $vars->{subheaders} = \%subheaders;
            $vars->{grouped_prop_override} = \%grouped_prop_override;

    } elsif ($propgroup eq "text") {
        my %subheaders = LJ::Customize->get_propgroup_subheaders;

        # props under the unsorted subheader include all props in the group that aren't under any of the other subheaders
        my %unsorted_props = map { $_ => 1 } @$groupprops;
        foreach my $subheader (keys %subheaders) {
            my @subheader_props = eval "\$theme->${subheader}_props";
            foreach my $prop_name (@subheader_props) {
                delete $unsorted_props{$prop_name} if $unsorted_props{$prop_name};
            }
        }
        $vars->{unsorted_props} = \%unsorted_props;
        $vars->{subheaders} = \%subheaders;
    } else {
        my %subheaders = LJ::Customize->get_propgroup_subheaders;

        # props under the unsorted subheader include all props in the group that aren't under any of the other subheaders
        my %unsorted_props = map { $_ => 1 } @$groupprops;
        foreach my $subheader (keys %subheaders) {
            my @subheader_props = eval "\$theme->${subheader}_props";
            foreach my $prop_name (@subheader_props) {
                delete $unsorted_props{$prop_name} if $unsorted_props{$prop_name};
            }
        }

        $vars->{unsorted_props} = \%unsorted_props;
        $vars->{subheaders} = \%subheaders;

    }

    if ($opts{show_lang_chooser}) { 

        my $pub = LJ::S2::get_public_layers();
        my $userlay = LJ::S2::get_layers_of_user($u);

        my @langs = LJ::S2::get_layout_langs($pub, $style->{'layout'});
        my $get_lang = sub {
            my $styleid = shift;
            foreach ($userlay, $pub) {
                return $_->{$styleid}->{'langcode'} if
                    $_->{$styleid} && $_->{$styleid}->{'langcode'};
            }
            return undef;
        };

        my $langcode = $get_lang->($style->{'i18n'}) || $get_lang->($style->{'i18nc'});
        # they have set a custom i18n layer
        if ($style->{'i18n'} &&
            ($style->{'i18nc'} != $style->{'i18n'} || ! defined $pub->{$style->{'i18n'}})) {
            push @langs, 'custom', DW::ml('widget.s2propgroup.language.custom');
            $langcode = 'custom';
        }
        $vars->{show_lang_chooser} = 1;
        $vars->{langcode} = $langcode;
        $vars->{langs} = \@langs;
    }

return DW::Template->template_string( 'customize/s2propgroup.tt', $vars );
}

sub skip_prop {

    my $prop = shift;
    my $prop_name = shift;
    my %opts = @_;

    my $props_to_skip = $opts{props_to_skip};
    my $theme = $opts{theme};

    if (!$prop) {
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
    } else {
        return 1 if $prop_name eq "text_view_friends_comm"
    }

    return 1 if $prop_name eq "custom_control_strip_colors";
    return 1 if $prop_name eq "control_strip_bgcolor";
    return 1 if $prop_name eq "control_strip_fgcolor";
    return 1 if $prop_name eq "control_strip_bordercolor";
    return 1 if $prop_name eq "control_strip_linkcolor";

    my $hook_rv = LJ::Hooks::run_hook("skip_prop_override", $prop_name, user => $opts{user}, theme => $theme, style => $opts{style});
    return $hook_rv if $hook_rv;

    return 0;
}

sub output_prop_element {
    my ( $prop, $prop_name, $u, $style, $theme, $props, $is_group, $grouped_prop_override, $overriding_values ) = @_;
    $grouped_prop_override ||= {};
    $overriding_values ||= {};

    my $name = $prop->{name};
    my $type = $prop->{type};

    my $can_use = LJ::S2::can_use_prop($u, $theme->layout_uniq, $name);

    my %prop_values = %$overriding_values ? %$overriding_values : LJ::Customize->get_s2_prop_values( $name, $u, $style );

    my $existing = $prop_values{existing};
    my $override = $prop_values{override};

    my %values = split( /\|/, $prop->{values} || '' );
    my $existing_display = defined $existing && defined $values{$existing} ? $values{$existing} : $existing;

    $existing_display = LJ::eall($existing_display);

    my $vars;
    my @values;
    @values = split( /\|/, $prop->{values} ) if $prop->{values};
    $vars->{name} = $name;
    $vars->{type} = $type;
    $vars->{can_use} = $can_use;
    $vars->{existing_display} = $existing_display;
    $vars->{grouped_prop_override} = $grouped_prop_override;
    $vars->{theme} = $theme;
    $vars->{u} = $u;
    $vars->{style} = $style;
    $vars->{is_group} = $is_group;
    $vars->{props} = $props;
    $vars->{prop} = $prop;
    $vars->{overriding_values} = $overriding_values;
    $vars->{eall} = \&LJ::eall;
    $vars->{help_icon} = \&LJ::help_icon;
    $vars->{output_prop_element} = \&output_prop_element;
    $vars->{override} = $override;
    $vars->{value_list} = \@values;

return DW::Template->template_string( 'customize/output_prop_element.tt', $vars );

  
}

sub render_linkslist {
    my %opts = @_;

    my $u = LJ::get_effective_remote();
    die "Invalid user." unless LJ::isu($u);

    my $post = $opts{post};
    my $linkobj = LJ::Links::load_linkobj($u, "master");
    my $link_min = $opts{link_min} || 5; # how many do they start with ?
    my $link_more = $opts{link_more} || 5; # how many do they get when they click "more"
    my $order_step = $opts{order_step} || 10; # step order numbers by

    # how many link inputs to show?
    my $showlinks = $post->{numlinks} || @$linkobj;
    my $caplinks = $u->count_max_userlinks;
    $showlinks += $link_more if $post->{'action:morelinks'};
    $showlinks = $link_min if $showlinks < $link_min;
    $showlinks = $caplinks if $showlinks > $caplinks;
    
    my $vars;
    $vars->{linkobj} = $linkobj;
    $vars->{link_min} = $link_min;
    $vars->{link_more} = $link_more;
    $vars->{order_step} = $order_step;
    $vars->{showlinks} = $showlinks;
    $vars->{caplinks} = $caplinks;

    return DW::Template->template_string( 'customize/linkslist.tt', $vars );
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

