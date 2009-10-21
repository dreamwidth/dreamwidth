# -*-perl-*-
use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
use LJ::ParseFeed;
require 'ljlib.pl';

#plan tests => 16;
plan skip_all => 'Fix this test!';

## These test cases are based roughly on Phil Ringnalda's eight <title> conformance tests:
##    <http://weblog.philringnalda.com/2005/12/18/who-knows-a-title-from-a-hole-in-the-ground>

my $testfeed = sub {
    my $entrybody = shift;

    my $contents = qq{
        <feed xmlns="http://www.w3.org/2005/Atom">
          <id>testing:atom:feed</id>
          <title>test atom feed</title>
          <author><name>testing</name></author>
          <link rel="alternate" type="text/html" href="$LJ::SITEROOT" />
          <link rel="self" type="text/xml" href="$LJ::SITEROOT" />
          <updated>2007-01-08T23:40:33Z</updated>
          <entry>
            <id>testing:atom:feed:entry</id>
            <updated>2006-09-14T07:39:07Z</updated>
            $entrybody
            <link rel=\"alternate\" type=\"text/html\" href=\"$LJ::SITEROOT\" />
          </entry>
        </feed>
    };

    my ($feed, $error) = LJ::ParseFeed::parse_feed($contents);
    return $feed->{'items'}->[0];

};

my $testtitle = sub {
    my $titleelem = shift;

    my $contents = qq{
        $titleelem
        <content type="html">content content content</content>
    };

    my $item = $testfeed->($contents);
    return $item->{'subject'};
};

my $testcontent = sub {
    my $contentelem = shift;

    my $contents = qq{
        <title>kumquats cheese blogosphere</title>
        $contentelem
    };

    my $item = $testfeed->($contents);
    return $item->{'text'};
};

#$testtitle->("<title>&amp;lt;title&amp;gt;</title>");

# When type="html", the contents should be escaped HTML
# The correct result is the content with one level of escaping removed
is($testtitle->(qq{<title type="html"><![CDATA[&lt;title>]]></title>}), "&lt;title>", "Title: HTML + CDATA");
is($testtitle->(qq{<title type="html">&amp;lt;title></title>}), "&lt;title>", "Title: HTML + Entities");
is($testtitle->(qq{<title type="html">&#38;lt;title></title>}), "&lt;title>", "Title: HTML + Numeric character references");

# When type="text", the contents are escaped plain text
# Since LiveJournal expects HTML in the subject field, parsefeed should
# be returning the text with HTML escaping applied.
is($testtitle->(qq{<title type="text"><![CDATA[<title>]]></title>}), "&lt;title&gt;", "Title: Text + CDATA");
is($testtitle->(qq{<title type="text">&lt;title></title>}), "&lt;title&gt;", "Title: Text + Entity");
is($testtitle->(qq{<title type="text">&#60;title></title>}), "&lt;title&gt;", "Title: Text + Numeric character references");

# When type="xhtml" the content is interpreted as normal XML with no special
# escaping. Therefore it should be returned basically verbatim, with no
# extra escaping or de-escaping.
is($testtitle->(qq{<title type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&lt;title></div></title>}), qq{<div xmlns="http://www.w3.org/1999/xhtml">&lt;title></div>}, "Title: XHTML + Entities");
is($testtitle->(qq{<title type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&#60;title></div></title>}), qq{<div xmlns="http://www.w3.org/1999/xhtml">&#60;title></div>}, "Title: XHTML + Numeric character references");

# Now do the same eight tests but on the entry content instead
is($testcontent->(qq{<content type="html"><![CDATA[&lt;content>]]></content>}), "&lt;content>", "Content: HTML + CDATA");
is($testcontent->(qq{<content type="html">&amp;lt;content></content>}), "&lt;content>", "Content: HTML + Entities");
is($testcontent->(qq{<content type="html">&#38;lt;content></content>}), "&lt;content>", "Content: HTML + Numeric character references");
is($testcontent->(qq{<content type="text"><![CDATA[<content>]]></content>}), "&lt;content&gt;", "Content: Text + CDATA");
is($testcontent->(qq{<content type="text">&lt;content></content>}), "&lt;content&gt;", "Content: Text + Entity");
is($testcontent->(qq{<content type="text">&#60;content></content>}), "&lt;content&gt;", "Content: Text + Numeric character references");
is($testcontent->(qq{<content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&lt;content></div></content>}), qq{<div xmlns="http://www.w3.org/1999/xhtml">&lt;content></div>}, "Content: XHTML + Entities");
is($testcontent->(qq{<content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&#60;content></div></content>}), qq{<div xmlns="http://www.w3.org/1999/xhtml">&#60;content></div>}, "Content: XHTML + Numeric character references");

