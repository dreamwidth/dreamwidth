#!/usr/bin/perl

use strict;
use lib "$ENV{'LJHOME'}/cgi-bin";
require 'ljlib.pl';

# so output happens quickly
$| = 1;

# make sure we got a parameter
my $propname = shift;
die "ERROR: no property specified\n" unless $propname;

# verify it's a valid property
my $prop = LJ::get_prop('user', $propname);

# see if we know how to handle this parameter
if ($propname eq 'external_foaf_url' && $prop->{cldversion} == 0) {
    # this one is simple; we're moving this one to the clusters 1000 users at a time
    print "Beginning initial data migration...\n";
    cluster_property($prop);

    # update the property to be indexed
    print "Updating property data in userproplist...\n";
    update_property($prop, { indexed => 0, cldversion => 4 });

    # strongly recommend a restart
    print "\n";
    print "* " x 38 . "\n";
    print "WARNING: It is recommended that you restart your web nodes now to cause the\n";
    print "         updated property to start to take effect.  Please press enter when\n";
    print "         this is done.\n";
    print "* " x 38 . "\n";
    readline STDIN;

    # now let's hope they restarted and let's migrate anybody who is still stuck
    print "Beginning final data migration...\n";
    cluster_property($prop);

    # done
    print "Finished migrating external_foaf_url property.\n";

} else {
    # don't know how to handle it
    die "ERROR: don't know how to handle '$propname' (has it already been handled?)\n";
}

##############################################################################
### helper subs

sub cluster_property {
    my $prop = shift;

    # some state tracking information
    my (%dbcms);          # ( clusterid => dbcm )
    my (%to_write);       # ( clusterid => [ [ userid, value ], [ userid, value ], ... ]
    # note: livejournal has only about 7500 external_foaf_urls... those should
    # be moved in less time than any database handle will time out, so I've made
    # the decision not to worry about handle timeouts right now.  all other sites
    # are probably no more than this size, so it should be fine for everybody.

    # setup our flushing sub that we'll need later
    my $flush = sub {
        my $cid = shift;

        # get the ref from to_write etc
        my $aref = $to_write{$cid};
        delete $to_write{$cid};

        # get handle to database if needed
        my $dbcm = $dbcms{$cid} || ($dbcms{$cid} = LJ::get_cluster_master($cid));

        # notice that we're flushing data
        print "\tflushing " . scalar(@$aref) . " items to cluster $cid...";

        # now construct SQL
        my $repstr = join(', ', map { "($_->[0], $prop->{upropid}, " .
                                      $dbcm->quote($_->[1]) . ")" } @$aref);
        $dbcm->do("REPLACE INTO userproplite2 (userid, upropid, value) VALUES $repstr");
        die "ERROR: database: " . $dbcm->errstr . "\n" if $dbcm->err;

        # done, status update
        print "flushed\n";
    };

    # start our main loop
    while (1) {
        # data storage for each loop
        my (%users, %values); # ( userid => user object or value )
        
        # clear our handles
        $LJ::DBIRole->flush_cache();
        
        # get main database handle
        my $dbh = LJ::get_db_writer();
        
        # select up to 1000 userid:value tuples
        print "Getting values...";
        my $vals = $dbh->selectall_arrayref
            ('SELECT userid, value FROM userprop WHERE upropid = ? LIMIT 1000',
             undef, $prop->{upropid});
        die "ERROR: database: " . $dbh->errstr . "\n" if $dbh->err;
        print "got " . scalar(@$vals) . " values.\n";

        # short circuit if we have 0
        return 1 if scalar @$vals == 0;

        # get the userids to load
        my @to_load;
        foreach my $row (@$vals) {
            my ($userid, $value) = @$row;
            $values{$userid} = $value;
            push @to_load, $userid;
        }

        # now load the users in one big grab
        print "Loading users...";
        LJ::load_userids_multiple([ map { $_ => \$users{$_} } @to_load ]);
        print "loaded.\n";

        # now push data onto the cluster lists
        while (my ($userid, $value) = each %values) {
            my $cid = $users{$userid}->{clusterid};

            # clusterid 0 means the user is expunged or somesuch, so we
            # don't weant to migrate their settings anywhere and should
            # just delete it.
            next unless $cid;

            # now push this onto the to_write array
            $to_write{$cid} ||= [];
            push @{$to_write{$cid}}, [ $userid, $value ];

            # now, flush this list if it's large (100 or more)
            $flush->($cid) if scalar @{$to_write{$cid}} >= 100;
        }

        # now flush everything that's left
        $flush->($_) foreach keys %to_write;

        # now delete from the global for items that we've written
        print "Deleting " . scalar(keys %values) . " items from global...";
        my $instr = join(',', map { $_ + 0 } keys %values);
        $dbh->do("DELETE FROM userprop WHERE upropid = $prop->{upropid} AND userid IN ($instr)");
        die "ERROR: database: " . $dbh->errstr . "\n" if $dbh->err;
        print "deleted.\n";

        # last if we had less than 1000 this time
        last if scalar @$vals < 1000;
    }
}

sub update_property {
    my ($prop, $sets) = @_;
    die "ERROR: nothing to set\n" unless %$sets;

    # now make the updates they want
    my $dbh = LJ::get_db_writer();
    my $updstr = join(', ', map { "$_ = " . $dbh->quote($sets->{$_}) } keys %$sets);
    $dbh->do("UPDATE userproplist SET $updstr WHERE upropid = $prop->{upropid}");
    die "ERROR: database: " . $dbh->errstr . "\n" if $dbh->err;
}
