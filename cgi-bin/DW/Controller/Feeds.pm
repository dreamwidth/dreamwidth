#!/usr/bin/perl
#
# DW::Controller::Feeds
#
# Pages for creating and listing syndicated feeds from other sites.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Feeds;

use strict;
use warnings;

use LJ::Feed;
use LJ::SynSuck;
use HTTP::Message;
use URI;

use DW::Routing;
use DW::Template;
use DW::Controller;

DW::Routing->register_string( '/feeds/index', \&index_handler, app => 1 );
DW::Routing->register_string( '/feeds/list',  \&list_handler,  app => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    return error_ml('error.suspended.text') if $remote->is_suspended;

    my $r         = DW::Request->get;
    my $did_post  = $r->did_post;
    my $post_args = $r->post_args;
    my $get_args  = $r->get_args;

    return error_ml('/feeds/index.tt.user.nomatch')
        if $did_post && $post_args->{userid} != $remote->id;

    # see if the user is trying to create a new feed

    if ( $post_args->{'action:addcustom'} || $get_args->{url} ) {
        my $acct = LJ::trim( $post_args->{acct} );
        my $url  = LJ::trim( $post_args->{synurl} || $get_args->{url} );
        $url =~ s!^feed://!http://!;    # eg, feed://www.example.com/
        $url =~ s/^feed://;             # eg, feed:http://www.example.com/

        if ( $acct ne "" ) {
            $acct = LJ::canonical_username($acct);

            # Name length needs to be 5 less then the username limit.
            return error_ml('/feeds/index.tt.invalid.accountname')
                unless $acct && $acct =~ /^\w{3,20}$/;

            return error_ml('/feeds/index.tt.invalid.reserved')
                if LJ::User->is_protected_username($acct);

            # Postpend _feed here, username should be valid by this point.
            $acct .= "_feed";
        }

        if ( $url ne "" ) {
            my $uri = URI->new($url);
            return error_ml('/feeds/index.tt.invalid.url')
                unless $uri->scheme && $uri->scheme =~ m/^https?$/ && $uri->host;

            my $hostname = $uri->host;
            my $port     = $uri->port;

            return error_ml('/feeds/index.tt.invalid.cantadd')
                if $hostname =~ /\Q$LJ::DOMAIN\E/i;

            return error_ml('/feeds/index.tt.invalid.port')
                if defined $port && $port != $uri->default_port && $port < 1024;

            if ( $uri->userinfo ) {
                $uri->userinfo(undef);
                return $r->redirect(
                    LJ::create_url(
                        "/feeds", args => { url => $uri->canonical, had_credentials => 1 }
                    )
                );
            }

            $url = $uri->canonical;
        }

        my $su;    # account to add (database row, not user object)

        if ($url) {

            $su = LJ::Feed::synrow_select( url => $url );

            unless ($su) {

                # check cap to create new feeds
                return error_ml('/feeds/index.tt.error.nocreate')
                    unless $remote->can_create_feeds;

                # if no account name, give them a proper entry form to pick one, but don't reprompt
                # for the url, just pass that through (we'll recheck it anyway, though)
                unless ($acct) {
                    $rv->{synurl}          = $url;
                    $rv->{had_credentials} = $get_args->{had_credentials};
                    return DW::Template->render_template( 'feeds/name.tt', $rv );
                }

                # create a safeagent to fetch the feed for validation purposes
                my $max_size = LJ::SynSuck::max_size();
                my $ua       = LJ::get_useragent(
                    role     => 'syn_new',
                    max_size => $max_size
                );
                $ua->agent("$LJ::SITENAME ($LJ::ADMIN_EMAIL; Initial check)");

                my $can_accept = HTTP::Message::decodable;
                my $res        = $ua->get( $url, 'Accept-Encoding' => $can_accept );
                my $content =
                      $res && $res->is_success
                    ? $res->decoded_content( charset => 'none' )
                    : undef;

                unless ($content) {
                    return error_ml( '/feeds/index.tt.invalid.toolarge',
                        { max => ( $max_size / 1024 ) } )
                        if $res && $res->is_success;
                    return DW::Template->render_template( 'error.tt',
                        { message => $res->status_line } )
                        if $remote->show_raw_errors;
                    return error_ml('/feeds/index.tt.invalid.http.text');
                }

                # Start out with the syn_url being equal to the url
                # they entered for the resource. If we end up parsing
                # the resource and finding it has a link to the real
                # feed, we then want to save the real feed address to use.

                my $syn_url = $url;

                # analyze link/meta tags
                while ( $content =~ m!<(link|meta)\b([^>]+)>!g ) {
                    my ( $type, $val ) = ( $1, $2 );

       # RSS/Atom
       # <link rel="alternate" type="application/(?:rss|atom)+xml" title="RSS" href="http://...." />
       # FIXME: deal with relative paths (eg, href="blah.rss") ... right now we need the full URI
                    if (   $type eq "link"
                        && $val =~ m!rel=.alternate.!i
                        && $val =~ m!type=.application/(?:rss|atom)\+xml.!i
                        && $val =~ m!href=[\"\'](https?://[^\"\']+)[\"\']!i )
                    {
                        $syn_url = $1;
                        last;
                    }
                }

                # Did we find a link to the real feed? If so, grab it.

                if ( $syn_url ne $url ) {
                    my $adu = LJ::Feed::synrow_select( url => $syn_url );

                    return $r->redirect(
                        LJ::create_url(
                            "/circle/$adu->{user}/edit", args => { action => 'subscribe' }
                        )
                    ) if $adu;

                    $res     = $ua->get($syn_url);
                    $content = $res && $res->is_success ? $res->content : "";
                }

                # check whatever we did get for validity (or pseudo-validity)
                # Must have a <[?:]rss <[?:]feed (for Atom support) <[?:]RDF
                return error_ml('/feeds/index.tt.invalid.notrss.text')
                    unless $content =~ m/<(\w+:)?(?:rss|feed|RDF)/;

                # before we try to create the account, make
                # sure that the name is not already in use
                if ( my $u = LJ::load_user($acct) ) {
                    return error_ml( '/feeds/index.tt.invalid.inuse.text2',
                        { user => $u->ljuser_display } );
                }

                # create the feed account
                my $synfeed = LJ::User->create_syndicated(
                    user    => $acct,
                    feedurl => $syn_url
                );

                # we made sure the name was OK, not sure why we failed
                return error_ml('/feeds/index.tt.error.unknown')
                    unless $synfeed;

                $su = LJ::Feed::synrow_select( userid => $synfeed->id );
            }

        }
        elsif ($acct) {

            # account but no URL, we can add this in any case
            $su = LJ::Feed::synrow_select( user => $acct );
            return error_ml('/feeds/index.tt.invalid.notexist') unless $su;

        }
        else {
            # need at least a URL
            return error_ml('/feeds/index.tt.invalid.needurl');
        }

        return error_ml('/feeds/index.tt.error.unknown') unless $su;

        # at this point, we have a new account, or an old account, but we have
        # an account, so let's redirect them to the subscribe page
        return $r->redirect(
            LJ::create_url( "/circle/$su->{user}/edit", args => { action => 'subscribe' } ) );
    }

    # finished trying to create a feed - still some form processing
    # below if the user wanted to add a popular feed from the list

    # load user's watch list so we can strip feeds they already watch
    my %watched = map { $_ => 1 } $remote->watched_userids;

    # get most popular feeds from memcache (limit 100)
    my $popsyn = LJ::Feed::get_popular_feeds();
    my @pop;

    # populate @pop and subscribe to any popular feeds they've chosen
    for ( 0 .. 99 ) {
        next unless defined $popsyn->[$_];
        my ( $user, $name, $suserid, $url, $count ) = @{ $popsyn->[$_] };

        my $suser = LJ::load_userid($suserid) or next;

        # skip suspended/deleted accounts & already watched feeds
        next if $watched{$suserid} || !$suser->is_visible;

        if ( $post_args->{'action:add'} && $post_args->{"add_$user"} ) {
            $remote->add_edge( $suser, watch => {} );
            $remote->add_to_default_filters($suser);
        }
        else {
            # @pop only holds the top 20 unsubscribed feeds
            push @pop,
                {
                user  => $user,
                url   => $url,
                count => $count,
                u     => $suser,
                name  => $name
                };
            last if @pop >= 20;
        }
    }

    # if we got to this point, we need to render the index template

    $rv->{poplist} = \@pop if @pop;
    $rv->{xmlimg}  = LJ::img( 'xml', '', { border => 0 } );

    return DW::Template->render_template( 'feeds/index.tt', $rv );
}

sub list_handler {
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 0 );
    return $rv unless $ok;

    my $r    = DW::Request->get;
    my $args = $r->get_args;       # no posting

    my $popsyn = LJ::Feed::get_popular_feeds();
    my @data;

    foreach (@$popsyn) {
        my ( $user, $name, $userid, $url, $count ) = @$_;
        push @data,
            {
            user       => $user,
            name       => $name,
            numreaders => $count,
            synurl     => $url
            };
    }

    return error_ml('/feeds/list.tt.error.nofeeds') unless @data;

    # $popsyn already defaults to "numreaders" sort
    my $sort = $args->{sort} || 'numreaders';

    if ( $sort eq "username" ) {
        @data = sort { $a->{user} cmp $b->{user} } @data;
    }
    elsif ( $sort eq "feeddesc" ) {
        @data = sort { $a->{name} cmp $b->{name} } @data;
    }

    # pagination
    my $curpage = $args->{page} || 1;
    my %items   = LJ::paging( \@data, $curpage, 100 );

    $rv->{sort} = $sort;
    $rv->{data} = $items{items};    # subset of accounts to display on this page
    $rv->{navbar} = LJ::paging_bar( $items{page}, $items{pages} );
    $rv->{resort} = sub { LJ::page_change_getargs( sort => $_[0] ) };
    $rv->{ljuser} = sub { LJ::ljuser( $_[0], { type => 'Y' } ) };
    $rv->{xmlimg} = LJ::img(
        'xml', '',
        {
            align  => 'middle',
            border => 0,
            alt    => LJ::Lang::ml('/feeds/list.tt.xml_icon.alt')
        }
    );

    return DW::Template->render_template( 'feeds/list.tt', $rv );
}

1;
