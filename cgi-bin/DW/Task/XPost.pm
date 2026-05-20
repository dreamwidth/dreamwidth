#!/usr/bin/perl
#
# DW::Task::XPost
#
# SQS worker for crossposting entries to external accounts.
#
# Authors:
#     Allen Petersen
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::XPost;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Time::HiRes qw/ gettimeofday /;

use DW::External::Account;
use DW::TaskQueue;
use LJ::Event::XPostSuccess;
use LJ::Lang;
use LJ::Protocol;
use LJ::User;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $arg = { %{ $self->args->[0] } };

    my ( $uid, $ditemid, $acctid, $password, $auth_challenge, $auth_response, $delete ) =
        map { delete $arg->{$_} }
        qw( uid ditemid accountid password auth_challenge
        auth_response delete );

    if ( keys %$arg ) {
        $log->error( "Unknown keys: " . join( ", ", keys %$arg ) );
        return DW::Task::COMPLETED;
    }
    unless ( defined $uid && defined $ditemid && defined $acctid ) {
        $log->error("Missing argument");
        return DW::Task::COMPLETED;
    }

    my $u = LJ::want_user($uid);
    unless ($u) {
        $log->error("Unable to load user with uid $uid");
        return DW::Task::FAILED;
    }

    if ( $u->is_suspended ) {
        $log->error("User is suspended.");
        return DW::Task::COMPLETED;
    }

    my $acct = DW::External::Account->get_external_account( $u, $acctid );
    unless ($acct) {
        $log->error("Unable to load account $acctid for uid $uid");
        return DW::Task::FAILED;
    }

    my $notify_fail = sub {
        DW::TaskQueue->dispatch(
            LJ::Event::XPostFailure->new(
                $u, $acctid, $ditemid, ( $_[0] || 'Unknown error message.' )
            )
        );
    };

    # LJRossia is temporarily broken, so skip - but we do want to notify
    if ( $acct->externalsite && $acct->externalsite->{sitename} eq 'LJRossia' ) {
        my $ljr_msg =
"Crossposts to LJRossia are disabled until the remote site fixes their XMLRPC protocol handler.";
        $notify_fail->($ljr_msg);
        return DW::Task::COMPLETED;
    }

    # LiveJournal has broken (or disabled) client posts - notify the user
    if ( $acct->externalsite && $acct->externalsite->{sitename} eq 'LiveJournal' ) {
        my $ljr_msg =
              "Crossposting to LiveJournal is temporarily disabled due to LiveJournal refusing "
            . "connections from us. Please see https://dw-maintenance.dreamwidth.org/86004.html for more details.";
        $notify_fail->($ljr_msg);
        return DW::Task::COMPLETED;
    }

    my $domain = $acct->externalsite ? $acct->externalsite->{domain} : 'unknown';

    my $entry = LJ::Entry->new( $u, ditemid => $ditemid );
    unless ( defined $entry && ( $delete || $entry->valid ) ) {
        $log->error("Unable to load entry $ditemid for uid $uid");
        return DW::Task::FAILED;
    }

    my %auth;
    if ($auth_response) {
        %auth = ( 'auth_challenge' => $auth_challenge, 'auth_response' => $auth_response );
    }
    else {
        %auth = ( 'password' => $password );
    }

    my $start = [gettimeofday];
    my $result =
        $delete ? $acct->delete_entry( \%auth, $entry ) : $acct->crosspost( \%auth, $entry );

    if ( $result->{success} ) {
        DW::TaskQueue->dispatch( LJ::Event::XPostSuccess->new( $u, $acctid, $ditemid ) );
        DW::Stats::increment( 'dw.worker.crosspost.success', 1, ["domain:$domain"] );
        $log->info( sprintf( "Successful post to %s for %s(%d).", $domain, $u->user, $u->id ) );
    }
    else {
        # In case this was a connection timeout, then we want to do special
        # handling to make sure we retry immediately
        if ( $result->{error} =~ /Failed to connect/ ) {
            $log->warn(
                sprintf(
                    "Timeout posting to %s for %s(%d)... will retry.",
                    $domain, $u->user, $u->id
                )
            );
            return DW::Task::FAILED;
        }

        # Some other failure, so let's just let it go through.
        $notify_fail->( $result->{error} );
        DW::Stats::increment( 'dw.worker.crosspost.failure', 1, ["domain:$domain"] );
        $log->error(
            sprintf(
                "Failed to post to %s for %s(%d): %s.",
                $domain, $u->user, $u->id, $result->{error} || 'Unknown error message.'
            )
        );
    }

    return DW::Task::COMPLETED;
}

1;
