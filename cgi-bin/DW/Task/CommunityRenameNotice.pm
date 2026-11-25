#!/usr/bin/perl
#
# DW::Task::CommunityRenameNotice - Queue email notices for a renamed community.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Task::CommunityRenameNotice;

use strict;
use warnings;

use LJ::Sendmail;
use Log::Log4perl;

use constant BATCH_SIZE   => 25;
use constant RETRY_SECS   => 60;
use constant MAX_ATTEMPTS => 10;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

my $eligible_members = q{
    FROM reluser
    JOIN user ON user.userid=reluser.targetid
    JOIN email ON email.userid=user.userid
   WHERE reluser.userid=? AND reluser.type='E'
     AND user.status='A' AND user.statusvis='V' AND user.clusterid<>0
};
my $mailbox = 'CAST(LOWER(email.email) AS BINARY)';

sub enqueue {
    my ( $class, $dbh, @details ) = @_;

    return $dbh->do(
'INSERT INTO community_rename_notice (commid, oldname, newname, profile) VALUES (?, ?, ?, ?)',
        undef, @details
    );
}

sub process_pending {
    my ( $class, $commid ) = @_;

    my $worked = eval {
        my $dbh = LJ::get_db_writer() or die 'No community rename notice writer';
        local $dbh->{RaiseError} = 1;
        local $dbh->{PrintError} = 0;
        _process_batch( $dbh, $commid );
    };
    $log->error('Could not advance the community rename notice outbox') if $@;
    return $worked // 0;
}

sub _process_batch {
    my ( $dbh, $commid ) = @_;

    my $batch = _transaction(
        $dbh,
        sub {
            my $filter = defined $commid ? 'AND n.commid=?' : '';
            my $notice = $dbh->selectrow_hashref(
                "SELECT n.* FROM community_rename_notice n WHERE (n.scanned=0 OR COALESCE((
                     SELECT MIN(r.next_attempt) FROM community_rename_recipient r
                      WHERE r.noticeid=n.noticeid
                 ), 0)<=UNIX_TIMESTAMP()) $filter ORDER BY n.noticeid LIMIT 1 FOR UPDATE",
                undef, defined $commid ? ($commid) : (),
            ) or return;

            my $ready = _ready_recipients( $dbh, $notice->{noticeid} );
            unless ( @$ready || $notice->{scanned} ) {
                _stage_page( $dbh, $notice );
                $ready = _ready_recipients( $dbh, $notice->{noticeid} );
            }
            return [ $notice, $ready ];
        }
    ) or return 0;

    my ( $notice, $ready ) = @$batch;
    my $subject = LJ::Lang::ml('rename.email.community.subject');
    my $body    = LJ::Lang::ml( 'rename.email.community.body',
        { map { $_ => $notice->{$_} } qw( oldname newname profile ) } );

    foreach my $recipient (@$ready) {
        _transaction( $dbh, sub { _deliver( $dbh, $notice, $recipient, $subject, $body ) } );
    }

    $dbh->do(
        'DELETE FROM community_rename_notice WHERE noticeid=? AND scanned=1 AND NOT EXISTS '
            . '(SELECT 1 FROM community_rename_recipient WHERE noticeid=?)',
        undef,
        ( $notice->{noticeid} ) x 2
    );
    return 1;
}

sub _ready_recipients {
    my ( $dbh, $noticeid ) = @_;

    return $dbh->selectcol_arrayref(
        'SELECT mailbox FROM community_rename_recipient WHERE noticeid=? '
            . 'AND next_attempt<=UNIX_TIMESTAMP() ORDER BY next_attempt, mailbox LIMIT ?',
        undef, $noticeid, BATCH_SIZE
    );
}

sub _stage_page {
    my ( $dbh, $notice ) = @_;

    my $page = $dbh->selectall_arrayref(
        "SELECT $mailbox AS mailbox, MIN(user.userid) $eligible_members
            AND $mailbox>? GROUP BY mailbox ORDER BY mailbox LIMIT ?",
        undef, $notice->{commid}, $notice->{after_mailbox}, BATCH_SIZE + 1
    );
    my $more = @$page > BATCH_SIZE;
    pop @$page if $more;
    foreach my $row (@$page) {
        $dbh->do(
            'INSERT INTO community_rename_recipient (noticeid, mailbox, memberid) VALUES (?, ?, ?)',
            undef, $notice->{noticeid}, @$row
        );
    }
    $dbh->do(
        'UPDATE community_rename_notice SET after_mailbox=?, scanned=? WHERE noticeid=?',
        undef,
        @$page ? $page->[-1][0] : $notice->{after_mailbox},
        $more ? 0 : 1,
        $notice->{noticeid}
    );
}

sub _deliver {
    my ( $dbh, $notice, $recipient, $subject, $body ) = @_;
    my @key = ( $notice->{noticeid}, $recipient );

    my ( $memberid, $failures ) = $dbh->selectrow_array(
        'SELECT memberid, failures FROM community_rename_recipient WHERE noticeid=? AND mailbox=? '
            . 'AND next_attempt<=UNIX_TIMESTAMP() FOR UPDATE',
        undef, @key
    );
    return unless $memberid;

    my $lookup = "SELECT email.email $eligible_members AND $mailbox=?";
    my ($address) = $dbh->selectrow_array( "$lookup AND user.userid=?",
        undef, $notice->{commid}, $recipient, $memberid );
    ($address) = $dbh->selectrow_array( "$lookup LIMIT 1", undef, $notice->{commid}, $recipient )
        unless defined $address;

    my $failed = defined $address && !eval { _queue_email( $address, $subject, $body ) };
    if ( !$failed || ++$failures >= MAX_ATTEMPTS ) {
        $dbh->do( 'DELETE FROM community_rename_recipient WHERE noticeid=? AND mailbox=?',
            undef, @key );
        $log->error( 'Dropped a recipient from community rename notice ',
            $notice->{noticeid}, ' after ', $failures, ' failed mail submissions' )
            if $failed;
    }
    else {
        $log->error('Could not queue a community rename notice email; will retry');
        $dbh->do(
            'UPDATE community_rename_recipient SET failures=?, next_attempt=UNIX_TIMESTAMP()+? '
                . 'WHERE noticeid=? AND mailbox=?',
            undef, $failures, RETRY_SECS, @key
        );
    }
}

sub _transaction {
    my ( $dbh, $work ) = @_;

    $dbh->begin_work;
    my $result;
    my $ok = eval { $result = $work->(); $dbh->commit; 1 };
    unless ($ok) {
        my $error = $@;
        $dbh->rollback unless $dbh->{AutoCommit};
        die $error;
    }
    return $result;
}

sub _queue_email {
    my ( $address, $subject, $body ) = @_;

    return 1 unless $address =~ /\A[^@\s]+\@[^@\s]+\z/;
    my @errors;
    LJ::check_email( $address, \@errors, { force_spelling => 1 } );
    return 1 if @errors;

    return LJ::send_mail(
        {
            to       => $address,
            from     => $LJ::BOGUS_EMAIL,
            fromname => $LJ::SITENAMESHORT,
            subject  => $subject,
            body     => $body,
        }
    );
}

1;
