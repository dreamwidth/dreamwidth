#
# Use this hook to turn on SSL mode if a certain header is present.  See the
# SSL documentation for more information on usage.
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

package DW::Hooks::SSL;

use strict;

LJ::register_hook( 'ssl_check', sub {
    my $r = $_[0]->{r}
        or return 0;

    return 1 if $LJ::SSL_HEADER &&
                $r->headers_in->{$LJ::SSL_HEADER} == 1;
    return 0;
} );

1;
