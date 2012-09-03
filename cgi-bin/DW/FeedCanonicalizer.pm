#!/usr/bin/perl
#
# DW::FeedCanonicalizer
#
# One-way canonicalize feed URL names into an "opaque representation"
#  for feed deduplication suggestions.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
package DW::FeedCanonicalizer;
use strict;
use 5.010;
use URI;
use URI::Escape;

my %LJISH_SITES = map { $_ => 1 } (
    'livejournal.com',
    'insanejournal.com',
    'deadjournal.com',
    'journalfen.net',
    'dreamwidth.org',
);

sub canonicalize {
    my $uri_string = $_[0];
    $uri_string = $uri_string->[0] if ref $uri_string eq 'ARRAY';

    my $uri = URI->new( $uri_string )->canonical;
    my $feed = $_[1];
    my $src = $_[2];
    my $orig_uri = $uri->clone;

    $uri->fragment(undef);
    $uri->query(undef);

    my $uri_str = $uri->as_string;

    say $uri_str;

    given ( $uri_str ) {
        # Let's see if this looks "LJ-ish".
        when( m!^https?://([a-z0-9\-_]+)\.([^/]+)/+(data/(?:rss|atom)|rss)$!i ) {
            continue if $1 eq 'www';
            continue if $3 eq 'rss' && ! $LJISH_SITES{$2};
            return make_ljish( $2, $1, $orig_uri );
        }
        
        when( m!^https?://(?:user|community)\.([^/]+)/+([a-z0-9\-_]+)/(data/(?:rss|atom)|rss)$!i ) {
            continue if $3 eq 'rss' && ! $LJISH_SITES{$1};
            return make_ljish( $1, $2, $orig_uri );
        }
        
        when( m!^https?://(?:www\.)?([^/]+)/+~([a-z0-9\-_]+)/(data/(?:rss|atom)|rss)$!i ) {
            continue if $3 eq 'rss' && ! $LJISH_SITES{$1};
            return make_ljish( $1, $2, $orig_uri );
        }

        # InsaneJournal decided to call communities something different
        when( m!^https?://(?:asylums)\.insanejournal\.com/+([a-z0-9\-_]+)/(?:data(?:rss|atom)|rss)$!i ) {
            return make_ljish( "insanejournal.com", $1, $orig_uri );
        }

        when( m!^https?://([a-z0-9\-\_]+)\.tumblr\.com/+rss(?:/|\.xml)?$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;
            return "tumblr://$username";
        }
        
        when( m!^https?://([a-z0-9\-\_]+)\.tumblr\.com/+tagged/([^/\?#]+)/rss(?:/|\.xml)?$!i ) {
            my $tag = uri_escape( uri_unescape( $2 ) );
            my $username = lc($1);
            $username =~ s/-/_/g;
            return "tumblr://$username/tagged/$tag";
        }
       
        when ( m!^https?://(?:www\.)?blogger\.com/+feeds/([0-9]+)/(posts|comments|[0-9]+/comments)/(default|full)/?$!i ) {
            return "blogger://$1/$2" . ( $3 eq 'full' ? '/full' : '' );
        }
        
        when ( m!^https?://(?:www\.)?blogger\.com/+feeds/([0-9]+)/posts/(default|full)/?$!i ) {
            return "blogger://$1/posts" . ( $2 eq 'full' ? '/full' : '' );
        }

        when ( m!^https?://feeds[0-9]*\.feedburner\.com/+(.+)$!i ) {
            return "feedburner://$1";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/*$!i ) {
            my %query = $orig_uri->query_form;

            continue unless $query{feed} ~~ ['rss', 'atom'];

            my $username = lc($1);
            $username =~ s/-/_/g;
            return "wordpress://$username";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+(?:rss|atom).xml$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;
            return "wordpress://$username";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+(?:rss|atom)/?$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;
            return "wordpress://$username";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+feed(?:/rss|/atom)?/?$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;
            return "wordpress://$username";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+comments/feed(?:/rss|/atom)?/?$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;
            return "wordpress://$username/comments";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+tag/([a-z0-9\-\_]+)/feed(?:/rss|/atom)?/?$!i ) {
            my $username = lc($1);
            my $tag = lc($2);

            $username =~ s/-/_/g;
            $tag =~ s/-/_/g;

            return "wordpress://$username/tag/$tag";
        }


        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+category/([a-z0-9\-\_]+)/feed(?:/rss|/atom)?/?$!i ) {
            my $username = lc($1);
            my $category = lc($2);

            $username =~ s/-/_/g;
            $category =~ s/-/_/g;

            return "wordpress://$username/category/$category";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+author/([a-z0-9\-\_]+)/feed(?:/rss|/atom)?/?$!i ) {
            my $username = lc($1);
            my $author = lc($2);

            $username =~ s/-/_/g;
            $author =~ s/-/_/g;

            return "wordpress://$username/author/$author";
        }

        when ( m!^https?://([a-z0-9\-\_\.]+)\.wordpress\.com/+([0-9]{4}/[0-9]{2}/[0-9]{2})/([a-z0-9\-\_]+)/feed(?:/rss|/atom)?/?$!i ) {
            my $username = lc($1);
            my $datepart = $2;
            my $article = lc($3);

            $username =~ s/-/_/g;
            $article =~ s/-/_/g;

            return "wordpress://$username/$datepart/$article";
        }

        when ( m!^https?://(?:www\.)?twitter\.com/+([a-z][a-z0-9\-_]*)/?$!i && $src eq 'link' ) {
            my $username = lc($1);
            $username =~ s/-/_/g;

            return "twitter://$username";
        }
        
        when ( m!^https?://(?:www\.)?twitter\.com/+statuses/user_timeline/([a-z][a-z0-9\-_]*)\.rss$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;

            return "twitter://$username";
        }

        when ( m!^https?://api\.twitter\.com/1/statuses/user_timeline\.rss$!i ) {
            my %query = $orig_uri->query_form;

            continue if $query{id};

            my $username = lc( $query{screen_name} );
            continue if $username =~ m/,/;
            continue unless $username;

            $username =~ s/-/_/g;

            return "twitter://$username";
        }

        when ( m!^https?://(?:www\.)?twitter\.com/+([a-z][a-z0-9\-_]*)/favorites/?$!i && $src eq 'link' ) {
            my $username = lc($1);
            $username =~ s/-/_/g;

            return "twitter://$username/favorites";
        }

        when ( m!^https?://(?:www\.)?twitter\.com/+favorites/([a-z][a-z0-9\-_]*)\.rss$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;

            return "twitter://$username/favorites";
        }
        
        when ( m!^https?://blog\.myspace\.com/+([a-z][a-z0-9\-_]*)/?!i && $src eq 'link' ) {
            my $username = lc($1);
            $username =~ s/-/_/g;

            return "myspace://$username";
        }
    }
    return undef unless $feed;

    my $rv = undef;
    $rv = canonicalize( $feed->{self}, undef, 'self' ) if ! defined $rv && $feed->{self};
    $rv = canonicalize( $feed->{link}, undef, 'link' ) if ! defined $rv && $feed->{link};

    return $rv;
}

sub make_ljish {
    my ( $domain, $username, $uri ) = @_;

    $username = lc($username);
    $username =~ s/-/_/g;

    my %query = $uri->query_form;

    if ( $query{tag} ) {
        return "ljish://$domain/$username?tag=" . uri_escape( $query{tag} );
    }

    return "ljish://$domain/$username";
}

1;
