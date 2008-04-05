#!/usr/bin/perl

package LJ::ExpungedUsers;

use strict;
use Carp qw(croak);

sub load_recent {
    my $class = shift;
    my %opts  = @_;

    my $within = delete $opts{within} || 3600;
    my $limit  = delete $opts{limit}  || 100;

    croak "invalid arguments: " . join(",", keys %opts) 
        if %opts;

    my $dbr = LJ::get_db_reader()
        or die "unable to contact global reader";

    my $sth = $dbr->prepare
        ("SELECT userid, expunge_time FROM expunged_users " . 
         "WHERE expunge_time > UNIX_TIMESTAMP() - ? LIMIT $limit");
    $sth->execute($within);

    my @uids = ();
    my %exp_times = (); # uid => exp_time
    while (my ($uid, $exp_time) = $sth->fetchrow_array) {
        push @uids, $uid;
        $exp_times{$uid} = $exp_time;
    }

    my $us = LJ::load_userids(@uids);

    return (grep { $_->[0]->{user} !~ /^ex_/ && !$_->[0]->is_identity }
            sort { $a->[0]->{user} cmp $b->[0]->{user} } 
            map { [ $us->{$_}, $exp_times{$_} ] } @uids);
}

sub load_single_user {
    my $class = shift;
    my $user  = shift;

    $user = LJ::canonical_username($user);
    croak "invalid user: $user"
        unless $user;

    my $u = LJ::load_user($user);

    # is the user actually expunged?
    return unless $u && $u->is_expunged;

    # did someone rename to it?
    return if $u->user =~ /^ex_/;

    # ding.
    return $u;
}

sub fuzzy_load_user {
    my $class = shift;
    my $user  = shift;

    $user = LJ::canonical_username($user);
    croak "invalid user: $user"
        unless $user;

    return $class->_query_result_array
        ("SELECT userid, expunge_time FROM expunged_users " . 
         "WHERE user LIKE ? LIMIT 10", $user . "%");
}

sub _query_result_array {
    my $class = shift;
    my ($sql, @vals) = @_;

    my $dbr = LJ::get_db_reader()
        or die "unable to contact global reader";

    my $sth = $dbr->prepare($sql);
    $sth->execute(@vals);
    die $dbr->errstr if $dbr->err;

    my @rows = ();
    while (my ($uid, $exp_time) = $sth->fetchrow_array) {
        push @rows, [ $uid => $exp_time ];
    }

    my $us = LJ::load_userids(map { $_->[0] } @rows);
    my @ret = ();
    foreach my $row (@rows) {
        my $u = $us->{$row->[0]};

        # someone already renamed to this?
        next if $u->{user} =~ /^ex_/;

        # push all users except for identity users
        push @ret, [ $u => $row->[1] ] unless $u->is_identity;
    }

    return @ret;
}

sub random_by_letter {
    my $class = shift;
    my %opts  = @_;

    my $letter   = substr(delete $opts{letter}, 0, 1) || '0';
    my $prev_max = delete $opts{prev_max} || 0;
    my $limit    = delete $opts{limit} || 100;

    croak "invalid arguments: " . join(",", keys %opts) 
        if %opts;

    my $dbr = LJ::get_db_reader()
        or die "unable to contact global reader";

    my $min = $prev_max + 0;

    my $sth = $dbr->prepare
        ("SELECT userid, expunge_time FROM expunged_users " . 
         "WHERE (user LIKE ? OR user LIKE ?) AND expunge_time>? " . 
         "LIMIT $limit");
    $sth->execute(uc($letter) . '%', lc($letter) . '%', $min);
    die $dbr->errstr if $dbr->err;

    my @rows = ();
    while (my ($uid, $exp_time) = $sth->fetchrow_array) {
        push @rows, [ $uid => $exp_time ];
    }

    # if we got less than the limit, then we hit the beginning
    if (@rows < $limit) {
        my $new_limit = $limit - @rows;
        $sth = $dbr->prepare
            ("SELECT userid, expunge_time FROM expunged_users " . 
             "WHERE (user LIKE ? OR user LIKE ?) AND expunge_time>? " . 
             "LIMIT $new_limit");
        $sth->execute(uc($letter) . '%', lc($letter). '%', 0);
        die $dbr->errstr if $dbr->err;
        
        while (my ($uid, $exp_time) = $sth->fetchrow_array) {
            push @rows, [ $uid => $exp_time ];
        }
    }

    my $us = LJ::load_userids(map { $_->[0] } @rows);
    my @ret = ();
    foreach my $row (@rows) {
        my $u = $us->{$row->[0]};

        # someone already renamed to this?
        next if $u->{user} =~ /^ex_/;

        # push all users except for identity users
        push @ret, [ $u => $row->[1] ] unless $u->is_identity;
    }

    return @ret;
}

1;
