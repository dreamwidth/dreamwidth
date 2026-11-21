# t/openid-insanejournal.t
#
# Tests for reusing legacy InsaneJournal OpenID accounts.
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

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );

my $suffix       = temp_user()->id;
my $legacy_url   = "http://dw_openid_$suffix.insanejournal.com/";
my $verified_url = "https://dw-openid-$suffix.insanejournal.com/";
my $legacy       = LJ::User::load_identity_user( 'O', $legacy_url );
BAIL_OUT('Could not create the legacy OpenID fixture') unless $legacy;

my $claimed = LJ::User::load_identity_user( 'O', $verified_url );
is( $claimed && $claimed->id,
    $legacy->id, 'the verified InsaneJournal URL resolves to the existing legacy account' );

ok(
    !LJ::User::load_existing_identity_user( 'O', "${verified_url}other/" ),
    'a different path on the same journal host does not resolve to the legacy account'
);

my $lj_legacy = LJ::User::load_identity_user( 'O', "http://dw_openid_$suffix.livejournal.com/" );
BAIL_OUT('Could not create the LiveJournal OpenID fixture') unless $lj_legacy;
ok( !LJ::User::load_existing_identity_user( 'O', "https://dw-openid-$suffix.livejournal.com/" ),
    'LiveJournal identity matching is unchanged' );

my $canonical_url = "http://dw-openid-$suffix-exact.insanejournal.com/";
my $canonical     = LJ::User::load_identity_user( 'O', $canonical_url );
my $alias =
    LJ::User::load_identity_user( 'O', "http://dw_openid_${suffix}_exact.insanejournal.com/" );
BAIL_OUT('Could not create the exact-match fixtures') unless $canonical && $alias;
isnt( $canonical->id, $alias->id, 'both stored spellings can already have distinct accounts' );
my $exact = LJ::User::load_existing_identity_user( 'O', $canonical_url );
is( $exact && $exact->id, $canonical->id, 'an exact identity takes precedence over the alias' );

done_testing();
