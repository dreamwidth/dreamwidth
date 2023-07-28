#!/usr/bin/perl
#
# DW::Controller::Manage::Circle
#
# /manage/circle
#
# Authors:
#      Cocoa <momijizukamori@gmail.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Circle;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/circle/index",  \&index_handler,  app => 1 );
DW::Routing->register_string( "/manage/circle/filter", \&filter_handler, app => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    return DW::Template->render_template( 'manage/circle/index.tt', $rv );
}

sub filter_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $r    = DW::Request->get;
    my $POST = $r->post_args;

    my $remote = $rv->{remote};
    my @groups = $remote->content_filters;

    if ( $r->did_post && $POST->{'mode'} eq "view" ) {

# for safety, since we will be redirecting to this page be strict in the value we accept for the pageview
        my $pageview = $POST->{pageview} eq "network" ? "network" : "read";

        my $user = lc( $POST->{'user'} );
        my $extra;
        if ( $POST->{type} eq "allfilters" ) {
            my $view = $POST->{'view'};
            if ( $view eq "all" ) {
                $extra = "?filter=0";
            }
            elsif ( $view eq "showpeople" ) {
                $extra = "?show=P&filter=0";
            }
            elsif ( $view eq "showcommunities" ) {
                $extra = "?show=C&filter=0";
            }
            elsif ( $view eq "showsyndicated" ) {
                $extra = "?show=F&filter=0";
            }
            elsif ( $view =~ /filter:(.+)?/ ) {
                $extra = "/$1";
            }
        }
        my $u = LJ::load_user($user);
        return $r->redirect( $u->journal_base() . "/$pageview${extra}" );
    }

    return DW::Template->render_template( 'manage/circle/filter.tt',
        { remote => $remote, groups => \@groups } );
}

1;
