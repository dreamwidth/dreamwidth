# -*-perl-*-
use strict;

use Test::More tests => 25;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::CleanHTML;

my ( $orig_post, $clean_post );

my $clean = sub {
    my ( $opts ) = @_;
    LJ::CleanHTML::clean_embed( \$orig_post, $opts );
};

note("no content");
$orig_post  = qq{};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "empty" );


note("simple object");
$orig_post  = qq{<object></object>};
$clean_post = qq{<object></object>};
$clean->();
is( $orig_post, $clean_post, "basic <object>" );

note("<object> and <embed> tags, params different case");
$orig_post  = qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowScrIpTaccess" value="always"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowScrIptAccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean_post = qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowScrIpTaccess" value="sameDomain"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="sameDomain" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean->();
is( $orig_post, $clean_post, "<object> and <embed> tags" );

note("<object> and <embed> tags");
$orig_post  = qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean_post = qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="sameDomain"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="sameDomain" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean->();
is( $orig_post, $clean_post, "<object> and <embed> tags" );

note("<object> and <embed> tags, keep never");
$orig_post  = qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="never"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="never" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean_post = qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="never"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="never" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean->();
is( $orig_post, $clean_post, "<object> and <embed> tags" );


note("script tag");
$orig_post = qq{<object><script>bar</script></object>};
$clean_post = qq{<object></object>};
$clean->();
is( $orig_post, $clean_post, "<script> tag" );


note("iframe tag");
$orig_post = qq{<iframe src="http://example.com/randompage"></iframe>};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag" );


my $id = "ABC123abc-_";
note("trusted site: youtube");
$orig_post = qq{<object width="640" height="385"><param name="movie" value="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean_post = qq{<object width="640" height="385"><param name="movie" value="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="sameDomain"></param><embed src="http://www.youtube.com/v/$id?fs=1&amp;hl=en_US" type="application/x-shockwave-flash" allowscriptaccess="sameDomain" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean->();
is( $orig_post, $clean_post, "old-style embeds" );


$orig_post = qq{<iframe src="http://www.youtube.com/"></iframe>};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: youtube (not an embed url)" );

$orig_post = qq{<iframe src="http://www.youtube.com/embed/123"></iframe>};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: youtube (invalid id)" );


$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id"></iframe>};
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id"></iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: www.youtube.com (iframe embed code)" );

$orig_post = qq{<iframe src="http://youtube.com/embed/$id"></iframe>};
$clean_post = qq{<iframe src="http://youtube.com/embed/$id"></iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: youtube.com (iframe embed code)" );

$orig_post = qq{<iframe src="http://abc.youtube.com/embed/$id"></iframe>};
$clean_post = qq{<iframe src="http://abc.youtube.com/embed/$id"></iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: abc.youtube.com (iframe embed code)" );

$orig_post = qq{<iframe src="http://www.not-youtube.com/embed/$id"></iframe>};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: not-youtube.com" );

$orig_post = qq{<iframe src="http://www.not-youtube.com/embed/$id"></iframe>};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: www.not-youtube.com" );

$orig_post = qq{<iframe src="http://youtube.com/embed/$id"></iframe> <iframe src="http://www.not-youtube.com/embed/$id"></iframe>};
$clean_post = qq{<iframe src="http://youtube.com/embed/$id"></iframe> };
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: youtube.com (iframe embed code)" );


# HTML 4 says an iframe can contain fallback content
# HTML 5 says an iframe contains no fallback content
# this doesn't actually concern itself with either. We just want to make sure
# that you can't sneak in malicious code by wrapping it in an iframe from a trusted domain
# (iframe contents are treated as text nodes, not HTML tokens, so these aren't stripped, merely escaped)
$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id"><iframe src="http://not-youtube.com/embed/$id"></iframe></iframe>};
# inner iframe tag closes the iframe; outer tag is discarded
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id">&lt;iframe src="http://not-youtube.com/embed/$id"&gt;</iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: nested trusted and untrusted" );

$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id"><script type="text/javascript">alert("hi");</script></iframe>};
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id">&lt;script type="text/javascript"&gt;alert("hi");&lt;/script&gt;</iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: nested trusted with script tags" );

$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id"><style type="text/css">alert(document["coo"+"kies"])</style></iframe>};
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id">&lt;style type="text/css"&gt;alert(document["coo"+"kies"])&lt;/style&gt;</iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: nested trusted with style tags" );


# and also make sure we are cleaning the iframe parameters properly
$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id" height="100" onload="alert('hi!');" width="200"></iframe>};
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id" height="100" width="200"></iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: trusted with malicious parameters" );

$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id" height="100" style="javascript:alert('hi')" width="200"></iframe>};
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id" height="100" width="200"></iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: trusted with malicious parameters" );

$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id" height="100" style="position: absolute;" width="200"></iframe>};
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id" height="100" width="200"></iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: trusted with malicious parameters" );


# not sure if we need to do anything about this
$orig_post = qq{<iframe src="http://www.youtube.com/embed/$id" width="1" height="1"></iframe>};
$clean_post = qq{<iframe src="http://www.youtube.com/embed/$id" width="1" height="1"></iframe>};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: trying to make it invisible" );


# what if it's malformed HTML?
TODO: {
    local $TODO = "Not sure how to handle this. The HTML parser treats iframe like it can't contain other tags, so anything up to a closing iframe tag is text. If it's self-closed or not closed, then everything up to the end is considered text. Curretly this means that all text after an unclosed iframe is wiped out and not saved to the db -- see LJ::parse_embed_module";
    $orig_post = qq{<iframe src="http://www.youtube.com/embed/$id" />end};
    $clean_post = qq{<iframe src="http://www.youtube.com/embed/$id"></iframe>end};
    $clean->();
    is( $orig_post, $clean_post, "<iframe> tag: self-closing trusted" );
}

$orig_post = qq{<iframe src="http://not-youtube.com/embed/$id" />end};
$clean_post = qq{end};
$clean->();
is( $orig_post, $clean_post, "<iframe> tag: self-closing untrusted" );


