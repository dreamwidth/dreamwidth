#!/usr/bin/perl
#
# DW::Controller
#
# Not actually a controller, but contains methods that help other controllers.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller;

use strict;
use warnings;
use Exporter;
use DW::Routing;
use DW::Template;

our ( @ISA, @EXPORT );
@ISA = qw/ Exporter /;
@EXPORT = qw/ needlogin error_ml success_ml controller /;

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
    return DW::Template->render_template(
        'error.tt', { message => LJ::Lang::ml( @_ ) }
    );
}

# return a success page using a language string
sub success_ml {
    return DW::Template->render_template(
        'success.tt', { message => LJ::Lang::ml( @_ ) }
    );
}

# helper controller.  give it a few arguments and it does nice things for you.
#
# Supported arguments: (1 stands for any true value, 0 for any false value)
# - anonymous => 1 -- lets anonymous (not logged in) visitors view the page
# - anonymous => 0 -- doesn't (default)
# - authas => 1 -- allows ?authas= in URL, generates authas form (not permitted
#                  if anonymous => 1 specified)
# - authas => 0 -- doesn't (default)
# - specify_user => 1 -- allows ?user= in URL (Note: requesting both authas and
#                        specify_user is allowed, but probably not a good idea)
# - specify_user => 0 -- doesn't (default)
# - privcheck => $privs -- user must be logged in and have at least one priv of
#                          the ones in this arrayref.
#                          Example: [ "faqedit:guides", "faqcat", "admin:*" ]
#
# Returns one of:
# - 0, $error_text (if there's an error)
# - 1, $hashref (if everything looks good)
#
# Returned hashref can be passed to DW::Template->render_template as the 2nd
# argument, and has the following keys:
# - remote -- the remote user object or undef (LJ::get_remote())
# - u -- user object for username in ?user= or ?authas= if present and valid,
#        otherwise same as remote
# - authas_html -- HTML for the "switch user" form
sub controller {
    my ( %args ) = @_;

    my $vars = {};
    my $fail = sub { return ( 0, $_[0] ); };
    my $ok   = sub { return ( 1, $vars ); };

    # some argument combinations are invalid, so just die.  this is something that should
    # be caught in development...
    die "Invalid usage of controller, check your calling arguments.\n"
        if ( $args{authas} && $args{specify_user} ) ||
           ( $args{authas} && $args{anonymous} ) ||
           ( $args{privcheck} && $args{anonymous} );

    # 'anonymous' pages must declare themselves, else we assume that a remote is
    # necessary as most pages require a user
    $vars->{u} = $vars->{remote} = LJ::get_remote();
    unless ( $args{anonymous} ) {
        $vars->{remote}
            or return $fail->( needlogin() );
    }

    # if they can specify a user argument, try to load that
    my $r = DW::Request->get;
    if ( $args{specify_user} ) {
        # use 'user' argument if specified, default to remote
        $vars->{u} = LJ::load_user( $r->get_args->{user} ) || $vars->{remote}
            or return $fail->( error_ml( 'error.invaliduser' ) );
    }

    # if a page allows authas it must declare it.  authas can only happen if we are
    # requiring the user to be logged in.
    if ( $args{authas} ) {
        $vars->{u} = LJ::get_authas_user( $r->get_args->{authas} || $vars->{remote}->user )
            or return $fail->( error_ml( 'error.invalidauth' ) );
        $vars->{authas_html} = LJ::make_authas_select( $vars->{remote}, { authas => $vars->{u}->user } );
    }

    # check user is suitably privved
    if ( my $privs = $args{privcheck} ) {
        # if they just gave us a string, throw it in an array
        $privs = [ $privs ] unless ref $privs eq 'ARRAY';

        # now iterate over the array and check.  the user must have ANY
        # of the privs to pass the test.
        my $has_one = 0;
        foreach my $priv ( @$privs ) {
            last if $has_one = $vars->{remote}->has_priv( $priv );
        }

        # now if they have none, throw an error message
        return $fail->( error_ml( 'admin.noprivserror',
                    { numprivs => scalar @$privs,
                      needprivs => join( ', ', sort @$privs ) } ) )
            unless $has_one;
    }

    # everything good... let the caller know they can continue
    return $ok->();
}

1;
