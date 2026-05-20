#!/usr/bin/perl
#
# DW::Task::SearchCopier
#
# Copies content into Manticore Search (RT mode). Structural port of
# DW::Task::SphinxCopier, with Manticore-specific swaps:
#   - Writes to the dw1 table via SphinxQL on @LJ::MANTICORE instead of
#     items_raw in the dw_sphinx MySQL staging DB.
#   - No stable doc IDs — Manticore auto-assigns. Upsert is DELETE+INSERT
#     on the natural key (journalid, jitemid, jtalkid) instead of REPLACE
#     with a preserved id.
#   - Body text stored uncompressed (no COMPRESS()). Manticore tokenizes
#     it directly.
#   - security_bits is an rt_attr_multi written as a (1,2,3) literal
#     rather than a CSV string stored in a MySQL column.
#   - No touchtime column on dw1 (unused by the read path; was only there
#     to support Sphinx's main+delta build schedule, which RT doesn't need).
#
# Routes to its own SQS queue automatically via class-name derivation
# (DW::Task::SearchCopier -> dw-task-searchcopier). Coexists with
# DW::Task::SphinxCopier during the Sphinx -> Manticore migration.
#
# Arg shape (hashref in args->[0]):
#   { userid => N }                              # full recopy (24h throttled)
#   { userid => N, force => 1 }                  # full recopy, bypass throttle
#   { userid => N, jitemid => J }                # one entry; handles deletes
#   { userid => N, jtalkid => T }                # one comment; handles deletes
#   { userid => N, jitemids => [J1, J2, ...] }   # mass-copy entries (not usually dispatched yet)
#   { userid => N, jtalkids => [T1, T2, ...] }   # mass-copy comments chunk
#   { userid => N, source => 'label' }           # optional provenance for logs
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::SearchCopier;

use strict;
use v5.10;

use DW::Task;      # must come before `use base` so COMPLETED/FAILED
                   # constants are defined before this file's body
                   # compiles under strict
use DW::TaskQueue;
use base 'DW::Task';

use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Carp qw/ croak /;
use DBI;
use Encode;

use constant _CHUNK_SIZE => 1000;

# Manticore SphinxQL connection. Parallels SphinxCopier's sphinx_db() —
# no %DBINFO entry exists for Manticore (it doesn't speak the full MySQL
# dialect LJ::get_dbh expects), so we open a raw DBI handle against
# @LJ::MANTICORE and do the SET NAMES dance ourselves.
sub manticore_db {
    $log->logcroak("\@LJ::MANTICORE is not configured.")
        unless @LJ::MANTICORE;

    my ( $host, undef, $sql_port ) = @LJ::MANTICORE;
    my $dbsx = DBI->connect(
        "DBI:mysql:host=$host;port=$sql_port",
        undef, undef,
        {
            RaiseError        => 0,
            AutoCommit        => 1,
            PrintError        => 0,
            mysql_enable_utf8 => 1,
        },
    ) or $log->logcroak("Unable to connect to Manticore search database.");

    $dbsx->do(q{SET NAMES 'utf8'});
    $log->logcroak( $dbsx->errstr ) if $dbsx->err;
    return $dbsx;
}

