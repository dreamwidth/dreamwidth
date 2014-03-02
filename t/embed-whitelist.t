# t/embed-whitelist.t
#
# Test DW::Hooks::EmbedWhitelist.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 43;

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

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

    # network-relative URLs
    test_good_url( "//www.youtube.com/embed/uzmR-Ru_P8Y", "network-relative url (//)" );
    test_bad_url( "/www.youtube.com/embed/uzmR-Ru_P8Y", "mis-pasted local-relative url" );
    test_bad_url( "ttp://www.youtube.com/embed/uzmR-Ru_P8Y", "mis-pasted url /w bad scheme" );
}

note( "misc" );
{
    test_good_url( "http://8tracks.com/mixes/878698/player_v3_universal" );
    test_good_url( "http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123/size=venti/bgcol=FFFFFF/linkcol=4285BB/" );
    test_good_url( "http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123" );

    test_good_url( "http://blip.tv/play/x11Xx11Xx.html" );

    test_good_url( "http://www.dailymotion.com/embed/video/x1xx11x" );

    test_good_url( "http://dotsub.com/media/9db493c6-6168-44b0-89ea-e33a31db48db/e/m" );

    test_good_url( "//instagram.com/p/cA1pRXKGBT/embed/" );

    test_good_url( "http://www.goodreads.com/widgets/user_update_widget?height=400&num_updates=3&user=12345&width=250" );

    test_good_url( "http://maps.google.com/maps?f=q&source=s_q&hl=en&geocode=&q=somethingsomething&aq=0&sll=00.000,-00.0000&sspn=0.00,0.0&vpsrc=0&ie=UTF8&hq=&hnear=somethingsomething&z=0&ll=0,-00&output=embed" );
    test_good_url( "https://www.google.com/calendar/b/0/embed?showPrint=0&showTabs=0&showCalendars=0&showTz=0&height=600&wkst=1&bgcolor=%23FFFFFF&src=foo%40group.calendar.google.com" );
    test_good_url( "https://docs.google.com/spreadsheet/pub?key=0ArL0HD_lYDPadEkxSi1DTzJDa09GUmtzWEEwUDd4WFE&output=html&widget=true" );
    test_good_url( "https://docs.google.com/document/d/1Bo38jRzUWrEAHT6oaNyeGLlluscRY6TS2lE2E1T94dQ/pub?embedded=true" );
    test_good_url( "https://docs.google.com/presentation/d/1AxZkO9k4ISxku0__jRD8Im6mJC9xv5i4MgETEJ_MnA8/embed?start=false&loop=false&delayms=3000" );

    test_good_url( "http://www.kickstarter.com/projects/25352323/arrival-a-short-film-by-alex-myung/widget/video.html" );
    test_good_url( "http://www.kickstarter.com/projects/25352323/arrival-a-short-film-by-alex-myung/widget/card.html" );

    test_good_url( "http://ext.nicovideo.jp/thumb/sm123123123" );
    test_good_url( "http://ext.nicovideo.jp/thumb/nm123123123" );
    test_good_url( "http://ext.nicovideo.jp/thumb/123123123" );

    test_good_url( "http://www.sbs.com.au/yourlanguage//player/embed/id/163111" );

    test_good_url( "http://www.scribd.com/embeds/123123/content?start_page=1&view_mode=list&access_key=" );

    test_good_url( "http://www.slideshare.net/slideshow/embed_code/12312312" );

    test_good_url( "http://w.soundcloud.com/player/?url=http%3A%2F%2Fapi.soundcloud.com%2Ftracks%2F23318382&show_artwork=true" );

    test_good_url( "https://embed.spotify.com/?uri=spotify:track:1DeuZgn99eUC1hreXTWBvY" );

    test_good_url( "http://www.twitvid.com/embed.php?guid=QNDLU&autoplay=0" );

    test_good_url( "http://player.vimeo.com/video/123123123?title=0&byline=0&portrait=0" );
    test_bad_url( "http://player.vimeo.com/video/123abc?title=0&byline=0&portrait=0" );

    test_good_url( "http://commons.wikimedia.org/wiki/File:somethingsomethingsomething.ogv?withJS=MediaWiki:MwEmbed.js&embedplayer=yes" );
    test_bad_url( "http://commons.wikimedia.org/wiki/File:1903_Burnley_Ironworks_company_steam_engine_in_use.ogv?withJS=MediaWiki:MwEmbed.js" );

    test_good_url( "http://www.plurk.com/getWidget?uid=123123123&h=375&w=200&u_info=2&bg=cf682f&tl=cae7fd" );

    test_good_url( "http://www.criticalcommons.org/Members/china_shop/clips/handle-with-care-white-collar-fanvid/embed_view" );
}


