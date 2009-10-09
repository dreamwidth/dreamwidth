# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::CleanHTML;
use HTMLCleaner;

my $orig_post;
my $clean_post;

my $clean = sub {
    my $opts = shift;

    LJ::CleanHTML::clean_event(\$orig_post, $opts);
};

# remove header tags
$orig_post = qq{<h1>test</h1>testing this<h2>testing again</h2>};
$clean_post = qq{testtesting thistesting again};
$clean->({ remove_sizes => 1 });
ok($orig_post eq $clean_post, "Header tags removed");

# remove colors
$orig_post = qq{<font COLOR="#f00" size="+2">test</font>};
$clean_post = qq{<font size="+2">test</font>};
$clean->({ remove_colors => 1 });
ok($orig_post eq $clean_post, "Colors removed");

# remove colors and sizes
$orig_post = qq{<h5><font align="center" color="#f00" face="arial" size="+2">test</font></h5>};
$clean_post = qq{<font align="center" face="arial">test</font>};
$clean->({ remove_colors => 1, remove_sizes => 1 });
ok($orig_post eq $clean_post, "Colors and sizes removed");

# remove fonts and sizes
$orig_post = qq{<font color="#f00" align="center" face="arial" size="+2">test</font>};
$clean_post = qq{<font color="#f00" align="center">test</font>};
$clean->({ remove_fonts => 1, remove_sizes => 1 });
ok($orig_post eq $clean_post, "Fonts and sizes removed");

# remove CSS colors
$orig_post = qq{<span style="color: #f00; background-color: #00f; font-weight: bold;">test</span>};
$clean_post = qq{<span style="\\s*font-weight: bold;\\s*">test<\\/span>};
$clean->({ remove_colors => 1 });
ok($orig_post =~ /^$clean_post$/, "CSS colors removed");

# remove CSS colors
$orig_post = qq{<span style="color: #f00">test</span>};
$clean_post = qq{<span style="\\s*">test<\\/span>};
$clean->({ remove_colors => 1 });
ok($orig_post =~ /^$clean_post$/, "CSS colors removed");

# remove CSS colors and sizes
$orig_post = qq{<div style="text-align: center;font-size:larger;COLOR:f00">test</div>};
$clean_post = qq{<div style="\\s*text-align: center;\\s*">test<\\/div>};
$clean->({ remove_colors => 1, remove_sizes => 1 });
ok($orig_post =~ /^$clean_post$/, "CSS colors and sizes removed");

# remove CSS fonts and sizes
$orig_post = qq{<div align="center" style="  font-size:   larger  ; font-FAMILY: 'Arial', sans-serif" class="foo">test</div>};
$clean_post = qq{<div align="center" style="\\s*\\s*" class="foo">test<\\/div>};
$clean->({ remove_fonts => 1, remove_sizes => 1 });
ok($orig_post =~ /^$clean_post$/, "CSS fonts and sizes removed");

1;
