#!/usr/bin/perl
##
## DW::External::OAuth
##
## Functions for authenticating or reauthenticating with OAuth-using external
##  sites. Currently they're specific to Twitter, but it should be 
##  reasonably straightforward to swap from Net::Twitter to Net::Simple::OAuth
##  to generalise.
##
## Authors:
##      Simon Waldman <swaldman@firecloud.org.uk>
##
## Copyright (c) 2012 by Dreamwidth Studios, LLC.
##
## This program is free software; you may redistribute it and/or modify it under
## the same terms as Perl itself. For a copy of the license, please reference
## 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::OAuth;
use strict;
use warnings;
use Net::Twitter;

sub start_oauth {
# Function to begin the OAuth process. Requests a request_token, stores this
#  in the db and returns the URL to redirect to for authorization.
#  Takes: extacct object
#  #FIXME: if this is generalised beyond twitter, will need to take info on site
#  Returns: On success, Hashref containing "auth_url"
#           On faliure, hashref containing "error"

    my $extacct = shift;

    #this shouldn't happen
    return { error => "Not an OAuth account" } unless $extacct->uses_oauth;

    my $userid = $extacct->userid;
    my $acctid = $extacct->acctid;

    #FIXME to generalise beyond Twitter, the callback url will need to be set
    # differently according to which settings page is needed.
    my $callbackurl = "$LJ::SITEROOT/manage/externalaccounts/twittersettings?callback=1&userid=$userid&acctid=$acctid";
    #this callback url must have the same domain as the one set up for the 
    #Twitter application at dev.twitter.com.

    #create a new Net::Twitter object
    my $twitter = Net::Twitter->new( {
        traits => ['API::REST', 'OAuth'],
        consumer_key => $LJ::TWITTER{consumer_key},
        consumer_secret => $LJ::TWITTER{consumer_secret}
    } );

    my $authurl = undef;
    eval { 
        $authurl = $twitter->get_authorization_url( callback => $callbackurl ); 
    };
    #NB $authurl is a URI object, not simple text. It is the currently correct
    # URL for Twitter authorisation with the request_token as a parameter.

    return { error => $@ } unless $authurl;

    #We have been issued a temporary token representing this authentication
    # request. We need to store this to use when twitter redirects the user
    # back to us.
    my $extacct_options = $extacct->options;

    $extacct_options->{is_authorized} = 0;
    $extacct_options->{request_token} = $twitter->request_token;
    $extacct_options->{request_token_secret} = $twitter->request_token_secret;

    #Since we are (re-)authorizing, throw away any existing access token.
    foreach ( qw/access_token access_token_secret/ ) {
        delete $extacct_options->{$_} if $extacct_options->{$_};
    }

    $extacct->set_options( $extacct_options );

    return { auth_url => $authurl };
}

sub oauth_callback {
# Function to continue the OAuth process after the user returns from the 
# other site.
#  Takes: user object for current remote, arguments from http request.
#  Returns: On success, Hashref containing "success => 1"
#           On faliure, hashref containing "error" => error msg

    my ( $remote, $get_args ) = @_;
    #get_args may have: userid, acctid, denied, oauth_token, oauth_verifier

    #make sure we have everything we should have
    unless ( $remote && $get_args->{userid} && $get_args->{acctid} &&
        ( ( $get_args->{oauth_token} && $get_args->{oauth_verifier} ) || 
        $get_args->{denied} ) ) {
            LJ::throw( "Required parameter(s) missing" );
    }

    #check that this callback relates to the current user 
    my $get_user = LJ::load_userid( $get_args->{userid} );
    LJ::throw( "Invalid userid" ) unless $get_user;
    return { error => 'oauth.callback.wronguser' }
        unless $remote->equals( $get_user );

    my $u = $get_user;

    #find the extacct in question
    my $extacct = DW::External::Account->get_external_account( $u,
        $get_args->{acctid} );
    LJ::throw( "Invalid acctid" ) unless $extacct;

    my $extacct_options = $extacct->options;

    #Does the request token coming back from the provider match the one
    # stored for this account?
    my $received_token = $get_args->{oauth_token} || $get_args->{denied};
    return { error => BML::ml( 'oauth.callback.tokenmismatch' ) }
        unless $received_token eq $extacct_options->{request_token};

    #did the OAuth provider deny authorization?
    return { error => BML::ml( 'oauth.callback.authdenied', 
            { service => 'Twitter', sitename => $LJ::SITENAMESHORT } ) }
        if $get_args->{denied};

    #At this point we're fairly sure that this is a real callback, that it
    #relates to the most recent authorization request for this user and
    #extacct, and that it's been authorized. Unless there's something I haven't
    #thought of.

    #Create a Net::Twitter object.
    #Doing this seperately here rather than combining with the same code in
    # XPostprotocol::Twitter, so that this can be generalised later to any
    # OAuth.
    my $twitter = Net::Twitter->new( {
        traits => ['API::REST', 'OAuth'],
        consumer_key => $LJ::TWITTER{consumer_key},
        consumer_secret => $LJ::TWITTER{consumer_secret},
        request_token => $extacct_options->{request_token},
        request_token_secret => $extacct_options->{request_token_secret}
    } );

    #Ask the provider to give us a long-term access token
    my ( $access_token, $access_token_secret, $user_id, $display_name ) = undef;
    eval {
        ( $access_token, $access_token_secret, $user_id, $display_name )
            = $twitter->request_access_token( 
                verifier => $get_args->{oauth_verifier} );
    };
    return { error => $@ } unless $access_token;

    #Save the new access token
    $extacct_options->{access_token} = $access_token;
    $extacct_options->{access_token_secret} = $access_token_secret;
    $extacct_options->{is_authorized} = 1;

    #Get rid of the temporary token
    delete @$extacct_options{ qw( request_token request_token_secret ) };
    
    $extacct->set_options( $extacct_options );

    return { success => 1 };
}

1;
