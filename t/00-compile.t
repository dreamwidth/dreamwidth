# t/00-compile.t
#
# Test code compilation.
#
# Authors:
#      Gabor Szabo <szabgab@gmail.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5";

use Test::Most;
use File::Temp;
use File::Find::Rule;
use File::Basename qw(dirname);
use File::Spec;

my $dir = File::Temp::tempdir( CLEANUP => 1 );

# FIXME: fix the modules that are now skipped
# some of the modules and scripts cannot yet be cleanly loaded
# instead of waiting them to be fixed we are skipping them for now
# They should be fixed or marked why they cannot run.
my %SKIP = (
    'Data/ObjectDriver/Driver/DBD/SQLite.pm' => 'Bareword "DBI::SQL_BLOB"',
    'Data/ObjectDriver/Driver/DBD/Oracle.pm' => 'no Oracle',

    'LJ/Global/BMLInit.pm' => 'BML::register_isocode called from non-conffile context',
    'cgi-bin/lj-bml-blocks.pl' => 'BML::register_block called from non-lookfile context',

    'cgi-bin/modperl.pl' => "Special file",
    'cgi-bin/modperl_subs.pl' => "Special file",
);

my @scripts = File::Find::Rule->file->name('*.pl')->in('cgi-bin', 'bin');
my @modules = File::Find::Rule->relative->file->name('*.pm')->in('cgi-bin');


plan tests => 1 * @scripts + 2 * @modules;
bail_on_fail;

#diag explain \@scripts;
#diag explain \@modules;

my $out = "$dir/out";
my $err = "$dir/err";
my $lib = File::Spec->catdir(dirname(dirname($0)), 'cgi-bin');
unshift @INC, $lib;

foreach my $file (@modules) {
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings = $_[0] || '' };

    if ($SKIP{$file}) {
        Test::More->builder->skip($SKIP{$file}) for 1..2;
    } else {
        require_ok($file);
        is( $warnings, '', "no warnings for $file" );
    }
}

foreach my $file (@scripts) {
    if ($SKIP{$file}) {
        Test::More->builder->skip($SKIP{$file});
        next;
    }

    system qq($^X -c -I$lib -I$ENV{LJHOME}/extlib/lib/perl5 $file > $out 2>$err);
    my $err_data = slurp($err);
    is($err_data, "$file syntax OK\n", "STDERR of $file");
}

# Bail out if any of the tests failed
BAIL_OUT("Aborting test suite") if scalar
    grep { not $_->{ok} } Test::More->builder->details;





######################################################################
# Support Functions

sub slurp {
    my $file = shift;
    open my $fh, '<', $file or die $!;
    local $/ = undef;
    return <$fh>;
}

