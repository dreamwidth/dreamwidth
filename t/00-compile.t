#!/usrb/bin/perl -w
use strict;
use Test::Most;
use File::Temp;
use File::Find::Rule;
use File::Basename qw(dirname);
use File::Spec;

my $dir = File::Temp::tempdir( CLEANUP => 1 );

# FIXME: fix the modules that are now skipped
# some of the modules and scripts cannot yet cleanly loaded
# instead of waiting them to be fixed we are skipping them for now
# They should be fixed or makred why they cannot run.
my %SKIP = (
    'LJ/PersistentQueue.pm'   => 'bug 1787  needs Data::Queue::Persistent',
    'LJ/LDAP.pm'              => 'bug 1788  needs Net::LDAP',
    'LJ/ConfCheck/General.pm' => 'needs to be integrated into LJ::ConfCheck',
    'LJ/S2/EntryPage.pm'      => 'definition of S2::PROPS is missing (found in src/s2/S2.pm)',
    'LJ/Widget/CreateAccountProfile.pm' => 'Bareword "LJ::BMAX_NAME"',
    'LJ/Widget/IPPU/SettingProd.pm' => 'Bareword "LJ::get_remote"',
    'DW/User/Edges/CommMembership.pm' => 'Undefined subroutine &DW::User::Edges::define_edge',
    'DW/User/Edges/WatchTrust.pm'  => 'Bareword "LJ::BMAX_GRPNAME2"',
    'DW/User/Edges.pm'   => 'Bareword "LJ::BMAX_GRPNAME2"',
    'DW/External/XPostProtocol/LJXMLRPC.pm' => 'Cant locate object method "new" via package "DW::External::XPostProtocol::LJXMLRPC"',

    'DW/Hooks/NavStrip.pm'    => 'Undefined subroutine &LJ::register_hook',
    'DW/Hooks/SiteScheme.pm'  => 'Undefined subroutine &LJ::register_hook',
    'LJ/Hooks/PingBack.pm'    => 'Undefined subroutine &LJ::register_hook',
    'DW/Hooks/SSL.pm'         => 'Undefined subroutine &LJ::register_hook',
    'DW/Hooks/Display.pm'     => 'Undefined subroutine &LJ::register_hook',
    'DW/Hooks/Changelog.pm'   => 'Undefined subroutine &LJ::register_hook',
    'DW/Hooks/EntryForm.pm'   => 'Undefined subroutine &LJ::register_hook',
    'DW/Hooks/SiteSearch.pm'  => 'Undefined subroutine &LJ::register_hook',

    'LJ/Test/AtomAPI.pm'      => 'needs Apache/Constants',
    'Test/FakeApache.pm'      => 'needs Apache/Constants.pm',
    'Apache/CompressClientFixup.pm' => 'needs Apache/Constants.pm',

    'Data/ObjectDriver/Driver/DBD/SQLite.pm' => 'Bareword "DBI::SQL_BLOB"',
    'Data/ObjectDriver/Driver/DBD/Oracle.pm' => 'no Oracle',

    'cgi-bin/dw-nonfree.pl' => 'Undefined subroutine &LJ::register_hook',
    'cgi-bin/ljdefaults.pl' => 'Cant return outside a subroutine at cgi-bin/ljdefaults.pl',    
    'cgi-bin/modperl.pl'    => 'Cant locate object method "server" via package "Apache2::ServerUtil"',
    'cgi-bin/lj-bml-init.pl' => 'Undefined subroutine &BML::register_isocode',
    'cgi-bin/ljlib-local.pl' => 'Undefined subroutine &LJ::register_hook',
    'cgi-bin/lj-bml-blocks.pl' => 'Undefined subroutine &BML::register_block',
    'cgi-bin/ljuserpics.pl'  => 'croak is not imported',
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

    system qq($^X -I$lib -e "require $module; print 'ok';" > $out 2>$err);
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

