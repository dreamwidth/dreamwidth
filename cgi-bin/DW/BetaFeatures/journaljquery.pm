#!/usr/bin/perl
#
# DW::BetaFeatures::journaljquery - Allow users to beta test the updated jquery-ified journals
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::BetaFeatures::journaljquery;

use strict;
use base "LJ::BetaFeatures::default";

sub args_list {
    my @implemented = (
        "Cut expand and collapse (basic)",
        "Logging in",
        "Screen/freeze/delete",
        "Control strip injection for non-supporting journals",
        "Quick reply",
        "Thread expander",
        "Same-page poll submission",
        "Media embed placeholder expansion",
        "Contextual hover",
        "Icon browser",
    );

    my @notimplemented = (
        "Same-page comment tracking",
        "Some features for the cut expand/collapse",
    );

    return (
        implemented => "<ul>" . join( "\n", map { "<li>$_</li>" } @implemented ) . "</ul>",
        notimplemented => "<ul>" . join( "\n", map { "<li>$_</li>" } @notimplemented ) . "</ul>",
    );
}

1;
