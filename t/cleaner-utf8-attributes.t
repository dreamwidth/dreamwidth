#!/usr/bin/perl
#
# t/cleaner-utf8-attributes.t
#
# Test UTF-8 output for character references in HTML attributes and cut labels.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use Encode ();

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;

my $cedilla = Encode::encode( 'UTF-8', chr(0xe7) );
my $heart   = Encode::encode( 'UTF-8', chr(0x2665) );

my @cases = (
    [ 'named Latin-1 reference',       '&ccedil;',                  $cedilla ],
    [ 'decimal Latin-1 reference',     '&#231;',                    $cedilla ],
    [ 'hexadecimal Latin-1 reference', '&#xE7;',                    $cedilla ],
    [ 'literal UTF-8',                 $cedilla,                    $cedilla ],
    [ 'Latin-1 and wider references',  '&ccedil; &hearts;',         "$cedilla $heart" ],
    [ 'literal UTF-8 and reference',   "$cedilla &ccedil;",         "$cedilla $cedilla" ],
    [ 'escaped ampersand',             '&amp;ccedil;',              '&ccedil;' ],
    [ 'markup characters',             '&lt;script&gt;&quot;&amp;', '<script>"&' ],
);

foreach my $case (@cases) {
    my ( $name, $input, $expected ) = @$case;
    foreach my $surface (qw(cut title alt)) {
        next if $surface eq 'cut' && $name =~ /^(?:escaped ampersand|markup characters)$/;
        subtest "$surface: $name" => sub {
            my $html =
                  $surface eq 'cut' ? qq{<lj-cut text='$input'>Hidden text</lj-cut>}
                : $surface eq 'title'
                ? qq{<a href="https://example.invalid/" title='$input'>Link</a>}
                : qq{<img src="https://example.invalid/image.png" alt='$input' />};

            LJ::CleanHTML::clean_event( \$html, { cuturl => 'https://example.invalid/entry' } );

            my $escaped = LJ::ehtml($expected);
            if ( $surface eq 'cut' ) {

                # A cut label is text rather than an attribute; quotes are literal.
                $escaped = $expected;
                $escaped =~ s/</&lt;/g;
                $escaped =~ s/>/&gt;/g;
                like(
                    $html,
                    qr{<a href="https://example\.invalid/entry#cutid1">\Q$escaped\E</a>},
                    'cut label preserves the intended characters'
                );
            }
            else {
                like( $html, qr{\b$surface="\Q$escaped\E"},
                    'attribute preserves and escapes the intended characters' );
            }
            ok( LJ::is_utf8($html),      'output is valid UTF-8 bytes' );
            ok( !Encode::is_utf8($html), 'output has no Perl character flag' );
        };
    }
}

done_testing();
