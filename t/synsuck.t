# t/synsuck.t
#
# Test LJ::SynSuck.
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

use Test::More tests => 24;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::SynSuck;


sub err {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ( $content, $type, $test ) = @_;

    subtest "$test (expect err)" => sub {
        plan tests => 2;

        my ( $ok, $rv ) = LJ::SynSuck::parse_items_from_feed( $content );
        ok( ! $ok, "returned status is an error" );
        is( $rv->{type}, $type, $rv->{message} ? "$rv->{message}" : "(no response message)" );
    };
}

sub success {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ( $content, $test, %opts ) = @_;

    my ( $ok, $rv );

    subtest "$test (expect ok)" => sub {
        plan tests => 1;

        ( $ok, $rv ) = LJ::SynSuck::parse_items_from_feed( $content, $opts{num_items} );
        ok( $ok, "returned status is ok" );
        die $rv->{message} unless $ok;
    };

    return @{$rv->{items}};
};


note("Error");
{
    my $content = q{<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0">
        <channel>
            <title>Blah
        </channel>
    </rss>
    };

    err( $content, "parseerror", "Mismatched tags" );
}

note("No items");
{
    my $content = q{<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <pubDate>Mon, 24 Jan 2011 00:00:00 GMT</pubDate>
    </channel>
    </rss>
    };

    err( $content, "noitems", "Empty feed" );
}


