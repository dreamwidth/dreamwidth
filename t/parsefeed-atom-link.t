# t/parsefeed-atom-link.t
#
# Test LJ::ParseFeed with 'rel' attributes
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

use Test::More tests => 3;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::ParseFeed;

my $testfeed = sub {
    my $link_content = shift;

    my $contents = qq {
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>testing:atom:feed</id>
  <title>test atom feed</title>
  <author><name>testing</name></author>
  <link rel="alternate" type="text/html" href="$LJ::SITEROOT" />
  <link rel="self" type="text/xml" href="$LJ::SITEROOT" />
  <updated>2007-01-08T23:40:33Z</updated>
  <entry>
    <id>testing:atom:feed:entry</id>
    $link_content
    <title>default userpic</title>
    <updated>2006-09-14T07:39:07Z</updated>
    <content type="html">content content content</content>
  </entry>
</feed>
};

    my ( $feed, $error ) = LJ::ParseFeed::parse_feed($contents);
    my $item = $feed->{'items'}->[0];
    return $item->{'link'};
};

is( $testfeed->("<link rel=\"alternate\" type=\"text/html\" href=\"$LJ::SITEROOT\" />"),
    $LJ::SITEROOT, "rel=alternate is fine" );

is( $testfeed->("<link type=\"text/html\" href=\"$LJ::SITEROOT\" />"),
    $LJ::SITEROOT, "no explicit rel attribute is also fine" );

ok( !$testfeed->("<link rel=\"bananas\" type=\"text/html\" href=\"$LJ::SITEROOT\" />"),
    "rel that isn't 'alternate' not okay" );
