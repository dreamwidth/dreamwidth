# t/watchtrust-userhelper.t
#
# Test watch and trust relationship lists without loading ljlib.pl.
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

use Test::More;
use DW::User::Edges::WatchTrust::UserHelper;

{

    package WatchTrustTestUser;

    sub new {
        my ( $class, %fields ) = @_;
        return bless \%fields, $class;
    }

    sub id                 { return $_[0]->{id} }
    sub display_name       { return $_[0]->{name} }
    sub statusvis          { return $_[0]->{status} }
    sub is_individual      { return $_[0]->{individual} }
    sub trusted_by_userids { return @{ $_[0]->{trusted_by} } }
    sub watched_by_userids { return @{ $_[0]->{watched_by} } }
}

my %users = map {
    my ( $id, $name, $status, $individual ) = @$_;
    $id => WatchTrustTestUser->new(
        id         => $id,
        name       => $name,
        status     => $status,
        individual => $individual
    );
} (
    [ 11, 'Zulu',      'V', 1 ],
    [ 12, 'Alpha',     'M', 1 ],
    [ 13, 'Echo',      'L', 1 ],
    [ 14, 'Deleted',   'D', 1 ],
    [ 15, 'Community', 'V', 0 ],
    [ 17, 'Hidden',    'V', 1 ],
    [ 18, 'Inbound',   'V', 1 ],
    [ 19, 'Outbound',  'V', 1 ],
    [ 20, 'Other',     'V', 1 ],
);

no warnings 'once';
local *LJ::load_userids = sub {
    return { map { $_ => $users{$_} } @_ };
};

my $owner = WatchTrustTestUser->new(
    trusted_by => [ 11, 12, 14, 15, 16, 17, 18 ],
    watched_by => [ 11, 13, 14, 15, 16, 17, 20 ],
);
my $helper = DW::User::Edges::WatchTrust::UserHelper->new(
    $owner,
    t_userids => { map { $_ => 1 } ( 11, 12, 14, 15, 16, 19 ) },
    w_userids => { map { $_ => 1 } ( 11, 13, 14, 15, 16, 17, 19 ) },
    hide_watch_test_cb => sub { return $_[0] == 17 },
    load_cap           => 1,
);

eval { DW::User::Edges::WatchTrust::UserHelper->new( $owner, unexpected => 1 ) };
like( $@, qr/unknown params/, 'rejects an unsupported constructor option' );

is_deeply(
    [ map { $_->id } $helper->mutually_trusted_users ],
    [ 12, 11 ],
    'mutual trusts include only visible individuals, sorted by display name'
);
is( scalar $helper->mutually_trusted_users, 2, 'counts the filtered mutual trusts' );

is_deeply(
    [ map { $_->id } $helper->mutually_watched_users ],
    [ 13, 11 ],
    'mutual watches exclude hidden users as well as unavailable accounts'
);
is( scalar $helper->mutually_watched_users, 2, 'counts the filtered mutual watches' );

is_deeply(
    [ map { $_->id } $helper->trusted_by_users ],
    [ 12, 18, 11 ],
    'exact inbound trusts include one-way trusts and omit hidden users'
);
is( scalar $helper->trusted_by_users, 3, 'exact inbound trust count can exceed the load cap' );

my $capped = DW::User::Edges::WatchTrust::UserHelper->new(
    WatchTrustTestUser->new( trusted_by => [ 11, 18, 20, 12 ] ),
    t_userids => { 11 => 1, 12 => 1, 19 => 1 },
    sloppy    => 1,
    load_cap  => 3,
);
is_deeply(
    [ map { $_->id } $capped->trusted_by_users ],
    [ 12, 18, 11 ],
    'capped inbound trusts prioritize both mutuals without spending a second slot on one'
);
is( scalar $capped->trusted_by_users, 3, 'capped inbound trust count reflects the limited list' );

my $inbound_only = DW::User::Edges::WatchTrust::UserHelper->new($owner);
is( scalar $inbound_only->mutually_trusted_users, 0, 'no mutual trusts without outbound trusts' );
is( scalar $inbound_only->mutually_watched_users, 0, 'no mutual watches without outbound watches' );

ok( !grep( m{(?:^|/)ljlib\.pl$}, keys %INC, values %INC ), 'does not load ljlib.pl' );

done_testing();
