#!/usr/bin/perl
#
# DW::Controller::Search::Multisearch
#
# Conversion of LJ's multisearch.bml, used for handling redirects
# from sitewide search bar (LJ::Widget::Search).
#
# Also includes handler for /tools/search which simply renders
# the search widget on a separate page.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2011-2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Search::Multisearch;

use strict;

use DW::Routing;
use DW::Template;
use DW::Controller;
use Locale::Codes::Country;

DW::Routing->register_string( '/multisearch', \&multisearch_handler, app => 1 );
DW::Routing->register_string( '/tools/search', \&toolsearch_handler, app => 1 );

sub multisearch_handler {
    my $r = DW::Request->get;
    my $args = $r->did_post ? $r->post_args : $r->get_args;

    my $type   = lc( $args->{'type'}   || '' );
    my $q      = lc( $args->{'q'}      || '' );
    my $output = lc( $args->{'output'} || '' );

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $tpl = 'multisearch.tt';

    # functions for handling various call types
    my ( $f_nav, $f_user, $f_int, $f_email, $f_im, $f_faq, $f_region );

    $f_nav = sub {
        # Some special shortcuts used for easy navigation
        return $r->redirect( "$LJ::SITEROOT/support/faqbrowse?faqid=$1&view=full" )
            if $q =~ /^faq (\d+)$/;
        return $r->redirect( "$LJ::SITEROOT/support/see_request?id=$2" )
            if $q =~ /^req(uest)? (\d+)$/;

        if ( $q =~ m!(.+)/(pics|full)! ) {
            if ( my $u = LJ::load_user_or_identity($1) ) {
                return $r->redirect( $u->profile_url( full => 1 ) )
                    if $2 eq "full";
                return $r->redirect( $u->allpics_base )
                    if $2 eq "pics";
            }
        }

	if ( $type eq "nav_and_user" ) {
	    if ( my $u = LJ::load_user_or_identity($q) ) {
                       return $r->redirect( $u->profile_url() );
	    }
	}

        my $eq = LJ::ehtml( $q );
        return error_ml( '/multisearch.tt.errorpage.nomatch.nav', { query => $eq } );

        return DW::Template->render_template( $tpl, $rv );

	};

    $f_user = sub {
        my $user = $q;
        $user =~ s!\@$LJ::USER_DOMAIN!!;
        $user =~ s!/(\w+)!!;
        my $what = defined $1 ? $1 : '';

        $user =~ s/-/_/g;
        $user =~ s/[^\w]//g;

        return $r->redirect( "$LJ::SITEROOT/random" ) unless $user;

        my $u = LJ::load_user( $user );
        return $r->redirect( "$LJ::SITEROOT/profile?user=$user" ) unless $u;

        return $r->redirect( $u->allpics_base ) if $what eq "pics";

        return $r->redirect( $u->journal_base . '/data/foaf' )
            if $output eq "foaf";

        my $url = $u->profile_url;
        $url .= "?mode=full" if $what eq 'full';
        return $r->redirect( $url );
    };

    $f_int = sub {
        return error_ml( '/multisearch.tt.errorpage.nointerest' ) unless $q;
        return $r->redirect( "$LJ::SITEROOT/interests?int=" . LJ::eurl( $q ) );
    };

    $f_email = sub {
        return error_ml( '/multisearch.tt.errorpage.noaddress' ) unless $q;

        my $dbr = LJ::get_db_reader();
        my $uid = $dbr->selectrow_array( qq{
            SELECT userid FROM user WHERE journaltype='P' AND statusvis='V'
            AND allow_contactshow='Y' AND email=? LIMIT 1 }, undef, $q );

        # if not in the user table, try the email table
        $uid ||= $dbr->selectrow_array( qq{
            SELECT e.userid FROM user u, email e WHERE e.email=?
            AND e.userid=u.userid AND u.journaltype='P' AND u.statusvis='V'
            AND u.allow_contactshow='Y' LIMIT 1 }, undef, $q );

        if ( my $u = LJ::load_userid( $uid ) ) {
            my $show = $u->opt_whatemailshow;
            if ( $show eq "A" || $show eq "B" ) {
                return $r->redirect( $u->journal_base . '/data/foaf' )
                    if $output eq "foaf";
                return $r->redirect( $u->profile_url );
            }
        }
        return error_ml( '/multisearch.tt.errorpage.nomatch' );
    };

    $f_im = sub {
        eval "use LJ::Directory::Constraint::ContactInfo;";
        return error_ml( 'error.tempdisabled' ) if $@;

        my $c = LJ::Directory::Constraint::ContactInfo->new( screenname => $q );
        my @uids = $c->matching_uids;

        if ( @uids == 1 ) {
            my $u = LJ::load_userid( $uids[0] );
            return $r->redirect( $u->journal_base . '/data/foaf' )
                if $output eq "foaf";
            return $r->redirect( $u->profile_url );

        } elsif ( @uids > 1 ) {
            $rv->{type} = 'im';

            my $us = [ values %{ LJ::load_userids( @uids ) } ];
            $rv->{results} = LJ::user_search_display(
                    users => $us, timesort => 1, perpage => 50 );

            return DW::Template->render_template( $tpl, $rv );
        }
        return error_ml( '/multisearch.tt.errorpage.nomatch' );
    };

    $f_region = sub {
        $q = LJ::trim( $q );
        my @parts = split /\s*,\s*/, $q;
        if ( @parts == 0 || @parts > 3 ) {
            $rv->{type} = 'region';
            return DW::Template->render_template( $tpl, $rv );
        }

        my $ctc = $parts[-1];
        my $country;
        if ( length( $ctc ) > 2 ) {
            # Must be country name
            $country = uc country2code( $ctc );
        } else {
            # Likely country code or invalid
            $country = uc country_code2code( $ctc, LOCALE_CODE_ALPHA_2,
                                             LOCALE_CODE_ALPHA_2 );
            $country ||= uc country2code( $ctc ); # 2-letter country name??
        }

        my ( $state, $city );

        if ( $country ) {
            pop @parts;
            if ( @parts == 1 ) {
                $state = $parts[0];
            } else {
                ( $city, $state ) = @parts;
            }

        } else {
            $country = "US";

            if ( @parts == 1 ) {
                $city = $parts[0];
            } else {
                ( $city, $state ) = @parts;
            }
        }

        ( $city, $state, $country ) = map { LJ::eurl($_) }
                                          ( $city, $state, $country );
        return $r->redirect( "$LJ::SITEROOT/directorysearch?s_loc=1" .
                             "&loc_cn=$country&loc_st=$state&loc_ci=$city" .
                             "&opt_sort=ut&opt_format=pics&opt_pagesize=50" );
    };

    $f_faq = sub {
        return error_ml( '/multisearch.tt.errorpage.nofaq' ) unless $q;
        return $r->redirect( "$LJ::SITEROOT/support/faqsearch?q=" . LJ::eurl( $q ) );
    };

    # set up dispatch table
    my $dispatch = { nav_and_user => $f_nav,
                     user         => $f_user,
                     int          => $f_int,
                     email        => $f_email,
                     im           => $f_im,
                     aolim        => $f_im,
                     icq          => $f_im,
                     yahoo        => $f_im,
                     jabber       => $f_im,
                     region       => $f_region,
                     faq          => $f_faq,
                   };

    return $dispatch->{$type}->() if exists $dispatch->{$type};

    # Unknown type, try running site hooks
    if ( $type ) {
        # TODO: check return value of this hook, and fall back to another hook
        # that shows the results here, rather than redirecting to another page
        return LJ::Hooks::run_hook( 'multisearch_custom_search_redirect',
                                    { type => $type, query => $q } );
    }

    # No type specified - redirect them somewhere useful.
    return $r->redirect( "$LJ::SITEROOT/tools/search" );
}

sub toolsearch_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    $rv->{widget} = LJ::Widget::Search->render;
    $rv->{sitename} = $LJ::SITENAMESHORT;
    return DW::Template->render_template( 'tools/search.tt', $rv );
}


1;
