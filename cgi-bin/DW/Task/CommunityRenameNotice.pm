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

use base 'DW::Task';
use DW::TaskQueue;
use LJ::Sendmail;
use Log::Log4perl;

use constant BATCH_SIZE => 25;

my $log = Log::Log4perl->get_logger(__PACKAGE__);

sub work {
    my ($self)   = @_;
    my ($notice) = @{ $self->args };

    my $subject = LJ::Lang::ml('rename.email.community.subject');
    my $body    = LJ::Lang::ml( 'rename.email.community.body',
        { map { $_ => $notice->{$_} } qw( oldname newname profile ) } );

    if ( $notice->{retry_address} ) {
        return _try_queue_email( $notice->{retry_address}, $subject, $body )
            ? DW::Task::COMPLETED
            : DW::Task::FAILED;
    }

    my $batch = eval { _mailboxes( $notice->{commid}, $notice->{after} // '' ) };
    unless ($batch) {
        $log->error('Could not read community rename notice recipients');
        return DW::Task::FAILED;
    }

    my $more = @$batch > BATCH_SIZE;
    pop @$batch if $more;
    my @followups;
    foreach my $row (@$batch) {
        my ( undef, $address ) = @$row;
        push @followups, { %$notice, retry_address => $address }
            unless _try_queue_email( $address, $subject, $body );
    }
    unshift @followups, { %$notice, after => $batch->[-1][0] } if $more;

    my $failed = 0;
    foreach my $followup (@followups) {
        next if eval { DW::TaskQueue->dispatch( ref($self)->new($followup) ) };
        $log->error('Could not enqueue a community rename notice follow-up');
        $failed = 1;
    }

    return $failed ? DW::Task::FAILED : DW::Task::COMPLETED;
}

sub _mailboxes {
    my ( $commid, $after ) = @_;
    my $dbh = LJ::get_db_writer() or return;
    my $sql = q{
        SELECT CAST(LOWER(email.email) AS BINARY) AS mailbox, MIN(BINARY email.email)
          FROM reluser
          JOIN user ON user.userid=reluser.targetid
          JOIN email ON email.userid=user.userid
         WHERE reluser.userid=? AND reluser.type='E'
           AND user.status='A' AND user.statusvis='V' AND user.clusterid<>0
           AND CAST(LOWER(email.email) AS BINARY)>?
         GROUP BY mailbox ORDER BY mailbox LIMIT ?
    };
    my $batch = $dbh->selectall_arrayref( $sql, undef, $commid, $after, BATCH_SIZE + 1 );
    return $dbh->err ? undef : $batch;
}

sub _try_queue_email {
    my $queued = eval { _queue_email(@_) };
    $log->error('Could not queue a community rename notice email') unless $queued;
    return $queued;
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
