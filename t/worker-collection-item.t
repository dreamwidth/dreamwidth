# t/worker-collection-item.t
#
# Test worker memory limits and collection items without ljlib.pl.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use Test::Most;
use Time::HiRes qw(sleep);

use DW::Collection::Item;
use LJ::Worker;

lives_ok { LJ::Worker->check_limits } 'worker starts without a memory limit';

LJ::Worker->set_memory_limit( 2**40 );
lives_ok { LJ::Worker->check_limits } 'worker continues when RSS is below the limit';

LJ::Worker->set_memory_limit(0);
sleep 1.05;
my $warning = '';
{
    local $SIG{__WARN__} = sub { $warning .= $_[0] };
    throws_ok { LJ::Worker->check_limits } qr/maximum ram usage: [1-9]\d* greater than 0/,
        'worker terminates after exceeding a zero-byte limit';
}
like( $warning, qr/Unable to contact mother process/, 'worker reports an unavailable mother' );

LJ::Worker->set_memory_limit(undef);
sleep 1.05;
lives_ok { LJ::Worker->check_limits } 'clearing the limit lets the next memory check continue';

my %row = (
    userid      => 17,
    colitemid   => 23,
    colid       => 42,
    itemtype    => 1,
    itemownerid => 96,
    itemid      => 108,
    logtime     => 1_767_323_045,
);
my $item = DW::Collection::Item->new_from_row(%row);
is_deeply(
    [ map { $item->$_() } qw(userid id colid itemtype itemownerid itemid logtime) ],
    [ @row{qw(userid colitemid colid itemtype itemownerid itemid logtime)} ],
    'collection row preserves the distinct collection and item identities'
);

my $other_item = DW::Collection::Item->new_from_row( %row, userid => 21, itemownerid => 97 );
is_deeply(
    [
        map { [ $_->userid, $_->colid, $_->id, $_->itemownerid, $_->itemid ] }
            ( $item, $other_item )
    ],
    [ [ 17, 42, 23, 96, 108 ], [ 21, 42, 23, 97, 108 ] ],
    'overlapping local IDs do not conflate rows belonging to different users'
);

ok( !grep( { defined && m{(?:^|/)ljlib[.]pl\z} } ( keys %INC, values %INC ) ),
    'ljlib.pl was not loaded' );
done_testing();
