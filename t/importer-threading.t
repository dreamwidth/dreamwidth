# t/importer-threading.t
#
# Tests the ordering of imported comments: parents are always written before
# their replies, whatever order the source delivered them in.
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

use lib "$ENV{LJHOME}/cgi-bin";
use DW::Importer::Threading;

sub c {
    my ( $id, $parent, $entry ) = @_;
    return { remote_id => $id, parent_id => $parent // 0, entry_id => $entry // 1 };
}

# writes comments, handing out local ids from 100 and remembering the order and parents
sub writer {
    my ($log) = @_;
    my $next = 100;
    return sub {
        my ( $comment, $local_parent, $local_entry ) = @_;
        push @$log, [ $comment->{remote_id}, $local_parent, $local_entry ];
        return $next++;
    };
}

# replies delivered before their parents are still written after them, with the parents' new ids
{
    my $t = DW::Importer::Threading->new( entries => { 1 => 11 } );
    is_deeply( [ $t->add($_) ], ['pending'], "comment $_->{remote_id} is queued" )
        foreach ( c( 5, 3 ), c( 3, 2 ), c( 2, 0 ), c( 4, 0 ) );

    my @log;
    is( $t->process( writer( \@log ) ), 4, 'all four are written' );
    is_deeply( [ map { $_->[0] } @log ], [ 2, 3, 4, 5 ], 'in id order once their parent is there' );
    is_deeply(
        $log[1],
        [ 3, 100, 11 ],
        'a reply gets its parent\'s new local id, and the local entry'
    );
    is_deeply( $log[3], [ 5, 101, 11 ], 'through a chain' );
    is( $t->local_id(5), 103, 'the new ids are remembered' );
    is_deeply( [ $t->orphans ], [], 'nothing is left over' );
}

# a parent that arrives in a later window holds its replies back until then
{
    my $t = DW::Importer::Threading->new( entries => { 1 => 11 } );
    $t->add( c( 9,  4 ) );
    $t->add( c( 10, 0 ) );

    my @log;
    $t->process( writer( \@log ) );
    is_deeply( [ map { $_->[0] } @log ], [10], 'the reply waits for its parent' );
    is_deeply( [ map { $_->{remote_id} } $t->orphans ], [9], 'and is not lost' );

    $t->add( c( 4, 0 ) );
    $t->process( writer( \@log ) );
    is_deeply( [ map { $_->[0] } @log ], [ 10, 4, 9 ], 'it is written once the parent has come' );
    is_deeply( [ $t->orphans ], [], 'and is no longer an orphan' );
}

# what is already imported is recognised, and parents that were imported earlier count
{
    my $t = DW::Importer::Threading->new( entries => { 1 => 11 }, known => { 7 => 70 } );
    is_deeply(
        [ $t->add( c( 7, 0 ) ) ],
        [ 'existing', 70 ],
        'an imported comment is reported as existing'
    );

    $t->add( c( 8, 7 ) );
    my @log;
    $t->process( writer( \@log ) );
    is_deeply( $log[0], [ 8, 70, 11 ], 'a new reply to it is attached to the existing comment' );
}

# comments on entries that are not imported are never written, and are reported
{
    my $t = DW::Importer::Threading->new( entries => { 1 => 11 }, known => { 6 => 60 } );
    is_deeply( [ $t->add( c( 5, 0, 99 ) ) ],
        ['unmapped_entry'], 'a comment on an unknown entry is not queued' );
    is_deeply( [ $t->add( c( 6, 0, 99 ) ) ], [ 'existing', 60 ], 'unless we already have it' );
    $t->add( c( 7, 5, 99 ) );
    $t->add( c( 8, 0, 1 ) );

    my @log;
    $t->process( writer( \@log ) );
    is_deeply( [ map { $_->[0] } @log ], [8], 'only the comment on a known entry is written' );
    is_deeply(
        [ map { $_->{remote_id} } $t->unmapped ],
        [ 5, 7 ],
        'the others are reported, in the order given'
    );
    is_deeply( [ $t->orphans ], [], 'and are not orphans' );
}

# replies to a comment that is never imported are orphans
{
    my $t = DW::Importer::Threading->new( entries => { 1 => 11 } );
    $t->add($_) foreach ( c( 3, 2 ), c( 4, 3 ), c( 5, 0 ) );

    my @log;
    $t->process( writer( \@log ) );
    is_deeply( [ map { $_->[0] } @log ], [5], 'only what has an ancestry is written' );
    is_deeply( [ map { $_->{remote_id} } $t->orphans ], [ 3, 4 ],
        'the rest are orphans, in order' );
}

# a writer that declines leaves the comment queued without losing the others
{
    my $t = DW::Importer::Threading->new( entries => { 1 => 11 } );
    $t->add($_) foreach ( c( 1, 0 ), c( 2, 1 ), c( 3, 0 ) );

    my $written = $t->process( sub { $_[0]->{remote_id} == 1 ? undef : 50 + $_[0]->{remote_id} } );
    is( $written, 1, 'one comment was written' );
    is_deeply(
        [ map { $_->{remote_id} } $t->orphans ],
        [ 1, 2 ],
        'the declined one and its reply wait'
    );
}

done_testing();
