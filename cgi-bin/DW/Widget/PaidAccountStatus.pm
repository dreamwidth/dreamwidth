#!/usr/bin/perl
#
# DW::Widget::PaidAccountStatus
#
# Renders happy box to show a paid account's status.
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

package DW::Widget::PaidAccountStatus;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

use DW::Pay;
use DW::Shop;

# general purpose shop CSS used by the entire shop system
sub need_res { qw( stc/widgets/shop.css ) }

# main renderer for this particular thingy
sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $account_type = DW::Pay::get_account_type_name( $remote );
    my $expires_at = DW::Pay::get_account_expiration_time( $remote );
    my $expires_on = $expires_at > 0
                     ? 'Your paid time expires: ' . LJ::mysql_time( $expires_at )
                     : '';

    my $ret = qq{
<div class='shop-account-status'>
    Your current account type is: <strong>$account_type</strong><br />
    $expires_on
</div>
    };

    return $ret;
}

1;
