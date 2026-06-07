# t/dw-locker.t
#
# Tests for DW::Locker (named advisory locks backed by MySQL GET_LOCK).
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

my $probe = eval { LJ::get_dbh( { unshared => 1 }, "master" ) };
plan skip_all => "no MySQL master available"
    unless $probe && $probe->{Driver}{Name} eq 'mysql';

my $name = "t:dwlocker:$$";

# Each lock holds its own dedicated connection, so a single locker still
# enforces mutual exclusion: a second acquire of the same name contends with
# the first instead of succeeding on a shared session.
my $locker = DW::Locker->new;

my $a = $locker->trylock($name);
ok( $a,                       "acquired $name" );
ok( !$locker->trylock($name), "second acquire of the same name is blocked (same locker)" );

$a->release;
my $b = $locker->trylock($name);
ok( $b,                               "re-acquired after release" );
ok( !DW::Locker->new->trylock($name), "a different locker is also blocked while held" );

# A blocking acquire returns undef once the wait elapses without the lock.
my $t0 = time();
ok( !$locker->trylock( $name, wait => 1 ), "blocking acquire times out while held" );
ok( time() - $t0 >= 1, "...and actually waited ~1s" );

$b->release;
ok( $locker->trylock( $name, wait => 1 ), "blocking acquire succeeds once free" );

# Auto-release when the holder goes out of scope (its connection drops).
{
    my $scoped = $locker->trylock("$name:scoped");
    ok( $scoped, "scoped lock acquired" );
}
ok( $locker->trylock("$name:scoped"), "scoped lock auto-released on scope exit" );

# A name longer than GET_LOCK's 64-char limit is normalized, not errored.
ok( $locker->trylock( "$name:" . ( "x" x 200 ) ), "over-long name normalized and acquired" );

done_testing();
