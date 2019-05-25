#!/usr/bin/perl
#
# DW::Setting::Display::AccountLevel - shows user's current account
# level and a link to the shop.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Setting::Display::AccountLevel;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && ( $u->is_person || $u->is_community ) && LJ::is_enabled('payments') ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.accounttype.label');
}

sub actionlink {
    my ( $class, $u ) = @_;

    my $paidstatus = DW::Pay::get_paid_status($u);

    my $gifturl = $u->gift_url;
    if ( $paidstatus && $paidstatus->{permanent} ) {
        return "";
    }
    elsif ( $paidstatus && DW::Pay::get_account_type( $u->userid ) eq "premium" ) {

        # tell premium paid users to just add more time, not upgrade
        return "<a href='$gifturl'>" . $class->ml('setting.display.accounttype.addmore') . "</a>";
    }
    else {
        return "<a href='$gifturl'>" . $class->ml('setting.display.accounttype.upgrade') . "</a>";
    }
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $paidstatus = DW::Pay::get_paid_status($u);
    my $typeid     = $paidstatus ? $paidstatus->{typeid} : DW::Pay::default_typeid();
    my $expiretime = "(never)";

    my $paidtype = "<strong>" . DW::Pay::type_name($typeid) . "</strong>";
    $expiretime = LJ::mysql_time( $paidstatus->{expiretime} )
        if $paidstatus && !$paidstatus->{permanent};

    if ( $paidstatus && $paidstatus->{expiresin} > 0 && !$paidstatus->{permanent} ) {
        return BML::ml( 'setting.display.accounttype.status',
            { status => $paidtype, exptime => $expiretime } );
    }
    else {
        return $paidtype;
    }
}

1;