note("RSS pubDate - descending");
{
    my $content = q {<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <pubDate>Mon, 24 Jan 2011 11:06:54 GMT</pubDate>

        <item>
            <title>Item 3</title>
            <link>http://example.com/feed/3</link>
            <description>baz</description>
            <author>someone</author>
            <guid isPermaLink="false">3</guid>
            <pubDate>Mon, 24 Jan 2011 03:00:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 2</title>
            <link>http://example.com/feed/2</link>
            <description>bar</description>
            <author>someone</author>
            <guid isPermaLink="false">2</guid>
            <pubDate>Sun, 23 Jan 2011 05:30:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 1</title>
            <link>http://example.com/feed/1</link>
            <description>foo</description>
            <author>someone</author>
            <guid isPermaLink="false">1</guid>
            <pubDate>Mon, 17 Jan 2011 20:00:00 GMT</pubDate>
        </item>

    </channel>
    </rss>};

    my @items = success( $content, "Correct order from RSS pubDate (originally descending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 1, 2, 3 ], "Items from feed returned in correct order (originally in descending order)" );
}

note("RSS pubDate - ascending");
{
    my $content = q {<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <pubDate>Mon, 24 Jan 2011 11:06:54 GMT</pubDate>

        <item>
            <title>Item 1</title>
            <link>http://example.com/feed/1</link>
            <description>foo</description>
            <author>someone</author>
            <guid isPermaLink="false">1</guid>
            <pubDate>Mon, 17 Jan 2011 20:00:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 2</title>
            <link>http://example.com/feed/2</link>
            <description>bar</description>
            <author>someone</author>
            <guid isPermaLink="false">2</guid>
            <pubDate>Sun, 23 Jan 2011 05:30:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 3</title>
            <link>http://example.com/feed/3</link>
            <description>baz</description>
            <author>someone</author>
            <guid isPermaLink="false">3</guid>
            <pubDate>Mon, 24 Jan 2011 03:00:00 GMT</pubDate>
        </item>
    </channel>
    </rss>};

    my @items = success( $content, "Correct order from RSS pubDate (originally ascending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 1, 2, 3 ], "Items from feed returned in correct order (originally in ascending order)" );
}

note( "Atom - descending" );
{
    my $content = q{<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <title>Feed title</title>
        <link rel="alternate" type="text/html" href="http://example.com/feed/atom" />
        <id>example:atom:feed</id>
        <updated>2011-01-23T17:38:49-08:00</updated>

        <entry>
            <title>Item 3</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/3" />
            <id>3</id>
            <published>2011-01-23T17:38:49-08:00</published>
            <updated>2011-01-23T17:38:49-08:00</updated>
            <author><name>someone</name></author>
            <content type="html">baz</content>
        </entry>

        <entry>
            <title>Item 2</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/2" />
            <id>2</id>
            <published>2011-01-23T13:59:55-08:00</published>
            <updated>2011-01-23T13:59:55-08:00</updated>
            <author><name>someone</name></author>
            <content type="html">bar</content>
        </entry>

        <entry>
            <title>Item 1</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/1" />
            <id>1</id>
            <published>2011-01-23T13:58:08-08:00</published>
            <updated>2011-01-23T13:58:08-08:00</updated>
            <author><name>someone</name></author>
            <content type="html">foo</content>
        </entry>
    </feed>};

    my @items = success( $content, "Correct order from Atom (originally descending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 1, 2, 3 ], "Items from feed returned in correct order (originally in descending order)" );
}

note( "Atom - ascending" );
{
    my $content = q{<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <title>Feed title</title>
        <link rel="alternate" type="text/html" href="http://example.com/feed/atom" />
        <id>example:atom:feed</id>
        <updated>2011-01-23T17:38:49-08:00</updated>

        <entry>
            <title>Item 1</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/1" />
            <id>1</id>
            <published>2011-01-23T13:58:08-08:00</published>
            <updated>2011-01-23T13:58:08-08:00</updated>
            <author><name>someone</name></author>
            <content type="html">foo</content>
        </entry>

        <entry>
            <title>Item 2</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/2" />
            <id>2</id>
            <published>2011-01-23T13:59:55-08:00</published>
            <updated>2011-01-23T13:59:55-08:00</updated>
            <author><name>someone</name></author>
            <content type="html">bar</content>
        </entry>

        <entry>
            <title>Item 3</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/3" />
            <id>3</id>
            <published>2011-01-23T17:38:49-08:00</published>
            <updated>2011-01-23T17:38:49-08:00</updated>
            <author><name>someone</name></author>
            <content type="html">baz</content>
        </entry>

    </feed>};

    my @items = success( $content, "Correct order from Atom (originally ascending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 1, 2, 3 ], "Items from feed returned in correct order (originally in ascending order)" );
}

note("RSS dc:date - descending");
{
    my $content = q {<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <dc:date>2011-01-24T11:06:54Z</dc:date>

        <item>
            <title>Item 3</title>
            <link>http://example.com/feed/3</link>
            <description>baz</description>
            <author>someone</author>
            <guid isPermaLink="false">3</guid>
            <dc:date>2011-01-24T03:00:00Z</dc:date>
        </item>

        <item>
            <title>Item 2</title>
            <link>http://example.com/feed/2</link>
            <description>bar</description>
            <author>someone</author>
            <guid isPermaLink="false">2</guid>
            <dc:date>2011-01-23T05:30:00Z</dc:date>
        </item>

        <item>
            <title>Item 1</title>
            <link>http://example.com/feed/1</link>
            <description>foo</description>
            <author>someone</author>
            <guid isPermaLink="false">1</guid>
            <dc:date>2011-01-17T20:00:00Z</dc:date>
        </item>

    </channel>
    </rss>};

    my @items = success( $content, "Correct order from RSS dc:date (originally descending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 1, 2, 3 ], "Items from feed returned in correct order (originally in descending order)" );
}

note("RSS dc:date - ascending");
{
    my $content = q {<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <dc:date>2011-01-24T11:06:54Z</dc:date>

        <item>
            <title>Item 1</title>
            <link>http://example.com/feed/1</link>
            <description>foo</description>
            <author>someone</author>
            <guid isPermaLink="false">1</guid>
            <dc:date>2011-01-17T20:00:00Z</dc:date>
        </item>

        <item>
            <title>Item 2</title>
            <link>http://example.com/feed/2</link>
            <description>bar</description>
            <author>someone</author>
            <guid isPermaLink="false">2</guid>
            <dc:date>2011-01-23T05:30:00Z</dc:date>
        </item>

        <item>
            <title>Item 3</title>
            <link>http://example.com/feed/3</link>
            <description>baz</description>
            <author>someone</author>
            <guid isPermaLink="false">3</guid>
            <dc:date>2011-01-24T03:00:00Z</dc:date>
        </item>
    </channel>
    </rss>};

    my @items = success( $content, "Correct order from RSS dc:date (originally ascending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 1, 2, 3 ], "Items from feed returned in correct order (originally in ascending order)" );
}

note( "Without datestamp - descending" );
{
    my $content = q{<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <title>Feed title</title>
        <link rel="alternate" type="text/html" href="http://example.com/feed/atom" />
        <id>example:atom:feed</id>
        <updated>2011-01-23T17:38:49-08:00</updated>

        <entry>
            <title>Item 3</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/3" />
            <id>3</id>
            <author><name>someone</name></author>
            <content type="html">baz</content>
        </entry>

        <entry>
            <title>Item 2</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/2" />
            <id>2</id>
            <author><name>someone</name></author>
            <content type="html">bar</content>
        </entry>

        <entry>
            <title>Item 1</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/1" />
            <id>1</id>
            <author><name>someone</name></author>
            <content type="html">foo</content>
        </entry>
    </feed>};

    my @items = success( $content, "Correct order without datestamps (originally descending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 1, 2, 3 ], "Items from feed returned in correct order (originally without datestamps in descending order)" );
}

note( "Without datestamp - ascending" );
{
    my $content = q{<?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <title>Feed title</title>
        <link rel="alternate" type="text/html" href="http://example.com/feed/atom" />
        <id>example:atom:feed</id>
        <updated>2011-01-23T17:38:49-08:00</updated>

        <entry>
            <title>Item 1</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/1" />
            <id>1</id>
            <author><name>someone</name></author>
            <content type="html">foo</content>
        </entry>

        <entry>
            <title>Item 2</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/2" />
            <id>2</id>
            <author><name>someone</name></author>
            <content type="html">bar</content>
        </entry>

        <entry>
            <title>Item 3</title>
            <link rel="alternate" type="text/html" href="http://example.com/feed/atom/3" />
            <id>3</id>
            <author><name>someone</name></author>
            <content type="html">baz</content>
        </entry>

    </feed>};

    my @items = success( $content, "Correct order without datestamps (originally ascending)" );
    is_deeply( [ map {$_->{id}} @items ], [ 3, 2, 1 ], "Items from feed returned in what we guessed is the correct order (originally without datestamps in ascending order)" );
}


note( "Active feed - too many items - descending" );
{
    my $content = q {<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <pubDate>Mon, 24 Jan 2011 11:06:54 GMT</pubDate>

        <item>
            <title>Item 3</title>
            <link>http://example.com/feed/3</link>
            <description>baz</description>
            <author>someone</author>
            <guid isPermaLink="false">3</guid>
            <pubDate>Mon, 24 Jan 2011 03:00:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 2</title>
            <link>http://example.com/feed/2</link>
            <description>bar</description>
            <author>someone</author>
            <guid isPermaLink="false">2</guid>
            <pubDate>Sun, 23 Jan 2011 05:30:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 1</title>
            <link>http://example.com/feed/1</link>
            <description>foo</description>
            <author>someone</author>
            <guid isPermaLink="false">1</guid>
            <pubDate>Mon, 17 Jan 2011 20:00:00 GMT</pubDate>
        </item>

    </channel>
    </rss>};

    my @items = success( $content, "Latest two items in the feed", num_items => 2 );
    is_deeply( [ map {$_->{id}} @items ], [ 2, 3 ], "Returned latest two items from feed (originally in descending order)" );
}

note( "Active feed - too many items - ascending" );
{
    my $content = q {<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <pubDate>Mon, 24 Jan 2011 11:06:54 GMT</pubDate>

        <item>
            <title>Item 1</title>
            <link>http://example.com/feed/1</link>
            <description>foo</description>
            <author>someone</author>
            <guid isPermaLink="false">1</guid>
            <pubDate>Mon, 17 Jan 2011 20:00:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 2</title>
            <link>http://example.com/feed/2</link>
            <description>bar</description>
            <author>someone</author>
            <guid isPermaLink="false">2</guid>
            <pubDate>Sun, 23 Jan 2011 05:30:00 GMT</pubDate>
        </item>

        <item>
            <title>Item 3</title>
            <link>http://example.com/feed/3</link>
            <description>baz</description>
            <author>someone</author>
            <guid isPermaLink="false">3</guid>
            <pubDate>Mon, 24 Jan 2011 03:00:00 GMT</pubDate>
        </item>
    </channel>
    </rss>};

    my @items = success( $content, "Latest two items in the feed", num_items => 2 );
    is_deeply( [ map {$_->{id}} @items ], [ 2, 3 ], "Returned latest two items from feed (originally in ascending order)" );
}

note( "Active feed - too many items - no datestamp ascending" );
{
    my $content = q {<?xml version="1.0" encoding="ISO-8859-1"?>
    <rss version="2.0">
    <channel>
        <title>Title</title>
        <link>http://www.example.com/</link>
        <description>Some Feed</description>
        <pubDate>Mon, 24 Jan 2011 11:06:54 GMT</pubDate>

        <item>
            <title>Item 1</title>
            <link>http://example.com/feed/1</link>
            <description>foo</description>
            <author>someone</author>
            <guid isPermaLink="false">1</guid>
        </item>

        <item>
            <title>Item 2</title>
            <link>http://example.com/feed/2</link>
            <description>bar</description>
            <author>someone</author>
            <guid isPermaLink="false">2</guid>
        </item>

        <item>
            <title>Item 3</title>
            <link>http://example.com/feed/3</link>
            <description>baz</description>
            <author>someone</author>
            <guid isPermaLink="false">3</guid>
        </item>
    </channel>
    </rss>};

    my @items = success( $content, "Latest two items in the feed (guessed)", num_items => 2 );
    is_deeply( [ map {$_->{id}} @items ], [ 2, 1 ], "Returned what we guessed are the latest two items from feed (originally without datestamps in ascending order)" );
}
