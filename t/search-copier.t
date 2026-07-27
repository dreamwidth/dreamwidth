# t/search-copier.t
#
# Unit tests for DW::Task::SearchCopier::_security_bits, the sole encoder that
# turns a log2 (security, allowmask) into the security_bits MVA stored in
# Manticore. The DW::Search query side (t/search.t) depends on this encoding,
# so pinning it here keeps the encode and query sides from silently drifting.
#
# Pure function: no DB, no Manticore, so this runs everywhere.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Task::SearchCopier;

sub bits { return DW::Task::SearchCopier::_security_bits(@_); }

# public / private carry a discriminator bit and no allowmask bits.
is_deeply( bits( 'public',  0 ), [102], 'public -> [102]' );
is_deeply( bits( 'private', 0 ), [101], 'private -> [101]' );

# usemask with no groups is auto-converted to private.
is_deeply( bits( 'usemask', 0 ), [101], 'usemask/allowmask=0 auto-converts to private [101]' );

# The crux: a plain access-list lock (allowmask=1) encodes to a lone [0].
# 0 is bit_breakdown(1) -- the default access group -- NOT garbage.
is_deeply( bits( 'usemask', 1 ), [0], 'usemask/allowmask=1 (access list) -> [0]' );

# Custom access filters live at bit >= 1 and carry no discriminator.
is_deeply( bits( 'usemask', 2 ), [1], 'usemask/allowmask=2 -> [1] (one custom group)' );
is_deeply( bits( 'usemask', 6 ), [ 1, 2 ], 'usemask/allowmask=6 -> [1,2] (two custom groups)' );

# 0 appears in the output ONLY for access-list entries: public/private never
# emit it, so DW::Search can treat a stored 0 as "access list" unambiguously.
ok( !( grep { $_ == 0 } @{ bits( 'public',  0 ) } ), 'public output never contains 0' );
ok( !( grep { $_ == 0 } @{ bits( 'private', 0 ) } ), 'private output never contains 0' );

# Encoder is pure: a numeric-string allowmask works and args are untouched.
my $mask = '1';
is_deeply( bits( 'usemask', $mask ), [0], 'numeric-string allowmask is handled' );
is( $mask, '1', 'argument not mutated' );

done_testing();
