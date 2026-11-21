# t/sysban-privs.t
#
# Tests the per-type authorization rule for web sysban management.
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

use Test::More tests => 11;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;
use LJ::User;

sub moderator {
    my (@scopes) = @_;
    return bless {
        _privloaded => { sysban => 1 },
        _priv       => @scopes ? { sysban => { map { $_ => 1 } @scopes } } : {},
        },
        'LJ::User';
}

my $scoped = moderator('fixture_alpha');
my $full   = moderator('*');

ok( LJ::Sysban::can_manage_type( $scoped, 'fixture_alpha' ), 'Matching scope allows the type' );
ok( !LJ::Sysban::can_manage_type( $scoped, 'fixture_beta' ),  'Other types need their own scope' );
ok( !LJ::Sysban::can_manage_type( $scoped, 'FIXTURE_ALPHA' ), 'Scope matching is exact' );
ok( !LJ::Sysban::can_manage_type( $scoped, undef ), 'Missing type does not use the page grant' );
ok( LJ::Sysban::can_manage_type( $full, 'fixture_alpha' ), 'Wildcard allows the first type' );
ok( LJ::Sysban::can_manage_type( $full, 'fixture_beta' ),  'Wildcard allows another type' );
ok( !LJ::Sysban::can_manage_type( $full,         '*' ), 'Wildcard is not itself a ban type' );
ok( !LJ::Sysban::can_manage_type( moderator(''), '' ),  'An empty grant does not name a type' );
ok( !LJ::Sysban::can_manage_type( moderator(), 'fixture_alpha' ), 'The grant is required' );
is_deeply( LJ::Sysban::populate_full_by_value('fixture.invalid'), {}, 'No allowed types to query' );
is_deeply( LJ::Sysban::populate_full_by_value_with_expired('fixture.invalid'),
    {}, 'No allowed types to query with expired bans' );
