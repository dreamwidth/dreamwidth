# t/clean-event.t
#
# Test LJ::CleanHTML::clean_event.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Mark Smith <mark@dreamwidth.org>
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 49;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;
use HTMLCleaner;

my $orig_post;
my $clean_post;

my $clean = sub {
    my $opts = shift;

    LJ::CleanHTML::clean_event( \$orig_post, $opts );
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

# we don't want to mess with tags in tables
# they should be restricted in scope to within the <td> tags they're in right now
$orig_post  = qq{<div><table><tr><td><span></td></tr></table></div>};
$clean_post = qq{<div><table><tr><td><span></td></tr></table></div>};
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
# and ignore the remaining closing </span> tag (which has no opening tag)
$orig_post  = qq{<div><span></div></span>};
$clean_post = qq{<div><span></span></div>};
$clean->();
is( $orig_post, $clean_post, "Wrong closing tag order" );

# if we open a tag, then a table, then let auto-close happen, verify that
# we close tags in the correct order
$orig_post  = qq{<strike><table>};
$clean_post = qq{<strike><table></table></strike>};
$clean->();
is( $orig_post, $clean_post, "Wrong closing tag order in table" );

# similarly, if we manually close a tag in the table, don't consider it
# closed.
$orig_post  = qq{<strike><table></strike>};
$clean_post = qq{<strike><table></table></strike>};
$clean->();
is( $orig_post, $clean_post, "Table left open to swallow closing tags" );

note("unwanted tags and attributes");

# remove header tags
$orig_post  = qq{<h1>test</h1>testing this<h2>testing again</h2>};
$clean_post = qq{testtesting thistesting again};
$clean->( { remove_sizes => 1 } );
ok( $orig_post eq $clean_post, "Header tags removed" );

# remove colors
$orig_post  = qq{<font COLOR="#f00" size="+2">test</font>};
$clean_post = qq{<font size="+2">test</font>};
$clean->( { remove_colors => 1 } );
ok( $orig_post eq $clean_post, "Colors removed" );

# remove colors and sizes
$orig_post  = qq{<h5><font align="center" color="#f00" face="arial" size="+2">test</font></h5>};
$clean_post = qq{<font align="center" face="arial">test</font>};
$clean->( { remove_colors => 1, remove_sizes => 1 } );
ok( $orig_post eq $clean_post, "Colors and sizes removed" );

# remove fonts and sizes
$orig_post  = qq{<font color="#f00" align="center" face="arial" size="+2">test</font>};
$clean_post = qq{<font color="#f00" align="center">test</font>};
$clean->( { remove_fonts => 1, remove_sizes => 1 } );
ok( $orig_post eq $clean_post, "Fonts and sizes removed" );

# remove CSS colors
$orig_post  = qq{<span style="color: #f00; background-color: #00f; font-weight: bold;">test</span>};
$clean_post = qq{<span style="\\s*font-weight: bold;\\s*">test<\\/span>};
$clean->( { remove_colors => 1 } );
ok( $orig_post =~ /^$clean_post$/, "CSS colors removed" );

# remove CSS colors
$orig_post  = qq{<span style="color: #f00">test</span>};
$clean_post = qq{<span style="\\s*">test<\\/span>};
$clean->( { remove_colors => 1 } );
ok( $orig_post =~ /^$clean_post$/, "CSS colors removed" );

# remove CSS colors and sizes
$orig_post  = qq{<div style="text-align: center;font-size:larger;COLOR:f00">test</div>};
$clean_post = qq{<div style="\\s*text-align: center;\\s*">test<\\/div>};
$clean->( { remove_colors => 1, remove_sizes => 1 } );
ok( $orig_post =~ /^$clean_post$/, "CSS colors and sizes removed" );

# remove CSS fonts and sizes
$orig_post =
qq{<div align="center" style="  font-size:   larger  ; font-FAMILY: 'Arial', sans-serif" class="foo">test</div>};
$clean_post = qq{<div align="center" style="\\s*\\s*" class="foo">test<\\/div>};
$clean->( { remove_fonts => 1, remove_sizes => 1 } );
ok( $orig_post =~ /^$clean_post$/, "CSS fonts and sizes removed" );

note("cut tags");

# get cut text
my $cut_text;
my $entry_text = qq{<cut text="first">111</cut><cut text="second">2222</cut>};

$orig_post = $entry_text;
$cut_text  = "111";
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under first cut, plain" );

$orig_post = $entry_text;
$cut_text  = "2222";
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under second cut, plain" );

$entry_text = qq{
<cut text="first"><a href="#first">111</a></cut>
<cut text="second"><a href="#second">2222</a></cut>};

$orig_post = $entry_text;
$cut_text  = qq{<a href="#first">111</a>};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under first cut, with HTML tags" );

$orig_post = $entry_text;
$cut_text  = qq{<a href="#second">2222</a>};
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under second cut, with HTML tags" );

$orig_post  = qq{<strong><textarea></strong>};
$clean_post = qq{<strong><textarea>&lt;/strong&gt;</textarea></strong>};
$clean->();
is( $orig_post, $clean_post, "Open textarea tag" );

$orig_post  = qq{<textarea><textarea></textarea>};
$clean_post = qq{<textarea>&lt;textarea&gt;</textarea>};
$clean->();
is( $orig_post, $clean_post, "Double textarea tag" );

# nested cut tags
$entry_text = qq{<cut text="outer">out <cut text="inner">in</cut></cut>};

$orig_post = $entry_text;
$cut_text  = qq{out <a name="cutid2"></a>in};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under outer cut, plain" );

$orig_post = $entry_text;
$cut_text  = qq{in};
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under inner cut, plain" );

$entry_text = qq{<cut text="outer"><strong>out</strong> <cut text="inner"><em>in</em></cut></cut>};

$orig_post = $entry_text;
$cut_text  = qq{<strong>out</strong> <a name="cutid2"></a><em>in</em>};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "Text under outer cut, HTML" );