sub work {
    my ( $self, $handle ) = @_;
    my $args = $self->args->[0];

    my $u = LJ::load_userid( $args->{userid} )
        or $log->logcroak("Invalid userid: $args->{userid}.");
    $log->info( "Search copier started for "
            . $u->user . "("
            . $u->id
            . "), source "
            . ( $args->{source} // 'unknown' )
            . "." );
    return DW::Task::COMPLETED unless $u->is_person || $u->is_community;
    return DW::Task::COMPLETED if $u->is_expunged;

    # Operator-configured skip list — journalids in @LJ::SKIP_SEARCH_IMPORT
    # are short-circuited regardless of task type (full recopy, chunk,
    # single-item update). Used to drain queued chunks fast for journals
    # we want to defer.
    if ( @LJ::SKIP_SEARCH_IMPORT
        && grep { $_ == $u->id } @LJ::SKIP_SEARCH_IMPORT )
    {
        $log->info( "Skipping search import for "
                . $u->user . "("
                . $u->id
                . ") (configured in SKIP_SEARCH_IMPORT)." );
        return DW::Task::COMPLETED;
    }

    # We copy comments for paid users, allowing them to search through the
    # comments to their journal.
    my $copy_comments = $u->is_paid ? 1 : 0;

    if ( exists $args->{jitemid} ) {
        $log->info("Requested copy of only entry $args->{jitemid}.");
        copy_entry( $u, $args->{jitemid}, !$copy_comments );
    }
    elsif ( exists $args->{jtalkid} ) {
        $log->info("Requested copy of only comment $args->{jtalkid}.");
        copy_comment( $u, $args->{jtalkid} ) if $copy_comments;
    }
    elsif ( exists $args->{jitemids} ) {
        $log->info("Requested copy of entries @{$args->{jitemids}}.");
        copy_entry( $u, $args->{jitemids}, !$copy_comments );
    }
    elsif ( exists $args->{jtalkids} ) {
        $log->info("Requested copy of comments @{$args->{jtalkids}}.");
        copy_comment( $u, $args->{jtalkids} ) if $copy_comments;
    }
    else {
        $log->info("Requested complete recopy of user.");

        # Throttle unless the caller passed force => 1. Routine dispatchers
        # (schedulers, app hooks) should leave force unset so the 24h
        # memcache key prevents stampedes. Explicit operator invocations
        # (search-tool import-user, or import-all --force) pass force to
        # bypass.
        unless ( $args->{force} ) {
            my $time = LJ::MemCache::get( [ $u->id, "search-copy-full:" . $u->id ] );
            if ( $time && $time > time() - 86400 ) {
                $log->info("Copied less than a day ago. Skipping.");
                return DW::Task::COMPLETED;
            }
        }
        LJ::MemCache::set( [ $u->id, "search-copy-full:" . $u->id ], time() );
        copy_entry( $u, undef, 1 );
        copy_comment($u) if $copy_comments;
    }

    return DW::Task::COMPLETED;
}

sub copy_comment {
    my ( $u, $only_jtalkid ) = @_;
    my $dbsx = manticore_db()
        or $log->logcroak("Manticore database not available.");
    my $dbfrom = LJ::get_cluster_master( $u->clusterid )
        or $log->logcroak("User cluster master not available.");

    # If the parameter is not an arrayref, then make it one if it's defined.
    $only_jtalkid = [$only_jtalkid]
        if defined $only_jtalkid && !ref $only_jtalkid;

    # A full comment import. We slice it by 1000 comment groups to make the
    # memory usage something that isn't insane.
    if ( !defined $only_jtalkid ) {
        my $maxid = $dbfrom->selectrow_array(
            'SELECT MAX(jtalkid) FROM talk2 WHERE journalid = ?',
            undef, $u->id );
        $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;

        return unless $maxid;

        # Skip comment recopy for journals over the configured size limit.
        # MAX(jtalkid) is a proxy for "how many comments" — close enough
        # for this purpose, since deletion gaps don't meaningfully change
        # the order of magnitude. If $LJ::SEARCH_MAX_COMMENT_RECOPY is
        # unset, no limit is applied.
        if ( defined $LJ::SEARCH_MAX_COMMENT_RECOPY
            && $maxid > $LJ::SEARCH_MAX_COMMENT_RECOPY )
        {
            $log->info( sprintf
                    'Skipping comment recopy for %s(%d): MAX(jtalkid)=%d > limit %d.',
                $u->user, $u->id, $maxid, $LJ::SEARCH_MAX_COMMENT_RECOPY );
            return;
        }

        # If we have <1000 comments, do the mass-copy immediately to avoid
        # queue overhead.
        if ( $maxid < _CHUNK_SIZE ) {
            $log->info("Short path: doing mass-copy immediately.");
            copy_comment( $u, [ 1 .. $maxid ] );
            $log->info("Done with mass-copy.");
            return;
        }

        # Schedule jobs to do the copying.
        my $n = 0;
        while ( $n < $maxid ) {
            my $m = $n + _CHUNK_SIZE;
            $m = $maxid if $m > $maxid;

            my $h = DW::TaskQueue->dispatch(
                DW::Task::SearchCopier->new( {
                    userid   => $u->id,
                    jtalkids => [ $n + 1 .. $m ],
                    source   => 'masscopy',
                } )
            );
            $log->info( "Scheduled mass-copy job for jtalkids "
                    . ( $n + 1 )
                    . " .. $m: handle = $h." );

            $n = $m;
        }
        $log->info("Done with mass-copy.");
        return;
    }

    # Chunk processor: specific jtalkids.
    my ( $entries, $comments );
    my @delete_jtalkids;
    my $allowpublic = $u->include_in_global_search ? 1 : 0;

    my $in = join ',', map { int $_ } @$only_jtalkid;
    $comments = $dbfrom->selectall_hashref(
        qq{SELECT jtalkid, nodeid, state, posterid, UNIX_TIMESTAMP(datepost) AS 'datepost'
           FROM talk2 WHERE journalid = ? AND jtalkid IN ($in)},
        'jtalkid', undef, $u->id
    );
    $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;
    return unless ref $comments eq 'HASH' && %$comments;

    # Now we have some comments, get the parent-entry data we need to build
    # security for the entries they're children of.
    {
        my %jitemids;
        $jitemids{ $comments->{$_}->{nodeid} } = 1 foreach keys %$comments;
        my $inlist = join( ',', map { '?' } keys %jitemids );
        $entries = $dbfrom->selectall_hashref(
            qq{SELECT jitemid, security, allowmask FROM log2
                WHERE journalid = ? AND jitemid IN ($inlist)},
            'jitemid', undef, $u->id, keys %jitemids
        );
        $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;

        foreach my $row ( values %$entries ) {

            # Auto-convert usemask-with-no-groups to private.
            $row->{security} = 'private'
                if $row->{security} eq 'usemask' && $row->{allowmask} == 0;

            # We need extra security bits for some metadata. We have to do
            # this this way because it makes it easier to later do searches
            # on various combinations of things at the same time. Also, even
            # though these are bits, we're not going to ever use them as
            # actual bits.
            my @extrabits;
            push @extrabits, 101 if $row->{security} eq 'private';
            push @extrabits, 102 if $row->{security} eq 'public';

            $row->{bits} = [ LJ::bit_breakdown( $row->{allowmask} ), @extrabits ];
        }
    }

    # Comment loop. Categorize into delete vs live (with a force_private
    # flag for states we don't want to expose).
    my @jtalkids;
    foreach my $jtalkid ( keys %$comments ) {
        my $state         = $comments->{$jtalkid}->{state};
        my $force_private = 0;

        if ( $state eq 'D' ) {
            push @delete_jtalkids, int($jtalkid);
            next;
        }
        elsif ( $state eq 'S' || ( $state ne 'A' && $state ne 'F' ) ) {

            # If it's screened or in an unexpected state, make it private so
            # only owners can see it.
            $force_private = 1;
        }

        push @jtalkids, [ $jtalkid, $force_private ];
    }

    my ( $ins_count, $ins_min, $ins_max ) = ( 0, undef, undef );
    while ( my @items = splice( @jtalkids, 0, _CHUNK_SIZE ) ) {
        last unless @items;

        my @l_jtalkids = map { $_->[0] } @items;
        my %private    = map { $_->[0] => $_->[1] } @items;
        my $in         = join ',', @l_jtalkids;

        my $text = $dbfrom->selectall_hashref(
            qq{SELECT jtalkid, subject, body
               FROM talktext2 WHERE journalid = ? AND jtalkid IN ($in)},
            'jtalkid', undef, $u->id
        );
        $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;

        foreach my $jtd ( keys %$text ) {
            my ( $subj, $body ) = ( $text->{$jtd}->{subject}, $text->{$jtd}->{body} );
            LJ::text_uncompress( \$subj );
            $text->{$jtd}->{subject} = Encode::decode( 'utf8', $subj );
            LJ::text_uncompress( \$body );
            $text->{$jtd}->{body} = Encode::decode( 'utf8', $body );
        }

        foreach my $jid ( keys %$text ) {
            my $bits = $private{$jid}
                ? [101]
                : ( $entries->{ $comments->{$jid}->{nodeid} }->{bits} // [101] );

            # Upsert via DELETE+INSERT on the natural key. Manticore auto-
            # assigns doc IDs and we never look them up — the (journalid,
            # jitemid, jtalkid) tuple is the logical primary key. Integers
            # are interpolated because Manticore's SphinxQL binds every '?'
            # placeholder as a string and refuses string filters on uint
            # attributes.
            $dbsx->do( sprintf(
                'DELETE FROM dw1 WHERE journalid=%d AND jitemid=%d AND jtalkid=%d',
                $u->id, $comments->{$jid}->{nodeid}, $jid,
            ) );
            $log->logcroak( $dbsx->errstr ) if $dbsx->err;

            my $sql = sprintf(
                'INSERT INTO dw1 (journalid, jitemid, jtalkid, poster_id, date_posted,'
                . ' allow_global_search, is_deleted, security_bits, title, body)'
                . ' VALUES (%d, %d, %d, %d, %d, %d, 0, %s, ?, ?)',
                $u->id, $comments->{$jid}->{nodeid}, $jid, $comments->{$jid}->{posterid},
                $comments->{$jid}->{datepost}, $allowpublic, _mva($bits),
            );
            $dbsx->do( $sql, undef,
                $text->{$jid}->{subject} // '', $text->{$jid}->{body} // '' );
            $log->logcroak( $dbsx->errstr ) if $dbsx->err;

            $ins_count++;
            $ins_min = $jid if !defined $ins_min || $jid < $ins_min;
            $ins_max = $jid if !defined $ins_max || $jid > $ins_max;
        }
    }
    if ($ins_count) {
        $log->info( sprintf 'Inserted %d comments (#%d-#%d) for %s(%d).',
            $ins_count, $ins_min, $ins_max, $u->user, $u->id );
    }

    # Deletes are easy...
    if (@delete_jtalkids) {
        my $ct = $dbsx->do(
            sprintf( 'DELETE FROM dw1 WHERE journalid = %d AND jtalkid IN (%s)',
                $u->id, join( ',', @delete_jtalkids ) )
        ) + 0;
        $log->logcroak( $dbsx->errstr ) if $dbsx->err;

        $log->info("Actually deleted $ct comments.") if $ct > 0;
    }
}

sub copy_entry {
    my ( $u, $only_jitemid, $skip_comments ) = @_;
    my $dbsx = manticore_db()
        or $log->logcroak("Manticore database not available.");
    my $dbfrom = LJ::get_cluster_master( $u->clusterid )
        or $log->logcroak("User cluster master not available.");

    # If we're being asked to look at one post (or a list of specific posts),
    # that simplifies our processing quite a bit.
    my ( $sx_jitemids, $db_times, %comment_jitemids );
    my ( @copy_jitemids, @delete_jitemids );

    my $jid = int $u->id;    # for interpolation into Manticore queries

    if ($only_jitemid) {
        my @wanted = ref $only_jitemid ? @$only_jitemid : ($only_jitemid);
        my $inlist = join( ',', map { int $_ } @wanted );

        $sx_jitemids = $dbsx->selectall_hashref(
            "SELECT id, jitemid FROM dw1 WHERE journalid = $jid AND jitemid IN ($inlist) AND jtalkid = 0",
            'jitemid',
        );
        $log->logcroak( $dbsx->errstr ) if $dbsx->err;

        $db_times = $dbfrom->selectall_hashref(
            qq{SELECT jitemid, UNIX_TIMESTAMP(logtime) AS 'createtime'
               FROM log2 WHERE journalid = ? AND jitemid IN ($inlist)},
            'jitemid', undef, $u->id,
        );
        $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;
    }
    else {
        $sx_jitemids = $dbsx->selectall_hashref(
            "SELECT id, jitemid FROM dw1 WHERE journalid = $jid AND jtalkid = 0",
            'jitemid',
        );
        $log->logcroak( $dbsx->errstr ) if $dbsx->err;

        $db_times = $dbfrom->selectall_hashref(
            q{SELECT jitemid, UNIX_TIMESTAMP(logtime) AS 'createtime'
              FROM log2 WHERE journalid = ?},
            'jitemid', undef, $u->id,
        );
        $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;
    }

    # Everything in log2 we want to (re)copy. %comment_jitemids tracks the
    # set we'll later use for comment discovery.
    foreach my $jitemid ( keys %$db_times ) {
        push @copy_jitemids, $jitemid;
        $comment_jitemids{$jitemid} = 1;
    }

    # Now find deleted posts: anything in dw1 but not in log2.
    foreach my $jitemid ( keys %$sx_jitemids ) {
        next if exists $db_times->{$jitemid};

        push @delete_jitemids, $jitemid;
        $comment_jitemids{$jitemid} = 1;
    }

    # Deletes are easy...
    if (@delete_jitemids) {
        my $ct = $dbsx->do(
            sprintf(
                'DELETE FROM dw1 WHERE journalid = %d AND jtalkid = 0 AND jitemid IN (%s)',
                $jid, join( ',', @delete_jitemids )
            )
        ) + 0;
        $log->logcroak( $dbsx->errstr ) if $dbsx->err;

        $log->info("Actually deleted $ct posts.");
    }

    # Now copy entries. This is not done en-masse since the major case will
    # be after a user already has most of their posts copied and is just
    # updating one or two.
    my $allowpublic = $u->include_in_global_search ? 1 : 0;
    my ( $ins_count, $ins_min, $ins_max ) = ( 0, undef, undef );
    foreach my $jitemid (@copy_jitemids) {
        my $row = $dbfrom->selectrow_hashref(
            q{SELECT l.journalid, l.jitemid, l.posterid, l.security, l.allowmask,
                     UNIX_TIMESTAMP(l.logtime) AS 'date_posted',
                     lt.subject, lt.event
              FROM log2 l INNER JOIN logtext2 lt ON (l.journalid = lt.journalid AND l.jitemid = lt.jitemid)
              WHERE l.journalid = ? AND l.jitemid = ?},
            undef, $u->id, $jitemid,
        );
        $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;

        # Just make sure, in case we don't have a corresponding logtext2 row.
        next unless $row;

        # Auto-convert usemask-with-no-groups to private.
        $row->{security} = 'private'
            if $row->{security} eq 'usemask' && $row->{allowmask} == 0;

        # Security bits as described in copy_comment above.
        my @extrabits;
        push @extrabits, 101 if $row->{security} eq 'private';
        push @extrabits, 102 if $row->{security} eq 'public';
        my $bits = [ LJ::bit_breakdown( $row->{allowmask} ), @extrabits ];

        # Very important, the search engine can't index compressed crap...
        foreach (qw/ subject event /) {
            LJ::text_uncompress( \$row->{$_} );

            # Required, we store raw-bytes in our own database but Manticore
            # expects things to be proper UTF-8.
            $row->{$_} = Encode::decode( 'utf8', $row->{$_} );
        }

        # Upsert via DELETE+INSERT on the natural key.
        $dbsx->do( sprintf(
            'DELETE FROM dw1 WHERE journalid=%d AND jitemid=%d AND jtalkid=0',
            $jid, $jitemid,
        ) );
        $log->logcroak( $dbsx->errstr ) if $dbsx->err;

        my $sql = sprintf(
            'INSERT INTO dw1 (journalid, jitemid, jtalkid, poster_id, date_posted,'
            . ' allow_global_search, is_deleted, security_bits, title, body)'
            . ' VALUES (%d, %d, 0, %d, %d, %d, 0, %s, ?, ?)',
            $jid, $jitemid, $row->{posterid}, $row->{date_posted},
            $allowpublic, _mva($bits),
        );
        $dbsx->do( $sql, undef, $row->{subject} // '', $row->{event} // '' );
        $log->logcroak( $dbsx->errstr ) if $dbsx->err;

        $ins_count++;
        $ins_min = $jitemid if !defined $ins_min || $jitemid < $ins_min;
        $ins_max = $jitemid if !defined $ins_max || $jitemid > $ins_max;
    }
    if ($ins_count) {
        $log->info( sprintf 'Inserted %d posts (#%d-#%d) for %s(%d).',
            $ins_count, $ins_min, $ins_max, $u->user, $u->id );
    }

    # After entries, if the caller wanted us to, discover and dispatch
    # comment copies for every post we just touched (comments that exist
    # in dw1 for that post plus any in talk2 we haven't seen yet).
    unless ($skip_comments) {
        my %commentids;
        foreach my $jitemid ( keys %comment_jitemids ) {

            # Comments we know about (so we can delete them if they've
            # been removed).
            my $jtalkids = $dbsx->selectcol_arrayref(
                sprintf(
                    'SELECT jtalkid FROM dw1 WHERE journalid = %d AND jitemid = %d AND jtalkid > 0',
                    $jid, int $jitemid,
                )
            );
            $log->logcroak( $dbsx->errstr ) if $dbsx->err;

            if ( $jtalkids && ref $jtalkids eq 'ARRAY' ) {
                $commentids{$_} = 1 foreach @$jtalkids;
            }

            # And this catches comments that we don't know about yet.
            my $jtalkids2 = $dbfrom->selectcol_arrayref(
                q{SELECT jtalkid FROM talk2 WHERE journalid = ? AND nodetype = 'L' AND nodeid = ?},
                undef, $u->id, $jitemid,
            );
            $log->logcroak( $dbfrom->errstr ) if $dbfrom->err;

            if ( $jtalkids2 && ref $jtalkids2 eq 'ARRAY' ) {
                $commentids{$_} = 1 foreach @$jtalkids2;
            }
        }
        copy_comment( $u, $_ ) foreach keys %commentids;
    }
}

# -----------------------------------------------------------------------------
# Helper: multi-value attribute literal for SphinxQL INSERT.
# rt_attr_multi columns are written as a parenthesized list: (1,2,3). Assumes
# all ints — security_bits is the only MVA we use.
# -----------------------------------------------------------------------------

sub _mva {
    return '(' . join( ',', @{ $_[0] } ) . ')';
}

1;
