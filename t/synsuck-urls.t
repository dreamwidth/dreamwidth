# t/synsuck-urls.t
#
# Test URL handling in syndicated entries.
#
# Authors:
#      Alex
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use utf8;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use File::Temp;
use HTML::TokeParser;
use HTTP::Response;
use LJ::CleanHTML;
use LJ::Entry;
use LJ::SynSuck;
use LJ::Test qw(temp_feed);

my $salt_file = File::Temp->new;
my $salt      = 'syndication test salt';
print {$salt_file} $salt or die $!;
close $salt_file or die $!;
local $LJ::PROXY_SALT_FILE   = $salt_file->filename;
local $LJ::PROXY_URL         = 'https://proxy.example.test';
local %LJ::KNOWN_HTTPS_SITES = ();

my $feed = temp_feed();
my $dbh  = LJ::get_db_writer();
my $row  = $dbh->selectrow_hashref(
    'SELECT u.user, s.* FROM user u JOIN syndicated s USING (userid) WHERE userid=?',
    undef, $feed->id, );

my $rss = encode_utf8(<<'RSS');
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<title>Image feed</title><link>https://news.example.test/</link><description>Images</description>
<item><title>International URLs</title><link>https://news.example.test/posts/item</link>
<guid isPermaLink="false">image-test</guid>
<description><![CDATA[<p>
<img alt="raw" src="http://images.example.test/разъёмы.jpg"
    srcset="http://images.example.test/小.jpg 320w, http://images.example.test/大.jpg 640w">
<img alt="named-entity" src="http://images.example.test/разъёмы-&eacute;.jpg">
<img alt="numeric-entity" src="http://images.example.test/猫&#xE9;.jpg">
<img alt="wide-entity" src="http://images.example.test/猫&#x1F600;.jpg">
<img alt="encoded" src="http://images.example.test/%d1%80.jpg?crop=a%2fb">
<img alt="query" src="http://images.example.test/caf%C3%A9/猫.jpg?name=😀&amp;size=2">
<img alt="ascii" src="http://images.example.test/plain.jpg?size=2&amp;fit=cover">
<img alt="https" src="https://images.example.test/猫.jpg"
    srcset="https://images.example.test/猫.jpg 1x, https://images.example.test/猫-大.jpg 2x">
<img alt="idn" src="http://пример.рф/путь.jpg">
<img alt="invalid-idn" src="http://пример..рф/путь.jpg">
<img alt="invalid-idn-srcset" src="https://images.example.test/fallback.jpg"
    srcset="https://пример..рф/путь.jpg 2x">
<img alt="relative" src="../猫.jpg">
<img alt="relative-entity" src="../猫&#x1F600;.jpg">
<img alt="unsafe" src="JaVaScRiPt:猫" srcset="data:image/png,猫">
<a title="absolute" href="https://news.example.test/новости?name=猫&amp;id=a%2fb">News</a>
<a title="relative" href="../новости">Relative</a>
<a title="scheme-relative" href="//news.example.test/новости">Scheme-relative</a>
<a title="idn" href="//пример.рф:8443/путь?name=猫#é">International hostname</a>
<a title="unsafe" href="jav&#x61;script&#58;猫">Unsafe</a>
<a title="data" href="data:text/html,猫">Unsafe</a>
</p>]]></description></item>
</channel></rss>
RSS

my $response = HTTP::Response->new(200);
$response->header( 'Content-Type' => 'application/rss+xml' );
my $imported = LJ::SynSuck::process_content( $row, [ $response, $rss ] );
ok( $imported, 'RSS item imported' ) or BAIL_OUT('cannot import test feed');

my $cluster = LJ::get_cluster_master($feed);
my ($itemid) =
    $cluster->selectrow_array( 'SELECT jitemid FROM log2 WHERE journalid=?', undef, $feed->id );
ok( $itemid, 'import created a feed entry' ) or BAIL_OUT('cannot find imported entry');

my $entry  = LJ::Entry->new( $feed, jitemid => $itemid );
my $html   = $entry->event_html;
my $parser = HTML::TokeParser->new( \$html );
my ( %images, %links );
while ( my $tag = $parser->get_tag( 'img', 'a' ) ) {
    my ( $name, $attrs ) = @$tag;
    $images{ $attrs->{alt} }  = $attrs if $name eq 'img' && defined $attrs->{alt};
    $links{ $attrs->{title} } = $attrs if $name eq 'a'   && defined $attrs->{title};
}

my $proxy = sub {
    my ( $target, $host ) = @_;
    $host //= 'images.example.test';
    my $host_path = "$host/$target";
    my $signature = substr( md5_hex("${salt}http://$host_path"), 0, 12 );
    my $source    = $feed->id . '-' . $entry->ditemid;
    return "$LJ::PROXY_URL/$signature/$source/$host_path";
};

