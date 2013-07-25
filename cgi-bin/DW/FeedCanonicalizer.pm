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
require 'ljlib.pl';
use URI;
use URI::Escape;

my %LJISH_SITES = map { $_ => 1 } (
    'livejournal.com',
    'insanejournal.com',
    'deadjournal.com',
    'journalfen.net',
    'dreamwidth.org',
);

my $LJISH_URL_PART = "(data/(?:rss|atom)(?:_friends|\.xml|\.html)?|"
    . "data/customview|rss(?:/friends|/data|\.xml|\.html)?)(/.+?)?(.+?)?";

sub canonicalize {
    my $uri_string = $_[0];
    $uri_string = $uri_string->[0] if ref $uri_string eq 'ARRAY';

    my $uri = URI->new( $uri_string )->canonical;
    return undef unless $uri->scheme ~~ [ qw/ http https / ];
    
    $uri->userinfo( undef );

    my $feed = $_[1];
    my $src = $_[2];
    my $orig_uri = $uri->clone;

    $uri->fragment(undef);
    $uri->query(undef);

    my $uri_str = $uri->as_string;

    given ( $uri_str ) {
        # Let's see if this looks "LJ-ish".
        when( m!^https?://(?:users|community|syndicated)\.([^/]+)/+([a-z0-9\-_]+)/$LJISH_URL_PART$!i ) {
            my ( $host, $sub, $feed, $extra, $spare ) = ( $1, $2, $3, $4, $5 );
            continue if $feed ~~ m/^rss/i && ! $LJISH_SITES{$host};
            continue if $spare && ! $LJISH_SITES{$host};
            return make_ljish( $host, $sub, $feed, $orig_uri, $extra );
        }

        when( m!^https?://([a-z0-9\-_]+)\.([^/]+)/+$LJISH_URL_PART$!i ) {
            my ( $sub, $host, $feed, $extra, $spare ) = ( $1, $2, $3, $4, $5 );
            continue if $sub eq 'www';
            continue if $feed ~~ m/^rss/i && ! $LJISH_SITES{$host};
            continue if $spare && ! $LJISH_SITES{$host};
            return make_ljish( $host, $sub, $feed, $orig_uri, $extra );
        }
        
        when( m!^https?://(?:www\.)?([^/]+)/+~([a-z0-9\-_]+)/$LJISH_URL_PART!i ) {
            my ( $host, $sub, $feed, $extra, $spare ) = ( $1, $2, $3, $4, $5 ); 
            continue if $feed ~~ m/^rss/i && ! $LJISH_SITES{$host};
            continue if $spare && ! $LJISH_SITES{$host};
            return make_ljish( $host, $sub, $feed, $orig_uri, $extra );
        }
        
        when( m!^https?://(?:www\.)?([^/]+)/+(?:users|community|syndicated)/([a-z0-9\-_]+)/$LJISH_URL_PART$!i ) {
            my ( $host, $sub, $feed, $extra, $spare ) = ( $1, $2, $3, $4, $5 );
            continue if $feed ~~ m/^rss/i && ! $LJISH_SITES{$host};
            continue if $spare && ! $LJISH_SITES{$host};
            return make_ljish( $host, $sub, $feed, $orig_uri, $extra );
        }

        # InsaneJournal decided to call communities something different
        when( m!^https?://(?:asylums)\.insanejournal\.com/+([a-z0-9\-_]+)/$LJISH_URL_PART$!i ) {
            return make_ljish( "insanejournal.com", $1, $2, $orig_uri, $3 );
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

        # Also handles blogspot and domains hosted on blogger/blogspot
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

        # Unfortunately, these two twitter ones cannot go away (yet)
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

        # twfeed.com replacement feed service
        when ( m!^https?://(?:www\.)twfeed\.com/+(?:rss|atom)/([a-z][a-z0-9\-_]*)$!i ) {
            my $username = lc($1);
            $username =~ s/-/_/g;

            return "twitter://$username";
        }

        when ( m!^https?://blog\.myspace\.com/+([a-z][a-z0-9\-_]*)/?!i && $src eq 'link' ) {
            my $username = lc($1);
            $username =~ s/-/_/g;

            return "myspace://$username";
        }
    
        when ( m!^https?://(?:www\.)?archiveofourown\.org/tags/([0-9]+)/feed\.(?:atom|rss)/?!i ) {
            return "ao3://tag/$1";
        }

        when ( m!^https?://feeds\.pinboard\.in/rss(?:/secret:[a-f0-9]+)?((?:/[a-z]:[^/]+?)+)(?:/public)?/?$! ) {
            my @parts = split('/', $1);
            my $url_end;
            foreach my $part ( @parts ) {
                if ( $part =~ m!^[ut]:!i ) {
                    $url_end .= "/" . lc($part);
                }
            }
            continue unless $url_end;
            return "pinboard:/" . $url_end;
        }
        
        when ( m!^https?://feeds\.pinboard\.in/rss/popular(/[^/]+)?/?$!i ) {
            return "pinboard://popular$1";
        }

        when ( m!^https?://gdata\.youtube\.com/feeds/base/users/([a-z0-9]+)/uploads/?$!i ) {
            return "youtube://users/$1/uploads";
        }
        
        when ( m!^https?://gdata\.youtube\.com/feeds/(?:api|base)/videos/-/(.+?)/?$!i ) {
            my $rv = join( '/', sort(
                map { join('|', sort( split(/\|/,$_ ) ) ) } # sort |'d together terms
                grep { $_ } split('/',$1) ) );
            return "youtube://videos/$rv";
        }

        when ( m!^https?://([a-z0-9_-]+)\.typepad\.com/+([^/]+)/(?:atom|rss)\.xml$!i ) {
            return "typepad://$1/$2";
        }
    }
    my $rv = undef;

    return undef unless defined $feed;

    $rv = canonicalize( $feed->{self}, undef, 'self' ) if ! defined $rv && $feed->{self};
    $rv = canonicalize( $feed->{link}, undef, 'link' ) if ! defined $rv && $feed->{link};
    $rv = canonicalize_id( $feed->{'atom:id'}, $uri, $orig_uri ) if ! defined $rv && $feed->{'atom:id'}; 
    $rv = canonicalize_id( $feed->{id}, $uri, $orig_uri ) if ! defined $rv && $feed->{id};

    $rv = canonicalize( $feed->{final_url}, undef, 'final_url' ) if ! defined $rv && $feed->{final_url};
    $rv = last_ditch( ( map { $feed->{$_} } qw( self final_url ) ) , $orig_uri->as_string ) if ! defined $rv;

    return $rv;
}

sub canonicalize_id {
    my ( $id, $uri, $orig_uri ) = @_;

    my $uri_str = $uri->as_string;
    given ( $id ) {
        when ( m!^tag:blogger\.com,1999:blog-([0-9]+)(\.comments)?$!i ) {
            my $url_bit = "blogger://$1/" . ( $2 eq '.comments' ? 'comments' : 'posts' );
            my ( $full ) = $uri_str =~ m!/(default|full)/?$!i;
            return $url_bit . ( $full eq 'full' ? '/full' : '' );
        }
        
        when ( m!^tag:blogger\.com,1999:blog-([0-9]+)\.post([0-9]+)\.\.comments$!i ) {
            my $url_bit = "blogger://$1/$2/comments";
            my ( $full ) = $uri_str =~ m!/(default|full)/?$!i;
            return $url_bit . ( $full eq 'full' ? '/full' : '' );
        }
    }
}

sub last_ditch {
    my @args = @_;
    foreach my $arg ( @args ) {
        next unless $arg;
        $arg = $arg->[0] if ref $arg eq 'ARRAY';

        my $uri = URI->new( $arg )->canonical;
        next unless $uri->scheme ~~ [ qw/ http https / ];

        $uri->fragment(undef);
        $uri->userinfo(undef);

        my $str = $uri->as_string;
        $str =~ s/^https?/last_ditch/;
        return $str;
    }
    return undef;
}

# Helpers

sub make_ljish {
    my ( $domain, $username, $feed, $uri, $extra_raw ) = @_;

    $username = lc($username);
    $username =~ s/-/_/g;

    my $extra = "";
    if ( $feed ~~ m/customview$/i ) {
        $extra = $extra_raw if $extra_raw ~~ m!^/!;
        return LJ::create_url("/$username/customview$extra",
            proto => "ljish",
            host => $domain,
            cur_args => { $uri->query_form },
            keep_args => [ qw/ styleid show filter / ] );
    } else {
        my $extra;
        $extra = "/friends" if $feed ~~ /friends$/;

        my %query = $uri->query_form;

        if ( $query{tag} ) {
            return "ljish://$domain/$username$extra?tag=" . uri_escape( $query{tag} );
        }

        return "ljish://$domain/$username$extra";
    }
}

1;
