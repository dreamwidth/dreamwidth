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
our ( %maint, %maintinfo );
require "$ENV{'LJHOME'}/cgi-bin/LJ/Directories.pm";    # extra XML::Encoding files in cgi-bin/XML/*
use LJ::SynSuck;

$maintinfo{'synsuck'}{opts}{locking} = "per_host";
$maint{'synsuck'} = sub {
    my $maxcount = shift || 0;
    my $verbose  = $LJ::LJMAINT_VERBOSE;

    my %child_jobs;                                    # child pid => [ userid, lock ]

    # get the next user to be processed
    my @all_users;
    my $get_next_user = sub {
        return shift @all_users if @all_users;

        # need to get some more rows
        my $dbh          = LJ::get_db_writer();
        my $current_jobs = join( ",", map { $dbh->quote( $_->[0] ) } values %child_jobs );
        my $in_sql       = $current_jobs ? " AND u.userid NOT IN ($current_jobs)" : "";
        my $sth =
            $dbh->prepare( "SELECT u.user, s.userid, s.synurl, s.lastmod, "
                . "       s.etag, s.numreaders, s.checknext "
                . "FROM user u, syndicated s "
                . "WHERE u.userid=s.userid AND u.statusvis='V' "
                . "AND s.checknext < NOW()$in_sql "
                . "LIMIT 500" );
        $sth->execute;
        while ( my $urow = $sth->fetchrow_hashref ) {
            push @all_users, $urow;
        }

        return undef unless @all_users;
        return shift @all_users;
    };

    # fork and manage child processes
    my $max_threads = $LJ::SYNSUCK_MAX_THREADS || 1;
    print "[$$] PARENT -- using $max_threads workers\n" if $verbose;

    my $threads      = 0;
    my $userct       = 0;
    my $keep_forking = 1;
    while ( $maxcount == 0 || $userct < $maxcount ) {

        if ( $threads < $max_threads && $keep_forking ) {
            my $urow = $get_next_user->();
            unless ($urow) {
                $keep_forking = 0;
                next;
            }

            my $lockname = "synsuck-user-" . $urow->{user};
            my $lock     = LJ::locker()->trylock($lockname);
            next unless $lock;
            print "Got lock on '$lockname'. Running\n" if $verbose;

            # spawn a new process
            if ( my $pid = fork ) {

                # we are a parent, nothing to do?
                $child_jobs{$pid} = [ $urow->{'userid'}, $lock ];
                $threads++;
                $userct++;
            }
            else {
                # handles won't survive the fork
                LJ::DB::disconnect_dbs();
                LJ::SynSuck::update_feed( $urow, $verbose );
                exit 0;
            }

            # wait for child(ren) to die
        }
        else {
            my $child = wait();
            last if $child == -1;
            delete $child_jobs{$child};
            $threads--;
        }
    }

    # Now wait on any remaining children so we don't leave zombies behind.
    while (%child_jobs) {
        my $child = wait();
        last if $child == -1;
        delete $child_jobs{$child};
        $threads--;
    }

    print "[$$] $userct users processed\n" if $verbose;
    return;
};

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
