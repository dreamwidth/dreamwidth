# t/importer-keys.t
#
# Pins the key formats LiveJournal imports store, which re-imports depend on to
# recognise what is already there.
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
use LJ::Comment;
use LJ::Test qw( temp_user );

use DW::Importer::Source::LiveJournal::Keys
    qw( entry_key comment_key crosspost_source index_entries index_comments );
use DW::Worker::ContentImporter::Local::Comments;
use DW::Worker::ContentImporter::Local::Entries;

# the strings the importer has always stored
is( entry_key( 'livejournal.com', 'someone', 1, 7 ), 'livejournal.com/someone/263',
    'an entry key' );
is(
    entry_key( 'insanejournal.com', 'some_comm', 4096, 255 ),
    'insanejournal.com/some_comm/1048831',
    'a larger one'
);
is(
    comment_key( 'livejournal.com/someone/263', 5 ),
    'livejournal.com/someone/263/1280',
    'a comment key'
);
is(
    crosspost_source( 'livejournal.com', 'someone', 12 ),
    'CROSSPOSTER livejournal.com someone 12 ',
    'the crosspost pseudo key keeps its trailing space'
);
is(
    comment_key( crosspost_source( 'livejournal.com', 'someone', 12 ), 5 ),
    'CROSSPOSTER livejournal.com someone 12 /1280',
    'and gives a comment key'
);

# and they are what the writers store: build the keys here, write through the importer's own
# code, and read back what it stored
{
    my $u   = temp_user();
    my $key = entry_key( 'livejournal.com', 'someone', 3, 9 );

    my %map;
    my ( $ok, $res ) = DW::Worker::ContentImporter::Local::Entries->post_event(
        {},
        \%map,
        $u, undef,
        {
            key       => $key,
            subject   => 's',
            event     => 'e',
            security  => 'public',
            allowmask => 0,
            eventtime => '2009-03-04 05:06:07',
            logtime   => '2009-03-04 05:06:08',
            props     => {},
        },
        []
    );
    die "post failed: $res->{errmsg}" unless $ok;
    is( LJ::Entry->new( $u, jitemid => $res->{itemid} )->prop('import_source'),
        $key, 'the entry stores its key' );

    my $err = '';
    my $id  = DW::Worker::ContentImporter::Local::Comments->insert_comment(
        $u,
        {
            orig_id  => 21,
            jitemid  => $res->{itemid},
            parentid => 0,
            posterid => 0,
            subject  => 's',
            body     => 'b',
            date     => '2009-03-06T01:00:00Z',
            state    => 'A',
            props    => {},
        },
        \$err
    );
    is(
        LJ::Comment->instance( $u, jtalkid => $id )->prop('import_source'),
        comment_key( $key, 21 ),
        'and the comment stores the key built from it'
    );

    # a crossposted entry is keyed by the crossposter's pseudo key when it is given
    $id = DW::Worker::ContentImporter::Local::Comments->insert_comment(
        $u,
        {
            orig_id      => 22,
            jitemid      => $res->{itemid},
            parentid     => 0,
            posterid     => 0,
            entry_source => crosspost_source( 'livejournal.com', 'someone', 3 ),
            subject      => 's',
            body         => 'b',
            date         => '2009-03-06T01:00:00Z',
            state        => 'A',
            props        => {},
        },
        \$err
    );
    is(
        LJ::Comment->instance( $u, jtalkid => $id )->prop('import_source'),
        comment_key( crosspost_source( 'livejournal.com', 'someone', 3 ), 22 ),
        'a crosspost\'s comments are keyed from its pseudo key'
    );
}

# reading the stored keys back: only this import's, matching names as the importer always has
{
    my %entries = (
        'livejournal.com/some_user/263'       => 11,    # itemid 1
        'livejournal.com/some_user/512'       => 12,    # itemid 2
        'livejournal.com/other/768'           => 13,    # somebody else's
        'insanejournal.com/some_user/1024'    => 14,    # another site
        'livejournal.com/some_user/oddball'   => 15,    # not an id at the end
        'livejournal.com/some-user/1280.html' => 16,    # dashes read as underscores, old style url
        'livejournal.com/some_comm/1536'      => 17,    # community entry
    );

    my $index = index_entries( \%entries, 'livejournal.com', 'some_user' );
    is_deeply(
        $index->{by_remote_id},
        { 1 => 11, 2 => 12, 5 => 16 },
        'entries of this import by remote id'
    );
    is_deeply(
        $index->{source_of},
        {
            11 => 'livejournal.com/some_user/263',
            12 => 'livejournal.com/some_user/512',
            16 => 'livejournal.com/some-user/1280.html'
        },
        'and the key each was stored under'
    );
    is_deeply(
        $index->{unparsed},
        ['livejournal.com/some_user/oddball'],
        'keys with no id are reported'
    );

    $index = index_entries( \%entries, 'livejournal.com', 'some_user', 'some_comm' );
    is( $index->{by_remote_id}->{6},
        17, 'a community import also matches the community\'s entries' );

    my %comments = (
        'livejournal.com/some_user/263/1280'             => 101,    # comment 5
        'livejournal.com/some_user/263/1536'             => 102,    # comment 6
        'livejournal.com/other/768/1280'                 => 103,
        'CROSSPOSTER livejournal.com some_user 12 /2048' => 104,    # comment 8, crossposted
    );
    is_deeply(
        index_comments( \%comments, 'livejournal.com', 'some_user' ),
        { 5 => 101, 6 => 102, 8 => 104 },
        'comments of this import by remote id'
    );
}

done_testing();
