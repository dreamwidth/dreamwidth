# t/clean-comment.t
#
# Test LJ::CleanHTML::clean_comment.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 28;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;

my $orig_comment;
my $clean_comment;

my $clean = sub {
    my $opts = shift;

    LJ::CleanHTML::clean_comment( \$orig_comment, $opts );
};

# remove various positioning and display rules
$orig_comment  = qq{<span style="display: none; display:none; display : none; display: inline">};
$clean_comment = qq{<span style="\\s*display: inline\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/, "Removed display:none ($orig_comment)" );

$orig_comment  = qq{<span style="margin-top: 10px;">};
$clean_comment = qq{<span style="\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/, "Removed margin ($orig_comment)" );

$orig_comment  = qq{<span style="height: 150px;">};
$clean_comment = qq{<span style="\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/, "Removed height" );

# handle unreasonably large padding values
$orig_comment =
qq{<span style="padding-top: 9999999px; padding-left: 9999999px; padding-top: 9999999px; padding-bottom: 9999999px"></span>};
$clean_comment = qq{<span style="\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/, "All padding removed. (Multiple rules, all too large)" );

$orig_comment  = qq{<span style="padding: 999px 999px 999px 999px"></span>};
$clean_comment = qq{<span style="\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/,
    "All padding removed. (Combined into one rule, all too large)" );

$orig_comment  = qq{<span style="padding-left: 999px; padding-right: 200px;"></span>};
$clean_comment = qq{<span style="\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/,
    "All padding removed. (Multiple rules, mixed too large and small enough)" );

$orig_comment  = qq{<span style="padding: 999px 200px;"></span>};
$clean_comment = qq{<span style="\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/,
    "All padding removed. (One dimension in a combined rule, mixed too large and small enough)" );

$orig_comment =
qq{<span style="padding-top: 200px; padding-left: 200px; padding-right: 150px; padding-bottom: 150px;"></span>};
$clean_comment =
qq{<span style="\\s*padding-top: 200px;\\s*padding-left: 200px;\\s*padding-right: 150px;\\s*padding-bottom: 150px;\\s*"><\\/span>};
$clean->( { remove_positioning => 1 } );
ok( $orig_comment =~ /^$clean_comment$/, "Padding not removed; of reasonable size." );

$orig_comment  = qq{<font color="red">test};
$clean_comment = qq{<font color="red">test</font>};
$clean->();
ok( $orig_comment eq $clean_comment, "Font tag closed." );

$orig_comment  = qq{<font color="red"></div>test};
$clean_comment = qq{<font color="red">test</font>};
$clean->();
ok( $orig_comment eq $clean_comment, "Spurious closing div stripped." );

$orig_comment  = qq{<font color="red"><div>test</font>};
$clean_comment = qq{<font color="red"><div>test</div></font>};
$clean->();
ok( $orig_comment eq $clean_comment, "Closing div inserted." );

$orig_comment  = qq{<div><font color="red"></div>test</font>};
$clean_comment = qq{<div><font color="red"></font></div>test};
$clean->();
ok( $orig_comment eq $clean_comment, "Bad open/closes fixed." );

$orig_comment  = qq{<h1><h2><h3><h1><h2><h3>};
$clean_comment = qq{<h1><h2><h3><h1><h2><h3></h3></h2></h1></h3></h2></h1>};
$clean->();
ok( $orig_comment eq $clean_comment, "Aggressively close things." );

$orig_comment  = qq{<h1><h2><h3><h1></h2><h2></h3><h3>};
$clean_comment = qq{<h1><h2><h3><h1></h1></h3></h2><h2><h3></h3></h2></h1>};
$clean->();
ok( $orig_comment eq $clean_comment, "Aggressive close with eaten extra close." );

note("Remove absolute sizes when logged out");
{
    $orig_comment  = qq{<span style="font-size: larger">foo</span>};
    $clean_comment = qq{<span style="font-size: larger">foo</span>};
    $clean->( { anon_comment => 1 } );
    is( $orig_comment, $clean_comment, "Retain relative font sizes" );

    $orig_comment  = qq{<span style="font-size:   10px  ">foo</span>};
    $clean_comment = qq{<span style="">foo</span>};
    $clean->( { anon_comment => 1 } );
    is( $orig_comment, $clean_comment, "Strip absolute font sizes" );

    $orig_comment  = qq{<span style="font-size:0.2em; font-weight: bold">foo</span>};
    $clean_comment = qq{<span style=" font-weight: bold">foo</span>};
    $clean->( { anon_comment => 1 } );
    is( $orig_comment, $clean_comment, "Strip absolute font sizes" );
}

note("Don't remove absolute sizes when logged in");
{
    $orig_comment  = qq{<span style="font-size: larger">foo</span>};
    $clean_comment = $orig_comment;
    $clean->();
    is( $orig_comment, $clean_comment, "Retain relative font sizes" );

    $orig_comment  = qq{<span style="font-size:   10px  ">foo</span>};
    $clean_comment = $orig_comment;
    $clean->();
    is( $orig_comment, $clean_comment, "Retain absolute font sizes" );

    $orig_comment  = qq{<span style="font-size:0.2em; font-weight: bold">foo</span>};
    $clean_comment = $orig_comment;
    $clean->();
    is( $orig_comment, $clean_comment, "Retain absolute font sizes" );

}

# remove background urls from logged out users
$orig_comment = qq{<span style="background: url('http://www.example.com/example.gif');"></span>};
$clean_comment =
qq{<span style="\\s*background: url\\(&\\#39;http://www.example.com/example.gif&\\#39;\\);\\s*"><\\/span>};
$clean->();
ok( $orig_comment =~ /^$clean_comment$/, "Background URL not cleaned: logged-in user" );

$orig_comment  = qq{<span style="background: url('http://www.example.com/example.gif');"></span>};
$clean_comment = qq{<span style="background:\\s*;\\s*"><\\/span>};
$clean->( { anon_comment => 1 } );
ok( $orig_comment =~ /^$clean_comment$/, "Background URL removed: anonymous comment" );

$orig_comment  = qq{pre<a href="asdf"> post};
$clean_comment = qq{pre<b> post</b> (asdf)};
$clean->( { anon_comment => 1 } );
is( $orig_comment, $clean_comment, "Full href bold escape" );

$orig_comment  = qq{pre<a href=""> post};
$clean_comment = qq{pre<b> post</b> ()};
$clean->( { anon_comment => 1 } );
is( $orig_comment, $clean_comment, "Empty href bold escape" );

# another table exploit involving a tags.
$orig_comment  = q{<a href=mailto:blah@blah.com><table>};
$clean_comment = q{<b></b> (mailto:blah@blah.com)};
$clean->( { anon_comment => 1 } );
is( $orig_comment, $clean_comment, "Anonymous comment bold escape" );

note("various allowed/disallowed tags");
{
    $orig_comment  = qq{<em>abc</em>};
    $clean_comment = qq{<em>abc</em>};
    $clean->();
    is( $orig_comment, $clean_comment, "em tag allowed" );

    $orig_comment  = qq{<marquee>abc</marquee>};
    $clean_comment = qq{abc};
    $clean->();
    is( $orig_comment, $clean_comment, "marquee tag not allowed" );

    $orig_comment  = qq{<blink>abc</blink>};
    $clean_comment = qq{abc};
    $clean->();
    is( $orig_comment, $clean_comment, "blink tag not allowed" );

}

1;
