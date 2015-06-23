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

use Test::More tests => 22;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use LJ::TextUtil;

note("html breaks");
ok(   LJ::has_too_many( "abcdn<br />" x 1, linebreaks => 0 ), "0 max, 1 break" );

ok( ! LJ::has_too_many( "abcdn<br />" x 1, linebreaks => 2 ), "2 max, 1 break" );
ok( ! LJ::has_too_many( "abcdn<br />" x 2, linebreaks => 2 ), "2 max, 2 breaks" );
ok(   LJ::has_too_many( "abcdn<br />" x 3, linebreaks => 2 ), "2 max, 3 breaks" );


note("newlines");
ok(   LJ::has_too_many( "abcdn\n" x 1, linebreaks => 0 ), "0 max, 1 newline" );

ok( ! LJ::has_too_many( "abcdn\n" x 1, linebreaks => 2 ), "2 max, 1 newline" );
ok( ! LJ::has_too_many( "abcdn\n" x 2, linebreaks => 2 ), "2 max, 2 newlines" );
ok(   LJ::has_too_many( "abcdn\n" x 3, linebreaks => 2 ), "2 max, 3 newlines" );


note("characters");
ok(   LJ::has_too_many( "abcdn\n", chars => 0 ), "0 max, 6 characters" );

ok( ! LJ::has_too_many( "abcde\n",   chars => 7 ), "7 max, 6 characters" );
ok( ! LJ::has_too_many( "abcdef\n",  chars => 7 ), "7 max, 7 characters" );
ok(   LJ::has_too_many( "abcdefg\n", chars => 7 ), "7 max, 8 characters" );


note("mix");
ok(   LJ::has_too_many( "abcdn\n", chars => 9, linebreaks => 0 ),
                                "9 chars, 6 chars; 0 linebreaks, 1 break" );
ok( ! LJ::has_too_many( "abcdn\n", chars => 9, linebreaks => 1 ),
                                "9 chars, 6 chars; 1 linebreaks, 1 break" );

ok(   LJ::has_too_many( "abcdn\n", chars => 0, linebreaks => 5 ),
                                "0 chars, 6 chars; 5 linebreaks, 1 break" );
ok( ! LJ::has_too_many( "abcdn\n", chars => 9, linebreaks => 5 ),
                                "9 chars, 6 chars; 5 linebreaks, 1 break" );

note( "striphtml user tags");
is( LJ::strip_html( qq{<lj user="test">} ), "test", qq{ strip_html <lj user="test"> } );
is( LJ::strip_html( qq{<user name="test">} ), "test", qq{ strip_html <user name="test"> } );

is( LJ::strip_html( qq{<lj user="test" site="dreamwidth.org">} ), "test", qq{ <lj user="test" site="dreamwidth.org"> } );
is( LJ::strip_html( qq{<user name="test" site="dreamwidth.org">} ), "test", qq{ <user name="test" site="dreamwidth.org"> } );

is( LJ::strip_html( qq{<lj site="dreamwidth.org" user="test">} ), "test", qq{ <lj site="dreamwidth.org" user="test"> } );
is( LJ::strip_html( qq{<user site="dreamwidth.org" name="test">} ), "test", qq{ <user site="dreamwidth.org" name="test"> } );
