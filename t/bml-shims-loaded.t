#!/usr/bin/perl
# Requiring ljlib.pl alone (workers, maintenance scripts, anything without
# app.psgi) must not load the BML engine: no ljlib-loaded module calls a
# BML::* shim any more, so a stray engine import would be a regression. The
# require runs in an isolated perl subprocess so this test file's own imports
# cannot mask what ljlib.pl pulls in.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

my ( $probe_fh, $probe_file ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $probe_fh <<'PROBE';
BEGIN { $LJ::_T_CONFIG = 1; }
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
for my $module (qw(DW/BML.pm Apache/BML.pm LJ/Global/BMLInit.pm)) {
    print "$module=", ( exists $INC{$module} ? 1 : 0 ), "\n";
}
print "GET_REQUEST=",  ( defined &BML::get_request  ? 1 : 0 ), "\n";
print "SET_LANGUAGE=", ( defined &BML::set_language ? 1 : 0 ), "\n";
print "ML=",           ( defined &BML::ml           ? 1 : 0 ), "\n";
print "ADAPTER=",      ( exists $INC{'DW/BML/RequestAdapter.pm'} ? 1 : 0 ), "\n";
PROBE
close $probe_fh;

open( my $out_fh, '-|', $^X, $probe_file ) or die "can't run probe subprocess: $!";
my @lines = <$out_fh>;
close $out_fh;

is( $? >> 8, 0, 'probe subprocess exited cleanly after requiring ljlib.pl alone' )
    or diag( "probe output:\n", @lines );

my %got;
for (@lines) {
    $got{$1} = $2 if /^([\w\/\.]+)=(\d)$/;
}

ok( !$got{'DW/BML.pm'},            'ljlib.pl alone does not load DW::BML' );
ok( !$got{'Apache/BML.pm'},        'ljlib.pl alone does not load Apache::BML' );
ok( !$got{'LJ/Global/BMLInit.pm'}, 'ljlib.pl alone does not load LJ::Global::BMLInit' );
ok( !$got{GET_REQUEST},            'BML::get_request is not defined without the engine' );
ok( !$got{SET_LANGUAGE},           'BML::set_language is not defined without the engine' );
ok( !$got{ML},                     'BML::ml is not defined without the engine' );
ok( $got{ADAPTER}, 'the hook/callback adapter module still loads without the engine' );

done_testing;
