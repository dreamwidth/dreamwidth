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

use Test::More tests => 66;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Hooks::EmbedWhitelist;

sub test_good_url {
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $url = $_[0];
    my $msg = $_[1];
    subtest "good embed url $url", sub {
        my ( $url_ok, $can_https ) = LJ::Hooks::run_hook( "allow_iframe_embeds", $url );
        ok( $url_ok, $msg );
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
    # 0-9
    test_good_url( "http://www.4shared.com/web/embed/file/VtBG91EOba" );
    test_good_url( "http://8tracks.com/mixes/878698/player_v3_universal" );

    # A
    test_good_url( "https://archive.org/embed/LeonardNimoy15Oct2013YiddishBookCenter" );

    # B
    test_good_url( "http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123/size=venti/bgcol=FFFFFF/linkcol=4285BB/" );
    test_good_url( "http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123" );

    test_good_url( "http://blip.tv/play/x11Xx11Xx.html" );

    # C
    test_good_url( "//codepen.io/enxaneta/embed/gPeZdP/?height=268&theme-id=0&default-tab=result" );
    test_good_url( "http://www.criticalcommons.org/Members/china_shop/clips/handle-with-care-white-collar-fanvid/embed_view" );

    # D
    test_good_url( "http://www.dailymotion.com/embed/video/x1xx11x" );
    test_good_url( "http://dotsub.com/media/9db493c6-6168-44b0-89ea-e33a31db48db/e/m" );

    # E
    test_good_url( "http://episodecalendar.com/icalendar/sampleuser\@example.com/abcde/", "Will 404, but correctly-formed" );

    # F
    test_good_url( "https://www.facebook.com/plugins/video.php?href=https%3A%2F%2Fwww.facebook.com%2FSenegocom%2Fvideos%2F775953559125595%2F&width=500&show_text=false&height=283&appId" );
    test_good_url( "https://www.flickr.com/photos/cards_by_krisso/13983859958/player/" );

    # G
    test_good_url( "http://www.goodreads.com/widgets/user_update_widget?height=400&num_updates=3&user=12345&width=250" );

    test_good_url( "http://maps.google.com/maps?f=q&source=s_q&hl=en&geocode=&q=somethingsomething&aq=0&sll=00.000,-00.0000&sspn=0.00,0.0&vpsrc=0&ie=UTF8&hq=&hnear=somethingsomething&z=0&ll=0,-00&output=embed" );
    test_good_url( "https://www.google.com/calendar/b/0/embed?showPrint=0&showTabs=0&showCalendars=0&showTz=0&height=600&wkst=1&bgcolor=%23FFFFFF&src=foo%40group.calendar.google.com" );
    test_good_url( "https://docs.google.com/spreadsheet/pub?key=0ArL0HD_lYDPadEkxSi1DTzJDa09GUmtzWEEwUDd4WFE&output=html&widget=true" );
    test_good_url( "https://docs.google.com/spreadsheets/d/1P84CUNTo5O4ZW7R58Gl1ksCknFx3p59XzzQa7y67IaI/pubhtml?gid=23737011&single=true&widget=true&headers=false" );
    test_good_url( "https://docs.google.com/document/d/1Bo38jRzUWrEAHT6oaNyeGLlluscRY6TS2lE2E1T94dQ/pub?embedded=true" );
    test_good_url( "https://docs.google.com/presentation/d/1AxZkO9k4ISxku0__jRD8Im6mJC9xv5i4MgETEJ_MnA8/embed?start=false&loop=false&delayms=3000" );

    # I
    test_good_url( "//imgur.com/a/J4OKE/embed" );
    test_good_url( "//instagram.com/p/cA1pRXKGBT/embed/" );

    # J
    test_good_url( "//www.jigsawplanet.com/?rc=play&amp;pid=35458f1355c4&amp;view=iframe" );
    test_good_url( "//jsfiddle.net/5c0ruh8s/10/embedded/" );

    # K
    test_good_url( "http://www.kickstarter.com/projects/25352323/arrival-a-short-film-by-alex-myung/widget/video.html" );
    test_good_url( "http://www.kickstarter.com/projects/25352323/arrival-a-short-film-by-alex-myung/widget/card.html" );

    # N
    test_good_url( "http://ext.nicovideo.jp/thumb/sm123123123" );
    test_good_url( "http://ext.nicovideo.jp/thumb/nm123123123" );
    test_good_url( "http://ext.nicovideo.jp/thumb/123123123" );

    test_good_url( "http://www.npr.org/templates/event/embeddedVideo.php?storyId=326182003&mediaId=327658636" );

    # O
    test_good_url( "https://onedrive.live.com/embed?cid=9B3AE57006984006&resid=9B3AE57006984006%21172&authkey=ACnVTXqwCqi3zpo" );

    # P
    test_good_url( "https://playmoss.com/embed/wingedbeastie/the-swamp-witch-nix-s-playlist" );
    test_good_url( "http://www.plurk.com/getWidget?uid=123123123&h=375&w=200&u_info=2&bg=cf682f&tl=cae7fd" );

    # S
    test_good_url( "http://www.sbs.com.au/yourlanguage//player/embed/id/163111" );
    test_good_url( "//scratch.mit.edu/projects/embed/144290094/?autostart=false" );
    test_good_url( "http://www.scribd.com/embeds/123123/content?start_page=1&view_mode=list&access_key=" );
    test_good_url( "http://www.slideshare.net/slideshow/embed_code/12312312" );
    test_good_url( "http://w.soundcloud.com/player/?url=http%3A%2F%2Fapi.soundcloud.com%2Ftracks%2F23318382&show_artwork=true" );
    test_good_url( "https://embed.spotify.com/?uri=spotify:track:1DeuZgn99eUC1hreXTWBvY" );

    # T
    test_good_url( "http://embed.ted.com/talks/handpring_puppet_co_the_genius_puppetry_behind_war_horse.html" );
    test_good_url( "http://i.cdn.turner.com/cnn/.element/apps/cvp/3.0/swf/cnn_416x234_embed.swf?context=embed&videoId=bestoftv/2012/09/05/exp-tsr-dem-platform-voice-vote.cnn" );

    # V
    test_good_url( "https://vid.me/e/v63?stats=1&amp;tools=1" );

    test_good_url( "http://player.vimeo.com/video/123123123?title=0&byline=0&portrait=0" );
    test_bad_url( "http://player.vimeo.com/video/123abc?title=0&byline=0&portrait=0" );

    test_good_url( "https://vine.co/v/bjHh0zHdgZT/embed/simple" );
    test_bad_url( "https://vine.co/v/bjHh0zHdgZT/embed/postcard" );
    test_bad_url( "https://vine.co/v/bjHh0zHdgZT/embed" );
    test_bad_url( "https://vine.co/v/abc/embed/simple" );

    # W
    test_good_url( "http://commons.wikimedia.org/wiki/File:somethingsomethingsomething.ogv?withJS=MediaWiki:MwEmbed.js&embedplayer=yes" );
    test_bad_url( "http://commons.wikimedia.org/wiki/File:1903_Burnley_Ironworks_company_steam_engine_in_use.ogv?withJS=MediaWiki:MwEmbed.js" );

    # Y
    test_good_url( "https://screen.yahoo.com/fashion-photographer-life-changed-chance-193621376.html?format=embed" );
    test_good_url( "http://video.yandex.ru/iframe/v-rednaia7/9hvgcmpgkd.5440/" );

    # Z
    test_good_url( "//www.zippcast.com/videoview.php?vplay=6c91dae3fc1bc909db0&auto=no" );

}
