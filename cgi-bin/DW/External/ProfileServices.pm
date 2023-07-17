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
    return $accounts if $accounts;

    $accounts = {};

    # load accounts from database and add to memcache (no expiration)
    my $dbcr = LJ::get_cluster_reader($u) or die;
    my $data = $dbcr->selectall_arrayref(
        "SELECT name, value FROM user_profile_accts WHERE userid=? ORDER BY name, value",
        { Slice => {} }, $uid );
    confess $dbcr->errstr if $dbcr->err;

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

sub save_profile_accts {
    my ( $u, $new_accts, %opts ) = @_;
    $u = LJ::want_user($u) or confess 'invalid user object';
    my $old_accts = $u->load_profile_accts;

    # expire memcache after updating db
    my $uid    = $u->userid;
    my $memkey = [ $uid, "profile_accts:$uid" ];

    return unless $u->writer;

    my %sites = map { $_->{name} => 1 } @{ DW::External::ProfileServices->list };

    # if %$old_accts is empty, we need to clear out the user's legacy userprops
    # to avoid an edge case where if a user clears out all of their accounts
    # later, the old userprop values will suddenly reappear on their profile
    unless (%$old_accts) {
        my $userprops = DW::External::ProfileServices->userprops;
        my %prop      = map { $_ => '' } @$userprops;
        $u->set_prop( \%prop, undef, { skip_db => 1 } );
    }

    # convert listref vals to sanitized hashref vals
    # note: we now lowercase to avoid value duplication
    # when allowing multiple values per account type
    my $remap = sub {
        my $href = shift;
        my %ret;

        foreach my $name ( keys %$href ) {
            next unless $sites{$name};
            foreach my $val ( @{ $href->{$name} } ) {
                $val = lc( $val // '' );
                next unless $val;
                $ret{$name} //= {};
                $ret{$name}->{$val} = 1;
            }
        }
        return %ret;
    };

    my %old = $remap->($old_accts);
    my %new = $remap->($new_accts);

    my $process = sub {
        my ( $hr1, $hr2 ) = @_;
        my %ret;

        foreach my $name ( keys %$hr1 ) {
            foreach my $val ( keys %{ $hr1->{$name} } ) {
                unless ( $hr2->{$name} && $hr2->{$name}->{$val} ) {
                    $ret{$name} //= [];
                    push @{ $ret{$name} }, $val;
                }
            }
        }
        return %ret;
    };

    my %del = $process->( \%old, \%new );
    my %add = $process->( \%new, \%old );

    foreach my $name ( keys %del ) {
        foreach my $val ( @{ $del{$name} } ) {
            $u->do( "DELETE FROM user_profile_accts WHERE userid = ? AND name = ? AND value = ?",
                undef, $uid, $name, $val );
            confess $u->errstr if $u->err;
        }
    }

    foreach my $name ( keys %add ) {
        foreach my $val ( @{ $add{$name} } ) {
            $u->do( "INSERT INTO user_profile_accts (userid, name, value) VALUES (?,?,?)",
                undef, $uid, $name, $val );
            confess $u->errstr if $u->err;
        }
    }

    LJ::MemCache::delete($memkey);

    return 1;
}
*LJ::User::save_profile_accts = \&save_profile_accts;
*DW::User::save_profile_accts = \&save_profile_accts;

1;
