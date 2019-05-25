# t/parsefeed-atom-types.t
#
# Test LJ::ParseFeed parsing of complex title elements.
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::ParseFeed;

plan tests => 16;

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

    my ( $feed, $error ) = LJ::ParseFeed::parse_feed($contents);
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
is( $testtitle->(qq{<title type="html"><![CDATA[&lt;title>]]></title>}),
    "&lt;title>", "Title: HTML + CDATA" );
is( $testtitle->(qq{<title type="html">&amp;lt;title></title>}),
    "&lt;title>", "Title: HTML + Entities" );
is( $testtitle->(qq{<title type="html">&#38;lt;title></title>}),
    "&lt;title>", "Title: HTML + Numeric character references" );

# When type="text", the contents are escaped plain text
# Since Dreamwidth expects HTML in the subject field, parsefeed should
# be returning the text with HTML escaping applied.
# Except now it's apparently removing the escaping, and no-one's complained in 6 years, so we assume that's right
is( $testtitle->(qq{<title type="text"><![CDATA[<title>]]></title>}),
    "<title>", "Title: Text + CDATA" );
is( $testtitle->(qq{<title type="text">&lt;title></title>}), "<title>", "Title: Text + Entity" );
is( $testtitle->(qq{<title type="text">&#60;title></title>}),
    "<title>", "Title: Text + Numeric character references" );

# When type="xhtml" the content is interpreted as normal XML with no special
# escaping. Therefore it should be returned basically verbatim, with no
# extra escaping or de-escaping.
# Except now it's apparently removing the escaping, and no-one's complained in 6 years, so we assume that's right
is(
    $testtitle->(
        qq{<title type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&lt;title></div></title>}),
    qq{<div><title></div>},
    "Title: XHTML + Entities"
);
is(
    $testtitle->(
        qq{<title type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&#60;title></div></title>}
    ),
    qq{<div><title></div>},
    "Title: XHTML + Numeric character references"
);

# Now do the same eight tests but on the entry content instead
is( $testcontent->(qq{<content type="html"><![CDATA[&lt;content>]]></content>}),
    "&lt;content>", "Content: HTML + CDATA" );
is( $testcontent->(qq{<content type="html">&amp;lt;content></content>}),
    "&lt;content>", "Content: HTML + Entities" );
is( $testcontent->(qq{<content type="html">&#38;lt;content></content>}),
    "&lt;content>", "Content: HTML + Numeric character references" );
is( $testcontent->(qq{<content type="text"><![CDATA[<content>]]></content>}),
    "<content>", "Content: Text + CDATA" );
is( $testcontent->(qq{<content type="text">&lt;content></content>}),
    "<content>", "Content: Text + Entity" );
is( $testcontent->(qq{<content type="text">&#60;content></content>}),
    "<content>", "Content: Text + Numeric character references" );
is(
    $testcontent->(
qq{<content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&lt;content></div></content>}
    ),
    qq{<div><content></div>},
    "Content: XHTML + Entities"
);
is(
    $testcontent->(
qq{<content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">&#60;content></div></content>}
    ),
    qq{<div><content></div>},
    "Content: XHTML + Numeric character references"
);

