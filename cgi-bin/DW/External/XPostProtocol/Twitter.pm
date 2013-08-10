#!/usr/bin/perl
##
## DW::External::XPostProtocol::Twitter
##
## XPostProtocol subclass for Twitter.
##
## Authors:
##      Simon Waldman <swaldman@firecloud.org.uk>
##
## Copyright (c) 2013 by Dreamwidth Studios, LLC.
##
## This program is free software; you may redistribute it and/or modify it under
## the same terms as Perl itself. For a copy of the license, please reference
## 'perldoc perlartistic' or 'perldoc perlgpl'.
##

package DW::External::XPostProtocol::Twitter;
use base 'DW::External::XPostProtocol';
use strict;
use warnings;

use Net::Twitter;
use LJ::MemCache;

sub instance {
    my ($class) = @_;
    my $acct = $class->_skeleton();
    return $acct;
}
*new = \&instance;

sub _skeleton {
    my ($class) = @_;
    return bless { protocolid => "Twitter" };
}

sub _get_net_twitter {
#Internal function. Takes an ExternalAccount object. Returns a Net::Twitter
#object with auth set up for that ExternalAccount.
# NB no check is done here that the access token is valid, etc, because
#  the route needed for the error would change depending on where it's
#  called from (worker or web).
#  I recommend checking that $twitter->authorized is true after using 
#  this to get $twitter.

    my ( $extacct ) = @_;

    LJ::throw( 'Not a Twitter account' )
        unless $extacct->siteid == 9;

    return Net::Twitter->new( {
            traits => ['API::RESTv1_1', 'OAuth'],
            consumer_key => $LJ::TWITTER{consumer_key},
            consumer_secret => $LJ::TWITTER{consumer_secret},
            access_token => $extacct->options->{access_token},
            access_token_secret => $extacct->options->{access_token_secret}
        } );
}

sub verify_auth {
# Takes an ExternalAccount object and checks that the OAuth credentials work.
# On success, returns a hashref containing { success => 1, 
# username => Twitter username }. On faliure, returns a hashref with
# {error => error }.

    my ( $self, $extacct ) = @_;
    LJ::throw( 'Required parameter missing' ) unless $extacct;
    LJ::throw( 'Not a DW::External::Account object' )
        unless $extacct->isa( 'DW::External::Account' );

    #check that this is a Twitter account.
    LJ::throw( 'Not a Twitter account' )
        unless $extacct->siteid == 9;

    #check the account's oauth_authorized flag - if already false, we can just fail
    unless ( $extacct->oauth_authorized ) {
        return { error => LJ::Lang::ml( 'twitter.auth.please_reauth', 
                { sitename => $LJ::SITENAMESHORT, 
                  url => "$LJ::SITEROOT/manage/externalaccounts/begin_oauth?acctid=$extacct->{acctid}" } ) };
    }

    # get a net::twitter object
    my $twitter = _get_net_twitter( $extacct );

    # if we don't have access token and secret in the db, we shouldn't have
    # got this far anyway - but just in case, check with the Net::Twitter obj.
    unless ( $twitter->authorized ) {
        return { error => LJ::Lang::ml( 'twitter.auth.please_reauth', 
                { sitename => $LJ::SITENAMESHORT, 
                  url => "$LJ::SITEROOT/manage/externalaccounts/begin_oauth?acctid=$extacct->{acctid}" } ) };
    }

    #Check with Twitter that the credentials are valid
    my $twitteruser;
    eval { $twitteruser = $twitter->verify_credentials; };

    #If that worked, return success with the username.
    return { success => 1, username => $twitteruser->{screen_name} }
        if $twitteruser;
    
    #If we're here it didn't work, so why not?
    return { error => _check_twitter_error( $@, $extacct ) };
}

