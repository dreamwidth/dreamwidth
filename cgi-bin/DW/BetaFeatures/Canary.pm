#!/usr/bin/perl
#
# DW::BetaFeatures::Canary
#
# Handler for putting someone in or out of using canary.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2022 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::BetaFeatures::Canary;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use base 'LJ::BetaFeatures::default';

use LJ::Session;

sub add_to_beta {
    my ( $cls, $u ) = @_;

    LJ::Session::set_cookie(
        dwcanary  => 1,
        domain    => $LJ::DOMAIN,
        path      => '/',
        http_only => 1,
        expires   => 365 * 86400,
    );

    $log->debug( 'Adding ', $u->user, '(', $u->id, ') to canary.' );
}

sub remove_from_beta {
    my ( $cls, $u ) = @_;

    LJ::Session::set_cookie(
        dwcanary  => 1,
        domain    => $LJ::DOMAIN,
        path      => '/',
        http_only => 1,
        delete    => 1,
    );

    $log->debug( 'Removing ', $u->user, '(', $u->id, ') from canary.' );
}

