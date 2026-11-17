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

use Test::More tests => 20;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user);
use LJ::Entry;

my $u = temp_user();

my $entry_real = $u->t_post_fake_entry;
my $ditemid    = $entry_real->{ditemid};
my $jitemid    = $entry_real->{jitemid};
my $anum       = $entry_real->{anum};

note("test entry from jitemid (valid jitemid)");
{
    LJ::Entry->reset_singletons;
    my $entry_from_jitemid = LJ::Entry->new( $u, jitemid => $jitemid );
    ok( $entry_from_jitemid->valid,        "valid entry" );
    ok( $entry_from_jitemid->correct_anum, "correct anum" );
}

note("test entry from jitemid (invalid jitemid");
{
    LJ::Entry->reset_singletons;
    my $entry_from_jitemid = LJ::Entry->new( $u, jitemid => $jitemid + 1 );
    ok( !$entry_from_jitemid->valid,        "invalid entry" );
    ok( !$entry_from_jitemid->correct_anum, "incorrect anum" );
}

note("test entry from ditemid (valid ditemid) ");
{
    LJ::Entry->reset_singletons;
    my $entry_from_ditemid = LJ::Entry->new( $u, ditemid => $ditemid );
    ok( $entry_from_ditemid->valid,        "valid entry" );
    ok( $entry_from_ditemid->correct_anum, "correct anum" );
}

note("test entry from ditemid (valid jitemid, invalid anum)");
{
    LJ::Entry->reset_singletons;
    my $entry_from_ditemid =
        LJ::Entry->new( $u, ditemid => ( $jitemid << 8 ) + ( ( $anum + 1 ) % 256 ) );
    ok( $entry_from_ditemid->valid,         "valid entry" );
    ok( !$entry_from_ditemid->correct_anum, "incorrect anum" );
}

note("test entry from ditemid (invalid jitemid, invalid anum)");
{
    LJ::Entry->reset_singletons;
    my $entry_from_ditemid = LJ::Entry->new( $u, ditemid => ( $jitemid + 1 ) );
    ok( !$entry_from_ditemid->valid,        "valid entry" );
    ok( !$entry_from_ditemid->correct_anum, "incorrect anum" );
}

note("correct_anum ignores a ditemid lazily filled by ditemid()");
{
    # A permalink emitted elsewhere (e.g. the active-entries module) calls ditemid()
    # on the shared singleton, which must not make correct_anum read _untrusted_anum.
    LJ::Entry->reset_singletons;
    my $entry_from_jitemid = LJ::Entry->new( $u, jitemid => $jitemid );
    $entry_from_jitemid->ditemid;
    ok( $entry_from_jitemid->correct_anum, "correct anum after ditemid() fills {ditemid}" );
}

note("dated URLs resolve by slug even when the slug is all digits");
{
    LJ::Entry->reset_singletons;
    my $decoy     = $u->t_post_fake_entry( body => 'numeric slug decoy' );
    my $colliding = $u->t_post_fake_entry( body => 'numeric slug collision' );
    my $absent    = $u->t_post_fake_entry( body => 'numeric slug absent ID' );
    isnt( $decoy->jitemid,     $colliding->jitemid, 'decoy and colliding entries differ' );
    isnt( $decoy->jitemid,     $absent->jitemid,    'decoy and absent-ID entries differ' );
    isnt( $colliding->jitemid, $absent->jitemid,    'numeric slug entries differ' );
    my $absent_id = ( $absent->jitemid + 1000 ) << 8;
    $colliding->slug( $decoy->ditemid );
    $absent->slug($absent_id);
    ok( LJ::Entry->new( $u, ditemid => $decoy->ditemid )->valid, 'colliding ID names an entry' );
    ok( !LJ::Entry->new( $u, ditemid => $absent_id )->valid, 'absent ID names no entry' );

    my $from_url = LJ::Entry->new_from_url( $colliding->url );
    is( $from_url && $from_url->ditemid, $colliding->ditemid, "slug matching another entry ID" );

    $from_url = LJ::Entry->new_from_url( $absent->url );
    is( $from_url && $from_url->ditemid, $absent->ditemid, "slug matching no entry ID" );

    my $wrong_date = $colliding->url;
    $wrong_date =~ s!/\d{4}/\d\d/\d\d/!/1900/01/01/!;
    ok( !LJ::Entry->new_from_url($wrong_date), "wrong date does not fall back to the entry ID" );

    $from_url = LJ::Entry->new_from_url( $u->journal_base . '/' . $decoy->ditemid . '.html' );
    is( $from_url && $from_url->ditemid, $decoy->ditemid, "entry ID URL keeps its meaning" );
}

1;

