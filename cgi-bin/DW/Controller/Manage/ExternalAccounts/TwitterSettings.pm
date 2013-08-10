#!/usr/bin/perl
##
## DW::Controller::Manage::ExternalAccounts::TwitterSettings
##
## /manage/externalaccounts/twittersettings
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


package DW::Controller::Manage::ExternalAccounts::TwitterSettings;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::External::Account;
use DW::External::OAuth;

DW::Routing->register_string( "/manage/externalaccounts/twittersettings", \&twittersettings_handler, app=>1 );

sub twittersettings_handler {
    my ( $ok, $rv ) = controller( anonymous => 0 );
    return $rv unless $ok;

    my $u = $rv->{u};

    return error_ml( 'twitter.twitter_disabled' ) unless $LJ::TWITTER{enabled};

    my $r = DW::Request->get;
    my $get_args = $r->get_args;
    my $post_args = $r->post_args;

    my @message_list;   #non-error messages to show at the top of the form
    my @error_list;     #error messages to show at the top of the form
    my $vars;        #hashref for outputs to the template;

    my $acctid = $post_args->{acctid} || $get_args->{acctid};
    #$acctid should indicate which of the user's accounts is being
    # edited. If undef, we are creating a new account.

    unless ( $acctid ) {
        #Making a new account.
        
        #check whether we already have the maximum number of external accounts
        my $max_accts = $u->count_max_xpost_accounts;
        my $acct_count = 
            scalar( DW::External::Account->get_external_accounts( $u ) );
        if ( $acct_count >= $max_accts ) {
            my $errstring = $max_accts == 1 ? 'twitter.maxaccounts.singular' :
                                            'twitter.maxaccounts.plural';
            return error_ml( $errstring, { max_accts => $max_accts } );
        }

        #default settings for new Twitter account. The user will get a chance
        #to change these after OAuth.
        my %opts = (
            username => '-',   #temporary dummy username. Will be updated
                               # after OAuth.
            password => 'dummy', #dummy password. OAuth accounts don't use it.
            xpostbydefault => 0,
            recordlink => 0,
            oauth_authorized => 0,
            savepassword => 1, #so that the user isn't asked for a
                               # non-existant password all the time
            siteid => 9,       #This is a twitter account.
        );

        $opts{options} = { prefix_text => LJ::Lang::ml( 'twitter.prefix_text.default', { siteabbrev => $LJ::SITENAMEABBREV } ) };
                                 
        #make the account
        my $extacct = DW::External::Account->create( $u, \%opts );
        LJ::throw( 'Failed to create new external account' )
            unless $extacct;

        #now start OAuth on the new account
        my $acctid = $extacct->acctid;
        return $r->redirect( "$LJ::SITEROOT/manage/externalaccounts/begin_oauth?acctid=$acctid" );

    }

    if ( $get_args->{callback} ) {
        #This is a callback in the middle of twitter's OAuth workflow.
        # We need to complete the OAuth process, and show the success or error.
        my $res = DW::External::OAuth::oauth_callback ( $u, $get_args );
        
        push @message_list, LJ::Lang::ml( 'twitter.auth.success', 
                { sitename => $LJ::SITENAMESHORT } )
            if $res->{success};

        push @error_list, $res->{error} if $res->{error};
    }

    my $extacct = DW::External::Account->get_external_account( $u, $acctid );
    LJ::throw( 'Could not retrieve external account object' ) unless $extacct;
    LJ::throw( 'Not an Twitter account' ) unless $extacct->siteid == 9;

    if ( $r->did_post ) {
    # Somebody pushed "Update" on the form.

        $post_args->{prefix_text} = LJ::trim( $post_args->{prefix_text} );

        my $form_ok = 1;

        #sanity-check for very long prefix text that wouldn't leave room for
        # a URL. The HTML box has maxlength of 100, so this should never 
        # happen.
        my ( $bl, $prefixlength ) = LJ::text_length( $post_args->{prefix_text});
        if ( $prefixlength > 100 ) {
            push @error_list, LJ::Lang::ml( 'twitter.settings.prefix_too_long' ) ;
            $form_ok = 0;
        }

        if ( $form_ok ) {
            #Update the options
            $extacct->set_xpostbydefault( $post_args->{tweetbydefault} );
            my $extacct_opts = $extacct->options;
            if ( $post_args->{prefix_text} ne $extacct_opts->{prefix_text} ) {
                $extacct_opts->{prefix_text} = $post_args->{prefix_text};
                $extacct->set_options( $extacct_opts );
            }

            #Now redirect to the main Other Sites page.
            return $r->redirect( "$LJ::SITEROOT/manage/settings/?cat=othersites&update=$acctid" );
        }

        #If we're here then there was a problem on the form. Pre-populate the
        # form data according to what was entered before:
        $vars->{formdata} = $post_args;
        
    }

    #by this point we should be editing an existing account

    #Test the auth. (and update the username while we're at it)
    my $res = $extacct->protocol->verify_auth( $extacct );

    if ( $res->{success} && $res->{username} ne $extacct->username ) {
        $extacct->set_username( $res->{username} );
        push @message_list, LJ::Lang::ml( 'twitter.username_updated' );
    }

    push @error_list, $res->{error} if $res->{error};

    my $extacct_opts = $extacct->options;

    #Things to pass to the template
    
    $vars->{acctid} = $acctid;

    #It's possible for verify_auth to fail and return an error for reasons that
    #aren't to do with OAuth (e.g. twitter is down). In this case, it should
    #have left oauth_authorized alone - so we'll check that rather than assuming
    #anything from the above.
    $vars->{is_authorized} = $extacct->oauth_authorized;

    #If verify_auth failed then this username may be out of date, but even an 
    #old username can be helpful in identifying an account to the user.
    $vars->{username} = $extacct->username;

    #get the current tweet-by-default setting
    $vars->{tweetbydefault} = $extacct->xpostbydefault;

    #get the currently-set prefix text (which may be blank)
    $vars->{prefix_text} = $extacct_opts->{prefix_text};

    $vars->{message_list} = \@message_list if @message_list;
    $vars->{error_list} = \@error_list if @error_list;

    return DW::Template->render_template( 'manage/externalaccounts/twittersettings.tt', $vars );
}

1;
