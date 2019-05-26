#!/usr/bin/perl
#
# DW::Controller::Nav
#
# This controller is for navigation handlers.
#
# Authors:
#      foxfirefey <skittisheclipse@gmail.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Nav;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Logic::MenuNav;
use LJ::JSON;

# Defines the URL for routing.  I could use register_string( '/nav' ... ) if I didn't want to capture arguments
# This is an application page, not a user styled page, and the default format is HTML (ie, /nav gives /nav.html)
DW::Routing->register_regex(
    qr!^/nav(?:/([a-z]*))?$!, \&nav_handler,
    app     => 1,
    formats => [ 'html', 'json' ]
);

# handles menu nav pages
sub nav_handler {
    my ( $opts, $cat ) = @_;
    my $r = DW::Request->get;

    # Check for a category like nav/read, then for a ?cat=read argument, else no category
    $cat ||= $r->get_args->{cat} || '';

    # this function returns an array reference of menu hashes
    my $menu_nav = DW::Logic::MenuNav->get_menu_display($cat)
        or return error_ml('/nav.tt.error.invalidcat');

    # this data doesn't need HTML in the titles, like in the real menu
    for my $menu (@$menu_nav) {
        for my $item ( @{ $menu->{items} } ) {
            $item->{text} = LJ::strip_html( $item->{text} );
        }
    }

    # display according to the format
    my $format = $opts->format;
    if ( $format eq 'json' ) {

        # this prints out the menu navigation as JSON and returns
        $r->print( to_json($menu_nav) );
        return $r->OK;
    }
    elsif ( $format eq 'html' ) {

        # these variables will get passed to the template
        my $vars = {
            menu_nav => $menu_nav,
            cat      => $cat,
        };

        $vars->{cat_title} = $menu_nav->[0]->{title} if $cat;

        # Now we tell it what template to render and pass in our variables
        return DW::Template->render_template( 'nav.tt', $vars );
    }
    else {
        # return 404 for an unknown format
        return $r->NOT_FOUND;
    }
}

1;
