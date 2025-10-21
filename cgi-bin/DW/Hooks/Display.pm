#!/usr/bin/perl
#
# DW::Hooks::Display
#
# A file for miscellaneous display-related hooks.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::Display;

use strict;
use LJ::Hooks;

# Displays extra info on finduser results. Called as:
#   LJ::Hooks::run_hooks("finduser_extrainfo", $u })
# Currently used to return paid status, expiration date, and number of
# unused invite codes.

LJ::Hooks::register_hook(
    'finduser_extrainfo',
    sub {
        my $u = shift;

        my $ret;

        my $paidstatus = DW::Pay::get_paid_status($u);
        my $numinvites = DW::InviteCodes->unused_count( userid => $u->id );

        unless ( DW::Pay::is_default_type($paidstatus) ) {
            $ret .= "  " . DW::Pay::type_name( $paidstatus->{typeid} );
            $ret .=
                $paidstatus->{permanent}
                ? ", never expires"
                : ", expiring " . LJ::mysql_time( $paidstatus->{expiretime} );
            $ret .= "\n";
        }

        if ($numinvites) {
            $ret .= "  Unused invites: " . $numinvites . "\n";
        }

        return $ret;
    }
);

1;
