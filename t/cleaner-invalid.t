# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'cleanhtml.pl';
use LJ::Test qw (temp_user);
use HTMLCleaner;

my $post;
my $clean_post;
my $clean = sub {
    $clean_post = $post;
    LJ::CleanHTML::clean_event(\$clean_post);
};

$post = "<b>bold text</b>";
$clean->();
is($clean_post, $post, "Valid HTML is okay.");


$post = "<marquee><font size=\"24\"><color=\"FF0000\">blah blah";
$clean->();
is($clean_post,
   qq {<marquee><font size="24"></font></marquee><div class='ljparseerror'>[<b>Error:</b> Irreparable invalid markup ('&lt;color=&quot;ff0000&quot;&gt;') in entry.  Owner must fix manually.  Raw contents below.]<br /><br /><div style="width: 95%; overflow: auto">} . LJ::ehtml($post) . "</div></div>",
   "Invalid HTML is not okay.");


my $u = temp_user();
$post = "<lj user=\"" . $u->user . "\">";
$clean->();
is($clean_post, $u->ljuser_display, "User tag is fine.");


my $u = temp_user();
$post = "<lj user=\"" . $u->user . "\"> and some text <marquee><font size=\"24\"><color=\"FF0000\">blah blah";
$clean->();
is($clean_post,
   $u->ljuser_display . qq { and some text <marquee><font size="24"></font></marquee><div class='ljparseerror'>[<b>Error:</b> Irreparable invalid markup ('&lt;color=&quot;ff0000&quot;&gt;') in entry.  Owner must fix manually.  Raw contents below.]<br /><br /><div style="width: 95%; overflow: auto">} . LJ::ehtml($post) . "</div></div>",
   "Invalid markup with a user tag renders correctly.");

