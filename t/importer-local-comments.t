# t/importer-local-comments.t
#
# Characterizes Local::Comments::insert_comment and get_comment_map, the writer
# the importers use to create comments: provenance keys, threading and
# per-state side effects.
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
use LJ::Entry;
use LJ::Test qw( temp_user );
use DW::Worker::ContentImporter::Local::Comments;
use DW::Worker::ContentImporter::Local::Entries;

my $entries  = 'DW::Worker::ContentImporter::Local::Entries';
my $comments = 'DW::Worker::ContentImporter::Local::Comments';

my $u      = temp_user();
my $poster = temp_user();

my $entry_key = 'example.com/user/256';
my %entry_map;
my ( $ok, $res ) = $entries->post_event(
    {},
    \%entry_map,
    $u, undef,
    {
        key       => $entry_key,
        subject   => 'entry',
        event     => 'entry body',
        security  => 'public',
        allowmask => 0,
        eventtime => '2009-03-04 05:06:07',
        logtime   => '2009-03-04 05:06:08',
        props     => {},
    },
    []
);
die "could not post the entry: $res->{errmsg}" unless $ok;
my $jitemid = $res->{itemid};

sub comment {
    my (%over) = @_;
    return {
        orig_id  => 5,
        jitemid  => $jitemid,
        parentid => 0,
        posterid => $poster->id,
        subject  => 'subject',
        body     => 'body',
        date     => '2009-03-04T05:06:07Z',
        state    => 'A',
        props    => {},
        %over,
    };
}

sub row {
    my ($jtalkid) = @_;
    return $u->selectrow_hashref(
        'SELECT parenttalkid, posterid, datepost, state, nodeid FROM talk2 '
            . 'WHERE journalid = ? AND jtalkid = ?',
        undef, $u->id, $jtalkid
    );
}

sub replycount {
    return $u->selectrow_array( 'SELECT replycount FROM log2 WHERE journalid = ? AND jitemid = ?',
        undef, $u->id, $jitemid );
}

# a top level comment is keyed by entry source plus the remote id shifted into LJ's key space
my $top;
{
    my $err = '';
    $top = $comments->insert_comment( $u, comment( orig_id => 5 ), \$err );
    ok( $top, 'insert_comment returns the new jtalkid' ) or diag($err);

    my $row = row($top);
    is( $row->{nodeid},       $jitemid,              'attached to the mapped entry' );
    is( $row->{parenttalkid}, 0,                     'top level has no parent' );
    is( $row->{posterid},     $poster->id,           'poster is kept' );
    is( $row->{datepost},     '2009-03-04 05:06:07', 'ISO timestamp is converted' );
    is( $row->{state},        'A',                   'state is kept' );
    is( replycount(),         1,                     'approved comments bump the reply count' );

    my $c = LJ::Comment->instance( $u, jtalkid => $top );
    is(
        $c->prop('import_source'),
        "$entry_key/" . ( 5 << 8 ),
        'import_source is entry key/(id<<8)'
    );
    ok( !$c->prop('imported_from'), 'imported_from is only set for external posters' );

    my $map = $comments->get_comment_map($u);
    is( $map->{ "$entry_key/" . ( 5 << 8 ) },
        $top, 'get_comment_map round-trips the key to jtalkid' );
}

# an explicit entry_source wins over the entry's own import_source
{
    my $err = '';
    my $id  = $comments->insert_comment( $u,
        comment( orig_id => 6, entry_source => 'CROSSPOSTER example.com user 9 ' ), \$err );
    ok( $id, 'comment with entry_source inserts' ) or diag($err);
    is(
        LJ::Comment->instance( $u, jtalkid => $id )->prop('import_source'),
        'CROSSPOSTER example.com user 9 /' . ( 6 << 8 ),
        'the supplied entry_source is used as the key prefix'
    );
}

# replies are threaded to their local parent
{
    my $err   = '';
    my $reply = $comments->insert_comment( $u, comment( orig_id => 7, parentid => $top ), \$err );
    ok( $reply, 'reply inserts' ) or diag($err);
    is( row($reply)->{parenttalkid}, $top, 'parent is the local jtalkid' );

    my $c = LJ::Comment->instance( $u, jtalkid => $reply );
    is( $c->parent->jtalkid, $top, 'LJ::Comment sees the thread' );
}

