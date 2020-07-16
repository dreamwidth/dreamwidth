# t/textutil.t
#
# Test LJ::TextUtil.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Aaron Isaac <wyntarvox@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 21;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use LJ::TextUtil;

note("html breaks");
ok( LJ::has_too_many( "abcdn<br />" x 1, linebreaks => 0 ), "0 max, 1 break" );

ok( !LJ::has_too_many( "abcdn<br>" x 1,   linebreaks => 2 ), "2 max, 1 break" );
ok( !LJ::has_too_many( "abcdn<br />" x 2, linebreaks => 2 ), "2 max, 2 breaks" );

note("ignoring literal newlines");
ok( !LJ::has_too_many( "abcdn<br />\n\n\n" x 1, linebreaks => 2 ), "2 max, 1 break" );

note("paragraphs and mixtures");
ok( LJ::has_too_many( "<p>abcdn</p>" x 1, linebreaks => 1 ), "1 max, 2 breaks" );

ok( !LJ::has_too_many( "<p>abc<br>dn</p>" x 1, linebreaks => 4 ), "4 max, 3 breaks" );
ok( !LJ::has_too_many( "<p>abcdn</p>" x 2,     linebreaks => 4 ), "4 max, 4 breaks" );

note("characters");
ok( LJ::has_too_many( "abcdn\n", chars => 0 ), "0 max, 6 characters" );

ok( !LJ::has_too_many( "abcde\n",  chars => 7 ), "7 max, 6 characters" );
ok( !LJ::has_too_many( "abcdef\n", chars => 7 ), "7 max, 7 characters" );
ok( LJ::has_too_many( "abcdefg\n", chars => 7 ), "7 max, 8 characters" );

note("mix");
ok( LJ::has_too_many( "abcdn<br>", chars => 10, linebreaks => 0 ),
    "10 chars, 9 chars; 0 linebreaks, 1 break" );
ok( !LJ::has_too_many( "abcdn<br>", chars => 10, linebreaks => 1 ),
    "10 chars, 9 chars; 1 linebreaks, 1 break" );

ok( LJ::has_too_many( "abcdn<br>", chars => 0, linebreaks => 5 ),
    "0 chars, 9 chars; 5 linebreaks, 1 break" );
ok( !LJ::has_too_many( "abcdn<br>", chars => 10, linebreaks => 5 ),
    "10 chars, 9 chars; 5 linebreaks, 1 break" );

note("striphtml user tags");
is( LJ::strip_html(qq{<lj user="test">}),   "test", qq{ strip_html <lj user="test"> } );
is( LJ::strip_html(qq{<user name="test">}), "test", qq{ strip_html <user name="test"> } );

is( LJ::strip_html(qq{<lj user="test" site="dreamwidth.org">}),
    "test", qq{ <lj user="test" site="dreamwidth.org"> } );
is( LJ::strip_html(qq{<user name="test" site="dreamwidth.org">}),
    "test", qq{ <user name="test" site="dreamwidth.org"> } );

is( LJ::strip_html(qq{<lj site="dreamwidth.org" user="test">}),
    "test", qq{ <lj site="dreamwidth.org" user="test"> } );
is( LJ::strip_html(qq{<user site="dreamwidth.org" name="test">}),
    "test", qq{ <user site="dreamwidth.org" name="test"> } );
