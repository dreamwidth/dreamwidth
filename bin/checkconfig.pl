#!/usr/bin/perl
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use lib "$ENV{LJHOME}/extlib/lib/perl5";
use Getopt::Long;
use version;

my $debs_only = 0;
my ( $only_check, $no_check, $opt_nolocal, $opt_install );

my %dochecks;    # these are the ones we'll actually do
my @checks = (   # put these in the order they should be checked in
    "timezone",
    "modules",
    "env",
    "database",
    "secrets",
);
foreach my $check (@checks) { $dochecks{$check} = 1; }

sub usage {
    die "Usage: checkconfig.pl
checkconfig.pl --needed-debs
checkconfig.pl --only=<check> | --no=<check>
checkconfig.pl --install

Checks are:
 " . join( ', ', @checks );
}

usage()
    unless GetOptions(
    'needed-debs' => \$debs_only,
    'only=s'      => \$only_check,
    'no=s'        => \$no_check,
    'nolocal'     => \$opt_nolocal,
    'install'     => \$opt_install,
    );

if ($debs_only) {
    $dochecks{database} = 0;
    $dochecks{timezone} = 0;
    $dochecks{secrets}  = 0;
}

usage() if $only_check && $no_check;

%dochecks = ( $only_check => 1 )
    if $only_check;

$dochecks{$no_check} = 0
    if $no_check;

my @errors;
my $err = sub {
    return unless @_;
    die "\nProblem:\n" . join( '', map { "  * $_\n" } @_ );
};

my %modules;

open MODULES, "<$ENV{LJHOME}/doc/dependencies-cpanm" or die;
foreach my $module_line (<MODULES>) {
    my ( $module, $ver ) = ( $1, $2 )
        if $module_line =~ /^(.+?)(?:@(.+))?$/;
    if ($module) {
        $modules{$module} = { ver => $ver };
    }
}
close MODULES;

sub check_modules {
    print "[Checking for Perl Modules....]\n"
        unless $debs_only;

    my ( @debs, @mods );

    foreach my $mod ( sort keys %modules ) {
        my $rv = eval "use $mod ();";
        if ($@) {
            my $dt = $modules{$mod};
            unless ($debs_only) {
                if ( $dt->{opt} ) {
                    print STDERR "Missing optional module $mod: $dt->{'opt'}\n";
                }
                else {
                    push @errors, "Missing perl module: $mod";
                }
            }
            push @mods, $dt->{ver} ? "$mod\@$dt->{ver}" : $mod;
            next;
        }

        my $ver_want = $modules{$mod}{ver};
        my $ver_got  = $mod->VERSION;

        # handle version strings with multiple decimal points
        # assumes there will never be a version part prepended
        # only appended
        if ( $ver_want && $ver_got ) {
            if ( version->parse($ver_want) > version->parse($ver_got) ) {
                if ( $modules{$mod}->{opt} ) {
                    print STDERR
                        "Out of date optional module: $mod (need $ver_want, $ver_got installed)\n";
                }
                else {
                    push @errors, "Out of date module: $mod (need $ver_want, $ver_got installed)";
                }
            }
        }
    }
    if ( @debs && -e '/etc/debian_version' ) {
        if ($debs_only) {
            print join( ' ', @debs );
        }
        else {
            print STDERR "\n# apt-get install ", join( ' ', @debs ), "\n\n";
        }
    }
    if (@mods) {
        print "\n# curl -L http://cpanmin.us | sudo perl - --self-upgrade\n";
        print "# cpanm -L \$LJHOME/extlib/ " . join( ' ', @mods ) . "\n\n";
        if ($opt_install) {
            system( "cpanm", "-n", "-L", "$ENV{LJHOME}/extlib/", @mods );
        }
    }

    $err->(@errors);
}

sub check_env {
    print "[Checking LJ Environment...]\n"
        unless $debs_only;

    $err->("\$LJHOME environment variable not set.")
        unless $ENV{'LJHOME'};
    $err->("\$LJHOME directory doesn't exist ($ENV{'LJHOME'})")
        unless -d $ENV{'LJHOME'};

    # before config.pl is called, we want to call the site-local checkconfig,
    # otherwise config.pl might load config-local.pl, which could load
    # new modules to implement site-specific hooks.
    my $local_config = "$ENV{'LJHOME'}/bin/checkconfig-local.pl";
    $local_config .= ' --needed-debs' if $debs_only;
    if ( !$opt_nolocal && -e $local_config ) {
        my $good = eval { require $local_config; };
        exit 1 unless $good;
    }

    eval { require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl"; };
    $err->("Failed to load ljlib.pl: $@") if $@;

    $err->("No config-local.pl file found at etc/config-local.pl")
        unless LJ::resolve_file('etc/config-local.pl');

}

sub check_database {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
    my $dbh = LJ::get_dbh("master");
    unless ($dbh) {
        $err->("Couldn't get master database handle.");
    }
    foreach my $c (@LJ::CLUSTERS) {
        my $dbc = LJ::get_cluster_master($c);
        next if $dbc;
        $err->("Couldn't get db handle for cluster \#$c");
    }
}

foreach my $check (@checks) {
    next unless $dochecks{$check};
    my $cn = "check_" . $check;
    no strict 'refs';
    &$cn;
}

unless ($debs_only) {
    print "All good.\n";
    print "NOTE: checkconfig.pl doesn't check everything yet\n";
}

sub check_timezone {
    print "[Checking Timezone...]\n";
    my $rv = eval "use DateTime::TimeZone;";
    if ($@) {
        $err->("Missing required perl module: DateTime::TimeZone");
    }

    my $timezone = DateTime::TimeZone->new( name => 'local' );

    $err->("Timezone must be UTC.") unless $timezone->is_utc;
}

sub check_secrets {
    print "[Checking Secrets...]\n";

    foreach my $secret ( keys %LJ::Secrets::secret ) {
        my $def     = $LJ::Secrets::secret{$secret};
        my $req_len = exists $def->{len} || exists $def->{min_len} || exists $def->{max_len};
        my $rec_len =
            exists $def->{rec_len} || exists $def->{rec_min_len} || exists $def->{rec_max_len};

        my $req_min = $def->{len} || $def->{min_len} || 0;
        my $req_max = $def->{len} || $def->{max_len} || 0;

        my $rec_min = $def->{rec_len} || $def->{rec_min_len} || 0;
        my $rec_max = $def->{rec_len} || $def->{rec_max_len} || 0;
        my $val = $LJ::SECRETS{$secret} || '';
        my $len = length($val);

        if ( !defined( $LJ::SECRETS{$secret} ) || !$LJ::SECRETS{$secret} ) {
            if ( $def->{required} ) {
                $err->("Missing requred secret '$secret': $def->{desc}");
            }
            else {
                print STDERR "Missing optional secret '$secret': $def->{desc}\n";
            }
        }
        elsif ( $req_len && ( $len < $req_min || $len > $req_max ) ) {
            if ( $req_min == $req_max ) {
                $err->("Secret '$secret' not of required length: is $len, must be $req_min");
            }
            else {
                $err->(
"Secret '$secret' not of required length: is $len, must be between $req_min and $req_max"
                );
            }
        }
        elsif ( $rec_len && ( $len < $rec_min || $len > $rec_max ) ) {
            if ( $rec_min == $rec_max ) {
                print STDERR
                    "Secret '$secret' not of recommended length: is $len, should be $rec_min\n";
            }
            else {
                print STDERR
"Secret '$secret' not of recommended length: is $len, should be between $rec_min and $rec_max\n";
            }
        }
    }
}
