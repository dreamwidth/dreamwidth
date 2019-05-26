#!/usr/bin/perl -w
###########################################################################

=head1 Tests For moveuclusterd

This is the test suite for 'moveuclusterd', the jobserver half of the
LiveJournal user-mover.

=cut

###########################################################################
package moveuclusterd_tests;
use strict;

use lib ( "$LJ::HOME/bin", "lib" );

use LJ::Test::Unit qw{+autorun};
use LJ::Test::Assertions qw{:all};

BEGIN {
    require 'moveuclusterd.pl';
}

my @test_goodjobspecs = (
    q{67645:23:30},
    q{3932342:117:62 prelock=1},
    q{1103617:85:88 giddy=whippingcream bollocks=queen prelock=1},
);
my @test_badjobspecs = ( q{}, q{14}, q{12:22}, );

### General tests
sub test_packages {
    foreach my $package (qw{JobServer JobServer::Job JobServer::Client}) {
        assert_no_exception { $package->isa('UNIVERSAL') };
    }
}

### JobServer::Job class tests
sub test_jobserverjob_new {
    my ( $obj, $rval );
    my $server = new JobServer;

    # Requires a server as first argument
    assert_exception {
        new JobServer::Job;
    };

    # Valid jobspecs
    foreach my $spec (@test_goodjobspecs) {
        assert_no_exception {
            $obj = new JobServer::Job $server, $spec
        };
        assert_instance_of 'JobServer::Job', $obj;

        my ( $userid, $scid, $dcid, $rest ) = split /[:\s]/, $spec, 4;
        $rest ||= '';

        assert_no_exception { $rval = $obj->userid };
        assert_equal $userid, $rval;

        assert_no_exception { $rval = $obj->srcclusterid };
        assert_equal $scid, $rval;

        assert_no_exception { $rval = $obj->dstclusterid };
        assert_equal $dcid, $rval;

        assert_no_exception { $rval = $obj->stringify };
        $rest = sprintf '(%s)', join( '|', split( /\s+/, $rest ) );
        assert_matches qr{$userid:$scid:$dcid \d+.\d+ $rest}, $rval;
    }

    # Invalid jobspecs
    foreach my $spec (@test_badjobspecs) {
        assert_exception {
            new JobServer::Job $server, $spec
        }
        "Didn't expect to be able to create job '$spec'";
    }
}

### JobServer class tests
sub test_jobserver_new {
    my $rval;

    assert_no_exception { $rval = new JobServer };
    assert_instance_of 'JobServer', $rval;
}

sub test_jobserver_addjobs {
    my $rval;
    my $js = new JobServer;

    # Should be able to call addJobs() with no jobs.
    assert_no_exception {
        local $^W = 0;    # Quell LJ::start_request()'s warnings
        $js->addJobs;
    };

    # Server should have 0 jobs queued
    assert_no_exception {
        $rval = $js->getJobList;
    };
    assert_matches qr{0 queued jobs, 0 assigned jobs for 0 clusters}, $rval->{footer}[0];
    assert_matches qr{0 of 0 total jobs assigned since},              $rval->{footer}[1];

    # Load up some job objects and add those
    my @jobs     = map { new JobServer::Job $js, $_ } @test_goodjobspecs;
    my $jobcount = scalar @jobs;
    assert_no_exception {
        local $^W = 0;    # Quell LJ::start_request()'s warnings
        $js->addJobs(@jobs);
    };

    # Now server should have the test jobs queued
    assert_no_exception {
        $rval = $js->getJobList;
    };
    assert_matches qr{$jobcount queued jobs, 0 assigned jobs for \d+ clusters}, $rval->{footer}[0];
    assert_matches qr{0 of $jobcount total jobs assigned since},                $rval->{footer}[1];

}

