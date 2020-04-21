#!/usr/bin/perl
#
# DW::TaskQueue
#
# Library for queueing and executing jobs.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::Display::ManageTOTP;
use base 'LJ::Setting';

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub actionlink {
    my ( $class, $u ) = @_;

    return "<a href='$LJ::SITEROOT/manage2fa'>Manage</a>";
}

sub label {
    my $class = shift;

    return 'Two-Factor Authentication';
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    return $u->has_totp
        ? "enabled (<a href='$LJ::SITEROOT/manage2fa'>view recovery codes</a>)"
        : "<em>disabled</em>";
}

1;