sub _check_twitter_error {
# Internal function. Takes a Net::Twitter::Error object and an extacct. Returns
# text for an  appropriate error message. If the error is invalid auth, sets
# oauth_authorized to 0 for the extacct.

    my ( $err, $extacct ) = @_;

    if( $err && $err->isa('Net::Twitter::Error') ) {

        #HTTP code 401 means invalid auth.
        if ( $err->http_response->{_rc} == 401 ) {
            $extacct->set_oauth_authorized( 0 );
            return LJ::Lang::ml( 'twitter.auth.please_reauth', 
                    { sitename => $LJ::SITENAMESHORT, 
                      url => "$LJ::SITEROOT/manage/externalaccounts/begin_oauth?acctid=$extacct->{acctid}" } );
        }

        #FIXME do we also want to look out for any other error codes?
        #eg 429 for rate-limiting, or 50x for errors at twitter's end?
        #see https://dev.twitter.com/docs/error-codes-responses

    } else {
        # If $err is not a Net::Twitter::Error object, 
        #  keep it if it says something, but otherwise insert a 
        #  "huh, I dunno?" string ;-)
        $err ||= 'No error object.';
    }

    #To have got this far, it's an error we're not specifically looking out for.
    return LJ::Lang::ml( 'twitter.unknown_error', {err => $err} );
}


sub crosspost {
# Takes an ExternalAccount object, an entry, an itemid (optional), and $delete
# (true for deleting a tweet). Ignores $auth, the auth info comes from the
# ExternalAccount options blob. Returns a hashref with success => 1,
# reference->{itemid} on success. Returns success => 0 and
# error => error on failure.

    my ($self, $extacct, $auth, $entry, $itemid, $delete) = @_;

    unless ( $LJ::TWITTER{enabled} ) {
        return {
            success => 0,
            error => LJ::Lang::ml( 'twitter.twitter_disabled' )
        }
    }

    my $twitter = _get_net_twitter( $extacct ); 
    unless ( $twitter->authorized ) {
        #This doesn't actually check that we are authorized - but it checks
        # that we at least have all the necessary credentials.
        # If we're not authorised we'll find out anyway when we try to 
        # tweet, so no need for an extra connection to Twitter to check.
        return {
            success => 0,
            error => LJ::Lang::ml( 'twitter.auth.please_reauth',
                { sitename => $LJ::SITENAMESHORT,
                  url => "$LJ::SITEROOT/manage/externalaccounts/begin_oauth?acctid=$extacct->{acctid}" } )
        }
    }

    my $status;

    if ( $delete ) {
        unless ( $itemid ) {
            return {
                success => 0,
                error => "Attempt to delete tweet without giving a tweet id."
            }
        }
        eval { $status = $twitter->destroy_status( $itemid ); }
        #note - error checking for this happens below.

    } elsif ( $itemid ) {
        #Not $delete, but with an $itemid, means we're editing.
        # for now, don't do anything for edits - just return success and the 
        # existing ID - unless the security of the post has changed to non-pub.
        # FIXME: Shoudln't really call this a success, it's confusing. Need 
        #  a third return status???
       
        if( $entry->security eq 'public' ) {
            return {
                success => 1,
                reference => { itemid => $itemid }
            };
        }

        #The entry has been edited and the security changed so that it is no
        #longer public. We should delete the tweet.
        eval { $status = $twitter->destroy_status( $itemid ); };
        #note - error checking for this happens below.
        $delete = 1;

    } else {
        #No $itemid means this is a new post.

        # Don't post for non-public entries
        unless( $entry->security eq 'public' ) {
            return {
                success => 0,
                error => LJ::Lang::ml( 'xpost.error.nonpublic', {
                        service => 'Twitter' } ) };
            }

        my $tweettext = tweettext_from_entry( $self, $extacct, $entry );
        unless ( $tweettext ) {
            return {
                success => 0,
                error => "Error generating tweet text. Please try again later.
                If the problem persists, please contact Support."
            }
        }

        eval { $status = $twitter->update( $tweettext ); };
    }

    # Any of the operations above will have left either a non-empty $status 
    # (if successful) or a $@ (if not successful).
    if ( $status ) {
        #If we've deleted we want to avoid returning the id of the deleted
        # tweet.
        if ( $delete ) {
            return {
                success => 1,
                reference => {itemid => undef }
            }
        }
        return {
            success => 1,
            reference => { itemid => $status->{id_str} }
        }
    } else {
        my $err = _check_twitter_error( $@, $extacct );
        return {
            success => 0,
            error => $err,
        }
    }
}

