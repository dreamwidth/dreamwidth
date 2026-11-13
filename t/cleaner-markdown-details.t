# t/cleaner-markdown-details.t
#
# Test paragraph grouping and sanitization of Markdown disclosure elements.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::CleanHTML;

foreach my $surface (qw(event comment)) {
    subtest $surface => sub {
        my $clean = sub {
            my ( $text, $editor ) = @_;
            my $opts = { editor => $editor // 'markdown_latest' };
            if ( $surface eq 'event' ) {
                LJ::CleanHTML::clean_event( \$text, $opts );
            }
            else {
                LJ::CleanHTML::clean_comment( \$text, $opts );
            }
            chomp $text;
            return $text;
        };

        my $source = <<'MARKDOWN';
<details><summary>Summary</summary>
Paragraph 1

Paragraph 2

Paragraph 3</details>
MARKDOWN

        like(
            $clean->($source),
            qr{
                \A <details> \s* <summary>Summary</summary>
                \s* <p>\s*Paragraph[ ]1</p> \s* <p>Paragraph[ ]2</p>
                \s* <p>Paragraph[ ]3</p> \s* </details> \z
            }x,
            'blank-line paragraphs all belong to the disclosure, with a direct-child summary'
        );

        # These are the other two forms in support request 46691. Unclosed p
        # tags are intentional: the report compares them with bare paragraphs.
        foreach my $explicit (
            "<p>Paragraph 1\n\n<p>Paragraph 2\n\n<p>Paragraph 3",
            "<p>Paragraph 1\n\nParagraph 2\n\nParagraph 3"
            )
        {
            my $html = $clean->("<details><summary>Summary</summary>\n$explicit</details>");
            like(
                $html,
                qr{
                    \A <details> \s* <summary>Summary</summary>
                    (?:(?!</details>).)* Paragraph[ ]1
                    (?:(?!</details>).)* Paragraph[ ]2
                    (?:(?!</details>).)* Paragraph[ ]3 .* </details> \z
                }xs,
                'explicit paragraph tags still keep all three paragraphs inside'
            );
        }

        like(
            $clean->("Before\n\n$source\nAfter"),
            qr{
                \A <p>Before</p> \s* <details> .* Paragraph[ ]3</p>
                \s* </details> \s* <p>\s*After</p> \z
            }xs,
            'surrounding text remains outside the disclosure'
        );

        like(
            $clean->(
                      '<details><summary>*Summary*</summary>**one**' . "\n\n"
                    . '[two][link]</details>'
                    . "\n\n[link]: https://example.com/"
            ),
            qr{
                \A <details> \s* <summary><em>Summary</em></summary>
                \s* <p><strong>one</strong></p>
                \s* <p><a[ ]href="https://example.com/">two</a></p> \s* </details> \z
            }x,
            'summary emphasis, body emphasis and reference links retain Markdown semantics'
        );

        like(
            $clean->("<details>\nOne\n\nTwo\n</details>"),
            qr{\A<details>\s*<p>\s*One</p>\s*<p>Two\s*</p>\s*</details>\z},
            'disclosures without an explicit summary retain both paragraphs'
        );

        like(
            $clean->(
                      '<details><summary>Outer</summary>One' . "\n\n"
                    . '<details><summary>Inner</summary>Two'
                    . "\n\nThree</details>\n\n"
                    . 'Four</details>'
            ),
            qr{
                \A <details> \s* <summary>Outer</summary> \s* <p>One</p>
                \s* <details> \s* <summary>Inner</summary>
                \s* <p>Two</p> \s* <p>Three</p> \s* </details>
                \s* <p>Four</p> \s* </details> \z
            }x,
            'nested disclosures keep their own paragraphs'
        );

        like(
            $clean->("<details><summary>List</summary>\n\n* one\n* two\n\n</details>"),
            qr{
                \A <details> \s* <summary>List</summary>
                \s* <ul> \s* <li>one</li> \s* <li>two</li> \s* </ul>
                \s* </details> \z
            }x,
            'Markdown lists remain blocks inside the disclosure'
        );

        like(
            $clean->( $source . "\n" . $source ),
            qr{\A<details>.*</details>\s*<details>.*</details>\z}s,
            'adjacent disclosures remain siblings'
        );

        like(
            $clean->(
                '<DETAILS title="a > b"><SUMMARY>Summary</SUMMARY>One' . "\n\nTwo</DETAILS>"
            ),
            qr{
                \A <details[ ]title="a[ ]&gt;[ ]b"> \s* <summary>Summary</summary>
                \s* <p>One</p> \s* <p>Two</p> \s* </details> \z
            }x,
            'tag case and greater-than signs inside quoted attributes are handled as HTML'
        );

        is(
            $clean->('`<details><summary>literal</summary></details>`'),
'<p><code>&lt;details&gt;&lt;summary&gt;literal&lt;/summary&gt;&lt;/details&gt;</code></p>',
            'inline code containing disclosure tags remains literal'
        );

        like(
            $clean->("    <details><summary>literal</summary></details>\n"),
            qr{
                \A <pre><code>&lt;details&gt;&lt;summary&gt;literal&lt;/summary&gt;&lt;/details&gt;
                \s* </code></pre> \z
            }x,
            'indented code containing disclosure tags remains literal'
        );

        is(
            $clean->('<pre><details>*literal*</details></pre>'),
            '<pre><details>*literal*</details></pre>',
            'raw preformatted HTML still suppresses Markdown'
        );
        is(
            $clean->('<div><details>*literal*</details></div>'),
            '<div><details>*literal*</details></div>',
            'raw HTML blocks still suppress Markdown'
        );

        foreach my $summary ( '<summary>Unclosed', '<summary>Title<summary>' ) {
            like(
                $clean->(
                          "<details>$summary\n\nHidden</details>\n\n"
                        . "Later paragraph one.\n\nLater paragraph two."
                ),
                qr{</details>\s*<p>Later[ ]paragraph[ ]one\.</p>
                    \s*<p>Later[ ]paragraph[ ]two\.</p>\z}x,
                'an unclosed summary cannot remove paragraph wrapping after its disclosure'
            );
        }

        foreach my $prefix ( '', '<details><summary>Title</summary>Body</details>' . "\n\n" ) {
            like(
                $clean->(
                          $prefix . "Use the <summary> element for titles.\n\n"
                        . "Second paragraph.\n\nThird paragraph."
                ),
                qr{<p>Second[ ]paragraph\.</p>\s*<p>Third[ ]paragraph\.</p>\z},
                'a stray summary outside a disclosure cannot remove later paragraph wrapping'
            );
        }

        my $unsafe = $clean->(<<'MARKDOWN');
<details open ontoggle="alert(1)"><summary onclick="alert(2)">Summary</summary>
Safe

<script>alert(3)</script>

<a href="javascript:alert(4)">Link</a>

Last</details>
MARKDOWN
        unlike(
            $unsafe,
            qr{<script|\bon(?:toggle|click)\s*=|javascript:}i,
            'handlers, scripts and unsafe links are still cleaned inside disclosures'
        );
        like(
            $unsafe,
            qr{\A<details\b.*Last</p>\s*</details>\z}s,
            'sanitization retains the complete disclosure body'
        );

        like(
            $clean->(
                '<details><summary>HTML</summary><p>One</p><p>Two</p></details>', 'html_raw0'
            ),
            qr{\A<details><summary>HTML</summary><p>One</p><p>Two</p></details>\z},
            'HTML editor behavior is unchanged'
        );
        is(
            $clean->("*one*\n\ntwo"),
            '<p><em>one</em></p>' . "\n\n<p>two</p>",
            'ordinary Markdown paragraph behavior is unchanged'
        );
    };
}

done_testing;
