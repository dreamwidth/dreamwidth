#!/usr/bin/perl
#
# DW::User::Edges::WatchTrust::Group
#
# This module implements helper functions to referring to a group of people
# trusted or watched by a given user.  Also assists with getting data about the
# reverse relationships - trusted by, watched by.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::User::Edges::WatchTrust::UserHelper;

use strict;
use Carp qw/ confess /;

sub new {
    my ( $pkg, $u, %args ) = @_;

    my $self = bless {
        u => $u,

        t_rev_userids => undef,    # if loaded, arrayref of userids that trust this user.
        t_userids     => {},       # hashref of userid => 1, for users that $u trusts.
        t_mut_userids => undef,    # once loaded, arrayref of mutually trusted userids

        w_rev_userids => undef,    # if loaded, arrayref of userids that watch this user.
        w_userids     => {},       # hashref of userid => 1, for users that $u watches.
        w_mut_userids => undef,    # once loaded, arrayref of mutually watched userids
    }, $pkg;

    # whether or not we can be sloppy with results on things that would
    # otherwise be unbounded.  see also:  load_cap.
    $self->{sloppy} = delete $args{sloppy};

    # don't load more than 5,000 LJ::User objects when
    # returning sloppy lists.
    $self->{load_cap} = delete $args{load_cap} || 5000;

    # should we exclude mutual watches from 'w_rev_userids'?
    $self->{mutualsep} = delete $args{mutuals_separate};

    # FIXME: sad that we have to pass this in, but currently
    # it's not cached on the $u singleton.  in future, remove this.
    # it's a hashref of { $userid => 1 }, for user's trusts
    $self->{t_userids} = delete $args{t_userids} || {};
    $self->{w_userids} = delete $args{w_userids} || {};

    # let them provide a callback to remove userids from lists.
    $self->{hide_watch_test} = delete $args{hide_watch_test_cb} || sub { 0 };

    confess 'unknown params' if %args;
    return $self;
}

# doesn't matter in trust groups!
sub reader_count {
    confess 'this function has no relevance to trust groups, please fix the caller';
}

# in scalar context, number of mutually watched users.
# in list context, LJ::User objects (sorted by display name)
sub mutually_watched_users {
    my $fom = $_[0];
    if (wantarray) {
        return @{ $fom->_mutually_watched_users };
    }
    return scalar @{ $fom->_mutually_watched_users };
}

# in scalar context, number of mutually trusted users.
# in list context, LJ::User objects (sorted by display name)
sub mutually_trusted_users {
    my $fom = $_[0];
    if (wantarray) {
        return @{ $fom->_mutually_trusted_users };
    }
    return scalar @{ $fom->_mutually_trusted_users };
}

# returns just inbound people/identity users (removing mutuals if specified)
# in scalar context, number of friend-ofs
# in list context, LJ::User objects
sub watched_by_users {
    my $fom = shift;
    if (wantarray) {
        return @{ $fom->_watched_by_users };
    }

    # scalar context
    my $ct = scalar @{ $fom->_watched_by_users };
    if ( $fom->{sloppy_load} ) {

        # we got sloppy results, so scalar $ct above isn't good.
        # skip all filtering and just set their friend-of count to
        # total edges in, less their mutual friend count if necessary
        # (which generally includes all communities they're a member of,
        # as people watch those)
        $ct = scalar @{ $fom->_watched_by_userids };
        if ( $fom->{mutualsep} ) {
            $ct -= scalar @{ $fom->_mutually_watched_userids };
        }

    }
    return $ct;
}

# in scalar context, returns count of people that trust you
# in list context, LJ::User objects
sub trusted_by_users {
    my $fom = shift;
    if (wantarray) {
        return @{ $fom->_trusted_by_users };
    }
    return scalar @{ $fom->_trusted_by_users };
}

# --------------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------------

# return arrayref of userids with friendof edges to this user.
sub _trusted_by_userids {
    my $fom = $_[0];
    return $fom->{t_rev_userids} ||= [ $fom->{u}->trusted_by_userids ];
}

# return arrayref of userids with friendof edges to this user.
sub _watched_by_userids {
    my $fom = $_[0];
    return $fom->{w_rev_userids} ||= [ $fom->{u}->watched_by_userids ];
}

