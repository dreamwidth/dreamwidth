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

    my $vars;
    $vars->{u} = $u;
    $vars->{remote} = $remote;
    $vars->{getextra} = ( $u ne $remote) ? ( "?authas=" . $u->user ) : '';
    $vars->{is_identity} = 1 if $u->is_identity;
    $vars->{is_community} = 1 if $u->is_community;
    $vars->{style} = LJ::Customize->verify_and_load_style($u);



    $vars->{cat} = defined $GET->get_args->{cat} ? $GET->get_args->{cat} : "";
    $vars->{layoutid} = defined $GET->get_args->{layoutid} ? $GET->get_args->{layoutid} : 0;
    $vars->{designer} = defined $GET->get_args->{designer} ? $GET->get_args->{designer} : "";
    $vars->{search} = defined $GET->get_args->{search} ? $GET->get_args->{search} : "";
    $vars->{page} = defined $GET->get_args->{page} ? $GET->get_args->{page} : 1;
    $vars->{show} = defined $GET->get_args->{show} ? $GET->get_args->{show} : 12;

    # create all our widgets
    my $current_theme = LJ::Widget::CurrentTheme->new;
    $vars->{current_theme} = $current_theme;
    $vars->{headextra} .= $current_theme->wrapped_js( page_js_obj => "Customize" );
    my $journal_titles = LJ::Widget::JournalTitles->new;
    $vars->{journal_titles} = $journal_titles;
    $vars->{headextra} = $journal_titles->wrapped_js;
    my $theme_nav = LJ::Widget::ThemeNav->new;
    $vars->{theme_nav} = $theme_nav;
    $vars->{headextra} .= $theme_nav->wrapped_js( page_js_obj => "Customize" );
    my $layout_chooser = LJ::Widget::LayoutChooser->new;
    $vars->{layout_chooser} = $layout_chooser;
    $vars->{headextra} .= $layout_chooser->wrapped_js( page_js_obj => "Customize" );


    # lazy migration of style name
    LJ::Customize->migrate_current_style($u);
        
    # Now we tell it what template to render and pass in our variables
    return DW::Template->render_template( 'customize.tt', $vars );

}

1;
