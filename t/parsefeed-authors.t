# t/parsefeed-authors.t
#
# Test LJ::ParseFeed with various author tags.
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

use Test::More tests => 10;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::ParseFeed;

my $feed_rss = q {
<rss version='2.0'
xmlns:lj='http://www.livejournal.org/rss/lj/1.0/'
xmlns:dw='http://www.livejournal.org/rss/lj/1.0/'
xmlns:atom10='http://www.w3.org/2005/Atom'
xmlns:dc='http://purl.org/dc/elements/1.1/'>
<channel>
<title>Title</title>
<link>http://examplecomm.dream.fu/</link>
<description>Title - Dreamwidth Studios</description>
<lastBuildDate>Thu, 03 Feb 2011 17:00:43 GMT</lastBuildDate>
<generator>LiveJournal / Dreamwidth Studios</generator>
<lj:journal>examplecomm</lj:journal>
<lj:journaltype>community</lj:journaltype>
<atom10:link rel='self' href='http://examplecomm.dream.fu/data/rss' />
<image>
<url>http://www.dream.fu/userpic/1/2</url>
<title>Title</title>
<link>http://examplecomm.dream.fu/</link>
<width>100</width>
<height>100</height>
</image>

<item>
<guid isPermaLink='true'>http://examplecomm.dream.fu/12345.html</guid>
<pubDate>Thu, 03 Feb 2011 17:00:43 GMT</pubDate>
<title>yo</title>
<link>http://examplecomm.dream.fu/12345.html</link>
<description>yo</description>
<comments>http://examplecomm.dream.fu/12345.html</comments>
<dc:creator>example-dc-creator</dc:creator>
</item>

<item>
<guid isPermaLink='true'>http://examplecomm.dream.fu/123.html</guid>
<pubDate>>Wed, 24 Nov 2010 06:52:33 GMT</pubDate>
<title>yo</title>
<link>http://examplecomm.dream.fu/123.html</link>
<description>yo</description>
<comments>http://examplecomm.dream.fu/123.html</comments>
<lj:poster>example-lj-poster</lj:poster>
<lj:security>public</lj:security>
<lj:reply-count>0</lj:reply-count>
</item>

<item>
<guid isPermaLink='true'>http://examplecomm.dream.fu/456.html</guid>
<pubDate>>Wed, 24 Jun 2010 06:52:33 GMT</pubDate>
<title>yo</title>
<link>http://examplecomm.dream.fu/456.html</link>
<description>yo</description>
<comments>http://examplecomm.dream.fu/456.html</comments>
<dw:poster>example-dw-poster</dw:poster>
<dw:security>public</dw:security>
<dw:reply-count>0</dw:reply-count>
</item>

</channel>
</rss>};

my $feed_atom = q {<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dw="https://www.dreamwidth.org" xmlns:lj="http://www.livejournal.com">
<title>Feed title</title>
<link rel="alternate" type="text/html" href="http://example.com/feed/atom" />
<id>example:atom:feed</id>
<updated>2011-01-23T17:38:49-08:00</updated>
<author>
<name>example-feed-author</name>
</author>

<entry>
<title>Item 1</title>
<link rel="alternate" type="text/html" href="http://example.com/feed/atom/1" />
<id>1</id>
<published>2011-01-23T13:58:08-08:00</published>
<updated>2011-01-23T13:58:08-08:00</updated>
<author>
<name>example-atom-author</name>
</author>
<content type="html">foo</content>
</entry>

<entry>
<title>Item 2</title>
<link rel="alternate" type="text/html" href="http://example.com/feed/atom/2" />
<id>2</id>
<published>2011-01-23T13:59:55-08:00</published>
<updated>2011-01-23T13:59:55-08:00</updated>
<dw:poster user="example-dw-poster"/>
<content type="html">bar</content>
</entry>

<entry>
<title>Item 3</title>
<link rel="alternate" type="text/html" href="http://example.com/feed/atom/3" />
<id>3</id>
<published>2011-01-23T17:38:49-08:00</published>
<updated>2011-01-23T17:38:49-08:00</updated>
<lj:poster user="example-lj-poster"/>
<content type="html">baz</content>
</entry>

<entry>
<title>Item 4</title>
<link rel="alternate" type="text/html" href="http://example.com/feed/atom/4" />
<id>4</id>
<published>2011-01-23T18:38:49-08:00</published>
<updated>2011-01-23T18:38:49-08:00</updated>
<content type="html">quux</content>
</entry>

<entry>
<title>Item 5</title>
<link rel="alternate" type="text/html" href="http://example.com/feed/atom/5" />
<id>5</id>
<published>2011-01-23T19:38:49-08:00</published>
<updated>2011-01-23T19:38:49-08:00</updated>
<lj:poster user="prefer-lj-poster"/>
<author>
<name>bogus-atom-author</name>
</author>
<content type="html">blech</content>
</entry>

</feed>};

my ( $parse_rss, $rss_error ) = LJ::ParseFeed::parse_feed( $feed_rss, "rss" );
is( $rss_error, undef, "RSS parse OK" );

SKIP: {
    skip "RSS parse failed", 3 if $rss_error;
    is( $parse_rss->{items}->[0]->{author}, "example-dc-creator", "<dc:creator> tag" );
    is( $parse_rss->{items}->[1]->{author}, "example-lj-poster",  "<lj:poster> tag" );
    is( $parse_rss->{items}->[2]->{author}, "example-dw-poster",  "<dw:poster> tag" );
}

my ( $parse_atom, $atom_error ) = LJ::ParseFeed::parse_feed( $feed_atom, "atom" );
is( $atom_error, undef, "Atom parse OK" );

SKIP: {
    skip "Atom parse failed", 5 if $atom_error;
    is( $parse_atom->{items}->[0]->{author}, "example-atom-author", "item <author> tag" );
    is( $parse_atom->{items}->[1]->{author}, "example-dw-poster",   "<dw:poster> tag" );
    is( $parse_atom->{items}->[2]->{author}, "example-lj-poster",   "<lj:poster> tag" );
    is( $parse_atom->{items}->[3]->{author}, "example-feed-author", "feed <author> tag" );
    is( $parse_atom->{items}->[4]->{author},
        "prefer-lj-poster", "both <lj:poster> and <author> tags" );
}