$orig_post = $entry_text;
$cut_text  = qq{<em>in</em>};
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "Text under inner cut, HTML" );

$entry_text = qq{<div class='ljcut'>Text here</div>};
$orig_post  = $entry_text;
$cut_text   = qq{Text here};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "text in <div> style cut is retrieved" );

$entry_text = qq{<div class='ljcut'>Text here</div> <lj-cut>Other text here</lj-cut>};
$orig_post  = $entry_text;
$cut_text   = qq{Text here};
$clean->( { cut_retrieve => 1 } );
is( $orig_post, $cut_text, "text in <div> style cut is retrieved" );

$orig_post = $entry_text;
$cut_text  = qq{Other text here};
$clean->( { cut_retrieve => 2 } );
is( $orig_post, $cut_text, "text in <lj-cut> style cut after <div> style cut is retrieved" );

# embed tags

note("<object> and <embed> tags");
$orig_post =
qq{<object width="640" height="385"><param name="movie" value="http://www.example.com/video"></param><param name="allowFullScreen" value="true"></param><param name="allowscriptaccess" value="always"></param><embed src="http://www.example.com/video" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" width="640" height="385"></embed></object>};
$clean_post = qq{};
$clean->();
is( $orig_post, $clean_post, "<object> and <embed> tags" );

note("various allowed/disallowed tags");
{
    $orig_post  = qq{<em>abc</em>};
    $clean_post = qq{<em>abc</em>};
    $clean->();
    is( $orig_post, $clean_post, "em tag allowed" );

    $orig_post  = qq{<marquee>abc</marquee>};
    $clean_post = qq{<marquee>abc</marquee>};
    $clean->();
    is( $orig_post, $clean_post, "marquee tag allowed" );

    $orig_post  = qq{<blink>abc</blink>};
    $clean_post = qq{<blink>abc</blink>};
    $clean->();
    is( $orig_post, $clean_post, "blink tag allowed" );

}

note("mismatched and misnested tags");
{
    # form tags not in a form should be displayed
    my $form_inner = qq{<select><option>hello</option><option>bye</option></select>};
    $orig_post  = qq{<form>$form_inner</form>};
    $clean_post = qq{<form>$form_inner</form>};
    $clean->();
    is( $orig_post, $clean_post, "form tags within a form are allowed" );

    $orig_post = $form_inner;
    $clean_post =
qq{&lt;select ... &gt;&lt;option ... &gt;hello&lt;/option&gt;&lt;option ... &gt;bye&lt;/option&gt;&lt;/select&gt;};
    $clean->();
    is( $orig_post, $clean_post, "form tags outside a form are escaped and displayed" );

    my $table_inner = qq{<tr><td>hello</td><td>bye</td></tr>};
    $orig_post  = qq{<table>$table_inner</table>};
    $clean_post = qq{<table>$table_inner</table>};
    $clean->();
    is( $orig_post, $clean_post, "table tags within a table are allowed" );

    $orig_post  = $table_inner;
    $clean_post = qq{&lt;tr&gt;&lt;td&gt;hello&lt;/td&gt;&lt;td&gt;bye&lt;/td&gt;&lt;/tr&gt;};
    $clean->();
    is( $orig_post, $clean_post, "table tags outside a table are escaped and displayed" );

    $orig_post  = qq{strong</strong> not <em><b>strong</em></b>};
    $clean_post = qq{strong not <em><b>strong</b></em>};
    $clean->();
    is( $orig_post, $clean_post,
        "mismatched closing tags or misnested closing tags shouldn't be displayed" );

    $orig_post  = qq{before <i>in i<i/> after};
    $clean_post = qq{before <i>in i<i> after</i></i>};
    $clean->();
    is( $orig_post, $clean_post,
        "self-closing tags that aren't actually self-closing should still be closed." );

    $entry_text = qq{before <strong><cut text="cut">in strong</strong>out strong</cut>after};

    $orig_post = $entry_text;
    $cut_text  = qq{in strongout strong};
    $clean->( { cut_retrieve => 1 } );
    is( $orig_post, $cut_text,
        "Text under cut with mismatched HTML tags within and with-out the cut (ignored)" );

    $orig_post  = $entry_text;
    $clean_post = qq{before <strong><a name="cutid1"></a>in strong</strong>out strongafter};
    $clean->();
    is( $orig_post, $clean_post,
        "Full text of entry, with mismatched HTML tags within and with-out the cut" );
}

note("expected wordbreak behavior");

$orig_post  = qq{wordbreak};
$clean_post = qq{word<wbr />brea<wbr />k};
$clean->( { wordlength => 4 } );
is( $orig_post, $clean_post, "Word break tags inserted where requested" );

$orig_post  = qq{insert a word<wbr>break};
$clean_post = qq{insert a word<wbr>break};
$clean->();
is( $orig_post, $clean_post, "Existing word break tags unchanged" );

$orig_post  = qq{word-break};
$clean_post = qq{word-<wbr />break};
$clean->( { wordlength => 8 } );
is( $orig_post, $clean_post, "Word break tag prefers punctuation points" );

$orig_post  = qq{&quot;entity&quot; test};
$clean_post = qq{&quot;entity&quot; test};
$clean->( { wordlength => 8 } );
is( $orig_post, $clean_post, "Word break handling of HTML entities OK" );

$orig_post  = qq{multi-character-string test};
$clean_post = qq{multi-character-<wbr />string test};
$clean->( { wordlength => 20 } );
is( $orig_post, $clean_post, "Choose last punctuation in string" );

$orig_post  = qq{"This_is_a_test_of_the_emergency_word_break_system."};
$clean_post = qq{"This_is_a_test_of_the_emergency_word_br<wbr />eak_system."};
$clean->( { wordlength => 40 } );
is( $orig_post, $clean_post, "Don't choose first character in string" );

$orig_post = qq{"Auto-linkify: http://www.dreamwidth.org/file/edit"};
$clean_post =
qq{"Auto-linkify: <a href="http://www.dreamwidth.org/file/edit">http://www.dreamwidth.org/file/edit</a>"};
$clean->( { wordlength => 40 } );
is( $orig_post, $clean_post, "Don't mutilate URL entity markers" );

1;
