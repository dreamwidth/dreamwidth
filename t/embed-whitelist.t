# -*-perl-*-
use strict;

use Test::More tests => 10;
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
