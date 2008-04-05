package LJ::M::FriendsOf;
use strict;
use Carp qw(croak);

sub new {
    my ($pkg, $u, %args) = @_;
    my $self = bless {
        u => $u,
        fo_ids => undef,  # if loaded, arrayref of userids that friend this user.
        friends => {},    # hashref of userid => 1, for users that $u friends.
        mutual_friendids => undef, # once loaded, arrayref of mutual friendids
    }, $pkg;

    # whether or not we can be sloppy with results on things that would
    # otherwise be unbounded.  see also:  load_cap.
    $self->{sloppy}   = delete $args{sloppy};
    # don't load more than 5,000 LJ::User objects when
    # returning sloppy lists.
    $self->{load_cap} = delete $args{load_cap} || 5000;

    # should we exclude mutual friends from 'friend_ofs'?
    $self->{mutualsep} = delete $args{mutuals_separate};

    # TODO: lame that we have to pass this in, but currently
    # it's not cached on the $u singleton.  in future, remove this.
    # it's a hashref of { $userid => 1 }, for user's friends
    $self->{friends}  = delete $args{friends};

    # let them provide a callback to remove userids from lists.
    $self->{hide_test} = delete $args{hide_test_cb} || sub { 0 };

    croak "unknown params" if %args;
    return $self;
}

# returns scalar number of readers watching this (used mostly/only for syndicated feeds)
sub reader_count {
    my $self = shift;
    return scalar @{ $self->_friendof_ids };
}

# in scalar context, number of mutual friends.
# in list context, LJ::User objects (sorted by display name)
sub mutual_friends {
    my $fom = shift;
    if (wantarray) {
        return @{ $fom->_mutual_friends };
    }
    return scalar @{ $fom->_mutual_friends };
}

# returns just inbound people/identity users (removing mutuals if specified)
# in scalar context, number of friend-ofs
# in list context, LJ::User objects
sub friend_ofs {
    my $fom = shift;
    if (wantarray) {
        return @{ $fom->_friend_ofs };
    }

    # scalar context
    my $ct = scalar @{ $fom->_friend_ofs };
    if ($fom->{sloppy_friendofs}) {
        # we got sloppy results, so scalar $ct above isn't good.
        # skip all filtering and just set their friend-of count to
        # total edges in, less their mutual friend count if necessary
        # (which generally includes all communities they're a member of,
        # as people watch those)
        $ct = scalar @{ $fom->_friendof_ids };
        if ($fom->{mutualsep}) {
            $ct -= scalar @{ $fom->_mutual_friendids };
        } else {
            # TODO: load their outbound friends.  find communities.  remove those
            # incoming counts.  that should account for almost all incoming
            # community edges because most people watch communities they're
            # a member of.  with this, we just err on the side of too high a
            # friend-of count when we're 5000+ friend-ofs
        }

    }
    return $ct;

}

# in scalar context, number of community memberships
# in list context, LJ::User objects
sub member_of {
    my $fom = shift;
    if (wantarray) {
        return @{ $fom->_member_of };
    }
    return scalar @{ $fom->_member_of };
}


# --------------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------------

# return arrayref of userids with friendof edges to this user.
sub _friendof_ids {
    my $fom = shift;
    return $fom->{fo_ids} ||= [ $fom->{u}->friendof_uids ];
}

# returns arrayref of LJ::User mutual friends, filter (visible people), and sorted by display name
sub _mutual_friends {
    my $fom = shift;
    return $fom->{mutual_friends} if $fom->{mutual_friends};

    # because friends outbound are capped, so then is this load_userids call
    my @ids = grep { ! $fom->{hide_test}->($_) } @{ $fom->_mutual_friendids };
    my $us = LJ::load_userids(@ids);
    return $fom->{mutual_friends} = [
                                     sort { $a->display_name cmp $b->display_name }
                                     grep { $_->{statusvis} =~ /[VML]/ &&
                                           ($_->{journaltype} eq "P" || $_->{journaltype} eq "I") }
                                     map  { $us->{$_} ? ($us->{$_}) : () }
                                     @ids
                                     ];
}

# returns arrayref of mutual friendids.  sorted by username
sub _mutual_friendids {
    my $fom = shift;
    return $fom->{mutual_friendids} if $fom->{mutual_friendids};
    my @mut;
    foreach my $uid (@{ $fom->_friendof_ids }) {
        push @mut, $uid if $fom->{friends}{$uid};
    }
    @mut = sort { $a <=> $b } @mut;
    return $fom->{mutual_friendids} = \@mut;
}

# returns arrayref of inbound people/identity LJ::User objects, not communities.  which means we gotta
# load them to filter, if it's not too much work.  returns in sorted order.
sub _friend_ofs {
    my $fom = shift;
    return $fom->{_friendof_us} if $fom->{_friendof_us};

    # two options to filter them: a) it's less than load_cap, so we
    # load all users and just look.  b) it's too many, so we load at
    # least the mutual friends + whatever's left in the load cap space
    my @to_load;
    my @uids = grep { ! $fom->{hide_test}->($_) } @{ $fom->_friendof_ids };

    # remove mutuals now, if mutual separation has been required
    if ($fom->{mutualsep}) {
        @uids = grep { ! $fom->{friends}{$_} } @uids;
    }

    if (@uids <= $fom->{load_cap} || !$fom->{sloppy}) {
        @to_load = @uids;
    } else {
        # too big.  we have to only load some.  result will be limited.
        # we'll always include mutual friends in our inbound load, unless we're
        # separating them out anyway, in which case it's not important to make
        # sure they're not forgotten, as they'll be included in the other list.
        my %is_mutual;
        unless ($fom->{mutualsep}) {
            @to_load = @{ $fom->_mutual_friendids };
            $is_mutual{$_} = 1 foreach @to_load;
        }

        my $remain = $fom->{load_cap} - @to_load;
        while ($remain > 0 && @uids) {
            my $uid = shift @uids;
            next if $is_mutual{$uid};  # already in mutual list
            push @to_load, $uid;
            $remain--;
        }
        $fom->{sloppy_friendofs} = 1;
    }

    my $us = LJ::load_userids(@to_load);
    return $fom->{_friendof_us} = [
                                    sort {
                                        $a->display_name cmp $b->display_name
                                    }
                                    grep {
                                        $_->{statusvis} =~ /[VML]/ &&
                                            ($_->{journaltype} eq "P" ||
                                             $_->{journaltype} eq "I")
                                        }
                                    map {
                                        $us->{$_} ? ($us->{$_}) : ()
                                        }
                                    @to_load
                                    ];

}

# return arrayref of LJ::User objects for community/shared memberships, sorted.
sub _member_of {
    my $fom = shift;
    return $fom->{_member_of_us} if $fom->{_member_of_us};

    # need to check all inbound edges to see if they're communities.
    my @to_load = grep { ! $fom->{hide_test}->($_) } @{ $fom->_friendof_ids };

    # but if there's too many, we'll assume you also read communities that
    # you're a member of, so we'll find them all in your mutual friendids.
    if (@to_load > $fom->{load_cap} && $fom->{sloppy}) {
        @to_load = @{ $fom->_mutual_friendids };
    }

    my $us = LJ::load_userids(@to_load);
    return $fom->{_member_of_us} = [
                                    sort {
                                        $a->display_name cmp $b->display_name
                                    }
                                    grep {
                                        $_->{statusvis} eq 'V' &&
                                            ($_->{journaltype} eq "C" ||
                                             $_->{journaltype} eq "S")
                                        }
                                    map {
                                        $us->{$_} ? ($us->{$_}) : ()
                                        }
                                    @to_load
                                    ];

}

1;
