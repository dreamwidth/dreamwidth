# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }


use LJ::Test qw(temp_user);
use LJ::Entry;

plan tests => 10;

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
    warn "$entry_real->{ditemid}; $entry_real->{anum} ;; $entry_from_ditemid->{ditemid}; $entry_from_ditemid->{anum}";
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

