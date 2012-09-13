# -*-perl-*-
use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
use LJ::ParseFeed;
BEGIN { require 'ljlib.pl'; }

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

    my ($feed, $error) = LJ::ParseFeed::parse_feed($contents);
    my $item = $feed->{'items'}->[0];
    return $item->{'link'};
};

is($testfeed->("<link rel=\"alternate\" type=\"text/html\" href=\"$LJ::SITEROOT\" />"),
   $LJ::SITEROOT, "rel=alternate is fine");

is($testfeed->("<link type=\"text/html\" href=\"$LJ::SITEROOT\" />"),
   $LJ::SITEROOT, "no explicit rel attribute is also fine");

ok(!$testfeed->("<link rel=\"bananas\" type=\"text/html\" href=\"$LJ::SITEROOT\" />"),
   "rel that isn't 'alternate' not okay");
