# t/importer-controller.t
#
# Tests the queue depth the importer page shows, which is read from the
# TheSchwartz job queue.
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
use LJ::Test qw( with_fake_memcache );
use TheSchwartz::Job;

use DW::Controller::Importer;

my $queue = 'DW::Controller::Importer';

sub enqueue {
    my ( $funcname, $uniqkey ) = @_;
    my $job = TheSchwartz::Job->new(
        funcname  => $funcname,
        uniqkey   => $uniqkey,
        arg       => {},
        run_after => time() - 60,
    );
    LJ::theschwartz()->insert($job) or die "could not enqueue $funcname";
}

with_fake_memcache {
    is_deeply( DW::Controller::Importer::get_queue(), {}, 'an empty queue has no depths' );

    LJ::MemCache::delete('importer_queue_depth');
    enqueue( 'DW::Worker::ContentImporter::LiveJournal::Entries',  'lj_entries-1' );
    enqueue( 'DW::Worker::ContentImporter::LiveJournal::Entries',  'lj_entries-2' );
    enqueue( 'DW::Worker::ContentImporter::LiveJournal::Comments', 'lj_comments-1' );
    enqueue( 'DW::Worker::SomethingElse',                          'other-1' );

    is_deeply(
        DW::Controller::Importer::get_queue(),
        { entries => 2, comments => 1 },
        'depth is counted per importer worker, ignoring other queues'
    );
};

# when the queue database cannot be reached the page still renders, with no depths
with_fake_memcache {
    no warnings 'redefine';
    local *LJ::theschwartz = sub { return undef };
    my $depth = DW::Controller::Importer::get_queue();
    is( ref $depth,          'HASH', 'an unreachable queue yields a hash, not an error string' );
    is( scalar keys %$depth, 0,      'with no entries' );
};

done_testing();
