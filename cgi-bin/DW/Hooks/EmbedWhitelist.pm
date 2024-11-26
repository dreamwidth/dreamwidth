#!/usr/bin/perl
#
# This code was based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# DW::Hooks::EmbedWhitelist
#
# Keep a whitelist of trusted sites which we trust for certain kinds of embeds
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.

package DW::Hooks::EmbedWhitelist;

use strict;
use LJ::Hooks;
use URI;

# for internal use only
# this is used when sites may offer embeds from multiple subdomain
# e.g., www, www1, etc
sub match_subdomain {
    my $want_domain     = $_[0];
    my $domain_from_uri = $_[1];

    return $domain_from_uri =~ /^(?:[\w.-]*\.)?\Q$want_domain\E$/;
}

sub match_full_path {
    my $want_path     = $_[0];
    my $path_from_uri = $_[1];

    return $path_from_uri =~ /^$want_path$/;
}

my %host_path_match = (

    # regex, whether this supports https or not
    "www.4shared.com" => [ qr!^/web/embed/file/!, 1 ],
    "8tracks.com"     => [ qr!^/mixes/!,          0 ],

    "airtable.com"  => [ qr!^/embed/!, 1 ],
    "archive.org"   => [ qr!^/embed/!, 1 ],
    "audiomack.com" => [ qr!^/embed/!, 1 ],

    "bandcamp.com"                => [ qr!^/EmbeddedPlayer/!, 1 ],
    "player.bilibili.com"         => [ qr!^/player.html$!,    1 ],
    "blip.tv"                     => [ qr!^/play/!,           1 ],
    "percolate.blogtalkradio.com" => [ qr!^/offsiteplayer$!,  1 ],
    "app.box.com"                 => [ qr!^/embed/s/!,        1 ],

    "chirb.it"                => [ qr!^/wp/!,             1 ],
    "codepen.io"              => [ qr!^/enxaneta/embed/!, 1 ],
    "coub.com"                => [ qr!^/embed/!,          1 ],
    "criticalcommons.org"     => [ qr!^/embed$!,          1 ],
    "www.criticalcommons.org" => [ qr!/embed_view$!,      0 ],

    "www.dailymotion.com" => [ qr!^/embed/video/!,                   1 ],
    "diode.zone"          => [ qr!^/videos/embed/[0-9a-fA-F\-]{36}!, 1 ],
    "dotsub.com"          => [ qr!^/media/!,                         1 ],
    "discordapp.com"      => [ qr!^/widget$!,                        1 ],

    "episodecalendar.com" => [ qr!^/icalendar/!, 0 ],

    "www.flickr.com"     => [ qr!/player/$!, 1 ],
    "www.funnyordie.com" => [ qr!/embed/!,   1 ],

    "getyarn.io"        => [ qr!^/yarn-clip/embed/[0-9a-fA-F\-]{36}!, 1 ],
    "www.goodreads.com" => [ qr!^/widgets/!,                          1 ],
    "giphy.com"         => [ qr!^/embed/\w+!,                         1 ],

    "maps.google.com"     => [ qr!^/maps!,                   1 ],
    "www.google.com"      => [ qr!^/(calendar/|maps/embed)!, 1 ],
    "calendar.google.com" => [ qr!^/calendar/!,              1 ],

    # drawings do not need to be whitelisted as they are images.
    # forms arent being allowed for security concerns.
    "docs.google.com"        => [ qr!^/(document|spreadsheets?|presentation)/!, 1 ],
    "books.google.com"       => [ qr!^/ngrams/!,                                1 ],
    "drive.google.com"       => [ qr!^/file/d/[a-zA-Z0-9]+/preview$!,           1 ],
    "player.gimletmedia.com" => [ qr!^/\w+$!,                                   1 ],

    "imgur.com"     => [ qr!^/a/.+?/embed!,     1 ],
    "instagram.com" => [ qr!^/p/.*/embed/$!,    1 ],
    "www.imdb.com"  => [ qr!^/videoembed/\w+$!, 0 ],

    "jsfiddle.net" => [ qr!/embedded/$!, 1 ],

    "www.kickstarter.com" => [ qr!/widget/[a-zA-Z]+\.html$!, 1 ],

    "html5-player.libsyn.com" => [ qr!^/embed/!,          1 ],
    "lichess.org"             => [ qr!/study/embed/!,     1 ],
    "www.loc.gov"             => [ qr!/item/[a-z0-9]+/$!, 1 ],

    "makertube.net"    => [ qr!^/videos/embed/[0-9a-fA-F\-]{36}!, 1 ],
    "mega.nz"          => [ qr!^/embed/!,                         1 ],
    "www.mixcloud.com" => [ qr!^/widget/iframe/$!,                1 ],
    "mixstep.co"       => [ qr!^/embed/!,                         1 ],
    "www.msnbc.com"    => [ qr!^/msnbc/embedded-video/\w+!,       1 ],
    "my.mail.ru"       => [ qr!^/video/embed/\d+!,                1 ],

    "nekocap.com"      => [ qr!^/view/[a-zA-Z0-9]+$!,                 1 ],
    "ext.nicovideo.jp" => [ qr!^/thumb/!,                             0 ],
    "noisetrade.com"   => [ qr!^/service/widgetv2/!,                  1 ],
    "www.npr.org"      => [ qr!^/templates/event/embeddedVideo\.php!, 1 ],

    "onedrive.live.com" => [ qr!^/embed$!, 1 ],

    "player.pbs.org" => [ qr!^/viralplayer/[0-9]+!,      1 ],
    "playmoss.com"   => [ qr!^/embed/!,                  1 ],
    "www.plurk.com"  => [ qr!^/getWidget$!,              1 ],
    "pastebin.com"   => [ qr!^/embed_iframe/\w+$!,       1 ],
    "podomatic.com"  => [ qr!^/embed/html5/episode/\d*!, 1 ],

    "www.random.org"       => [ qr!^/widgets/integers/iframe.php$!,        1 ],
    "www.redditmedia.com"  => [ qr!^/r/\w+/comments/\w+/\w+/$!,            1 ],
    "www.reverbnation.com" => [ qr!^/widget_code/html_widget/artist_\d+$!, 1 ],
    "rumble.com"           => [ qr!^/embed/[a-zA-Z0-9]+/$!,                1 ],
    "rutube.ru"            => [ qr!^/play/embed/[0-9]+$!,                  1 ],

    "www.sbs.com.au" => [ qr!/player/embed/!, 0 ]
    ,    # best guess; language parameter before /player may vary
    "scratch.mit.edu"    => [ qr!^/projects/embed/!,           1 ],
    "www.scribd.com"     => [ qr!^/embeds/!,                   1 ],
    "www.slideshare.net" => [ qr!^/slideshow/embed_code/!,     1 ],
    "api.smugmug.com"    => [ qr!^/services/embed/\w+$!,       1 ],
    "w.soundcloud.com"   => [ qr!^/player/!,                   1 ],
    "embed.spotify.com"  => [ qr!^/$!,                         1 ],
    "open.spotify.com"   => [ qr!^/($)|(embed/[/\w]+)!,        1 ],
    "www.strava.com"     => [ qr!^/activities/\d+/embed/\w+$!, 1 ],
    "streamable.com"     => [ qr!^/[eos]/!,                    1 ],

    "embed.ted.com" => [ qr!^/talks/!, 1 ],

    "vid.me"           => [ qr!^/e/!,                              1 ],
    "player.vimeo.com" => [ qr!^/video/\d+$!,                      1 ],
    "vine.co"          => [ qr!^/v/[a-zA-Z0-9]{11}/embed/simple$!, 1 ],

    # Videos seemed to use an 11-character identification; may need to be changed
    "vk.com" => [ qr!^/video_ext\.php$!, 1 ],

    "fast.wistia.com" => [ qr!^/embed/iframe/\w+$!, 1 ],

    "video.yandex.ru" => [ qr!^/iframe/[\-\w]+/[a-z0-9]+\.\d{4}/?$!, 1 ]
    ,    #don't think the last part can include caps; amend if necessary

    "www.zippcast.com" => [ qr!^/videoview\.php$!, 0 ],

);

