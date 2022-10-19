# Alert site administrators when someone makes a money order
#
# Authors:
#     Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Hooks::MailboxAlert;

use strict;
use LJ::Hooks;

LJ::Hooks::register_hook(
    'check_money_order_pending',
    sub {
        my ( $cart, $u ) = @_;

        LJ::send_mail(
            {
                to       => $LJ::ACCOUNTS_EMAIL,
                from     => $LJ::BOGUS_EMAIL,
                fromname => $LJ::SITENAME,
                subject  => LJ::Lang::ml(
                    'shop.admin.checkmoneyorder.subject',
                    { sitename => $LJ::SITENAME }
                ),
                body => LJ::Lang::ml(
                    'shop.admin.checkmoneyorder.body',
                    {
                        user       => LJ::isu($u) ? $u->display_name : $cart->email,
                        receipturl => "$LJ::SITEROOT/shop/receipt?ordernum=" . $cart->ordernum,
                    }
                ),
            }
        );

    }
);

1;
