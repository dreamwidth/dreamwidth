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

use Test::More tests => 40;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use LJ::TextUtil;
use LJ::Hooks;

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

note("text_in - valid UTF-8");
ok( LJ::text_in("hello world"),        "ASCII is valid UTF-8" );
ok( LJ::text_in("caf\xc3\xa9"),        "valid multi-byte UTF-8" );
ok( LJ::text_in("\xe2\x9c\x93 check"), "valid 3-byte UTF-8 char" );
ok( LJ::text_in(""),                   "empty string is valid" );

note("text_in - invalid UTF-8");
ok( !LJ::text_in("\xff\xfe"),       "invalid bytes fail text_in" );
ok( !LJ::text_in("hello\x80world"), "lone continuation byte fails" );
ok( !LJ::text_in("caf\xc3"),        "truncated multi-byte sequence fails" );

note("text_trim - UTF-8 safety");
is( LJ::text_trim( "abcdef", 3, 0 ), "abc", "text_trim respects byte limit on ASCII" );
is( LJ::text_trim( "a\xc3\xa9b", 3, 0 ),
    "a\xc3\xa9", "text_trim does not cut inside a multi-byte char" );
is( LJ::text_trim( "a\xe2\x9c\x93b", 4, 0 ),
    "a\xe2\x9c\x93", "text_trim keeps complete 3-byte char within byte limit" );

note("clean_utf8");
is( LJ::clean_utf8("hello"),       "hello",       "clean ASCII is unchanged" );
is( LJ::clean_utf8("caf\xc3\xa9"), "caf\xc3\xa9", "clean multi-byte UTF-8 is unchanged" );
is( LJ::clean_utf8(""),            "",            "empty string is unchanged" );
like( LJ::clean_utf8("caf\xc3"), qr/^caf/, "truncated multi-byte gets cleaned" );
ok( LJ::text_in( LJ::clean_utf8("caf\xc3") ),            "clean_utf8 output passes text_in" );
ok( LJ::text_in( LJ::clean_utf8("\xff\xfe junk \x80") ), "arbitrary bad bytes become valid UTF-8" );
is( LJ::clean_utf8(undef), "", "undef input returns empty string" );

note("clean_utf8 - 4-byte UTF-8 (emoji)");
is( LJ::clean_utf8("\xf0\x9f\x8e\x89"), "\xf0\x9f\x8e\x89", "4-byte emoji preserved" );
is( LJ::clean_utf8("\xe4\xb8\xad\xf0\x9f\x8e"),
    "\xe4\xb8\xad", "valid CJK preserved, truncated 4-byte emoji stripped" );