# note: these hash keys are for reference, only the value is checked
my %complex_match = (
    "youtube.com" => sub {

        ## YouTube (http://apiblog.youtube.com/2010/07/new-way-to-embed-youtube-videos.html)
        if (   match_subdomain( "youtube.com", $_[0]->host )
            || match_subdomain( "youtube-nocookie.com", $_[0]->host ) )
        {
            return ( 1, 1 ) if match_full_path( qr!/embed/[-_a-zA-Z0-9]{11,}!, $_[0]->path );
        }
    },

    "commons.wikimedia.org" => sub {
        if ( $_[0]->host eq "commons.wikimedia.org" ) {
            return ( 1, 1 )
                if $_[0]->path =~ m!^/wiki/File:! && $_[0]->query =~ m/embedplayer=yes/;
        }
    },

    "turner.com" => sub {
        if ( $_[0]->host eq "i.cdn.turner.com" ) {
            return ( 1, 1 )
                if $_[0]->path =~ '/cnn_\d+x\d+_embed.swf$'
                && $_[0]->query =~ m/^context=embed&videoId=/;
        }
    },

    "player.theplatform.com" => sub {
        if ( $_[0]->host eq "player.theplatform.com" ) {
            return ( 1, 1 )
                if $_[0]->path =~ 'MSNBCEmbeddedOffSite' && $_[0]->query =~ m/^guid=/;
        }
    },

    "www.facebook.com" => sub {
        if ( $_[0]->host eq "www.facebook.com" ) {
            return ( 1, 1 )
                if $_[0]->path eq '/plugins/video.php'
                && $_[0]->query =~
                m/^(height=\d+&)?href=https%3A%2F%2Fwww.facebook.com%2F[^%]+%2Fvideos%2F/;
        }

    },

    "www.jigsawplanet.com" => sub {
        if ( $_[0]->host eq "www.jigsawplanet.com" ) {
            return ( 1, 1 ) if $_[0]->query =~ m/rc=play/;
        }
    },

    "screen.yahoo.com" => sub {
        if ( $_[0]->host eq "screen.yahoo.com" ) {
            return ( 1, 1 ) if $_[0]->query =~ m/format=embed/;
        }
    },

    "livejournal.com" => sub {
        if ( match_subdomain( "livejournal.com", $_[0]->host ) ) {
            return ( 1, 1 )
                if match_full_path( qr!/\d+\.html!, $_[0]->path ) && $_[0]->query =~ m/embed/;
        }
    },

    "music.yandex.ru" => sub {
        if ( $_[0]->host eq "music.yandex.ru" ) {
            return ( 1, 1 ) if $_[0]->fragment =~ m!track/\d+/\d+!;
        }
    },

    "player.twitch.tv" => sub {
        if ( $_[0]->host eq "player.twitch.tv" ) {
            return ( 1, 1 ) if $_[0]->query =~ m/video=v\d+/;
        }
    },
);

