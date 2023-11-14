#!/usr/bin/perl
#
# DW::Worker::XPostWorker
#
# TheSchwartz worker module for crossposting. Called with:
# LJ::theschwartz()->insert('DW::Worker::XPostWorker', {
# 'uid' => $remote->userid, 'ditemid' => $itemid, 'ditemid' => $itemid,
# 'accountid' => $acctid, 'password' => $auth{password},
# 'auth_challenge' => $auth{auth_challenge},
# 'auth_response' => $auth{auth_response}, 'delete' => 0' });
#
# Authors:
#      Allen Petersen
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Worker::XPostWorker;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Time::HiRes qw/ gettimeofday /;

use DW::External::Account;
use LJ::Event::XPostSuccess;
use LJ::Lang;
use LJ::Protocol;
use LJ::User;

use base 'TheSchwartz::Worker';

sub schwartz_capabilities { return ('DW::Worker::XPostWorker'); }

sub max_retries { 5 }

sub retry_delay {
    my ( $class, $fails ) = @_;

    return ( 10, 30, 60, 300, 600 )[$fails];
}

sub keep_exit_status_for { 86400 }    # 24 hours

# FIXME: tune value?
sub grab_for { 600 }

sub work {
    my ( $class, $job ) = @_;
    my $arg = { %{ $job->arg } };

    my ( $uid, $ditemid, $acctid, $password, $auth_challenge, $auth_response, $delete ) =
        map { delete $arg->{$_} }
        qw( uid ditemid accountid password auth_challenge
        auth_response delete );
    return $job->permanent_failure( "Unknown keys: " . join( ", ", keys %$arg ) )
        if keys %$arg;
    return $job->permanent_failure("Missing argument")
        unless defined $uid && defined $ditemid && defined $acctid;

    my $u = LJ::want_user($uid)
        or return $job->failed("Unable to load user with uid $uid");
    return $job->permanent_failure("User is suspended.")
        if $u->is_suspended;

    my $acct = DW::External::Account->get_external_account( $u, $acctid )
        or return $job->failed("Unable to load account $acctid for uid $uid");

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
        return $job->permanent_failure($ljr_msg);
    }

    # LiveJournal has broken (or disabled) client posts - notify the user
    if ( $acct->externalsite && $acct->externalsite->{sitename} eq 'LiveJournal' ) {
        my $ljr_msg =
              "Crossposting to LiveJournal is temporarily disabled due to LiveJournal refusing "
            . "connections from us. Please see https://dw-maintenance.dreamwidth.org/86004.html for more details.";
        $notify_fail->($ljr_msg);
        return $job->permanent_failure($ljr_msg);
    }

    my $domain = $acct->externalsite ? $acct->externalsite->{domain} : 'unknown';

    my $entry = LJ::Entry->new( $u, ditemid => $ditemid );
    return $job->failed("Unable to load entry $ditemid for uid $uid")
        unless defined $entry && ( $delete || $entry->valid );

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

        # FIXME: subroutine not implemented
        # DW::Stats::timing( 'dw.worker.crosspost.success_time', $start, [ "domain:$domain" ] );
        printf STDERR "[xpost] Successful post to %s for %s(%d).\n", $domain, $u->user, $u->id;
    }
    else {
        # In case this was a connection timeout, then we want to do special
        # handling to make sure we retry immediately, but if we exhaust
        # max_retries, we should give up instead of rescheduling for later.
        if ( $result->{error} =~ /Failed to connect/ ) {
            printf STDERR "[xpost] Timeout posting to %s for %s(%d)... will retry.\n",
                $domain, $u->user, $u->id;
            return $job->failed("Timeout encountered, maybe retry.");
        }

        # Some other failure, so let's just let it go through.
        $notify_fail->( $result->{error} );
        DW::Stats::increment( 'dw.worker.crosspost.failure', 1, ["domain:$domain"] );

        # FIXME: subroutine not implemented
        # DW::Stats::timing( 'dw.worker.crosspost.failure_time', $start, [ "domain:$domain" ] );
        printf STDERR "[xpost] Failed to post to %s for %s(%d): %s.\n",
            $domain, $u->user, $u->id, $result->{error} || 'Unknown error message.';
    }

    $job->completed;
}

1;
