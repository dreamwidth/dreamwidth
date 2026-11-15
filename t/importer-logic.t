# t/importer-logic.t
#
# Tests DW::Logic::Importer's per-user import bookkeeping.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );
use Storable qw( thaw );

use DW::Logic::Importer;

my $dbh = LJ::get_db_writer();

sub add_import {
    my ( $u, $impid ) = @_;
    $dbh->do(
        'INSERT INTO import_data (userid, import_data_id, hostname, username, password_md5) '
            . 'VALUES (?, ?, ?, ?, ?)',
        undef, $u->id, $impid, 'remote.example', $u->user, 'x'
    );
    die $dbh->errstr if $dbh->err;
}

sub options_of {
    my ( $u, $impid ) = @_;
    my $raw = $dbh->selectrow_array(
        'SELECT options FROM import_data WHERE userid = ? AND import_data_id = ?',
        undef, $u->id, $impid );
    return $raw ? thaw($raw) : undef;
}

# import ids are per-user counters, so two users routinely have an import with the same id;
# saving one user's options must not touch the other's
{
    my ( $one, $two ) = ( temp_user(), temp_user() );
    add_import( $one, 1 );
    add_import( $two, 1 );

    my $err = DW::Logic::Importer->set_import_data_options_for_user(
        $one,
        import_data_id        => 1,
        lj_entries_remap_icon => 1
    );
    ok( !$err, 'options saved' ) or diag($err);

    is_deeply(
        options_of( $one, 1 ),
        { lj_entries_remap_icon => 1 },
        'the options land on this user'
    );
    is( options_of( $two, 1 ), undef, "another user's import with the same id is untouched" );
}

done_testing();
