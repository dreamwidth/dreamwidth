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

# Displays extra info on finduser results. Called as:
#   LJ::run_hooks("finduser_extrainfo", $u })
# Currently used to return paid status, expiration date, and number of
# unused invite codes. 

LJ::register_hook( 'finduser_extrainfo', sub {
    my $u = shift;

    my $ret;

    my $paidstatus = DW::Pay::get_paid_status( $u );
    my $numinvites = DW::InviteCodes->unused_count( userid => $u->id );

    if ( $paidstatus ) {
        $ret .= "  " . DW::Pay::type_name( $paidstatus->{typeid} ) . ", expiring " . LJ::mysql_time( $paidstatus->{expiretime} ) . "\n";
    }

    if ( $numinvites ) {
        $ret .= "  Unused invites: " . $numinvites . "\n";
    }

});

1;
