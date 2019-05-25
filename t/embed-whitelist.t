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

use Test::More tests => 99;

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
        ok( !LJ::Hooks::run_hook( "allow_iframe_embeds", $url ), $msg );
    }
}

note("testing various schemas");
{
    test_bad_url(
"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==",
        "data schema"
    );

    test_good_url( "http://www.youtube.com/embed/123457890abc",
        "known good (assumed good for this test)" );
    test_bad_url( "data://www.youtube.com/embed/123457890abc", "looks good, but has a bad schema" );
}

note("youtube");
{
    test_good_url( "http://www.youtube.com/embed/x1xx2xxxxxX",  "normal youtube url" );
    test_good_url( "https://www.youtube.com/embed/x1xx2xxxxxX", "https youtube url" );
    test_good_url( "http://www.youtube-nocookie.com/embed/x1xx2xxxxxX",
        "privacy-enhanced youtube url" );
    test_good_url( "https://www.youtube-nocookie.com/embed/x1xx2xxxxxX",
        "https privacy-enhanced youtube url" );

    # with arguments
    test_good_url( "http://www.youtube.com/embed/x1xx2xxxxxX?somearg=1&otherarg=2",
        "with arguments" );

    test_bad_url( "http://www.youtube.com/notreallyembed/x1xx2xxxxxX",     "wrong path" );
    test_bad_url( "http://www.youtube.com/embed/x1xx2xxxxxX/butnotreally", "wrong path" );

    # network-relative URLs
    test_good_url( "//www.youtube.com/embed/uzmR-Ru_P8Y", "network-relative url (//)" );
    test_bad_url( "/www.youtube.com/embed/uzmR-Ru_P8Y",      "mis-pasted local-relative url" );
    test_bad_url( "ttp://www.youtube.com/embed/uzmR-Ru_P8Y", "mis-pasted url /w bad scheme" );
}

