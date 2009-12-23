#!/usr/bin/perl
#
# DW::Hooks::SiteSearch
#
# Hooks for Site Search functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::SiteSearch;

use strict;
use LJ::Hooks;

LJ::Hooks::register_hook( 'setprop', sub {
    my %opts = @_;
    return unless $opts{prop} eq 'opt_blockglobalsearch';

    # ensure we can talk to our system
    my $dbh = LJ::get_dbh( 'sphinx_search' )
        or die "Unable to get sphinx_search database handle.\n";
    $dbh->do( 'UPDATE posts_raw SET allow_global_search = ? WHERE journal_id = ?',
              undef, $opts{value} eq 'Y' ? 0 : 1, $opts{u}->id );
    die $dbh->errstr if $dbh->err;

    # looks good
    return 1;
} );

1;
