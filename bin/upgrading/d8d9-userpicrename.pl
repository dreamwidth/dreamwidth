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
#
# Goes over every user, updating their dversion to 9 and
# moves userpicmap2 over to userpicmap3
#
use strict;
use warnings;
BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}
use Term::ReadLine;
use Getopt::Long;
use DW::User::DVersion::Migrate8To9;

my $BLOCK_SIZE = 10_000; # get users in blocks of 10,000
my $VERBOSE    = 0;      # print out extra info
my $need_help;
my @cluster;
my @users;
my $endtime;

my $help = <<"END";
Usage: $0 [options]
Options:
    --cluster=N Specify user cluster to work on (by default, all clusters)
    --hours=N   Work no more than N hours (by default, work until all is done)
    --user=N    Specify users to migrate (by default, all users on the specified clusters)
    --verbose   Be noisy
    --help      Print this help and exit
END

GetOptions(
    "help"      => \$need_help,
    "cluster=i" => \@cluster,
    "user=s"    => \@users,
    "verbose"   => \$VERBOSE,
    "hours=i"   => sub { $endtime = $_[1]*3600+time(); },
) or die $help;

if ( $need_help ) {
    print $help;
    exit(0);
}

unless ( @cluster ) {
    no warnings 'once';
    @cluster = ( 0, @LJ::CLUSTERS );
}

my $dbh = LJ::get_db_writer()
    or die "Could not connect to global master";

my $users = join( ', ', map { $dbh->quote($_) } @users );

my $term = new Term::ReadLine 'd8-d9 migrator';
my $line = $term->readline( "Do you want to update to dversion 9 (userpicmap3)? [N/y] " );
unless ( $line =~ /^y/i ) {
    print "Not upgrading to dversion 9\n\n";
    exit;
}

print "\n--- Upgrading users to dversion (userpicmap3) ---\n\n";

# get user count
my $total = $dbh->selectrow_array( "SELECT COUNT(*) FROM user WHERE dversion = 8" );
print "\tTotal users at dversion 8: $total\n\n";

my $migrated = 0;
my $flag_stop_work = 0;

MAIN_LOOP:
foreach my $cid ( @cluster ) {

    while ( 1 ) {
        my $sth;
        if ( @users ) {
            $sth = $dbh->prepare( "SELECT userid FROM user WHERE dversion=8 AND clusterid=? AND user IN ($users) LIMIT $BLOCK_SIZE" );
        } else {
            $sth = $dbh->prepare( "SELECT userid FROM user WHERE dversion=8 AND clusterid=? LIMIT $BLOCK_SIZE" );
        }
        $sth->execute( $cid );
        die $sth->errstr if $sth->err;

        my $count = $sth->rows;
        print "\tGot $count users on cluster $cid with dversion=8\n";
        last unless $count;
       
        local( $SIG{TERM}, $SIG{INT}, $SIG{HUP} );
        $SIG{TERM} = $SIG{INT} = $SIG{HUP} = sub { $flag_stop_work = 1; };
        while ( my ( $userid ) = $sth->fetchrow_array ) {
            if ( $flag_stop_work ) {
                warn "Exiting by signal...";
                last MAIN_LOOP;
            }
            if ( $endtime && time()>$endtime ) {
                warn "Exiting by time condition...";
                last MAIN_LOOP;
            }

            my $u = LJ::load_userid( $userid )
                or die "Invalid userid: $userid";
             
            if ( $u->is_expunged ) {
                ## special case: expunged (deleted) users
                ## just update dbversion, don't move or delete(?) data
                $u->update_self( { 'dversion' => 9 } );
                print "\tUpgrading version of deleted user $u->{user}\n" if $VERBOSE;
                $migrated++;
            } else {
                # lock while upgrading
                my $lock = LJ::locker()->trylock( "d8d9-$userid" );
                unless ( $lock ) {
                    print STDERR "Could not get a lock for user " . $u->user . ".\n";
                    next;
                }

                my $ok = eval { $u->upgrade_to_dversion_9 };
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

print "--- Done migrating $migrated of $total users to dversion 9 ---\n";
