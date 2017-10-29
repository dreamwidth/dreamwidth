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
use LJ::Hooks;

LJ::Hooks::register_hook( 'ssl_check', sub {
    my $apache_r = $_[0]->{r}
        or return 0;

    # Set if all traffic is SSL
    return 1 if $LJ::ALL_TRAFFIC_IS_SSL;

    # SSL_HEADER would be set by caching proxy
    return 1 if $LJ::SSL_HEADER &&
                ( $apache_r->headers_in->{$LJ::SSL_HEADER} == 1 ||
                  lc $apache_r->headers_in->{$LJ::SSL_HEADER} eq 'https' );
    # fallback: true if using port defined in config
    return 1 if $LJ::SSL_PORT &&
                $apache_r->get_server_port == $LJ::SSL_PORT;
    return 0;
} );

1;