# remote posters keep their provenance, anonymous comments have no poster
{
    my $err = '';
    my $ext = $comments->insert_comment( $u,
        comment( orig_id => 8, posterid => $poster->id, source => 'example.com' ), \$err );
    is(
        LJ::Comment->instance( $u, jtalkid => $ext )->prop('imported_from'),
        'example.com',
        'imported_from records the remote site'
    );

    my $anon = $comments->insert_comment( $u, comment( orig_id => 9, posterid => 0 ), \$err );
    ok( $anon, 'anonymous comment inserts' ) or diag($err);
    is( row($anon)->{posterid}, 0, 'anonymous comments have posterid 0' );
}

# state handling: screened comments are flagged on the entry, deleted ones keep no text,
# and neither counts as a reply
{
    my $before = replycount();
    my $err    = '';

    my $screened = $comments->insert_comment( $u, comment( orig_id => 10, state => 'S' ), \$err );
    is( row($screened)->{state}, 'S',     'screened state is kept' );
    is( replycount(),            $before, 'screened comments do not bump the reply count' );
    my $p    = LJ::get_prop( log => 'hasscreened' );
    my $flag = $u->selectrow_array(
        'SELECT value FROM logprop2 WHERE journalid = ? AND jitemid = ? AND propid = ?',
        undef, $u->id, $jitemid, $p->{id} );
    ok( $flag, 'the entry is marked as having screened comments' );

    my $deleted = $comments->insert_comment( $u, comment( orig_id => 11, state => 'D' ), \$err );
    is( row($deleted)->{state}, 'D',     'deleted state is kept' );
    is( replycount(),           $before, 'deleted comments do not bump the reply count' );
    my $texts =
        $u->selectrow_array( 'SELECT COUNT(*) FROM talktext2 WHERE journalid = ? AND jtalkid = ?',
        undef, $u->id, $deleted );
    is( $texts, 0, 'deleted comments store no text' );
}

# the importer's own props cannot be supplied by the remote data
{
    my $err = '';
    my $id  = $comments->insert_comment( $u,
        comment( orig_id => 12, props => { import_source => 'forged' } ), \$err );
    like(
        LJ::Comment->instance( $u, jtalkid => $id )->prop('import_source'),
        qr/^\Q$entry_key\E\/\d+$/,
        'a supplied import_source prop is dropped in favour of the computed key'
    );
}

# a failed insert says why in the caller's error variable
{
    my $err = '';
    my $id = $comments->insert_comment( $u, comment( orig_id => 20, date => 'not a date' ), \$err );
    ok( !$id, 'an insert the database rejects returns false' );
    like( $err, qr/Database Error/, 'and the reason reaches the caller' );
    ok( !exists $comments->get_comment_map($u)->{ "$entry_key/" . ( 20 << 8 ) },
        'nothing is keyed' );
}

# updating a comment must not replace the text of comments that already have one
{
    local %LJ::FIX_COMMENT_IMPORT = ( $u->user => 1 );
    my $err = '';

    my $kept =
        $comments->insert_comment( $u, comment( orig_id => 21, body => 'original words' ), \$err );
    my $blank =
        $comments->insert_comment( $u, comment( orig_id => 22, body => 'to be blanked' ), \$err );
    $u->do( 'UPDATE talktext2 SET body = ? WHERE journalid = ? AND jtalkid = ?',
        undef, '', $u->id, $blank );

    foreach my $id ( $kept, $blank ) {
        $comments->update_comment( $u,
            { id => $id, subject => 'remote subject', body => 'remote body', props => {} }, \$err );
    }

    my $body = sub {
        my ($id) = @_;
        return LJ::text_uncompress(
            $u->selectrow_array(
                'SELECT body FROM talktext2 WHERE journalid = ? AND jtalkid = ?',
                undef, $u->id, $id
            )
        );
    };
    is( $body->($kept),  'original words', 'a comment with text keeps it' );
    is( $body->($blank), 'remote body',    'an empty comment gets the remote text' );
}

done_testing();
