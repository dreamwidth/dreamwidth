#!/usr/bin/perl
#
# Goes over every user, updating their dversion to 8 and
# migrating whatever polls they have to their user cluster

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin/";
require "ljlib.pl";
use LJ::Poll;
use Term::ReadLine;

my $BLOCK_SIZE = 10_000; # get users in blocks of 10,000
my $VERBOSE    = 0;      # print out extra info

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

foreach my $cid (@LJ::CLUSTERS) {
    my $udbh = LJ::get_cluster_master($cid)
        or die "Could not get cluster master handle for cluster $cid";

    while (1) {
        my $sth = $dbh->prepare("SELECT userid FROM user WHERE dversion=7 AND clusterid=? LIMIT $BLOCK_SIZE");
        $sth->execute($cid);
        die $sth->errstr if $sth->err;

        my $count = $sth->rows;
        print "\tGot $count users on cluster $cid with dversion=7\n";
        last unless $count;

        while (my ($userid) = $sth->fetchrow_array) {
            my $u = LJ::load_userid($userid)
                or die "Invalid userid: $userid";

            # lock while upgrading
            my $lock = LJ::locker()->trylock("d7d8-$userid");
            unless ($lock) {
                print STDERR "Could not get a lock for user " . $u->user . ".\n";
                next;
            }

            my $ok = eval { $u->upgrade_to_dversion_8 };
            $lock->release;

            die $@ if $@;

            print "\tMigrated user " . $u->user . "... " . ($ok ? 'ok' : 'ERROR') . "\n"
                if $VERBOSE;

            $migrated++ if $ok;
        }

        print "\t - Migrated $migrated users so far\n\n";

        # make sure we don't end up running forever for whatever reason
        last if $migrated > $total;
    }
}

print "--- Done migrating $migrated of $total users to dversion 8 ---\n";
