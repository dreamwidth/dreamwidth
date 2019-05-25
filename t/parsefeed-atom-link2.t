# t/parsefeed-atom-link2.t
#
# Test LJ::ParseFeed detection of alternate/rel links in atom.
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

use Test::More tests => 8;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::ParseFeed;

#  These tests are of the correct identification of an "alternate" link.
#  We assume here that an HTML alternate link is preferred over text/plain,
#  despite the fact that preferring the latter is technically allowed.

# This is taken verbatim from James Snell's set of test cases:
#    <http://www.snellspace.com/public/linktests.xml>

# Here's a giant, obnoxious hunk of XML!
my $contents = qq{
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>tag:snellspace.com,2006:/atom/conformance/linktest/</id>
  <title>Atom Link Tests</title>
  <updated>2005-01-18T15:10:00Z</updated>
  <author><name>James Snell</name></author>
  <link href="http://www.intertwingly.net/wiki/pie/LinkConformanceTests" />
  <link rel="self" href="http://www.snellspace.com/public/linktests.xml" />
  
  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/1</id>
    <title>Just a single Alternate Link</title>
    <updated>2005-01-18T15:00:01Z</updated>
    <summary>The aggregator should pick the second link as the alternate</summary>
    <link rel="http://example.org/random"
         href="http://www.snellspace.com/public/wrong" /> 
    <link href="http://www.snellspace.com/public/linktests/alternate" />
    <link rel="http://example.org/random"
         href="http://www.snellspace.com/public/wrong" /> 
  </entry>

  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/2</id>
    <title>Two alternate links</title>
    <updated>2005-01-18T15:00:02Z</updated>
    <summary>The aggregator should pick either the second or third link below as the alternate</summary>
    <link rel="ALTERNATE" href="http://www.snellspace.com/public/linktests/wrong" />    
    <link href="http://www.snellspace.com/public/linktests/alternate" />
    <link type="text/plain" href="http://www.snellspace.com/public/linktests/alternate2" />
    <link rel="ALTERNATE" href="http://www.snellspace.com/public/linktests/wrong" />
  </entry>

  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/3</id>
    <title>One of each core link rel type</title>
    <updated>2005-01-18T15:00:03Z</updated>
    <summary>The aggregator should pick the first link as the alternate</summary>
    <link href="http://www.snellspace.com/public/linktests/alternate" />
    <link rel="enclosure" href="http://www.snellspace.com/public/linktests/enclosure" length="19" />
    <link rel="related" href="http://www.snellspace.com/public/linktests/related" />
    <link rel="self" href="http://www.snellspace.com/public/linktests/self" />
    <link rel="via" href="http://www.snellspace.com/public/linktests/via" />
  </entry>  

  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/4</id>
    <title>One of each core link rel type + An additional alternate link</title>
    <updated>2005-01-18T15:00:04Z</updated>
    <summary>The aggregator should pick either the first or last links as the alternate. First link is likely better.</summary>
    <link href="http://www.snellspace.com/public/linktests/alternate" />
    <link rel="enclosure" href="http://www.snellspace.com/public/linktests/enclosure" length="19" />
    <link rel="related" href="http://www.snellspace.com/public/linktests/related" />
    <link rel="self" href="http://www.snellspace.com/public/linktests/self" />
    <link rel="via" href="http://www.snellspace.com/public/linktests/via" />
    <link rel="alternate" type="text/plain" href="http://www.snellspace.com/public/linktests/alternate2" />
  </entry>  
  
  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/5</id>
    <title>Entry with a link relation registered by an extension</title>
    <updated>2005-01-18T15:00:05Z</updated>
    <summary>The aggregator should ignore the license link without throwing any errors.  The first link should be picked as the alternate.</summary>
    <link href="http://www.snellspace.com/public/linktests/alternate" />
    <link rel="license" href="http://www.snellspace.com/public/linktests/license" />
  </entry>
  
  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/6</id>
    <title>Entry with a link relation identified by URI</title>
    <updated>2005-01-18T15:00:06Z</updated>
    <summary>The aggregator should ignore the second link without throwing any errors.  The first link should be picked as the alternate.</summary>
    <link href="http://www.snellspace.com/public/linktests/alternate" />
    <link rel="http://example.org" href="http://www.snellspace.com/public/linktests/example" />
  </entry>
  
  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/7</id>
    <title>Entry with a link relation registered by an extension</title>
    <updated>2005-01-18T15:00:05Z</updated>
    <summary>The aggregator should ignore the license link without throwing any errors.  The second link should be picked as the alternate.</summary>
    <link rel="license" href="http://www.snellspace.com/public/linktests/license" />
    <link href="http://www.snellspace.com/public/linktests/alternate" />
  </entry>
  
  <entry>
    <id>tag:snellspace.com,2006:/atom/conformance/linktest/8</id>
    <title>Entry with a link relation identified by URI</title>
    <updated>2005-01-18T15:00:06Z</updated>
    <summary>The aggregator should ignore the first link without throwing any errors.  The second link should be picked as the alternate.</summary>
    <link rel="http://example.org" href="http://www.snellspace.com/public/linktests/example" />
    <link href="http://www.snellspace.com/public/linktests/alternate" />
  </entry>
  
</feed>
};

my ( $feed, $error ) = LJ::ParseFeed::parse_feed($contents);

foreach my $item ( @{ $feed->{items} } ) {
    is( $item->{link}, "http://www.snellspace.com/public/linktests/alternate", $item->{subject} );
}

