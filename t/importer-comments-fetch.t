# t/importer-comments-fetch.t
#
# Tests the blob store cache in front of the comment export fetch: a retry inside
# one import reuses the downloaded XML, a new import downloads it again, and a dry
# run reads the cache but never fills it. Rejected metadata is fetched again.
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
use HTTP::Response;
use LJ::Test qw( temp_user );

use DW::Importer::Source::LiveJournal;
use DW::Importer::Source::LiveJournal::Transport;

my $u = temp_user();

# the remote site: whatever $current_xml holds, and a count of how often it was asked
my ( $current_xml, $requests ) = ( '', 0 );
my ( %current_windows, @requested_windows );
{
    no warnings qw( redefine once );
    *DW::Importer::Source::LiveJournal::Transport::session = sub { return 'session' };
    *LWP::UserAgent::request                               = sub {
        my ( undef, $request ) = @_;
        my %query = $request->uri->query_form;
        $requests++;
        push @requested_windows, $query{startid};
        my $r = HTTP::Response->new( 200, 'OK' );
        $r->content( $current_windows{ $query{startid} } // $current_xml );
        return $r;
    };
}

sub import_data {
    my ($import_id) = @_;
    return {
        userid         => $u->id,
        import_data_id => $import_id,
        hostname       => 'remote.example',
        username       => 'someone',
    };
}

sub fetch {
    my ( $import_id, %opts ) = @_;
    my $startid = delete $opts{startid} // 1;
    my $transport =
        DW::Importer::Source::LiveJournal::Transport->new( data => import_data($import_id), %opts );
    return $transport->comment_export( 'comment_meta', $startid, 10000, sub { } );
}

$current_xml = qq{<?xml version="1.0"?><livejournal><maxid>1</maxid></livejournal>};
is( fetch(1),  $current_xml, 'first fetch returns the remote data' );
is( $requests, 1,            'and asked the remote site' );

is( fetch(1),  $current_xml, 'a retry within the same import returns the same data' );
is( $requests, 1,            'without asking the remote site again' );

$current_xml = qq{<?xml version="1.0"?><livejournal><maxid>2</maxid></livejournal>};
is( fetch(2),  $current_xml, 'a later import sees what the remote site has now, not a stale copy' );
is( $requests, 2,            'because it fetched again' );

# a dry run asks the remote site every time, and leaves nothing for a real run to trust
$current_xml = qq{<?xml version="1.0"?><livejournal><maxid>3</maxid></livejournal>};
$requests    = 0;
is( fetch( 3, dry_run => 1 ), $current_xml, 'a dry run returns the remote data' );
is( fetch( 3, dry_run => 1 ), $current_xml, 'and again' );
is( $requests, 2,            'asking the remote site each time: it cached nothing' );
is( fetch(3),  $current_xml, 'a real run of the same import fetches' );
is( $requests, 3,            'rather than finding a copy the dry run left' );

# what a real run cached is read by a dry run
is( fetch( 3, dry_run => 1 ), $current_xml, 'a dry run after a real run returns the data' );
is( $requests, 3, 'from the cache' );

for my $case ( [ 4, 'fresh malformed window', 0 ], [ 5, 'already cached malformed window', 1 ] ) {
    my ( $import_id, $name, $prime_cache ) = @$case;
    subtest $name => sub {
        my $read_metadata = sub {
            my $source = DW::Importer::Source::LiveJournal->new( data => import_data($import_id) );
            return $source->comment_meta;
        };
        my $header       = qq{<?xml version="1.0"?><livejournal>};
        my $last_comment = sub {
            my ($id) = @_;
            return "<comments><comment id='$id' posterid='0'/></comments></livejournal>";
        };
        $current_xml     = '';
        %current_windows = (
            1 => "$header<maxid>7</maxid><nextid>4</nextid>" . $last_comment->(1),
            4 => "$header<maxid>7</maxid><nextid>7</nextid>",
            7 => $header . $last_comment->(7),
        );

        if ($prime_cache) {
            is( fetch( $import_id, startid => 4 ), $current_windows{4}, 'cache the old response' );
        }
        @requested_windows = ();

        my $outcome;
        {
            local $SIG{__WARN__} = sub { };
            eval { $read_metadata->() };
            $outcome = $@;
        }
        is( ref $outcome ? $outcome->status : $outcome,
            'temp_fail', 'the broken window is retryable' );
        is_deeply(
            \@requested_windows,
            $prime_cache ? [1] : [ 1, 4 ],
            'the first attempt stops at the malformed window'
        );

        $current_windows{4} .= $last_comment->(4);
        @requested_windows = ();

        my $meta = eval { $read_metadata->() };
        is( $@, '', 'the same import succeeds with a fresh transport' );
        is_deeply(
            \@requested_windows,
            [ 4, 7 ],
            'only the rejected and unread windows are fetched'
        );
        is_deeply(
            [ sort keys %{ $meta->{comments} // {} } ],
            [ 1, 4, 7 ],
            'the corrected and later windows contribute comments'
        );

        @requested_windows = ();
        %current_windows   = ();
        my $replay = eval { $read_metadata->() };
        is( $@, '', 'the repaired import remains readable without the remote' );
        is_deeply( $replay, $meta, 'the cache replays all the accepted metadata' );
        is_deeply( \@requested_windows, [], 'including the successfully replaced window' );
    };
}

done_testing();
