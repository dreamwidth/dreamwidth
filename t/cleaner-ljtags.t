# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'cleanhtml.pl';
use HTMLCleaner;

my $lju_sys = LJ::ljuser("system");

my $fullurl = "http://lj.example/full.html";
my $clean = sub {
    my $raw = shift;
    my %opts = @_;
    LJ::CleanHTML::clean_event(\$raw, {
        cuturl => defined $opts{cuturl} ? $opts{cuturl} : $fullurl,
    });
    return $raw;
};

# old lj user tag
is($clean->("some text <lj user=system> more text"),
   "some text $lju_sys more text", "old lj user tag");

# testing <lj comm> tag maps to an lj user tag
is($clean->("some text <lj comm=system> more text"),
   "some text $lju_sys more text", "lj comm= on a user");

# span ljuser
is($clean->("[<span class=ljuser>system</span>]"),
   "[$lju_sys]", "span ljuser");
is($clean->("[<span class=ljuser>bob <img src=\"http://www.lj.bradfitz.com/img/userinfo.gif\" /> system</span>]"),
   "[$lju_sys]", "span ljuser with junk inside");

# old lj-ut
is($clean->("And a cut:<lj-cut>foooooooooooooo</lj-cut>"),
            "And a cut:<b>(&nbsp;<a href=\"$fullurl#cutid1\">Read more...</a>&nbsp;)</b>",
            "old lj-cut");
is($clean->("And a cut:<lj-cut text='foo'>foooooooooooooo</lj-cut>"),
            "And a cut:<b>(&nbsp;<a href=\"$fullurl#cutid1\">foo</a>&nbsp;)</b>",
            "old lj-cut w/ text");

# new lj-cut
is($clean->(qq{New cut: <div class="ljcut">baaaaaaaaaarrrrr</div>}),
   qq{New cut: <div><b>(&nbsp;<a href="http://lj.example/full.html#cutid1">Read more...</a>&nbsp;)</b></div>},
   "new lj-cut w/ div");

is($clean->(qq{New cut: <div class="ljcut" text="This is my div cut">baaaaaaaaaarrrrr</div>}),
   qq{New cut: <div><b>(&nbsp;<a href="http://lj.example/full.html#cutid1">This is my div cut</a>&nbsp;)</b></div>},
   "new lj-cut w/ div w/ text");

# nested div cuts
is($clean->(qq{Nested: <div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>}),
   qq{Nested: <div><b>(&nbsp;<a href="http://lj.example/full.html#cutid1">Nested</a>&nbsp;)</b></div>},
   "nested div cuts");
is($clean->(qq{Nested: <div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>},
            cuturl => ""),
   qq{Nested: <a name="cutid1"></a><div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>},
   "nested div cuts, expanded");
is($clean->(qq{Nested: <div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div></div>},
            cuturl => ""),
   qq{Nested: <a name="cutid1"></a><div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>&lt;/div&gt;},
   "nested div cuts, expanded, user's extra close div");
is($clean->(qq{Nested: <div class="ljcut"><div><div></div></div></div>fin},
            cuturl => ""),
   qq{Nested: <a name="cutid1"></a><div class="ljcut" text="Read more..."><div><div></div></div></div>fin},
   "nested div cuts, more");

# MORE TO TEST:

#  -- cutdisabled flag?
#  -- ... ?







