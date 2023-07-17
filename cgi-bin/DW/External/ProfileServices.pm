#!/usr/bin/perl
#
# DW::External::ProfileServices
#
# Information on external services referenced on profile pages.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::External::ProfileServices;

use strict;
use warnings;

use Carp qw/ confess /;

sub list {
    my ( $class, %opts ) = @_;

    # load services from memcache
    my $memkey   = 'profile_services';
    my $services = LJ::MemCache::get($memkey);
    return $services if $services;

    # load services from database and add to memcache (expiring hourly)
    my $dbr  = LJ::get_db_reader();
    my $data = $dbr->selectall_hashref(
        "SELECT service_id, name, userprop, imgfile, title_ml,"
            . " url_format, maxlen FROM profile_services",
        "name"
    );
    confess $dbr->errstr if $dbr->err;

    $services = [ map { $data->{$_} } sort keys %$data ];
    LJ::MemCache::set( $memkey, $services, 3600 );

    return $services;
}

sub userprops {
    my ( $class, %opts ) = @_;

    my $services = $class->list;
    my @userprops;

    foreach my $site (@$services) {
        push @userprops, $site->{userprop} if defined $site->{userprop};
    }

    return \@userprops;
}

### user methods

sub load_profile_accts {
    my ( $u, %args ) = @_;
    $u = LJ::want_user($u) or confess 'invalid user object';
    my $uid = $u->userid;

    # load accounts from memcache
    my $memkey   = [ $uid, "profile_accts:$uid" ];
    my $accounts = LJ::MemCache::get($memkey);
    return $accounts if $accounts && !$args{force_db};

    $accounts = {};

    # load accounts from database and add to memcache (no expiration)
    my $dbcr = LJ::get_cluster_reader($u) or die;
    my $data = $dbcr->selectall_arrayref(
        "SELECT service_id, account_id, value FROM user_profile_accts"
            . " WHERE userid=? ORDER BY value",
        { Slice => {} },
        $uid
    );
    confess $dbcr->errstr if $dbcr->err;

    foreach my $acct (@$data) {
        my $s_id = $acct->{service_id};
        $accounts->{$s_id} //= [];
        push @{ $accounts->{$s_id} }, [ $acct->{account_id}, $acct->{value} ];
    }

    LJ::MemCache::set( $memkey, $accounts );

    return $accounts;
}
*LJ::User::load_profile_accts = \&load_profile_accts;
*DW::User::load_profile_accts = \&load_profile_accts;

sub save_profile_accts {
    my ( $u, $new_accts, %opts ) = @_;
    $u = LJ::want_user($u) or confess 'invalid user object';
    my $old_accts = $u->load_profile_accts( force_db => 1 );

    # expire memcache after updating db
    my $uid    = $u->userid;
    my $memkey = [ $uid, "profile_accts:$uid" ];

    return unless $u->writer;

    # if %$old_accts is empty, we need to clear out the user's legacy userprops
    # to avoid an edge case where if a user clears out all of their accounts
    # later, the old userprop values will suddenly reappear on their profile
    unless (%$old_accts) {
        my $userprops = DW::External::ProfileServices->userprops;
        my %prop      = map { $_ => '' } @$userprops;
        $u->set_prop( \%prop, undef, { skip_db => 1 } );
    }

    while ( my ( $s_id, $multival ) = each %$new_accts ) {
        foreach my $val (@$multival) {
            if ( ref $val && $val->[1] ) {

                # update the value of the existing row
                $u->do(
                    "UPDATE user_profile_accts SET value = ? WHERE account_id = ? AND userid = ?",
                    undef, $val->[1], $val->[0], $uid );
            }
            elsif ( ref $val ) {

                # delete the existing row
                $u->do( "DELETE FROM user_profile_accts WHERE account_id = ? AND userid = ?",
                    undef, $val->[0], $uid );
            }
            else {
                # new addition or legacy upgrade
                my $a_id = LJ::alloc_user_counter( $u, 'P' );
                $u->do(
                    "INSERT INTO user_profile_accts (userid, account_id, service_id, value)"
                        . " VALUES (?,?,?,?)",
                    undef, $uid, $a_id, $s_id, $val
                );
            }
            confess $u->errstr if $u->err;
        }
    }

    LJ::MemCache::delete($memkey);

    return 1;
}
*LJ::User::save_profile_accts = \&save_profile_accts;
*DW::User::save_profile_accts = \&save_profile_accts;

1;
