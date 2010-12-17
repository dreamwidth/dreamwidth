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

note("malformed html");
$orig_post  = qq{<div><span>abc</div>};
$clean_post = qq{<div><span>abc</span></div>};
$clean->();
is( $orig_post, $clean_post, "Inner tag isn't closed" );

$orig_post  = qq{<div><table><tr><td></td></tr></table><span></div>};
$clean_post = qq{<div><table><tr><td></td></tr></table><span></span></div>};
$clean->();
is( $orig_post, $clean_post, "Tag outside a table isn't closed" );

# this is a bit weird; we don't want to mess with tags in tables
# so we just close it after, leading to this HTML
$orig_post  = qq{<div><table><tr><td><span></td></tr></table></div>};
$clean_post = qq{<div><table><tr><td><span></td></tr></table></div></span>};
$clean->();
is( $orig_post, $clean_post, "Non-table-related tag inside a table is open" );

$orig_post  = qq{<div><table><tr><td></tr></table></div>};
$clean_post = qq{<div><table><tr><td></tr></table></div>};
$clean->();
is( $orig_post, $clean_post, "Table-related-tag inside a table is open" );

$orig_post  = qq{<div><img /></div>};
$clean_post = qq{<div><img /></div>};
$clean->();
is( $orig_post, $clean_post, "Slash-closed tag" );

$orig_post  = qq{<div><span>};
$clean_post = qq{<div><span></span></div>};
$clean->();
is( $orig_post, $clean_post, "No closing tags" );

# in this case, we consider the <span> within the div as unclosed
# and the closing </span> as extra/unrelated.
# Therefore, we close the opening tag (which needs to be closed)
# and escape the closing tag (which has no opening tag)
$orig_post  = qq{<div><span></div></span>};
$clean_post = qq{<div><span></span></div>&lt;/span&gt;};
$clean->();
is( $orig_post, $clean_post, "Wrong closing tag order" );

note("unwanted tags and attributes");
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

note("cut tags");
# get cut text
my $cut_text;
my $entry_text = qq{<cut text="first">111</cut><cut text="second">2222</cut>};

$orig_post = $entry_text;
$cut_text = "111";
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under first cut, plain" );

$orig_post = $entry_text;
$cut_text = "2222";
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under second cut, plain" );

$entry_text = qq{
<cut text="first"><a href="#first">111</a></cut>
<cut text="second"><a href="#second">2222</a></cut>};

$orig_post = $entry_text;
$cut_text = qq{<a href="#first">111</a>};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under first cut, with HTML tags" );

$orig_post = $entry_text;
$cut_text = qq{<a href="#second">2222</a>};
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under second cut, with HTML tags" );


# nested cut tags
$entry_text = qq{<cut text="outer">out <cut text="inner">in</cut></cut>};

$orig_post = $entry_text;
$cut_text = qq{out <a name="cutid2"></a>in};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under outer cut, plain" );

$orig_post = $entry_text;
$cut_text = qq{in};
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under inner cut, plain" );

$entry_text = qq{<cut text="outer"><strong>out</strong> <cut text="inner"><em>in</em></cut></cut>};

$orig_post = $entry_text;
$cut_text = qq{<strong>out</strong> <a name="cutid2"></a><em>in</em>};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under outer cut, HTML" );

$orig_post = $entry_text;
$cut_text = qq{<em>in</em>};
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under inner cut, HTML" );

1;
