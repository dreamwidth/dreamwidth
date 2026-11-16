# t/importer-worker-base.t
#
# Tests the outcome handling shared by all importer jobs.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );

use DW::Worker::ContentImporter::LiveJournal::Bio;

my $class = 'DW::Worker::ContentImporter::LiveJournal::Bio';

{

    package Test::FakeJob;
    sub new { return bless { result => undef }, shift }
    sub failures          { 0 }
    sub funcname          { 'DW::Worker::ContentImporter::LiveJournal::Bio' }
    sub completed         { $_[0]->{result} = 'completed' }
    sub failed            { $_[0]->{result} = 'failed: ' . $_[1] }
    sub permanent_failure { $_[0]->{result} = 'permanent: ' . $_[1] }
}

# error text comes from remote sites and can hold anything, including printf directives;
# it has to be recorded as written
{
    my $u    = temp_user();
    my $data = { userid => $u->id, import_data_id => 1, hostname => 'remote.example' };
    my $text = 'Remote said: 100% of %s and %d went %n wrong';

    my $job = Test::FakeJob->new;
    $class->fail( $data, 'lj_bio', $job, $text );
    is( $job->{result}, "permanent: $text", 'a permanent failure keeps the message as written' );

    $job = Test::FakeJob->new;
    $class->temp_fail( $data, 'lj_bio', $job, $text );
    is( $job->{result}, "failed: $text", 'so does a temporary failure' );

    $job = Test::FakeJob->new;
    $class->fail( $data, 'lj_bio', $job, 'Unable to load target with id %d.', 42 );
    is(
        $job->{result},
        'permanent: Unable to load target with id 42.',
        'formats are still filled in when given arguments'
    );
}

done_testing();
