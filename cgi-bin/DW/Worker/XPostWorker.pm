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

use strict;
use warnings;
use lib "$LJ::HOME/cgi-bin";

package DW::Worker::XPostWorker;
use base 'TheSchwartz::Worker';
use DW::External::Account;
use LJ::Event::XPostSuccess;
use LJ::User;
use LJ::Lang;

BEGIN { require "ljprotocol.pl" }

sub schwartz_capabilities { return ('DW::Worker::XPostWorker'); }

sub max_retries { 5 }

sub retry_delay {
    my ($class, $fails) = @_;

    return (10, 30, 60, 300, 600)[$fails];
}

sub keep_exit_status_for { 86400 } # 24 hours

# FIXME: tune value?
sub grab_for { 600 }

sub work {
    my ($class, $job) = @_;

    my $arg = { %{$job->arg} };

    my ($uid, $ditemid, $acctid, $password, $auth_challenge, $auth_response, $delete) = map { delete $arg->{$_} } qw( uid ditemid accountid password auth_challenge auth_response delete );

    return $job->permanent_failure("Unknown keys: " . join(", ", keys %$arg))
        if keys %$arg;
    return $job->permanent_failure("Missing argument")
        unless defined $uid && defined $ditemid && defined $acctid;
        
    # get the user from the uid
    my $u = LJ::want_user($uid) or return $job->failed("Unable to load user with uid $uid");

    # get the account from the acctid
    my $acct = DW::External::Account->get_external_account($u, $acctid);
    # fail if no available account
    return $job->failed("Unable to load account $acctid for uid $uid") unless defined $acct;

    my $entry = LJ::Entry->new($u, ditemid => $ditemid);
    return $job->failed("Unable to load entry $ditemid for uid $uid") unless defined $entry;

    my %auth;
    if ($auth_response) {
        %auth = ( 'auth_challenge' => $auth_challenge, 'auth_response' => $auth_response );
    } else {
        %auth = ( 'password' => $password );
    }

    my $result = $delete ? $acct->delete_entry(\%auth, $entry) : $acct->crosspost(\%auth, $entry);
    my $sclient = LJ::theschwartz();
    if ($result->{success}) {
        $sclient->insert_jobs(LJ::Event::XPostSuccess->new($u, $acctid, $ditemid)->fire_job );
    } else {
        $sclient->insert_jobs(
            LJ::Event::XPostFailure->new(
                $u, $acctid, $ditemid, ( $result->{error} || 'Unknown error message.' )
            )->fire_job
        );
    }
    
    $job->completed;
}

1;
