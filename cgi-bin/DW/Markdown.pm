# DW::Markdown - Dreamwidth's Markdown paragraph handling
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

package DW::Markdown;

use strict;
use warnings;

use parent 'Text::Markdown';
use HTML::TokeParser;

sub _FormParagraphs {
    my ( $self, $text, $options ) = @_;

    return $self->SUPER::_FormParagraphs( $text, $options )
        unless $text =~ m{</?(?:details|summary)(?:\s|>)}i;

    $text =~ s/\A\n+//;
    $text =~ s/\n+\z//;

    my @paragraphs;
    my $details_depth = 0;
    my $in_summary    = 0;
    my $details_tag   = sub {
        my ($type) = @_;
        $details_depth++ if $type eq 'S';
        $details_depth-- if $type eq 'E' && $details_depth;
        $in_summary = 0;
    };
    my $protect = sub {
        my ($html) = @_;
        my $key = Text::Markdown::_md5_utf8($html);
        $self->{_html_blocks}{$key} = $html;
        push @paragraphs, $key;
    };

    foreach my $paragraph ( split /\n{2,}/, $text ) {
        if ( exists $self->{_html_blocks}{$paragraph} ) {

            # Lists and blockquotes can absorb a lazy continuation containing
            # </details>. Keep their HTML intact, but account for its boundaries.
            my $block  = $self->{_html_blocks}{$paragraph};
            my $parser = HTML::TokeParser->new( \$block );
            while ( my $token = $parser->get_token ) {
                $details_tag->( $token->[0] )
                    if ( $token->[0] eq 'S' || $token->[0] eq 'E' )
                    && $token->[1] eq 'details';
            }
            push @paragraphs, $paragraph;
            next;
        }
        if ( !$in_summary && $paragraph !~ m{</?(?:details|summary)(?:\s|>)}i ) {
            push @paragraphs, $paragraph;
            next;
        }

        # Process spans first so code spans and escaped tags remain literal.
        # Existing raw HTML blocks have already been protected by Text::Markdown.
        my $html     = $self->_RunSpanGamut($paragraph);
        my $parser   = HTML::TokeParser->new( \$html );
        my $fragment = '';
        my $rendered = '';
        my $flush    = sub {
            if ( $fragment =~ /\S/ ) {
                $fragment =~ s/^[ \t]*//;
                $fragment = "<p>$fragment</p>" if $options->{wrap_in_p_tags} && !$in_summary;
                $rendered .= $fragment;
            }
            $fragment = '';
        };

        while ( my $token = $parser->get_token ) {
            my $type = $token->[0];
            my $raw  = $token->[ $type eq 'S' ? 4 : $type eq 'E' || $type eq 'PI' ? 2 : 1 ];

            if (
                ( $type eq 'S' || $type eq 'E' )
                && ( $token->[1] eq 'details'
                    || ( $details_depth && $token->[1] eq 'summary' ) )
                )
            {
                $flush->();
                $rendered .= $raw;
                if ( $token->[1] eq 'details' ) {
                    $details_tag->($type);
                }
                else {
                    $in_summary = $type eq 'S';
                }
            }
            else {
                $fragment .= $raw;
            }
        }
        $flush->();
        $protect->($rendered);
    }

    # Keep the disclosure boundaries outside generated paragraphs. Treating the
    # whole details element as a raw HTML block would disable Markdown in its body.
    # Hashes also prevent the superclass from interpreting the processed spans twice.
    return $self->SUPER::_FormParagraphs( join( "\n\n", @paragraphs ), $options );
}

1;
