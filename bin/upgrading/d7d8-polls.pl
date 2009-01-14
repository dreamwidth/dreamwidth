#!/usr/bin/perl
#
# Goes over every user, updating their dversion to 8 and
# migrating whatever polls they have to their user cluster

use strict;
use warnings;
use lib "$ENV{'LJHOME'}/cgi-bin/";
require "ljlib.pl";
use LJ::Poll;
use Term::ReadLine;
use Getopt::Long;

my $BLOCK_SIZE = 10_000; # get users in blocks of 10,000
my $VERBOSE    = 0;      # print out extra info
my $need_help;
my @cluster;
my $endtime;

my $help = <<"END";
Usage: $0 [options]
Options:
    --cluster=N Specify user cluster to work on (by default, all clusters)
    --hours=N   Work no more than N hours (by default, work until all is done)
    --verbose   Be noisy
    --help      Print this help and exit
END

GetOptions(
    "help"      => \$need_help,
    "cluster=i" => \@cluster,
    "verbose"   => \$VERBOSE,
    "hours=i"   => sub { $endtime = $_[1]*3600+time(); },
    
) or die $help;
if ($need_help) {
    print $help;
    exit(0);
}

unless (@cluster) {
    no warnings 'once';
    @cluster = (0, @LJ::CLUSTERS);
}

my %handle;

# database handle retrieval sub
my $get_db_handles = sub {
    # figure out what cluster to load
    my $cid = shift(@_) + 0;

    my $dbh = $handle{writer};
    unless ($dbh) {
        $dbh = $handle{writer} = LJ::get_dbh({ raw => 1 }, "master");
        print "Connecting to master writer ($dbh)...\n";
        eval {
            $dbh->do("SET wait_timeout=28800");
        };
        $dbh->{'RaiseError'} = 1;
    }

    my $dbhslo = $handle{reader};
    unless ($dbhslo) {
        $dbhslo = $handle{reader} = LJ::get_dbh({ raw => 1 }, "slow", "master");
        print "Connecting to master reader ($dbhslo)...\n";
        eval {
            $dbhslo->do("SET wait_timeout=28800");
        };
        $dbhslo->{'RaiseError'} = 1;
    }


    my $dbcm;
    $dbcm = $handle{$cid} if $cid;
    if ($cid && ! $dbcm) {
        $dbcm = $handle{$cid} = LJ::get_cluster_master({ raw => 1 }, $cid);
        print "Connecting to cluster $cid ($dbcm)...\n";
        return undef unless $dbcm;
        eval {
            $dbcm->do("SET wait_timeout=28800");
        };
        $dbcm->{'RaiseError'} = 1;
    }

    # return one or both, depending on what they wanted
    return $cid ? ($dbh, $dbhslo, $dbcm) : $dbh;
};


my $dbh = LJ::get_db_writer()
    or die "Could not connect to global master";


my $term = new Term::ReadLine 'd7-d8 migrator';
my $line = $term->readline("Do you want to update to dversion 8 (clustered polls)? [N/y] ");
unless ($line =~ /^y/i) {
    print "Not upgrading to dversion 8\n\n";
    exit;
}

print "\n--- Upgrading users to dversion 8 (clustered polls) ---\n\n";

# get user count
my $total = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion = 7");
print "\tTotal users at dversion 7: $total\n\n";

my $migrated = 0;
my $flag_stop_work = 0;

MAIN_LOOP:
foreach my $cid (@cluster) {
    # get a handle for every user to revalidate our connection?
    my ($mdbh, $mdbhslo, $udbh) = $get_db_handles->($cid)
        or die "Could not get cluster master handle for cluster $cid";

    while (1) {
        my $sth = $mdbh->prepare("SELECT userid FROM user WHERE dversion=7 AND clusterid=? LIMIT $BLOCK_SIZE");
        $sth->execute($cid);
        die $sth->errstr if $sth->err;

        my $count = $sth->rows;
        print "\tGot $count users on cluster $cid with dversion=7\n";
        last unless $count;
        
        local($SIG{TERM}, $SIG{INT}, $SIG{HUP});
        $SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { $flag_stop_work = 1; };
        while (my ($userid) = $sth->fetchrow_array) {
            if ($flag_stop_work) {
                warn "Exiting by signal...";
                last MAIN_LOOP;
            }
            if ($endtime && time()>$endtime) {
                warn "Exiting by time condition...";
                last MAIN_LOOP;
            }

            my $u = LJ::load_userid($userid)
                or die "Invalid userid: $userid";
             
            if ($cid==0) {
                ## special case: expunged (deleted) users
                ## just update dbversion, don't move or delete(?) data
                LJ::update_user($u, { 'dversion' => 8 });
                print "\tUpgrading version of deleted user $u->{user}\n" if $VERBOSE;
                $migrated++;
            }
            else{
                # assign this dbcm to the user
                if ($udbh) {
                    $u->set_dbcm($udbh)
                        or die "unable to set database for $u->{user}: dbcm=$udbh\n";
                }

                # lock while upgrading
                my $lock = LJ::locker()->trylock("d7d8-$userid");
                unless ($lock) {
                    print STDERR "Could not get a lock for user " . $u->user . ".\n";
                    next;
                }

                my $ok = eval { $u->upgrade_to_dversion_8($mdbh, $mdbhslo, $udbh) };
                die $@ if $@;

                print "\tMigrated user " . $u->user . "... " . ($ok ? 'ok' : 'ERROR') . "\n"
                    if $VERBOSE;

                $migrated++ if $ok;
            }
        }

        print "\t - Migrated $migrated users so far\n\n";

        # make sure we don't end up running forever for whatever reason
        last if $migrated > $total;
    }
}

print "--- Done migrating $migrated of $total users to dversion 8 ---\n";
