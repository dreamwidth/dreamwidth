#!/usr/bin/perl
#
# DW::Hooks::Pay
#
# Hooks tht are part of the payment system.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2008 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::Pay;

use strict;

# FIXME: these should probably be stripped

LJ::register_hook( 'name_caps', sub {
    my $caps = shift()+0;

    if ( $caps & 128 ) {
        return "Premium Permanent Account";
    } elsif ( $caps & 64 ) {
        return "Basic Permanent Account";
    } elsif ( $caps & 16 ) {
        return "Premium Paid Account";
    } elsif ( $caps & 8 ) {
        return "Basic Paid Account";;
    } else {
        return "Free Account";
    }
} );

LJ::register_hook( 'name_caps_short', sub {
    my $caps = shift()+0;

    if ( $caps & 128 ) {
        return "Premium Permanent";
    } elsif ( $caps & 64 ) {
        return "Basic Permanent";
    } elsif ( $caps & 16 ) {
        return "Premium Paid";
    } elsif ( $caps & 8 ) {
        return "Basic Paid";;
    } else {
        return "Free";
    }
} );

LJ::register_hook( 'userinfo_rows', sub {
    my $u = $_[0]->{u};
    my $remote = $_[0]->{remote};

    return if $u->is_identity || $u->is_syndicated;

    my $type = LJ::run_hook( 'name_caps', $u->{caps} );

    return ( 'Account Type', $type )
        unless LJ::u_equals( $u, $remote );

    my $ps = DW::Pay::get_paid_status( $u );
    return ( 'Account Type', $type )
        unless $ps && ! $ps->{permanent};

    return ( 'Account Type', "$type<br />Expires: " . LJ::mysql_time( $ps->{expiretime} ) );
} );

1;
