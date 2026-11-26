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
<img alt="escaped-idn" src="https://%65xample.рф/path">
<img alt="userinfo-escaped-idn" src="https://josé@%C3%A9.example/x.jpg">
<img alt="fullwidth-host" src="https://ｅxample.com/">
<img alt="escaped-fullwidth-host" src="https://%EF%BC%A5xample.com/">
<img alt="fullwidth-slash" src="https://example／invalid.test/">
<img alt="ignored-host" src="https://exam&#xAD;&#x200B;ple.com/">
<img alt="escaped-ignored-host" src="https://exam%C2%ADple.com/">
<img alt="ignored-first-label" src="https://&#xAD;.example/">
<img alt="ignored-last-label" src="https://example.&#xAD;/">
<img alt="idn-ideographic-dot" src="https://example。com/image.jpg">
<img alt="idn-fullwidth-dot" src="https://example．com/image.jpg">
<img alt="idn-halfwidth-dot" src="https://example｡com/image.jpg">
<img alt="idn-invalid-dot" src="https://example。-com/image.jpg">
<img alt="idn-decomposed" src="https://e&#x301;.example/image.jpg">
<img alt="userinfo-escaped-decomposed" src="https://josé@e%CC%81.example/image.jpg">
<img alt="relative-invalid-idn" src="//пример..рф/путь.jpg">
<img alt="userinfo" src="https://пользователь:пароль%2f@[2001:db8::1]:8443/img.png">
<img alt="userinfo-invalid-idn" src="https://josé@пример..рф/путь.jpg">
<img alt="invalid-idn-srcset" src="https://images.example.test/fallback.jpg"
    srcset="https://пример..рф/путь.jpg 2x">
<img alt="relative-idn-srcset" src="https://images.example.test/fallback.jpg"
    srcset="//%65xample.рф/猫.jpg 1x, //пример.рф/大.jpg 2x">
<img alt="relative-invalid-idn-srcset" src="https://images.example.test/fallback.jpg"
    srcset="https://images.example.test/plain.jpg 1x, //пример..рф/путь.jpg 2x">
