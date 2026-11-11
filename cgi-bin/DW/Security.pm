#!/usr/bin/perl
#
# DW::Security
#
# Shared normalization of security levels and access masks.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Security;

use strict;
use warnings;

=head2 normalize( $security, $allowmask )

Returns a security level and access mask. The legacy friends and access aliases
mean usemask with basic access (mask 1). Explicit usemask preserves its mask,
defaulting to 0 when undefined; other security levels have no access mask.

Callers supply a defined security level and validate it for their own operation.

=cut

sub normalize {
    my ( $class, $security, $allowmask ) = @_;

    return ( 'usemask', 1 )               if $security =~ /^(?:friends|access)$/;
    return ( $security, $allowmask // 0 ) if $security eq 'usemask';
    return ( $security, 0 );
}

1;