note("misc");
{
    # 0-9
    test_good_url("http://www.4shared.com/web/embed/file/VtBG91EOba");
    test_good_url("http://8tracks.com/mixes/878698/player_v3_universal");

    # A
    test_good_url("https://airtable.com/embed/shr5l5zt9nyBVMj4L");
    test_good_url("https://archive.org/embed/LeonardNimoy15Oct2013YiddishBookCenter");
    test_good_url("https://audiomack.com/embed/song/ariox-1/faded");

    # B
    test_good_url(
"http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123/size=venti/bgcol=FFFFFF/linkcol=4285BB/"
    );
    test_good_url("http://bandcamp.com/EmbeddedPlayer/v=2/track=123123123");

    test_good_url("http://blip.tv/play/x11Xx11Xx.html");

    test_good_url("https://app.box.com/embed/s/eqbvgyrj6uqftb6k8vz2wcdzu4wx7yy4");

    # C
    test_good_url("https://chirb.it/wp/pnC9Kh");
    test_good_url("//codepen.io/enxaneta/embed/gPeZdP/?height=268&theme-id=0&default-tab=result");
    test_good_url("http://coub.com/embed/x1xx2xxxxxX");
    test_good_url(
"http://www.criticalcommons.org/Members/china_shop/clips/handle-with-care-white-collar-fanvid/embed_view"
    );

    # D
    test_good_url("http://www.dailymotion.com/embed/video/x1xx11x");
    test_good_url("http://dotsub.com/media/9db493c6-6168-44b0-89ea-e33a31db48db/e/m");
    test_good_url("https://discordapp.com/widget?id=305444013354254349&theme=dark");

    # E
    test_good_url( "http://episodecalendar.com/icalendar/sampleuser\@example.com/abcde/",
        "Will 404, but correctly-formed" );

    # F
    test_good_url(
"https://www.facebook.com/plugins/video.php?href=https%3A%2F%2Fwww.facebook.com%2FSenegocom%2Fvideos%2F775953559125595%2F&width=500&show_text=false&height=283&appId"
    );
    test_good_url("https://www.flickr.com/photos/cards_by_krisso/13983859958/player/");
    test_good_url("//www.funnyordie.com/embed/7156588dc7");

    # G
    test_good_url(
"http://www.goodreads.com/widgets/user_update_widget?height=400&num_updates=3&user=12345&width=250"
    );
    test_good_url("https://giphy.com/embed/Om0tF9bYdLCKI");

    test_good_url(
"http://maps.google.com/maps?f=q&source=s_q&hl=en&geocode=&q=somethingsomething&aq=0&sll=00.000,-00.0000&sspn=0.00,0.0&vpsrc=0&ie=UTF8&hq=&hnear=somethingsomething&z=0&ll=0,-00&output=embed"
    );
    test_good_url(
"https://www.google.com/maps/embed?pb=!1m14!1m12!1m3!1d10271.13503700941!2d11.57008615!3d49.94039865!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!5e0!3m2!1sde!2sde!4v1494881096867"
    );
    test_good_url(
"https://www.google.com/calendar/b/0/embed?showPrint=0&showTabs=0&showCalendars=0&showTz=0&height=600&wkst=1&bgcolor=%23FFFFFF&src=foo%40group.calendar.google.com"
    );
    test_good_url(
"https://docs.google.com/spreadsheet/pub?key=0ArL0HD_lYDPadEkxSi1DTzJDa09GUmtzWEEwUDd4WFE&output=html&widget=true"
    );
    test_good_url(
"https://docs.google.com/spreadsheets/d/1P84CUNTo5O4ZW7R58Gl1ksCknFx3p59XzzQa7y67IaI/pubhtml?gid=23737011&single=true&widget=true&headers=false"
    );
    test_good_url(
"https://docs.google.com/document/d/1Bo38jRzUWrEAHT6oaNyeGLlluscRY6TS2lE2E1T94dQ/pub?embedded=true"
    );
    test_good_url(
"https://docs.google.com/presentation/d/1AxZkO9k4ISxku0__jRD8Im6mJC9xv5i4MgETEJ_MnA8/embed?start=false&loop=false&delayms=3000"
    );

    test_good_url("https://player.gimletmedia.com/awhk76");

    # I
    test_good_url("//imgur.com/a/J4OKE/embed");
    test_good_url("//instagram.com/p/cA1pRXKGBT/embed/");
    test_good_url("http://www.imdb.com/videoembed/vi1743501593");

    # J
    test_good_url("//www.jigsawplanet.com/?rc=play&amp;pid=35458f1355c4&amp;view=iframe");
    test_good_url("//jsfiddle.net/5c0ruh8s/10/embedded/");

    # K
    test_good_url(
"http://www.kickstarter.com/projects/25352323/arrival-a-short-film-by-alex-myung/widget/video.html"
    );
    test_good_url(
"http://www.kickstarter.com/projects/25352323/arrival-a-short-film-by-alex-myung/widget/card.html"
    );

    # L
    test_good_url("https://lichess.org/study/embed/JYjprYmJ/CeyjnPCj");

    test_good_url("https://shad-tkhom.livejournal.com/1244088.html?embed");
    test_bad_url( "https://shad-tkhom.livejournal.com/1244088.html",         "missing embed flag" );
    test_bad_url( "https://shad-tkhom.livejournal.com/1244sd088.html?embed", "invalid item id" );
    test_bad_url( "https://shad_tkhom.livejournal.com/1244sd088.html?embed", "bad username" );

    # M
    test_good_url(
"https://www.mixcloud.com/widget/iframe/?feed=https%3A%2F%2Fwww.mixcloud.com%2Fvladmradio%2F25-podcast-from-august-24-2016%2F&hide_cover=1&light=1"
    );
    test_good_url("https://mixstep.co/embed/20v1uter690o");
    test_good_url("https://my.mail.ru/video/embed/420151911556087230");
    test_good_url(
"http://player.theplatform.com/p/7wvmTC/MSNBCEmbeddedOffSite?guid=n_hayes_cmerkleyimmig_180604"
    );

    # N
    test_good_url("http://ext.nicovideo.jp/thumb/sm123123123");
    test_good_url("http://ext.nicovideo.jp/thumb/nm123123123");
    test_good_url("http://ext.nicovideo.jp/thumb/123123123");

    test_good_url("http://noisetrade.com/service/widgetv2/ff3a6475-69ef-479d-9773-8ef1676f3cfb");

    test_good_url(
        "http://www.npr.org/templates/event/embeddedVideo.php?storyId=326182003&mediaId=327658636");

    # O
    test_good_url(
"https://onedrive.live.com/embed?cid=9B3AE57006984006&resid=9B3AE57006984006%21172&authkey=ACnVTXqwCqi3zpo"
    );

    # P
    test_good_url("https://playmoss.com/embed/wingedbeastie/the-swamp-witch-nix-s-playlist");
    test_good_url(
        "http://www.plurk.com/getWidget?uid=123123123&h=375&w=200&u_info=2&bg=cf682f&tl=cae7fd");
    test_good_url("https://pastebin.com/embed_iframe/Juks92Y2");

    # R
    test_good_url(
"https://www.reverbnation.com/widget_code/html_widget/artist_299962?widget_id=55&pwc[song_ids]=4189683&context_type=song&pwc[size]=small&pwc[color]=dark"
    );
    test_good_url(
"https://www.random.org/widgets/integers/iframe.php?title=True+Random+Number+Generator&buttontxt=Generate&width=160&height=200&border=on&bgcolor=%23FFFFFF&txtcolor=%23777777&altbgcolor=%23CCCCFF&alttxtcolor=%23000000&defaultmin=&defaultmax=&fixed=off"
    );

    # S
    test_good_url("http://www.sbs.com.au/yourlanguage//player/embed/id/163111");
    test_good_url("//scratch.mit.edu/projects/embed/144290094/?autostart=false");
    test_good_url(
        "http://www.scribd.com/embeds/123123/content?start_page=1&view_mode=list&access_key=");
    test_good_url("http://www.slideshare.net/slideshow/embed_code/12312312");
    test_good_url(
"http://w.soundcloud.com/player/?url=http%3A%2F%2Fapi.soundcloud.com%2Ftracks%2F23318382&show_artwork=true"
    );
    test_good_url("https://embed.spotify.com/?uri=spotify:track:1DeuZgn99eUC1hreXTWBvY");
    test_good_url("https://open.spotify.com/embed/track/5IsdA6g8IFKGmC1xl37OG1");
    test_good_url("https://open.spotify.com/?uri=spotify:track:1DeuZgn99eUC1hreXTWBvY");
    test_good_url("https://open.spotify.com/embed/album/2aE3VcIiNPqqo4VzOXiDoR");
    test_good_url(
"https://open.spotify.com/embed/user/64f31rn6hwblzmssibjvs75e8/playlist/1ACvcMYSJoqa3gwOw6j0NR"
    );
    test_good_url(
"https://www.strava.com/activities/1997053955/embed/54dd7dc49efe8f9b00b8fceb01fa822fcc7de662"
    );
    test_good_url("https://streamable.com/s/asq5b/knxvuf");

    # T
    test_good_url(
        "http://embed.ted.com/talks/handpring_puppet_co_the_genius_puppetry_behind_war_horse.html");
    test_good_url(
"http://i.cdn.turner.com/cnn/.element/apps/cvp/3.0/swf/cnn_416x234_embed.swf?context=embed&videoId=bestoftv/2012/09/05/exp-tsr-dem-platform-voice-vote.cnn"
    );

    # V
    test_good_url("https://vid.me/e/v63?stats=1&amp;tools=1");
    test_good_url("https://vk.com/video_ext.php?oid=-49280571&id=165718332&hash=5eb26e7a4cd9982d");

    test_good_url("http://player.vimeo.com/video/123123123?title=0&byline=0&portrait=0");
    test_bad_url("http://player.vimeo.com/video/123abc?title=0&byline=0&portrait=0");

    test_good_url("https://vine.co/v/bjHh0zHdgZT/embed/simple");
    test_bad_url("https://vine.co/v/bjHh0zHdgZT/embed/postcard");
    test_bad_url("https://vine.co/v/bjHh0zHdgZT/embed");
    test_bad_url("https://vine.co/v/abc/embed/simple");

    # W
    test_good_url(
"http://commons.wikimedia.org/wiki/File:somethingsomethingsomething.ogv?withJS=MediaWiki:MwEmbed.js&embedplayer=yes"
    );
    test_bad_url(
"http://commons.wikimedia.org/wiki/File:1903_Burnley_Ironworks_company_steam_engine_in_use.ogv?withJS=MediaWiki:MwEmbed.js"
    );

    test_good_url("https://fast.wistia.com/embed/iframe/k1akcpc0ik");

    # Y
    test_good_url(
"https://screen.yahoo.com/fashion-photographer-life-changed-chance-193621376.html?format=embed"
    );
    test_good_url("http://video.yandex.ru/iframe/v-rednaia7/9hvgcmpgkd.5440/");
    test_good_url("https://music.yandex.ru/iframe/#track/31910432/247808/");

    # Z
    test_good_url("//www.zippcast.com/videoview.php?vplay=6c91dae3fc1bc909db0&auto=no");

}
