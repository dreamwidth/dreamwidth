# t/importer-comments-fetch.t
#
# Tests the on-disk cache in front of the comment export fetch: a retry inside
# one import reuses the downloaded XML, a new import downloads it again.
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
use File::Path qw( make_path remove_tree );
use HTTP::Response;
use LJ::Test qw( temp_user );

use DW::Importer::Source::LiveJournal::Transport;

my $u   = temp_user();
my $dir = "$LJ::HOME/logs/imports/" . $u->id;
make_path($dir);

# the remote site: whatever $current_xml holds, and a count of how often it was asked
my ( $current_xml, $requests ) = ( '', 0 );
{
    no warnings qw( redefine once );
    *DW::Importer::Source::LiveJournal::Transport::session = sub { return 'session' };
    *LWP::UserAgent::request                               = sub {
        $requests++;
        my $r = HTTP::Response->new( 200, 'OK' );
        $r->content($current_xml);
        return $r;
    };
}

sub fetch {
    my ($impid) = @_;
    my $data = {
        userid         => $u->id,
        import_data_id => $impid,
        hostname       => 'remote.example',
        username       => 'someone',
    };
    return DW::Importer::Source::LiveJournal::Transport->new( data => $data )
        ->comment_export( 'comment_meta', 1, 10000, sub { } );
}

$current_xml = qq{<?xml version="1.0"?><livejournal><maxid>1</maxid></livejournal>};
is( fetch(1),  $current_xml, 'first fetch returns the remote data' );
is( $requests, 1,            'and asked the remote site' );

is( fetch(1),  $current_xml, 'a retry within the same import returns the same data' );
is( $requests, 1,            'without asking the remote site again' );

$current_xml = qq{<?xml version="1.0"?><livejournal><maxid>2</maxid></livejournal>};
is( fetch(2),  $current_xml, 'a later import sees what the remote site has now, not a stale copy' );
is( $requests, 2,            'because it fetched again' );

remove_tree($dir);
done_testing();