is(
    $images{raw}{src},
    $proxy->('%D1%80%D0%B0%D0%B7%D1%8A%D1%91%D0%BC%D1%8B.jpg'),
    'proxy signs the percent-encoded Cyrillic image URL'
);
is(
    $images{raw}{srcset},
    $proxy->('%E5%B0%8F.jpg') . ' 320w, ' . $proxy->('%E5%A4%A7.jpg') . ' 640w',
    'each responsive image URL is encoded and signed'
);
is(
    $images{'named-entity'}{src},
    $proxy->('%D1%80%D0%B0%D0%B7%D1%8A%D1%91%D0%BC%D1%8B-%C3%A9.jpg'),
    'named character reference and literal Cyrillic are encoded and signed'
);
is(
    $images{'numeric-entity'}{src},
    $proxy->('%E7%8C%AB%C3%A9.jpg'),
    'Latin-1-range character reference and literal UTF-8 are encoded and signed'
);
is(
    $images{'wide-entity'}{src},
    $proxy->('%E7%8C%AB%F0%9F%98%80.jpg'),
    'wide character reference and literal UTF-8 are encoded and signed'
);
is(
    $images{encoded}{src},
    $proxy->('%d1%80.jpg?crop=a%2fb'),
    'existing percent escapes are preserved verbatim'
);
is(
    $images{query}{src},
    $proxy->('caf%C3%A9/%E7%8C%AB.jpg?name=%F0%9F%98%80&size=2'),
    'UTF-8 query values are escaped without changing query separators'
);
is(
    $images{ascii}{src},
    $proxy->('plain.jpg?size=2&fit=cover'),
    'ASCII URL and signature are unchanged'
);
my $https_image = 'https://images.example.test/%E7%8C%AB';
is( $images{https}{src}, "$https_image.jpg", 'HTTPS images are encoded without proxying' );
is(
    $images{https}{srcset},
    "$https_image.jpg 1x, $https_image-%E5%A4%A7.jpg 2x",
    'HTTPS responsive images are encoded like src without proxying'
);
is(
    $images{idn}{src},
    $proxy->( '%D0%BF%D1%83%D1%82%D1%8C.jpg', 'xn--e1afmkfd.xn--p1ai' ),
    'proxy signs the punycode hostname and percent-encoded path'
);
ok(
    $images{'invalid-idn'} && !length( $images{'invalid-idn'}{src} // '' ),
    'malformed internationalized hostname is not sent to the proxy'
);
is_deeply(
    $images{'invalid-idn-srcset'},
    { alt => 'invalid-idn-srcset', src => 'https://images.example.test/fallback.jpg' },
    'malformed responsive image URL falls back to src'
);
is(
    $images{relative}{src},
    'https://news.example.test/%E7%8C%AB.jpg',
    'relative image URL resolves against the feed item URL'
);
is(
    $images{'relative-entity'}{src},
    'https://news.example.test/%E7%8C%AB%F0%9F%98%80.jpg',
    'relative image URL preserves literal UTF-8 and a wide character reference'
);

my $news_path = '%D0%BD%D0%BE%D0%B2%D0%BE%D1%81%D1%82%D0%B8';
is(
    $links{absolute}{href},
    "https://news.example.test/$news_path?name=%E7%8C%AB&id=a%2fb",
    'absolute link path and query value are encoded without changing existing escapes'
);
is(
    $links{relative}{href},
    "https://news.example.test/$news_path",
    'relative link resolves against the feed item URL'
);
is(
    $links{'scheme-relative'}{href},
    "https://news.example.test/$news_path",
    'scheme-relative link resolves to the encoded URL'
);
is(
    $links{idn}{href},
    'https://xn--e1afmkfd.xn--p1ai:8443/%D0%BF%D1%83%D1%82%D1%8C?name=%E7%8C%AB#%C3%A9',
    'scheme-relative link preserves the port and escapes its path, query, and fragment'
);

ok( $images{unsafe} && !length( $images{unsafe}{src} // '' ), 'javascript image URL is stripped' );
ok( $images{unsafe} && !exists $images{unsafe}{srcset},       'data URL in srcset is stripped' );
ok(
    $links{unsafe} && !exists $links{unsafe}{href},
    'entity-obfuscated javascript link is stripped'
);
ok( $links{data} && !exists $links{data}{href}, 'data link is stripped' );

my $character_html = '<img src="https://images.example.test/猫&#x1F600;.jpg">';
LJ::CleanHTML::clean_event( \$character_html, { preformatted => 1 } );
like(
    $character_html,
    qr{src="https://images\.example\.test/%E7%8C%AB%F0%9F%98%80\.jpg"},
    'cleaner also encodes the correct URL from a Perl character string'
);

my $character_relative_html = '<p>猫<img src="../猫&#x1F600;.jpg"></p>';
LJ::CleanHTML::resolve_relative_urls( \$character_relative_html,
    'https://news.example.test/posts/item' );
is(
    $character_relative_html,
    '<p>猫<img src="https://news.example.test/%E7%8C%AB%F0%9F%98%80.jpg"></p>',
    'relative resolution preserves surrounding characters and escapes the URL'
);

done_testing();
