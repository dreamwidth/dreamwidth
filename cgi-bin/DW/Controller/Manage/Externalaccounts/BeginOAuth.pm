#!/usr/bin/perl
##
## DW::Controller::Manage::Externalaccounts::BeginOAuth
##
## /manage/externalaccounts/beginoauth
##
## Authors:
##      Simon Waldman <swaldman@firecloud.org.uk>
##
## Copyright (c) 2012 by Dreamwidth Studios, LLC.
##
## This program is free software; you may redistribute it and/or modify it under
## the same terms as Perl itself. For a copy of the license, please reference
## 'perldoc perlartistic' or 'perldoc perlgpl'.
##
#


package DW::Controller::Manage::Externalaccounts::BeginOAuth;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::External::Account;
use DW::External::OAuth;

DW::Routing->register_string( "/manage/externalaccounts/begin_oauth", \&beginoauth_handler, app=>1 );

sub beginoauth_handler {
    my ( $ok, $rv ) = controller( anonymous => 0 );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $acctid = $r->get_args->{acctid};
    LJ::throw( 'Required parameter missing' ) unless $acctid;

    my $extacct = DW::External::Account->get_external_account( 
        $rv->{u}, $acctid );
    LJ::throw( 'Could not retrieve extacct' ) unless $extacct;
    my $res = DW::External::OAuth::start_oauth( $extacct );

    LJ::throw( 'Unexpected return from start_oauth' )
        unless ref $res eq 'HASH';
    return error_ml( 'oauth.start.fail', { error => $res->{error} } )
        if $res->{error};

    return $r->redirect( $res->{auth_url} );
}
1;
