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

    # remove all quoted lines, nice and easy
    foreach ( @lines ) {
        last if m/^\s*>/;

        # e.g., --- Original Message ---
        # but this can be in various languages, so  not hardcoding the text
        last if m/^\s*-{3,}[^-]+-{3,}\s*$/;

        # the bogus email we sent the comments as wrapped in <>
        last if m/<\s?$LJ::BOGUS_EMAIL>/;

        $num_lines++;
    }

    @lines = splice @lines, 0, $num_lines;

    # go back through the last few lines
    # look for something that looks like:
    #       On (date), someone wrote:
    my $max_backtrack = 3;
    my $backtrack = 0;

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

=head2 C<< $class->reply_subject( $text ) >>

Clean out "Re:" from the subject and decode HTML entities

=cut
sub reply_subject {
    my ( $class, $subject ) = @_;

    $subject =~ s/^(Re:\s*)*//i;
    $subject = "Re: $subject" if $subject;

    return LJ::dhtml( $subject );
}

1;
