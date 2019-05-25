#!/usr/bin/perl
#
# DW::Widget::PaidAccountStatus
#
# Renders happy box to show a paid account's status.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::PaidAccountStatus;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

use DW::Pay;
use DW::Shop;

sub need_res { qw( stc/shop.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $account_type = DW::Pay::get_account_type_name($remote);
    my $expires_at   = DW::Pay::get_account_expiration_time($remote);
    my $expires_on =
        $expires_at > 0
        ? "<br />"
        . $class->ml('widget.paidaccountstatus.expiretime') . " "
        . LJ::mysql_time($expires_at)
        : '';

    my $ret = "<div class='shop-item-highlight shop-account-status'>";
    $ret .= $class->ml('widget.paidaccountstatus.accounttype') . " ";
    $ret .= "<strong>$account_type</strong>$expires_on";
    $ret .= "</div>";

    return $ret;
}

1;