<img alt="relative" src="../猫.jpg">
<img alt="relative-entity" src="../猫&#x1F600;.jpg">
<img alt="unsafe" src="JaVaScRiPt:猫" srcset="data:image/png,猫">
<a title="absolute" href="https://news.example.test/новости?name=猫&amp;id=a%2fb">News</a>
<a title="relative" href="../новости">Relative</a>
<a title="scheme-relative" href="//news.example.test/новости">Scheme-relative</a>
<a title="idn" href="//пример.рф:8443/путь?name=猫#é">International hostname</a>
<a title="escaped-idn" href="https://%65xample.рф/path">Escaped ASCII in IDN hostname</a>
<a title="escaped-utf8-idn" href="//%D0%BFример.рф/path">Escaped UTF-8 in IDN hostname</a>
<a title="fullwidth-host" href="https://ｅxample.com/">Fullwidth letter</a>
<a title="escaped-fullwidth-host" href="https://%EF%BC%A5xample.com/">Escaped fullwidth letter</a>
<a title="fullwidth-digit" href="//ex９ample.com/">Fullwidth digit</a>
<a title="fullwidth-slash" href="https://example／invalid.test/">Fullwidth slash</a>
<a title="fullwidth-colon" href="https://example：443/">Fullwidth colon</a>
<a title="fullwidth-at" href="https://example＠invalid.test/">Fullwidth at sign</a>
<a title="escaped-fullwidth-backslash" href="https://example%EF%BC%BCinvalid.test/">Escaped fullwidth backslash</a>
<a title="compatibility-dot" href="https://example․com/">One dot leader</a>
<a title="ignored-host" href="https://exam&shy;ple.com/">Soft hyphen</a>
<a title="escaped-ignored-host" href="https://exam%C2%ADple.com/">Escaped soft hyphen</a>
<a title="ignored-first-label" href="https://&shy;.example/">Empty first label</a>
<a title="ignored-last-label" href="https://example.&shy;/">Empty last label</a>
<a title="ignored-rooted-host" href="https://exam&#xFEFF;ple.com./">Rooted hostname</a>
<a title="ignored-decomposed-host" href="https://e&#x34F;&#x301;.example/">Decomposed hostname</a>
<a title="idn-japanese" href="https://例え.example/">Japanese hostname</a>
<a title="idn-sharp-s" href="https://faß.example/">Sharp s</a>
<a title="idn-final-sigma" href="https://ς.example/">Final sigma</a>
<a title="idn-host-delimiter" href="https://%2Fexample.рф/">Encoded delimiter</a>
<a title="idn-host-control" href="https://%00example.рф/">Encoded control</a>
<a title="idn-host-whitespace" href="https://%20example.рф/">Encoded whitespace</a>
<a title="idn-host-bad-escape" href="https://%ZZexample.рф/">Malformed escape</a>
<a title="idn-host-bad-label" href="https://%2Dпример.рф/">Malformed label</a>
<a title="idn-host-bad-utf8" href="https://%FFпример.рф/">Malformed UTF-8</a>
<a title="userinfo" href="https://josé@example.com/photo.jpg">International username</a>
<a title="userinfo-escaped-host" href="https://josé@%65xample.com/path">Escaped hostname</a>
<a title="userinfo-escaped-idn" href="https://josé@%C3%A9.example/x.jpg">Escaped IDN</a>
<a title="userinfo-host-delimiter" href="https://josé@bad%2Fhost.com/">Encoded delimiter</a>
<a title="userinfo-host-control" href="https://josé@bad%00host.com/">Encoded control</a>
<a title="userinfo-host-bad-escape" href="https://josé@bad%ZZhost.com/">Malformed escape</a>
<a title="userinfo-idn" href="http://josé@пример.рф/путь.jpg">International authority</a>
<a title="userinfo-relative" href="//josé@example.com/photo.jpg">Relative username</a>
<a title="userinfo-invalid-idn" href="//josé@пример..рф/путь.jpg">Malformed hostname</a>
<a title="absolute-invalid-idn" href="http://пример..рф/">Malformed absolute hostname</a>
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
    $images{'invalid-idn'} && !exists $images{'invalid-idn'}{src},
    'an absolute image URL with a malformed internationalized hostname loses src'
);
is(
    $images{'escaped-idn'}{src},
    'https://example.xn--p1ai/path',
    'image URL decodes hostname escapes before IDNA conversion'
);
my $userinfo_escaped_idn_url = 'https://jos%C3%A9@xn--9ca.example/x.jpg';
is( $images{'userinfo-escaped-idn'}{src},
    $userinfo_escaped_idn_url,
    'image escapes its username and converts a fully percent-escaped internationalized hostname' );

for my $case (qw(fullwidth-host escaped-fullwidth-host)) {
    is( $images{$case}{src}, 'https://example.com/', "image maps $case to ASCII" );
    is( $links{$case}{href}, 'https://example.com/', "link maps $case to ASCII" );
}
is( $links{'fullwidth-digit'}{href},
    'https://ex9ample.com/',
    'scheme-relative link maps a fullwidth digit before resolving the URL' );
ok( $images{'fullwidth-slash'} && !exists $images{'fullwidth-slash'}{src},
    'image rejects a fullwidth slash in the hostname' );
for my $case (
    qw(fullwidth-slash fullwidth-colon fullwidth-at escaped-fullwidth-backslash compatibility-dot))
{
    ok( $links{$case} && !exists $links{$case}{href}, "link rejects $case in the hostname" );
}
for my $case (qw(ignored-host escaped-ignored-host)) {
    is( $images{$case}{src}, 'https://example.com/', "image strips $case characters" );
    is( $links{$case}{href}, 'https://example.com/', "link strips $case characters" );
}
for my $case (qw(ignored-first-label ignored-last-label)) {
    ok( $images{$case} && !exists $images{$case}{src}, "image rejects $case" );
    ok( $links{$case}  && !exists $links{$case}{href}, "link rejects $case" );
}
is( $links{'ignored-rooted-host'}{href},
    'https://example.com./', 'mapping preserves an explicit root dot' );
is( $links{'ignored-decomposed-host'}{href},
    'https://xn--9ca.example/', 'ignored characters are removed before Unicode normalization' );
is(
    $links{'idn-japanese'}{href},
    'https://xn--r8jz45g.example/',
    'link encodes a Japanese hostname'
);
is( $links{'idn-sharp-s'}{href}, 'https://xn--fa-hia.example/', 'link preserves sharp s in IDNA' );
is( $links{'idn-final-sigma'}{href},
    'https://xn--3xa.example/', 'link preserves final sigma in IDNA' );

