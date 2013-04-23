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
        last if m/^\s*-*Original Message-*/;
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
        # so look for date-like things toomail
        last if m!^\s*On (Mon|Tue|Wed|Thu|Fri|Sat|Sun|(?:\d{2}/\d{2}/\d{4})|(?:[a-z]{3,4} \d{1,2}, \d{4}))!i;
    }

    @lines = splice @lines, 0, $num_lines - $backtrack
        unless $backtrack > $max_backtrack || $backtrack >= $num_lines;

    return join "", @lines;
}

=head2 C<< $class->reply_subject( $text ) >>

Clean out "Re:" from the subject

=cut
sub reply_subject {
    my ( $class, $subject ) = @_;

    $subject =~ s/^(Re:\s*)*//i;
    $subject = "Re: $subject" if $subject;

    return $subject;
}

1;