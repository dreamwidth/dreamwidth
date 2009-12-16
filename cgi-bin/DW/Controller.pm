#!/usr/bin/perl
#
# DW::Controller
#
# Not actually a controller, but contains methods that help other controllers.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller;

use strict;
use warnings;
use Exporter;
use DW::Routing::Apache2;
use DW::Template::Apache2;

our ( @ISA, @EXPORT );
@ISA = qw/ Exporter /;
@EXPORT = qw/ needlogin error_ml controller /;

# redirects the user to the login page to handle that eventuality
sub needlogin {
    my $r = DW::Request->get;

    my $uri = $r->uri;
    if ( my $qs = $r->query_string ) {
        $uri .= '?' . $qs;
    }
    $uri = LJ::eurl( $uri );

    $r->header_out( Location => "$LJ::SITEROOT/?returnto=$uri" );
    return $r->REDIRECT;
}

# returns an error page using a language string
sub error_ml {
    return DW::Template::Apache2->render_template(
        'error.tt', { message => LJ::Lang::ml( $_[0] ) }
    );
}

# helper controller.  give it a few arguments and it does nice things for you.
sub controller {
    my ( %args ) = @_;

    my $vars = {};
    my $fail = sub { return ( 0, $_[0] ); };
    my $ok   = sub { return ( 1, $vars ); };

    # ensure the arguments make sense... anonymous means we cannot authas
    delete $args{authas} if $args{anonymous};

    # 'anonymous' pages must declare themselves, else we assume that a remote is
    # necessary as most pages require a user
    unless ( $args{anonymous} ) {
        $vars->{u} = $vars->{remote} = LJ::get_remote()
            or return $fail->( needlogin() );
    }

    # if a page allows authas it must declare it.  authas can only happen if we are
    # requiring the user to be logged in.
    my $r = DW::Request->get;
    if ( $args{authas} ) {
        $vars->{u} = LJ::get_authas_user( $r->get_args->{authas} || $vars->{remote}->user )
            or return $fail->( error_ml( 'error.invalidauth' ) );
        $vars->{authas_html} = LJ::make_authas_select( $vars->{remote}, { authas => $vars->{u}->user } );
    }

    # everything good... let the caller know they can continue
    return $ok->();
}

1;
