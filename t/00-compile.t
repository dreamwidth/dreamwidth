#!/usrb/bin/perl -w
use strict;
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

my @scripts = File::Find::Rule->file->name('*.pl')->in('cgi-bin');
my @modules = File::Find::Rule->relative->file->name('*.pm')->in('cgi-bin');


plan tests => 2 * @scripts + 2 * @modules;
bail_on_fail;

#diag explain \@scripts;
#diag explain \@modules;

my $out = "$dir/out";
my $err = "$dir/err";
my $lib = File::Spec->catdir(dirname(dirname($0)), 'cgi-bin');

foreach my $file (@modules) {
    my $module = substr $file, 0, -3;
    $module =~ s{/}{::}g;

    if ($SKIP{$file}) {
        Test::More->builder->skip($SKIP{$file}) for 1..2;
        next;
    }

    system qq($^X -I$lib -e "require 'ljlib.pl'; require( $module ); print 'ok';" > $out 2>$err);
    my $err_data = slurp($err);
    is($err_data, '', "STDERR of $file");

    my $out_data = slurp($out);
    is($out_data, 'ok', "STDOUT of $file");
}

foreach my $file (@scripts) {
    if ($SKIP{$file}) {
        Test::More->builder->skip($SKIP{$file}) for 1..2;
        next;
    }

    system qq($^X -I$lib $file > $out 2>$err);
    my $err_data = slurp($err);
    is($err_data, '', "STDERR of $file");

    my $out_data = slurp($out);
    is($out_data, '', "STDOUT of $file");
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

