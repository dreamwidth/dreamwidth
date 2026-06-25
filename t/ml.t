# t/ml.t
#
# Tests the basics of the multilang (ML) string system: LJ::Lang::set_text /
# get_text / get_text_multi, the in-process + memcache caching, parent-language
# fallback, and the production "auto-load strings from the source files on a DB
# miss" behavior.
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

my $gen  = eval { LJ::Lang::get_dom('general') };
my $dmid = $gen ? $gen->{dmid} : undef;
plan skip_all => "ML general domain not loaded in test DB" unless $dmid;

my $fixture = "$ENV{LJHOME}/views/dev/t_ml_autoload.tt.text";
my @cleanup;

# clear the in-process + memcache copies of a code across every language
sub flush_code {
    my $code = shift;
    my $lc   = lc $code;
    LJ::MemCache::delete("ml.$_.$dmid.$lc") for ( 'en', @LJ::LANGS );
}

# force a real DB read of a code (bypassing %TXT_CACHE and memcache)
sub db_value {
    my ( $lang, $code ) = @_;
    flush_code($code);
    local $LJ::NO_ML_CACHE = 1;
    return LJ::Lang::get_text_multi( $lang, $dmid, [$code] )->{$code};
}

# start each code from a clean slate
sub fresh_code {
    my $code = shift;
    push @cleanup, $code;
    eval { LJ::Lang::remove_text( $dmid, $code ); };
    flush_code($code);
    return $code;
}

# find a child language of en so we can exercise parent fallback
my $child;
{
    my $en = LJ::Lang::get_lang('en');
    if ($en) {
        my $dbr = LJ::get_db_reader();
        ($child) = $dbr->selectrow_array(
            "SELECT lncode FROM ml_langs WHERE parentlnid = ? AND lncode <> 'en' LIMIT 1",
            undef, $en->{lnid} );
    }
}
diag( "child language for fallback tests: " . ( $child // "(none found)" ) );

# ---------------------------------------------------------------------------
# is_missing_string
# ---------------------------------------------------------------------------
ok( LJ::Lang::is_missing_string(''),                     "empty string is missing" );
ok( LJ::Lang::is_missing_string('[missing string foo]'), "[missing ...] is missing" );
ok( !LJ::Lang::is_missing_string('a real value'),        "a real value is not missing" );

# ---------------------------------------------------------------------------
# basic round trip: set_text -> get_text_multi (DB) -> get_text (prod)
# ---------------------------------------------------------------------------
{
    my $code = fresh_code("zzz.mltest.basic");
    ok( LJ::Lang::is_missing_string( db_value( 'en', $code ) ), "unset code is missing in the DB" );

    ok( LJ::Lang::set_text( $dmid, 'en', $code, "Hello World", {} ), "set_text stores a string" );
    is( db_value( 'en', $code ), "Hello World", "get_text_multi reads it back from the DB" );

    local $LJ::IS_DEV_SERVER = 0;
    is( LJ::Lang::get_text( 'en', $code, $dmid ),
        "Hello World", "get_text (prod) returns the stored string" );
}

# ---------------------------------------------------------------------------
# cache coherence: a set_text must clear a previously-cached miss
# (this is what lets an auto-load be seen by a long-lived worker)
# ---------------------------------------------------------------------------
{
    local $LJ::IS_DEV_SERVER = 0;
    my $code = fresh_code("zzz.mltest.cache");

    LJ::Lang::get_text( 'en', $code, $dmid );    # caches the empty miss
    LJ::Lang::set_text( $dmid, 'en', $code, "Now Set", {} );
    is( LJ::Lang::get_text( 'en', $code, $dmid ),
        "Now Set", "set_text invalidates the cached miss (no stale empty)" );
}

# ---------------------------------------------------------------------------
# parent/child fallback: setting en with childrenlatest materializes a row
# for each descendant language
# ---------------------------------------------------------------------------
SKIP: {
    skip "no child language available", 2 unless $child;
    my $code = fresh_code("zzz.mltest.fallback");
    LJ::Lang::set_text( $dmid, 'en', $code, "Parent Text", { childrenlatest => 1 } );
    is( db_value( 'en',   $code ), "Parent Text", "en has the row" );
    is( db_value( $child, $code ), "Parent Text", "child language falls back to the en source" );
}

# ---------------------------------------------------------------------------
# our change: auto-load a general-domain string from the source files
# ---------------------------------------------------------------------------
{
    my $code = fresh_code("/dev/t_ml_autoload.tt.auto");

    open my $fh, '>', $fixture or die "can't write fixture $fixture: $!";
    print $fh ";; -*- coding: utf-8 -*-\n.auto=Autoloaded Value\n";
    close $fh;

    ok(
        LJ::Lang::is_missing_string( db_value( 'en', $code ) ),
        "fixture code is absent from the DB before any request"
    );

    # dev: reads straight from the file, must NOT persist to the DB
    {
        local $LJ::IS_DEV_SERVER = 1;
        is(
            LJ::Lang::get_text( 'en', $code, $dmid ),
            "Autoloaded Value",
            "dev get_text reads the value from the file"
        );
    }
    ok(
        LJ::Lang::is_missing_string( db_value( 'en', $code ) ),
        "dev did not persist the string to the DB"
    );

    # prod: auto-loads from the file AND persists it
    {
        local $LJ::IS_DEV_SERVER = 0;
        is(
            LJ::Lang::get_text( 'en', $code, $dmid ),
            "Autoloaded Value",
            "prod get_text auto-loads the value from the file"
        );
    }
    is( db_value( 'en', $code ), "Autoloaded Value", "prod auto-load persisted the string" );

SKIP: {
        skip "no child language available", 1 unless $child;
        is(
            db_value( $child, $code ),
            "Autoloaded Value",
            "auto-load materialized the child-language fallback row"
        );
    }

    unlink $fixture;
}

END {
    if ($dmid) {
        foreach my $code (@cleanup) {
            eval { LJ::Lang::remove_text( $dmid, $code ); };
        }
    }
    unlink $fixture if $fixture;
}

done_testing();
