# t/entry-lookup.t
#
# Test LJ::Entry lookups.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 10;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user);
use LJ::Entry;

my $u = temp_user();

my $entry_real = $u->t_post_fake_entry;
my $ditemid = $entry_real->{ditemid};
my $jitemid = $entry_real->{jitemid};
my $anum = $entry_real->{anum};

note( "test entry from jitemid (valid jitemid)" );
{
    LJ::Entry->reset_singletons;
    my $entry_from_jitemid = LJ::Entry->new( $u, jitemid => $jitemid );
    ok( $entry_from_jitemid->valid, "valid entry" );
    ok( $entry_from_jitemid->correct_anum, "correct anum" );
}

note( "test entry from jitemid (invalid jitemid" );
{
    LJ::Entry->reset_singletons;
    my $entry_from_jitemid = LJ::Entry->new( $u, jitemid => $jitemid + 1 );
    ok( ! $entry_from_jitemid->valid, "invalid entry" );
    ok( ! $entry_from_jitemid->correct_anum, "incorrect anum" );
}

note( "test entry from ditemid (valid ditemid) ");
{
    LJ::Entry->reset_singletons;
    my $entry_from_ditemid = LJ::Entry->new( $u, ditemid => $ditemid );
    ok( $entry_from_ditemid->valid, "valid entry" );
    ok( $entry_from_ditemid->correct_anum, "correct anum" );
}

note( "test entry from ditemid (valid jitemid, invalid anum)" );
{
    LJ::Entry->reset_singletons;
    my $entry_from_ditemid = LJ::Entry->new( $u, ditemid => ( $jitemid << 8 ) + ( ( $anum + 1 ) % 256 ) );
    ok(   $entry_from_ditemid->valid, "valid entry" );
    ok( ! $entry_from_ditemid->correct_anum, "incorrect anum" );
}

note( "test entry from ditemid (invalid jitemid, invalid anum)" );
{
    LJ::Entry->reset_singletons;
    my $entry_from_ditemid = LJ::Entry->new( $u, ditemid => ( $jitemid + 1 ) );
    ok( ! $entry_from_ditemid->valid, "valid entry" );
    ok( ! $entry_from_ditemid->correct_anum, "incorrect anum" );
}

1;

