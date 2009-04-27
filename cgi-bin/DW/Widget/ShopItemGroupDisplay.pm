#!/usr/bin/perl
#
# DW::Widget::ShopItemGroupDisplay
#
# Renders a group of shop items for display on the first page of the shop.
#
# Authors:
#      Janine Costanzo <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::ShopItemGroupDisplay;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

sub need_res { qw( stc/shop.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote();
    my $ret;

    if ( $opts{group} eq 'paidaccounts' ) {
        $ret .= "<h2>" . $class->ml( 'widget.shopitemgroupdisplay.paidaccounts.header' ) . "</h2>";
        $ret .= "<ul>";
        if ( $remote && $remote->is_personal && DW::Pay::get_account_type( $remote ) ne 'seed' ) {
            $ret .= "<li>" . $class->ml( 'widget.shopitemgroupdisplay.paidaccounts.item.self', { aopts => "href='$LJ::SITEROOT/shop/account?for=self'", user => $remote->ljuser_display } ) . "</li>";
            $ret .= "<li>" . $class->ml( 'widget.shopitemgroupdisplay.paidaccounts.item.differentaccount', { aopts => "href='$LJ::SITEROOT/shop/account?for=gift'" } ) . "</li>";
        } else {
            $ret .= "<li>" . $class->ml( 'widget.shopitemgroupdisplay.paidaccounts.item.exisitingaccount', { aopts => "href='$LJ::SITEROOT/shop/account?for=gift'" } ) . "</li>";
        }
        $ret .= "<li>" . $class->ml( 'widget.shopitemgroupdisplay.paidaccounts.item.newaccount', { aopts => "href='$LJ::SITEROOT/shop/account?for=new'" } ) . "</li>";
        $ret .= "</ul>";
    }

    return $ret;
}

1;
