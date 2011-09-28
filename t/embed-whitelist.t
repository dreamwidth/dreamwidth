# -*-perl-*-
use strict;

use Test::More tests => 26;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use DW::Hooks::EmbedWhitelist;

sub test_good_url {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $url = $_[0];
    my $msg = $_[1];
    subtest "good embed url $url", sub {
        ok( LJ::Hooks::run_hook( "allow_iframe_embeds", $url ), $msg );
    }
}

sub test_bad_url {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $url = $_[0];
    my $msg = $_[1];
    subtest "bad embed url $url", sub {
        ok( ! LJ::Hooks::run_hook( "allow_iframe_embeds", $url ), $msg );
    }
}

note( "testing various schemas" );
{
    test_bad_url( "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==", "data schema" );

    test_good_url( "http://www.youtube.com/embed/123457890abc", "known good (assumed good for this test)" );
    test_bad_url( "data://www.youtube.com/embed/123457890abc", "looks good, but has a bad schema" );
}

note( "youtube" );
{
    test_good_url( "http://www.youtube.com/embed/x1xx2xxxxxX", "normal youtube url" );
    test_good_url( "https://www.youtube.com/embed/x1xx2xxxxxX", "https youtube url" );
    test_good_url( "http://www.youtube-nocookie.com/embed/x1xx2xxxxxX", "privacy-enhanced youtube url" );
    test_good_url( "https://www.youtube-nocookie.com/embed/x1xx2xxxxxX", "https privacy-enhanced youtube url" );

    # with arguments
    test_good_url( "http://www.youtube.com/embed/x1xx2xxxxxX?somearg=1&otherarg=2", "with arguments" );

    test_bad_url( "http://www.youtube.com/notreallyembed/x1xx2xxxxxX", "wrong path");
    test_bad_url( "http://www.youtube.com/embed/x1xx2xxxxxX/butnotreally", "wrong path");
}

note( "misc" );
{
    test_good_url( "http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123/size=venti/bgcol=FFFFFF/linkcol=4285BB/" );
    test_good_url( "http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123" );

    test_good_url( "http://blip.tv/play/x11Xx11Xx.html" );

    test_good_url( "http://www.dailymotion.com/embed/video/x1xx11x" );

    test_good_url( "http://dotsub.com/media/9db493c6-6168-44b0-89ea-e33a31db48db/e/m" );

    test_good_url( "http://maps.google.com/maps?f=q&source=s_q&hl=en&geocode=&q=somethingsomething&aq=0&sll=00.000,-00.0000&sspn=0.00,0.0&vpsrc=0&ie=UTF8&hq=&hnear=somethingsomething&z=0&ll=0,-00&output=embed" );

    test_good_url( "http://ext.nicovideo.jp/thumb/sm123123123" );
    test_good_url( "http://ext.nicovideo.jp/thumb/nm123123123" );
    test_good_url( "http://ext.nicovideo.jp/thumb/123123123" );

    test_good_url( "http://www.sbs.com.au/yourlanguage//player/embed/id/163111" );

    test_good_url( "http://www.scribd.com/embeds/123123/content?start_page=1&view_mode=list&access_key=" );

    test_good_url( "http://www.slideshare.net/slideshow/embed_code/12312312" );

    test_good_url( "http://player.vimeo.com/video/123123123?title=0&byline=0&portrait=0" );
    test_bad_url( "http://player.vimeo.com/video/123abc?title=0&byline=0&portrait=0" );

    test_good_url( "http://commons.wikimedia.org/wiki/File:somethingsomethingsomething.ogv?withJS=MediaWiki:MwEmbed.js&embedplayer=yes" );
    test_bad_url( "http://commons.wikimedia.org/wiki/File:1903_Burnley_Ironworks_company_steam_engine_in_use.ogv?withJS=MediaWiki:MwEmbed.js" );
}


