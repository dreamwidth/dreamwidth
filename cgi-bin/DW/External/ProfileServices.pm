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
        "SELECT name, userprop, imgfile, title_ml, url_format, maxlen FROM profile_services",
        "name" );
    die $dbr->errstr if $dbr->err;

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
    return $accounts if $accounts;

    $accounts = {};

    # load accounts from database and add to memcache (no expiration)
    my $dbcr = LJ::get_cluster_reader($u) or die;
    my $data = $dbcr->selectall_arrayref(
        "SELECT name, value FROM user_profile_accts WHERE userid=? ORDER BY name, value",
        { Slice => {} }, $uid );
    die $dbcr->errstr if $dbcr->err;

    foreach my $acct (@$data) {
        my $name = $acct->{name};
        $accounts->{$name} //= [];
        push @{ $accounts->{$name} }, $acct->{value};
    }

    LJ::MemCache::set( $memkey, $accounts );

    return $accounts;
}
*LJ::User::load_profile_accts = \&load_profile_accts;
*DW::User::load_profile_accts = \&load_profile_accts;

1;