sub tweettext_from_entry {
# Takes an extacct and an entry object. Returns the correct text to tweet about
# that entry. Returns undef on error (which is probably a difficulty getting
#  the url length from Twitter)
# Everything in here needs to be careful about using character lengths rather
# than byte lengths. Twitter supports unicode & it counts characters, not bytes.

    my ( $self, $extacct, $entry ) = @_;
    my $tweettext;  #output.

    #Find out how many characters the link takes up
    my $urllength = _t_co_urllength( $extacct );
    #If the urllength wasn't cached and couldn't be retrieved from twitter,
    # this will have returned undef.
    return undef unless $urllength;

    my $prefix = $extacct->options->{prefix_text};
    my $entry_subject = $entry->subject_text;

    #We don't want the byte lengths below; $bl and $bl1 are throwaways. We 
    # want the char lengths, which are the 2nd return value from text_length.
    my ( $bl, $subjlength ) = LJ::text_length( $entry_subject );
    my ( $bl1, $prefixlength ) = LJ::text_length( $prefix );

    #The -2 on the end of this is to allow for spaces after prefix & subject.
    my $maxsubjlength = 140 - $prefixlength - $urllength - 2;

    #If the prefix is so long that we can't fit at least 10 chars of subject,
    # omit the subject completely, as it would be silly. We *shouldn't* have
    # such a long prefix, unless twitter makes $urllength huge in the future,
    # but hey.
    if ( $maxsubjlength > 10 ) {

        #\N{U+2026} represents the Unicode elipsis (...) character.
        my $subjecttext = $subjlength > $maxsubjlength ?
            LJ::text_trim( $entry_subject, 0, ( $maxsubjlength - 1 )) . 
                "\N{U+2026}" :
            $entry_subject;

        $tweettext = $prefix . ' ' . $subjecttext . ' ' . $entry->url;

    } else {

        my $maxprefixlength = 140 - $urllength - 1;
        my $truncatedprefix = $prefixlength > $maxprefixlength ?
            LJ::text_trim( $prefix, 0, ( $maxprefixlength - 1 )) . 
                "\N{U+2026}" :
            $prefix;

        $tweettext = $truncatedprefix . ' ' . $entry->url;

    }

    return $tweettext;
}

sub _t_co_urllength {
# Takes an externalaccount object.
# Returns the number of characters that twitter considers a http URL to take
# up, as scalar.

# URLs on Twitter are automatically shortened using t.co, but the full URL
# is still shown to users. The number of characters that they are
# considered to take up is equal to the length of the hidden t.co shortened
# URL. This length changes (so far, increases) from time to time.

    #We only need the extacct because Twitter won't let you do *anything*
    #without authenticating at present.
    my $extacct = shift;
    LJ::throw( 'Need an extacct' ) unless $extacct;

    #First, see whether it's set manually
    return $LJ::TWITTER{t_co_urllength} 
        if defined $LJ::TWITTER{t_co_urllength};

    #If it hasn't been set manually and we're not using memcache, we have a 
    # problem.
    LJ::throw( 'If Memcache is not in use, t_co_urllength must be set in config-local.pl' ) 
        unless @LJ::MEMCACHE_SERVERS;

    #see whether Memcache already knows it.
    my $urllength = LJ::MemCache::get( 'twitter:t_co_urllength' );
    return $urllength if defined $urllength;

    #It seems that we don't know it at present. So find out from Twitter.
    my $twitter = _get_net_twitter( $extacct );
    my $config;
    eval { $config = $twitter->get_configuration; };
    $urllength = $config->{short_url_length};
    return undef unless $urllength;

    #save this to memcache for the next 2 days
    LJ::MemCache::set( 'twitter:t_co_urllength', $urllength, 48*60*60 );

    return $urllength;
}

sub public_posts_only {
# Only allow public entries to be sent to Twitter.
    return 1;
}

sub uses_oauth {
# Used by External::Account to determine whether this protocol uses oauth
    return 1;
}

1;
