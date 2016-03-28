# t/cleaner-ljtags.t
#
# Test LJ::CleanHTML with LJ-specific tags.
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
use LJ::CleanHTML;
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

# old lj-cut
is($clean->("And a cut:<lj-cut>foooooooooooooo</lj-cut>"),
            "And a cut:<span class=\"cuttag_container\"><span style=\"display: none;\" id=\"span-cuttag___1\" class=\"cuttag\"></span><b>(&nbsp;<a href=\"$fullurl#cutid1\">Read more...</a>&nbsp;)</b><div style=\"display: none;\" id=\"div-cuttag___1\" aria-live=\"assertive\"></div></span>",
            "old lj-cut");
is($clean->("And a cut:<lj-cut text='foo'>foooooooooooooo</lj-cut>"),
            "And a cut:<span class=\"cuttag_container\"><span style=\"display: none;\" id=\"span-cuttag___1\" class=\"cuttag\"></span><b>(&nbsp;<a href=\"$fullurl#cutid1\">foo</a>&nbsp;)</b><div style=\"display: none;\" id=\"div-cuttag___1\" aria-live=\"assertive\"></div></span>",
            "old lj-cut w/ text");

# new lj-cut
is($clean->(qq{New cut: <div class="ljcut">baaaaaaaaaarrrrr</div>}),
   qq{New cut: <div><span class="cuttag_container"><span style="display: none;" id="span-cuttag___1" class="cuttag"></span><b>(&nbsp;<a href="http://lj.example/full.html#cutid1">Read more...</a>&nbsp;)</b><div style="display: none;" id="div-cuttag___1" aria-live="assertive"></div></span></div>},
   "new lj-cut w/ div");

is($clean->(qq{New cut: <div class="ljcut" text="This is my div cut">baaaaaaaaaarrrrr</div>}),
   qq{New cut: <div><span class="cuttag_container"><span style="display: none;" id="span-cuttag___1" class="cuttag"></span><b>(&nbsp;<a href="http://lj.example/full.html#cutid1">This is my div cut</a>&nbsp;)</b><div style="display: none;" id="div-cuttag___1" aria-live="assertive"></div></span></div>},
   "new lj-cut w/ div w/ text");

# nested div cuts
is($clean->(qq{Nested: <div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>}),
   qq{Nested: <div><span class="cuttag_container"><span style="display: none;" id="span-cuttag___1" class="cuttag"></span><b>(&nbsp;<a href="http://lj.example/full.html#cutid1">Nested</a>&nbsp;)</b><div style="display: none;" id="div-cuttag___1" aria-live="assertive"></div></span></div>},
   "nested div cuts");
is($clean->(qq{Nested: <div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>},
            cuturl => ""),
   qq{Nested: <a name="cutid1"></a><div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>},
   "nested div cuts, expanded");
is($clean->(qq{Nested: <div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div></div>},
            cuturl => ""),
   qq{Nested: <a name="cutid1"></a><div class="ljcut" text="Nested">baaaaaaaaaa<div style="background: red">I AM RED</div>arrrrrr</div>},
   "nested div cuts, expanded, ignored user's extra close div");
is($clean->(qq{Nested: <div class="ljcut"><div><div></div></div></div>fin},
            cuturl => ""),
   qq{Nested: <a name="cutid1"></a><div class="ljcut" text="Read more..."><div><div></div></div></div>fin},
   "nested div cuts, more");

# MORE TO TEST:

#  -- cutdisabled flag?
#  -- ... ?







