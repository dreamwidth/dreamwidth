#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::CleanEmail;

use strict;

=head1 NAME

DW::CleanEmail - Clean up text from email

=head1 SYNOPSIS

=cut

=head2 C<< $class->nonquoted_text( $text ) >>

Returns original content from an email body. That is, non-quoted

=cut

sub nonquoted_text {
    my ( $class, $text ) = @_;

    my @lines = split /$/m, $text;

    my $num_lines = 0;
    my $address   = quotemeta( $LJ::BOGUS_EMAIL // '' );

    # remove all quoted lines, nice and easy
    foreach (@lines) {
        last if m/^\s*>/;

        # e.g., --- Original Message ---
        # but this can be in various languages, so  not hardcoding the text
        last if m/^\s*-{3,}[^-]+-{3,}\s*$/;

        # Angle brackets may be literal or entity-escaped, with an optional mailto suffix.
        # Standalone mailto forms need a terminator so longer addresses do not match.
        if (
            $address
            && m{
              <\h*$address\h*(?=>|<mailto:)
            | &lt;\h*$address\h*(?=&gt;|&lt;mailto:)
            | mailto:\h*$address(?=$|[\s>"'\]),;?]|&(?:gt|quot|apos|\#39);)
        }ix
            )
        {
            my $quote_start = _quote_block_start( substr $_, 0, $-[0] );
            if ( defined $quote_start ) {
                my $reply = substr $_, 0, $quote_start;
                return join "", @lines[ 0 .. $num_lines - 1 ], $reply if $reply =~ /\S/;
            }

            last;
        }

        $num_lines++;
    }

    @lines = splice @lines, 0, $num_lines;

    # go back through the last few lines
    # look for something that looks like:
    #       On (date), someone wrote:
    my $max_backtrack = 3;
    my $backtrack     = 0;

    foreach ( reverse @lines ) {
        $backtrack++;
        last if $backtrack > $max_backtrack;

        last if m/^\s*On.+wrote:\s*$/i;

        # sometimes that gets split across two lines
        # so look for date-like things too
        last if m!^\s*On (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)!i;
        last if m!
              (?:\d{2}/\d{2}/\d{4})                 # mm/dd/yyyy
            | (?:[a-z]{3,4}\s+\d{1,2},\s+\d{4})     # Jan 31, 2013
            | (?:\d{1,2}\s+[a-z]{3,4}\s+\d{4})      # 31 Jan 2013

        !ix;
    }

    @lines = splice @lines, 0, $num_lines - $backtrack
        unless $backtrack > $max_backtrack || $backtrack >= $num_lines;

    return join "", @lines;
}

sub _quote_block_start {
    my ($before_address) = @_;

    # Use the innermost open block so an enclosing block can keep its reply text.
    # Include adjacent opening wrappers and br/hr separators only if no content intervenes.
    my @blocks;
    my $boundary;
    my $previous_end = -1;
    while (
        $before_address =~ m{\s*<(/?)([a-z][\w:-]*)(?=[\s/>])(?:[^"'<>]++|"[^"]*"|'[^']*')*>}ig )
    {
        my ( $closing, $tag, $start, $end ) = ( $1, lc $2, $-[0], $+[0] );
        my $is_block = $tag =~ /\A(?:div|p|blockquote)\z/;
        if ( !$closing && ( $is_block || $tag eq 'br' || $tag eq 'hr' ) ) {
            $boundary = $start if $start != $previous_end;
            push @blocks, $boundary if $is_block;
            $previous_end = $end;
        }
        else {
            pop @blocks if $is_block;
            $previous_end = -1;
        }
    }

    return $blocks[-1];
}

=head2 C<< $class->reply_subject( $text ) >>

Clean out "Re:" from the subject and decode HTML entities

=cut

sub reply_subject {
    my ( $class, $subject ) = @_;

    $subject =~ s/^(Re:\s*)*//i;
    $subject = "Re: $subject" if $subject;

    return LJ::dhtml($subject);
}

1;
