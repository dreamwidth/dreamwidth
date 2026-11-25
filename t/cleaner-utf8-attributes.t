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

foreach my $case ( [ 'href', 'title', '<a %s>Link</a>' ], [ 'src', 'alt', '<img %s />' ], ) {
    my ( $url_attr, $text_attr, $tag ) = @$case;
    subtest "relative $url_attr preserves UTF-8" => sub {
        my $html = sprintf $tag, qq{$url_attr="caf&ccedil;-$cedilla" $text_attr="&ccedil;"};

        LJ::CleanHTML::resolve_relative_urls( \$html, 'https://example.invalid/feed/' );

        like(
            $html,
            qr{\b$url_attr="https://example\.invalid/feed/caf%C3%A7-%C3%A7"},
            'resolved URL percent-encodes the UTF-8 bytes of both characters'
        );
        like(
            $html,
            qr{\b$text_attr="\Q$cedilla\E"},
            'rewritten tag preserves the decoded text attribute'
        );
        ok( LJ::is_utf8($html),      'output is valid UTF-8 bytes' );
        ok( !Encode::is_utf8($html), 'output has no Perl character flag' );
    };
}

subtest 'clean accepts a Perl character string' => sub {
    my $html = qq{<a href="https://example.invalid/post" title="\x{2665} &ccedil;">Link</a>};
    ok( utf8::is_utf8($html), 'input has the Perl character flag' );

    my $parsed = eval { LJ::CleanHTML::clean_event( \$html, {} ); 1 };
    ok( $parsed, 'clean_event does not croak' ) or return diag($@);

    my $expected = Encode::encode_utf8("\x{2665} \x{e7}");
    like( $html, qr{\btitle="\Q$expected\E"}, 'title preserves characters and decodes the entity' );
    ok( LJ::is_utf8($html), 'output is valid UTF-8 bytes' );
};

subtest 'resolve_relative_urls accepts a Perl character string' => sub {
    my $html = qq{<a href="post" title="\x{2665} &ccedil;">Link</a>};
    ok( utf8::is_utf8($html), 'input has the Perl character flag' );

    my $parsed =
        eval { LJ::CleanHTML::resolve_relative_urls( \$html, 'https://example.invalid/feed/' ); 1 };
    ok( $parsed, 'resolve_relative_urls does not croak' ) or return diag($@);

    like( $html, qr{\bhref="https://example\.invalid/feed/post"}, 'relative URL becomes absolute' );
    like(
        $html,
        qr{\btitle="\x{2665} \x{e7}"},
        'title preserves characters and decodes the entity'
    );
};

done_testing();
