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
    my $details_depth  = 0;
    my $in_summary     = 0;
    my $disclosure_tag = sub {
        my ( $type, $tag ) = @_;
        if ( $tag eq 'details' ) {
            $details_depth++ if $type eq 'S';
            $details_depth-- if $type eq 'E' && $details_depth;
            $in_summary = 0;
        }
        elsif ( $details_depth && $tag eq 'summary' ) {
            $in_summary = $type eq 'S';
        }
    };
    my $protect = sub {
        my ($html) = @_;
        my $key = Text::Markdown::_md5_utf8($html);
        $self->{_html_blocks}{$key} = $html;
        push @paragraphs, $key;
    };

    # Parse the rendered paragraphs together: an HTML comment can cross blank
    # lines, and disclosure-looking text inside it must remain opaque.
    my $html = join "\n\n", map {
        exists $self->{_html_blocks}{$_} ? $_ : $self->_RunSpanGamut($_)
    } split /\n{2,}/, $text;
    my $parser = HTML::TokeParser->new( \$html );
    my $fragment = '';
    my $rendered = '';
    my $flush = sub {
        if ( $fragment =~ /\S/ ) {
            $fragment =~ s/^[ \t]*//;
            $fragment = "<p>$fragment</p>" if $options->{wrap_in_p_tags} && !$in_summary;
            $rendered .= $fragment;
        }
        $fragment = '';
    };
    my $finish_paragraph = sub {
        $flush->();
        $protect->($rendered) if length $rendered;
        $rendered = '';
    };
    my $scan_block = sub {
        my ($block) = @_;
        my $tokens = HTML::TokeParser->new( \$block );
        my @opened;
        while ( my $token = $tokens->get_token ) {
            my ( $type, $tag ) = @$token;
            if ( $type eq 'S' ) {
                push @opened, $tag;
            }
            elsif ( $type eq 'E' ) {
                my $match;
                for ( my $i = $#opened; $i >= 0; $i-- ) {
                    if ( $opened[$i] eq $tag ) {
                        $match = $i;
                        last;
                    }
                }
                if ( defined $match ) {
                    # The cleaner closes anything opened inside a container
                    # when that container ends. Those openings are block-local.
                    splice @opened, $match;
                }
                else {
                    # A lazy continuation may instead close a disclosure that
                    # began outside the stored list or blockquote.
                    $disclosure_tag->( $type, $tag );
                }
            }
        }
    };

    while ( my $token = $parser->get_token ) {
        my $type = $token->[0];
        my $raw = $token->[ $type eq 'S' ? 4 : $type eq 'E' || $type eq 'PI' ? 2 : 1 ];
        if ( $type eq 'T' ) {
            foreach my $part ( split /(\n{2,})/, $raw ) {
                if ( $part =~ /\A\n{2,}\z/ ) {
                    $finish_paragraph->();
                }
                elsif ( exists $self->{_html_blocks}{$part} ) {
                    $finish_paragraph->();
                    $scan_block->( $self->{_html_blocks}{$part} );
                    push @paragraphs, $part;
                }
                else {
                    $fragment .= $part;
                }
            }
        }
        elsif (
            ( $type eq 'S' || $type eq 'E' )
            && ( $token->[1] eq 'details'
                || ( $details_depth && $token->[1] eq 'summary' ) )
            )
        {
            $flush->();
            $rendered .= $raw;
            $disclosure_tag->( $type, $token->[1] );
        }
        else {
            $fragment .= $raw;
        }
    }
    $finish_paragraph->();

    # Keep the disclosure boundaries outside generated paragraphs. Treating the
    # whole details element as a raw HTML block would disable Markdown in its body.
    # Hashes also prevent the superclass from interpreting the processed spans twice.
    return $self->SUPER::_FormParagraphs( join( "\n\n", @paragraphs ), $options );
}

1;