LJ::Hooks::register_hook(
    'allow_iframe_embeds',
    sub {
        my ( $embed_url, %opts ) = @_;

        return 0 unless $embed_url;

        # the URI module hates network-relative URIs, eg '//youtube.com'
        if ( substr( $embed_url, 0, 2 ) eq '//' ) {
            $embed_url = 'http:' . $embed_url;
        }

        my $parsed_uri = URI->new($embed_url);

        my $uri_scheme = $parsed_uri->scheme;
        return 0 unless $uri_scheme eq "http" || $uri_scheme eq "https";

        my $uri_host = $parsed_uri->host;
        my $uri_path = $parsed_uri->path;    # not including query

        my $host_details = $host_path_match{$uri_host};
        my $path_regex   = $host_details->[0];

        return ( 1, $host_details->[1] ) if $path_regex && ( $uri_path =~ $path_regex );

        my @complex_ok = grep { $_ } map { $_->($parsed_uri) } values %complex_match;
        return @complex_ok if @complex_ok;

        return 0;
    }
);

LJ::Hooks::register_hook(
    'list_iframe_embed_domains',
    sub {
        my @list = ( keys %host_path_match, keys %complex_match );
        my $tld  = sub {
            my ($dom) = @_;
            my $idx = ( $dom =~ /\.com?\.\w+$/ ) ? -3 : -2;
            return [ split /\./, $dom ]->[$idx];
        };

        my $sort_domain = sub { $tld->($a) cmp $tld->($b) || $a cmp $b };
        return [ sort $sort_domain @list ];
    }
);

1;
