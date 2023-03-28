# Hooks to modify the index list for /legal (views/legal/index.tt)
#
# Authors:
#     Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Hooks::LegalIndex;

use strict;
use warnings;
use LJ::Hooks;

LJ::Hooks::register_hook(
    'modify_legal_index',
    sub {
        my $index = $_[0];
        my @extra = qw ( principles diversity dmca );
        unshift @$index, @extra;
    }
);

1;
