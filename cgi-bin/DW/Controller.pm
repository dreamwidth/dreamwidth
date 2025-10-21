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
use DW::Template;
use URI;

our ( @ISA, @EXPORT );
@ISA    = qw/ Exporter /;
@EXPORT = qw/ needlogin error_ml success_ml controller /;

# redirects the user to the login page to handle that eventuality
sub needlogin {
    my $r = DW::Request->get;

    my $uri = $r->uri;
    if ( my $qs = $r->query_string ) {
        $uri .= '?' . $qs;
    }
    $uri = LJ::eurl($uri);

    $r->header_out( Location => "$LJ::SITEROOT/?returnto=$uri" );
    return $r->REDIRECT;
}

# returns an error page using a language string
sub error_ml {
    return DW::Template->render_template( 'error.tt',
        { message => LJ::Lang::ml( $_[0], $_[1] ), opts => $_[2] } );
}

# return a success page using a language string
sub success_ml {
    return DW::Template->render_template( 'success.tt',
        { message => LJ::Lang::ml( $_[0], $_[1] ), links => $_[2] } );
}

# return a success page, takes the following arguments:
#   - a scope page in the form of `page-name.tt', in the form that DW::Controller->render_template expects
#       this scope's corresponding .tt.text should have a ".success.message" and ".success.title"
#   - a hashref of arguments to ".success.message", if needed
#   - a list of links, with each link being in the form of { text_ml => ".success.link.x", url => LJ::create_url( "..." ) }
sub render_success {
    return DW::Template->render_template(
        'success-page.tt',
        {
            scope             => "/" . $_[1],
            message_arguments => $_[2],
            links             => $_[3],
        }
    );
}

# helper controller.  give it a few arguments and it does nice things for you.
#
# Supported arguments: (1 stands for any true value, 0 for any false value)
# - anonymous => 1 -- lets anonymous (not logged in) visitors view the page
# - anonymous => 0 -- doesn't (default)
# - authas => 1  or { args } -- allows ?authas= in URL, generates authas form
#                              (not permitted if anonymous => 1 specified)
# - authas => 0 -- doesn't (default)
# - specify_user => 1 -- allows ?user= in URL (Note: requesting both authas and
#                        specify_user is allowed, but probably not a good idea)
# - specify_user => 0 -- doesn't (default)
# - privcheck => $privs -- user must be logged in and have at least one priv of
#                          the ones in this arrayref.
#                          Example: [ "faqedit:guides", "faqcat", "admin:*" ]
# - skip_domsess => 1 -- (for user domains) don't redirect if there is no
#                         domain login cookie
# - skip_domsess => 0 -- (for user domains) do redirect for the user domain
#                        cookie (default)
# - form_auth => 0 -- Do not automatically check form auth ( current default )
# - form_auth => 1 -- Automatically check form auth ( planned to be future default )
#    On any new controller, please try and pass "form_auth => 0" if you are checking
#      the form auth yourself, or if the automatic check will cause problems.
#      Thank you.
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
    my (%args) = @_;

    my $vars = {};
    my $fail = sub { return ( 0, $_[0] ); };
    my $ok   = sub { return ( 1, $vars ); };

    # some argument combinations are invalid, so just die.  this is something that should
    # be caught in development...
    die "Invalid usage of controller, check your calling arguments.\n"
        if ( $args{authas} && $args{specify_user} )
        || ( $args{authas} && $args{anonymous} )
        || ( $args{privcheck} && $args{anonymous} );

    $args{form_auth} //= 0;

    # 'anonymous' pages must declare themselves, else we assume that a remote is
    # necessary as most pages require a user
    $vars->{u} = $vars->{remote} = LJ::get_remote();

    my $r = DW::Request->get;
    $vars->{r} = $r;

    # check to see if we need to do a bounce to set the domain cookie
    unless ( $r->did_post || $args{skip_domsess} ) {
        my $burl = LJ::remote_bounce_url();
        if ($burl) {
            $r->err_header_out( "Cache-Control" => "no-cache" );
            return $fail->( $r->redirect($burl) );
        }
    }

    unless ( $args{anonymous} ) {
        $vars->{remote}
            or return $fail->( needlogin() );
    }

    # if they can specify a user argument, try to load that
    if ( $args{specify_user} ) {

        # use 'user' argument if specified, default to remote
        $vars->{u} = LJ::load_user( $r->get_args->{user} ) || $vars->{remote}
            or return $fail->( error_ml('error.invaliduser') );
    }

    # if a page allows authas it must declare it.  authas can only happen if we are
    # requiring the user to be logged in.
    if ( $args{authas} ) {
        $vars->{u} = LJ::get_authas_user( $r->get_args->{authas} || $vars->{remote}->user )
            or return $fail->( error_ml('error.invalidauth') );

        my $authas_args = $args{authas} == 1 ? {} : $args{authas};

        # older pages
        $vars->{authas_html} =
            LJ::make_authas_select( $vars->{remote}, { authas => $vars->{u}->user } );

        # foundation pages
        $vars->{authas_form} =
              "<form action='"
            . LJ::create_url()
            . "' method='get'>"
            . LJ::make_authas_select( $vars->{remote},
            { authas => $vars->{u}->user, foundation => 1, %{ $authas_args || {} } } )
            . "</form>";
    }

    # check user is suitably privved
    if ( my $privs = $args{privcheck} ) {

        # if they just gave us a string, throw it in an array
        $privs = [$privs] unless ref $privs eq 'ARRAY';

        # now iterate over the array and check.  the user must have ANY
        # of the privs to pass the test.
        my $has_one = 0;
        my @privnames;
        foreach my $priv (@$privs) {

            # if priv is a string, assign the priv having to has_one and stop searching
            if ( not ref($priv) ) {
                if ( $vars->{remote}->has_priv($priv) ) {
                    $has_one = 1;
                    last;
                }
                else {
                    push @privnames, $priv;
                }
            }
            elsif ( ref($priv) eq "CODE" ) {    # if priv is a function, get the result and name
                my ( $result, $name ) = $priv->( $vars->{remote} );
                if ($result) {
                    $has_one = 1;
                    last;
                }
                else {
                    push @privnames, $name;
                }
            }
            else {
                die "Malformed priv in privcheck!";
            }
        }

        # now if they have none, throw an error message
        return $fail->(
            error_ml(
                'admin.noprivserror',
                {
                    numprivs  => scalar @$privs,
                    needprivs => join( ', ', sort @privnames )
                }
            )
        ) unless $has_one;
    }

    if ( $r->did_post && $args{form_auth} ) {
        my $post_args = $r->post_args || {};
        return $fail->( error_ml('error.invalidform') )
            unless LJ::check_form_auth( $post_args->{lj_form_auth} );
        $vars->{post_args} = $post_args;
    }

    # everything good... let the caller know they can continue
    return $ok->();
}

# checks a URL to make sure it's ok to redirect to it.
#
# note that this checks on the host name of the given URL, so it's important
# to make sure to pass in a full, absolute URL rather than a relative URI.
sub validate_redirect_url {
    my $url = $_[0];

    return 0 unless $url;

    # Redirect to offsite uri if allowed, and not an internal LJ redirect.
    my $parsed_uri = URI->new($url);

    # if the given URI isn't valid, the URI module doesn't even give the
    # returned object a host method
    my $redir_host = eval { $parsed_uri->host } || "";

    return $LJ::REDIRECT_ALLOWED{$redir_host} || $redir_host =~ m#${LJ::DOMAIN}$#i;
}

1;