# returns arrayref of LJ::User mutually trusted, filter (visible people), and sorted by display name
sub _mutually_trusted_users {
    my $fom = $_[0];
    return $fom->{t_mut_users} if $fom->{t_mut_users};

    # because outbound relationships are capped, so then is this load_userids call
    my @ids = @{ $fom->_mutually_trusted_userids };
    my $us  = LJ::load_userids(@ids);
    return $fom->{t_mut_users} = [
        sort { $a->display_name cmp $b->display_name }
        grep { $_->statusvis =~ /[VML]/ && $_->is_individual }
        map  { $us->{$_} ? ( $us->{$_} ) : () } @ids
    ];
}

# returns arrayref of LJ::User mutually watched, filter (visible people), and sorted by display name
sub _mutually_watched_users {
    my $fom = $_[0];
    return $fom->{w_mut_users} if $fom->{w_mut_users};

    # because outbound relationships are capped, so then is this load_userids call
    my @ids = grep { !$fom->{hide_watch_test}->($_) } @{ $fom->_mutually_watched_userids };
    my $us  = LJ::load_userids(@ids);
    return $fom->{w_mut_users} = [
        sort { $a->display_name cmp $b->display_name }
        grep { $_->statusvis =~ /[VML]/ && $_->is_individual }
        map  { $us->{$_} ? ( $us->{$_} ) : () } @ids
    ];
}

# returns arrayref of mutually trusted userids.  sorted by username
sub _mutually_trusted_userids {
    my $fom = $_[0];
    return $fom->{t_mut_userids} if $fom->{t_mut_userids};
    confess 'attempted to get mutually trusted users with no input'
        unless $fom->{t_userids};

    my @mut;
    foreach my $uid ( @{ $fom->_trusted_by_userids } ) {
        push @mut, $uid if $fom->{t_userids}{$uid};
    }
    @mut = sort { $a <=> $b } @mut;

    return $fom->{t_mut_userids} = \@mut;
}

# returns arrayref of mutually watched userids.  sorted by username
sub _mutually_watched_userids {
    my $fom = $_[0];
    return $fom->{w_mut_userids} if $fom->{w_mut_userids};
    confess 'attempted to get mutually watched users with no input'
        unless $fom->{w_userids};

    my @mut;
    foreach my $uid ( @{ $fom->_watched_by_userids } ) {
        push @mut, $uid if $fom->{w_userids}{$uid};
    }
    @mut = sort { $a <=> $b } @mut;

    return $fom->{w_mut_userids} = \@mut;
}

# returns arrayref of inbound people/identity LJ::User objects, not communities.  which means we gotta
# load them to filter, if it's not too much work.  returns in sorted order.
sub _trusted_by_users {
    my $fom = $_[0];
    return $fom->{_trusted_by_users} if $fom->{_trusted_by_usercs};

    # two options to filter them: a) it's less than load_cap, so we
    # load all users and just look.  b) it's too many, so we load at
    # least the mutual friends + whatever's left in the load cap space
    my @to_load;
    my @uids = grep { !$fom->{hide_watch_test}->($_) } @{ $fom->_trusted_by_userids };

    # remove mutuals now, if mutual separation has been required
    if ( $fom->{mutualsep} ) {
        @uids = grep { !$fom->{trusted_users}{$_} } @uids;
    }

    if ( @uids <= $fom->{load_cap} || !$fom->{sloppy} ) {
        @to_load = @uids;
    }
    else {
        # too big.  we have to only load some.  result will be limited.
        # we'll always include mutual friends in our inbound load, unless we're
        # separating them out anyway, in which case it's not important to make
        # sure they're not forgotten, as they'll be included in the other list.
        my %is_mutual;
        unless ( $fom->{mutualsep} ) {
            @to_load = @{ $fom->_mutually_trusted_userids };
            $is_mutual{$_} = 1 foreach @to_load;
        }

        my $remain = $fom->{load_cap} - @to_load;
        while ( $remain > 0 && @uids ) {
            my $uid = shift @uids;
            next if $is_mutual{$uid};    # already in mutual list
            push @to_load, $uid;
            $remain--;
        }
        $fom->{sloppy_load} = 1;
    }

    my $us = LJ::load_userids(@to_load);
    return $fom->{_trusted_by_users} = [
        sort { $a->display_name cmp $b->display_name }
        grep { $_->statusvis =~ /[VML]/ && $_->is_individual }
        map  { $us->{$_} ? ( $us->{$_} ) : () } @to_load
    ];

}

1;
