# t/parsefeed-atom-link3.t
#
# Test LJ::ParseFeed handling of xml:base in atom feeds.
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

use Test::More tests => 12;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::ParseFeed;

#  These tests check for correct handling of xml:base

# This is taken verbatim from Aristotle Pagaltzis's set of test cases:
#    <http://plasmasturm.org/attic/atom-tests/xmlbase.atom>

# Here's a giant, obnoxious hunk of XML!
my $contents = qq{
<feed xmlns="http://www.w3.org/2005/Atom" xml:base="http://example.org/tests/">
    <title>xml:base support tests</title>
    <subtitle type="html">All alternate links should point to &lt;code>http://example.org/tests/base/result.html&lt;/code>; all links in content should point where their label says.</subtitle>
    <link href="http://example.org/tests/base/result.html"/>
    <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base</id>
    <updated>2006-01-17T12:35:16+01:00</updated>

    <entry>
        <title>1: Alternate link: Absolute URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test1</id>
        <updated>2006-01-17T12:35:16+01:00</updated>
    </entry>

    <entry>
        <title>2: Alternate link: Host-relative absolute URL</title>
        <link href="/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test2</id>
        <updated>2006-01-17T12:35:15+01:00</updated>
    </entry>

    <entry>
        <title>3: Alternate link: Relative URL</title>
        <link href="base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test3</id>
        <updated>2006-01-17T12:35:14+01:00</updated>
    </entry>

    <entry>
        <title>4: Alternate link: Relative URL with parent directory component</title>
        <link href="../tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test4</id>
        <updated>2006-01-17T12:35:13+01:00</updated>
    </entry>

    <entry>
        <title>5: Content: Absolute URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test5</id>
        <content type="html">&lt;a href="http://example.org/tests/base/result.html"&gt;http://example.org/tests/base/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:12+01:00</updated>
    </entry>

    <entry>
        <title>6: Content: Host-relative URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test6</id>
        <content type="html">&lt;a href="/tests/base/result.html"&gt;http://example.org/tests/base/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:11+01:00</updated>
    </entry>

    <entry>
        <title>7: Content: Relative URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test7</id>
        <content type="html">&lt;a href="base/result.html"&gt;http://example.org/tests/base/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:10+01:00</updated>
    </entry>

    <entry>
        <title>8: Content: Relative URL with parent directory component</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test8</id>
        <content type="html">&lt;a href="../tests/base/result.html"&gt;http://example.org/tests/base/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:9+01:00</updated>
    </entry>

    <entry xml:base="http://example.org/tests/entrybase/">
        <title type="html">9: Content, &lt;code>&amp;lt;entry>&lt;/code> has base: Absolute URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test9</id>
        <content type="html">&lt;a href="http://example.org/tests/entrybase/result.html"&gt;http://example.org/tests/entrybase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:8+01:00</updated>
    </entry>

    <entry xml:base="http://example.org/tests/entrybase/">
        <title type="html">10: Content, &lt;code>&amp;lt;entry>&lt;/code> has base: Host-relative URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test10</id>
        <content type="html">&lt;a href="/tests/entrybase/result.html"&gt;http://example.org/tests/entrybase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:7+01:00</updated>
    </entry>

    <entry xml:base="http://example.org/tests/entrybase/">
        <title type="html">11: Content, &lt;code>&amp;lt;entry>&lt;/code> has base: Relative URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test11</id>
        <content type="html">&lt;a href="result.html"&gt;http://example.org/tests/entrybase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:6+01:00</updated>
    </entry>

    <entry xml:base="http://example.org/tests/entrybase/">
        <title type="html">12: Content, &lt;code>&amp;lt;entry>&lt;/code> has base: Relative URL with parent directory component</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test12</id>
        <content type="html">&lt;a href="../entrybase/result.html"&gt;http://example.org/tests/entrybase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:5+01:00</updated>
    </entry>

    <entry>
        <title type="html">13: Content, &lt;code>&amp;lt;content>&lt;/code> has base: Absolute URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test13</id>
        <content type="html" xml:base="http://example.org/tests/contentbase/">&lt;a href="http://example.org/tests/contentbase/result.html"&gt;http://example.org/tests/contentbase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:4+01:00</updated>
    </entry>

    <entry>
        <title type="html">14: Content, &lt;code>&amp;lt;content>&lt;/code> has base: Host-relative URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test14</id>
        <content type="html" xml:base="http://example.org/tests/contentbase/">&lt;a href="/tests/contentbase/result.html"&gt;http://example.org/tests/contentbase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:3+01:00</updated>
    </entry>

    <entry>
        <title type="html">15: Content, &lt;code>&amp;lt;content>&lt;/code> has base: Relative URL</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test15</id>
        <content type="html" xml:base="http://example.org/tests/contentbase/">&lt;a href="result.html"&gt;http://example.org/tests/contentbase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:2+01:00</updated>
    </entry>

    <entry>
        <title type="html">16: Content, &lt;code>&amp;lt;content>&lt;/code> has base: Relative URL with parent directory component</title>
        <link href="http://example.org/tests/base/result.html"/>
        <id>tag:plasmasturm.org,2005:Atom-Tests:xml-base:Test16</id>
        <content type="html" xml:base="http://example.org/tests/contentbase/">&lt;a href="../contentbase/result.html"&gt;http://example.org/tests/contentbase/result.html&lt;/a&gt;</content>
        <updated>2006-01-17T12:35:1+01:00</updated>
    </entry>

</feed>
};

my ( $feed, $error ) = LJ::ParseFeed::parse_feed($contents);

foreach my $item ( @{ $feed->{items} } ) {
    is( $item->{link}, "http://example.org/tests/base/result.html", $item->{subject} );
}

