#!/usr/bin/perl
#
# DW::External::Site::Bluesky
#
# Class to support the special case of users with @*.bsky.social usernames (so
# you don't have to tack a .bsky on the end).
#
# Authors:
#      Joshua Barrett <jjbarr@ptnote.dev>
#
# Copyright (c) 2026 by Dreamwidth Studios LLC.
#
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself. For a copy of the
# license, please reference 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::External::Site::BlueskySocial;

use strict;
use base 'DW::External::Site::Bluesky';
use Carp qw/ croak /;

sub canonical_username {
    my $input = $_[1];
    my $user  = "";

    if ( $input =~ m/^\s*((?:[a-z0-9][a-z0-9\-]*)?[a-z0-9])\s*$/i ) {
        $user = lc $1 . ".bsky.social";
    }
    return $user;
}

1;
