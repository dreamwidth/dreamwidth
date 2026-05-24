# t/dw-locker.t
#
# Tests for DW::Locker (MySQL GET_LOCK advisory locks with file fallback).
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Locker;
use File::Temp qw/ tempdir /;

# ---- file backend ----
my $dir = tempdir( CLEANUP => 1 );
my $fl  = DW::Locker->new( backend => 'file', lockdir => $dir );

my $lock = $fl->trylock("foo");
ok( $lock,                "file: acquired foo" );
ok( !$fl->trylock("foo"), "file: second acquire of foo fails while held" );
ok( $fl->trylock("bar"),  "file: a different name acquires" );

$lock->release;
ok( $fl->trylock("foo"), "file: re-acquire foo after release" );

# auto-release on scope exit
{
    my $scoped = DW::Locker->new( backend => 'file', lockdir => $dir )->trylock("scoped");
    ok( $scoped, "file: scoped lock acquired" );
}
ok( DW::Locker->new( backend => 'file', lockdir => $dir )->trylock("scoped"),
    "file: scoped lock auto-released on scope exit" );

# ---- mysql backend (requires the devcontainer MySQL master) ----
SKIP: {
    my $probe = eval { LJ::get_dbh( { unshared => 1 }, "master" ) };
    skip "no MySQL master available", 7
        unless $probe && $probe->{Driver}{Name} eq 'mysql';

    my $l1 = DW::Locker->new( backend => 'mysql' );
    my $l2 = DW::Locker->new( backend => 'mysql' );
    my $name = "t:dwlocker:$$";

    my $m = $l1->trylock($name);
    ok( $m, "mysql: l1 acquired" );
    is( ( ref $m && $m->{backend} ), 'mysql', "mysql: lock uses the mysql backend" );
    ok( !$l2->trylock($name), "mysql: l2 blocked while l1 holds" );
    $m->release;
    ok( $l2->trylock($name), "mysql: l2 acquires after release" );

    # a name longer than the 64-char GET_LOCK limit is normalized, not errored
    ok(
        $l1->trylock( "t:dwlocker:" . ( "x" x 200 ) ),
        "mysql: over-long name normalized and acquired"
    );

    # auto-release when the holder goes out of scope (connection drops)
    my $sname = "t:dwlocker:scope:$$";
    {
        my $s = DW::Locker->new( backend => 'mysql' )->trylock($sname);
        ok( $s, "mysql: scoped lock acquired" );
    }
    ok(
        DW::Locker->new( backend => 'mysql' )->trylock($sname),
        "mysql: scoped lock auto-released on scope exit"
    );
}

done_testing();