for my $separator (qw(ideographic fullwidth halfwidth)) {
    is(
        $images{"idn-$separator-dot"}{src},
        'https://example.com/image.jpg',
        "image maps the $separator hostname separator to an ASCII dot"
    );
}
ok(
    $images{'idn-invalid-dot'} && !exists $images{'idn-invalid-dot'}{src},
    'image rejects an invalid label after mapping a Unicode hostname separator'
);
is(
    $images{'idn-decomposed'}{src},
    'https://xn--9ca.example/image.jpg',
    'image normalizes a decomposed hostname to NFC before IDNA conversion'
);
is(
    $images{'userinfo-escaped-decomposed'}{src},
    'https://jos%C3%A9@xn--9ca.example/image.jpg',
    'image normalizes a percent-escaped decomposed hostname to NFC'
);
ok(
    $images{'relative-invalid-idn'} && !exists $images{'relative-invalid-idn'}{src},
    'a scheme-relative image URL with a malformed internationalized hostname loses src'
);
my $image_user = '%D0%BF%D0%BE%D0%BB%D1%8C%D0%B7%D0%BE%D0%B2%D0%B0%D1%82%D0%B5%D0%BB%D1%8C';
my $image_pass = '%D0%BF%D0%B0%D1%80%D0%BE%D0%BB%D1%8C';
is( $images{userinfo}{src}, "https://$image_user:$image_pass%2f\@[2001:db8::1]:8443/img.png",
    'image credentials are escaped without changing the separator, existing escape, or IP literal'
);
ok(
    $images{'userinfo-invalid-idn'} && !exists $images{'userinfo-invalid-idn'}{src},
    'an absolute image URL with userinfo still rejects a malformed internationalized hostname'
);
is_deeply(
    $images{'invalid-idn-srcset'},
    { alt => 'invalid-idn-srcset', src => 'https://images.example.test/fallback.jpg' },
    'malformed responsive image URL falls back to src'
);
is(
    $images{'relative-idn-srcset'}{srcset},
    '//example.xn--p1ai/%E7%8C%AB.jpg 1x, //xn--e1afmkfd.xn--p1ai/%E5%A4%A7.jpg 2x',
    'scheme-relative srcset candidates are normalized without changing their descriptors'
);
is_deeply(
    $images{'relative-invalid-idn-srcset'},
    { alt => 'relative-invalid-idn-srcset', src => 'https://images.example.test/fallback.jpg' },
    'a malformed scheme-relative candidate drops the entire srcset'
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
is(
    $links{'escaped-idn'}{href},
    'https://example.xn--p1ai/path',
    'absolute link decodes hostname escapes before IDNA conversion'
);
is(
    $links{'escaped-utf8-idn'}{href},
    'https://xn--e1afmkfd.xn--p1ai/path',
    'scheme-relative link decodes escaped UTF-8 alongside literal UTF-8 in the hostname'
);

for my $invalid_host (qw(delimiter control whitespace bad-escape bad-label bad-utf8)) {
    my $link = $links{"idn-host-$invalid_host"};
    ok( $link && !exists $link->{href},
        "internationalized hostname with $invalid_host loses href" );
}
is(
    $links{userinfo}{href},
    'https://jos%C3%A9@example.com/photo.jpg',
    'absolute link escapes its username with an ASCII hostname'
);
is(
    $links{'userinfo-escaped-host'}{href},
    'https://jos%C3%A9@%65xample.com/path',
    'escaping the username preserves an existing escape in a valid ASCII hostname'
);
is( $links{'userinfo-escaped-idn'}{href},
    $userinfo_escaped_idn_url,
    'link escapes its username and converts a fully percent-escaped internationalized hostname' );

for my $invalid_host (qw(delimiter control bad-escape)) {
    my $link = $links{"userinfo-host-$invalid_host"};
    ok( $link && !exists $link->{href}, "hostname with $invalid_host loses href" );
}
is(
    $links{'userinfo-idn'}{href},
    'http://jos%C3%A9@xn--e1afmkfd.xn--p1ai/%D0%BF%D1%83%D1%82%D1%8C.jpg',
    'absolute link escapes its username and path and converts the internationalized hostname'
);
is(
    $links{'userinfo-relative'}{href},
    'https://jos%C3%A9@example.com/photo.jpg',
    'scheme-relative link escapes its username before resolution'
);
ok(
    $links{'userinfo-invalid-idn'} && !exists $links{'userinfo-invalid-idn'}{href},
    'a scheme-relative link with userinfo still rejects a malformed internationalized hostname'
);
ok(
    $links{'absolute-invalid-idn'} && !exists $links{'absolute-invalid-idn'}{href},
    'an absolute link with a malformed internationalized hostname loses href'
);

ok( $images{unsafe} && !length( $images{unsafe}{src} // '' ), 'javascript image URL is stripped' );
ok( $images{unsafe} && !exists $images{unsafe}{srcset},       'data URL in srcset is stripped' );
ok(
    $links{unsafe} && !exists $links{unsafe}{href},
    'entity-obfuscated javascript link is stripped'
);
ok( $links{data} && !exists $links{data}{href}, 'data link is stripped' );

my $empty_href_html = '<a href="">Current page</a>';
LJ::CleanHTML::clean_event( \$empty_href_html, { preformatted => 1 } );
like( $empty_href_html, qr{<a\b[^>]*\bhref=""[^>]*>Current page</a>}, 'empty href is preserved' );

my $whitespace_href_html = '<a href="   ">Whitespace link</a>';
LJ::CleanHTML::clean_event( \$whitespace_href_html, { preformatted => 1 } );
like(
    $whitespace_href_html,
    qr{<a\b[^>]*\bhref=""[^>]*>Whitespace link</a>},
    'whitespace-only href becomes an empty href'
);

my $malformed_href_html = '<a href="http://пример..рф/">Malformed hostname</a>';
LJ::CleanHTML::clean_event( \$malformed_href_html, { preformatted => 1 } );
my $malformed_href_parser = HTML::TokeParser->new( \$malformed_href_html );
my $malformed_href_link   = $malformed_href_parser->get_tag('a');
ok(
    $malformed_href_link && !exists $malformed_href_link->[1]{href},
    'malformed internationalized href is removed rather than emptied'
);

my $placeholder_html =
    '<img src="http://пример..рф/x.jpg"><img src="https://example.test/x.jpg">';
LJ::CleanHTML::clean_event( \$placeholder_html, { preformatted => 1, extractimages => 1 } );
my $placeholder_parser = HTML::TokeParser->new( \$placeholder_html );
my @placeholder_urls;
while ( my $tag = $placeholder_parser->get_tag('a') ) {
    push @placeholder_urls, $tag->[1]{href} if ( $tag->[1]{class} // '' ) eq 'ljimgplaceholder';
}
is_deeply(
    \@placeholder_urls,
    ['https://example.test/x.jpg'],
    'image extraction only emits a linked placeholder for a usable URL'
);

my $character_html = '<img src="https://images.example.test/猫&#x1F600;.jpg">';
LJ::CleanHTML::clean_event( \$character_html, { preformatted => 1 } );
like(
    $character_html,
    qr{src="https://images\.example\.test/%E7%8C%AB%F0%9F%98%80\.jpg"},
    'cleaner also encodes the correct URL from a Perl character string'
);

my $byte_html = '<span title="caf&eacute;">Cafe</span>';
LJ::CleanHTML::clean_event( \$byte_html, { preformatted => 1 } );
like( $byte_html, qr{title="caf\xC3\xA9"}, 'cleaner decodes a non-URL attribute entity as UTF-8' );

for my $codepoint ( 0xAD, 0x200B, 0x2060, 0xFE0F, 0xFEFF, 0xE0100 ) {
    my $url = encode_utf8( 'https://exam' . chr($codepoint) . 'ple.com/' );
    is( LJ::CleanHTML::https_url($url),
        'https://example.com/',
        sprintf( 'image URL strips literal U+%04X from the hostname', $codepoint ) );
}
for my $invalid ( '%00', '%1F', '%7F', '%20', "\x{200D}", "\x{FF0F}", "\x{2024}" ) {
    is( LJ::CleanHTML::https_url("https://exam%C2%AD${invalid}ple.com/"),
        '', 'image URL still rejects invalid hostname characters alongside a soft hyphen' );
}

my $character_relative_html = '<p>猫<img src="../猫&#x1F600;.jpg"></p>';
LJ::CleanHTML::resolve_relative_urls( \$character_relative_html,
    'https://news.example.test/posts/item' );
is(
    $character_relative_html,
    '<p>猫<img src="https://news.example.test/%E7%8C%AB%F0%9F%98%80.jpg"></p>',
    'relative resolution preserves surrounding characters and escapes the URL'
);

done_testing();
