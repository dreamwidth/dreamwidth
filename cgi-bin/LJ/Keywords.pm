# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use LJ::Global::Constants;

package LJ;


# this function takes an intid and returns the associated keyword/intcount.
sub get_interest {
    my $intid = $_[0];
    return undef unless $intid && $intid =~ /^\d+$/;
    my ( $int, $intcount );

    my $memkey = [$intid, "introw:$intid"];
    my $cached = LJ::MemCache::get( $memkey );
    # memcache row is of form [$intid, $int, $intcount];

    if ( $cached && ref $cached eq 'ARRAY' ) {
        ( $intid, $int, $intcount ) = @$cached;
    } else {
        my $dbr = LJ::get_db_reader();
        ( $int ) =
            $dbr->selectrow_array( "SELECT keyword FROM sitekeywords WHERE kwid=?",
                                          undef, $intid );
        die $dbr->errstr if $dbr->err;
        ( $intcount ) =
            $dbr->selectrow_array( "SELECT intcount FROM interests WHERE intid=?",
                                   undef, $intid );
        die $dbr->errstr if $dbr->err;
        LJ::MemCache::set( $memkey, [$intid, $int, $intcount], 3600*12 );
    }

    return wantarray() ? ($int, $intcount) : $int;
}


# name: LJ::get_sitekeyword_id
# des: Get the id for a global keyword.
# args: keyword, autovivify?
# des-keyword: A string keyword to get the id of.
# returns: Returns a kwid into [dbtable[sitekeywords]].
#          If the keyword doesn't exist, it is automatically created for you.
# des-autovivify: If present and 1, automatically create keyword.
#                 If present and 0, do not automatically create the keyword.
#                 If not present, default behavior is the old
#                 style -- yes, do automatically create the keyword.
#
sub get_sitekeyword_id {
    my ( $kw, $autovivify, %opts ) = @_;
    $autovivify = 1 unless defined $autovivify;

    # setup the keyword for use
    return 0 unless defined $kw && $kw =~ /\S/;
    $kw = LJ::text_trim( $kw, LJ::BMAX_SITEKEYWORD, LJ::CMAX_SITEKEYWORD );
    $kw = LJ::utf8_lc( $kw ) unless $opts{allowmixedcase};

    # get the keyword and insert it if necessary
    my $dbr = LJ::get_db_reader();
    my $kwid = $dbr->selectrow_array( "SELECT kwid FROM sitekeywords WHERE keyword=?", undef, $kw );
    $kwid = defined $kwid ? $kwid + 0 : 0;
    if ( $autovivify && ! $kwid ) {
        # create a new keyword
        $kwid = LJ::alloc_global_counter( 'K' );
        return undef unless $kwid;

        # attempt to insert the keyword
        my $dbh = LJ::get_db_writer();
        my $rv = $dbh->do( "INSERT IGNORE INTO sitekeywords (kwid, keyword) VALUES (?, ?)", undef, $kwid, $kw );
        return undef if $dbh->err;

        # at this point, if $rv is 0, the keyword is already there so try again
        unless ( $rv ) {
            $kwid = $dbh->selectrow_array( "SELECT kwid FROM sitekeywords WHERE keyword=?", undef, $kw );
            $kwid = defined $kwid ? $kwid + 0 : 0;
            return undef if $dbh->err;
        }
    }
    return $kwid;
}


sub interest_string_to_list {
    my $intstr = $_[0];
    return unless defined $intstr;

    $intstr =~ s/^\s+//;  # strip leading space
    $intstr =~ s/\s+$//;  # strip trailing space
    $intstr =~ s/\n/,/g;  # newlines become commas
    $intstr =~ s/\s+/ /g; # strip duplicate spaces from the interest

    # final list is ,-sep
    return grep { length } split (/\s*,\s*/, $intstr);
}


# This function takes a list of intids and returns the list of uids
# for accounts interested in ALL of the given interests.
#
# Args: arrayref of intids, hashref of opts
# Returns: array of uids
#
# Valid opts: nousers => 1, nocomms => 1
#
sub users_with_all_ints {
    my ( $ints, $opts ) = @_;
    $opts ||= {};
    return unless defined $ints && ref $ints eq 'ARRAY';

    my @intids = grep /^\d+$/, @$ints;  # numeric only
    return unless @intids;

    my @tables;
    push @tables, 'userinterests' unless $opts->{nousers};
    push @tables, 'comminterests' unless $opts->{nocomms};
    return unless @tables;

    # allow restricting to user's circle
    my $cids;
    if ( $opts->{circle} && ( my $u = LJ::get_remote() ) ) {
        my @circle = ( $u->circle_userids, $u->member_of_userids, $u->id );
        $cids = join ',', @circle;
    }

    my $dbr = LJ::get_db_reader();
    my $qs = join ',', map { '?' } @intids;
    my @uids;

    foreach ( @tables ) {
        my $q = "SELECT userid FROM $_ WHERE intid IN ($qs)";
        $q .= " AND userid IN ($cids)" if $cids;
        my $uref = $dbr->selectall_arrayref( $q, undef, @intids );
        die $dbr->errstr if $dbr->err;

        # Count the number of times the uid appears.
        # If it's the same as the number of interests, it has all of them.
        my %ucount;
        $ucount{ $_->[0] }++ foreach @$uref;
        push @uids, grep { $ucount{$_} == scalar @intids } keys %ucount;
    }

    return @uids;
}


sub validate_interest_list {
    my $interrors = ref $_[0] eq "ARRAY" ? shift : [];
    my @ints = @_;

    my @valid_ints = ();
    foreach my $int (@ints) {
        $int = lc($int);       # FIXME: use utf8?
        $int =~ s/^i like //;  # *sigh*
        next unless $int;

        # Specific interest failures
        my ($bytes,$chars) = LJ::text_length($int);

        my $error_string = '';
        if ($int =~ /[\<\>]/) {
            $int = LJ::ehtml($int);
            $error_string .= '.invalid';
        } else {
            $error_string .= '.bytes' if $bytes > LJ::BMAX_SITEKEYWORD;
            $error_string .= '.chars' if $chars > LJ::CMAX_SITEKEYWORD;
        }

        if ($error_string) {
            $error_string = "error.interest$error_string";
            push @$interrors, [ $error_string,
                                { int => $int,
                                  bytes => $bytes,
                                  bytes_max => LJ::BMAX_SITEKEYWORD,
                                  chars => $chars,
                                  chars_max => LJ::CMAX_SITEKEYWORD
                                }
                              ];
            next;
        }
        push @valid_ints, $int;
    }
    return @valid_ints;
}


# end package LJ functions; begin user object methods.

package LJ::User;

# $opts is optional, with keys:
#    forceids => 1   : don't use memcache for loading the intids
#    forceints => 1   : don't use memcache for loading the interest rows
#    justids => 1 : return arrayref of intids only, not names/counts
# returns otherwise an arrayref of interest rows, sorted by interest name
#
sub get_interests {
    my ( $u, $opts ) = @_;
    $opts ||= {};
    return undef unless LJ::isu( $u );

    # first check request cache inside $u
    if ( my $ints = $u->{_cache_interests} ) {
        return [ map { $_->[0] } @$ints ] if $opts->{justids};
        return $ints;
    }

    my $uid = $u->userid;
    my $uitable = $u->is_community ? 'comminterests' : 'userinterests';

    # load the ids
    my $mk_ids = [$uid, "intids:$uid"];
    my $ids;
    $ids = LJ::MemCache::get($mk_ids) unless $opts->{forceids};
    unless ( $ids && ref $ids eq "ARRAY" ) {
        $ids = [];
        my $dbh = LJ::get_db_writer();
        my $sth = $dbh->prepare( "SELECT intid FROM $uitable WHERE userid=?" );
        $sth->execute( $uid );
        push @$ids, $_ while ($_) = $sth->fetchrow_array;
        LJ::MemCache::add( $mk_ids, $ids, 3600*12 );
    }

    # FIXME: set a 'justids' $u cache key in this case, then only return that
    #        later if 'justids' is requested?  probably not worth it.
    return $ids if $opts->{justids};

    # load interest rows
    my %need;
    $need{$_} = 1 foreach @$ids;
    my @ret;

    unless ( $opts->{forceints} ) {
        if ( my $mc = LJ::MemCache::get_multi( map { [$_, "introw:$_"] } @$ids ) ) {
            while ( my ($k, $v) = each %$mc ) {
                next unless $k =~ /^introw:(\d+)/;
                delete $need{$1};
                push @ret, $v;
            }
        }
    }

    if ( %need ) {
        my $ids = join( ",", map { $_ + 0 } keys %need );
        my $dbr = LJ::get_db_reader();
        my $ints = $dbr->selectall_hashref( "SELECT kwid, keyword FROM sitekeywords ".
                                            "WHERE kwid IN ($ids)", 'kwid' );
        my $counts = $dbr->selectall_hashref( "SELECT intid, intcount FROM interests ".
                                              "WHERE intid IN ($ids)", 'intid' );
        my $memc_store = 0;
        foreach my $intid ( keys %$ints ) {
            my $int = $ints->{$intid}->{keyword};
            my $count = $counts->{$intid}->{intcount} + 0;
            my $aref = [$intid, $int, $count];
            # minimize latency... only store 25 into memcache at a time
            # (too bad we don't have set_multi.... hmmmm)
            if ( $memc_store++ < 25 ) {
                # if the count is fairly high, keep item in memcache longer,
                # since count's not so important.
                my $expire = $count < 10 ? 3600*12 : 3600*48;
                LJ::MemCache::add( [$intid, "introw:$intid"], $aref, $expire );
            }
            push @ret, $aref;
        }
    }

    @ret = sort { $a->[1] cmp $b->[1] } @ret;
    return $u->{_cache_interests} = \@ret;
}


sub interest_count {
    my $u = shift;
    return undef unless LJ::isu( $u );

    # FIXME: fall back to SELECT COUNT(*) if not cached already?
    return scalar @{ $u->get_interests( { justids => 1 } ) };
}


sub interest_list {
    my $u = shift;
    return undef unless LJ::isu( $u );

    return map { $_->[1] } @{ $u->get_interests() };
}


sub interest_update {
    my ( $u, %opts ) = @_;
    return undef unless LJ::isu( $u );
    my ( $add, $del ) = ( $opts{add}, $opts{del} );
    return 1 unless $add || $del;  # nothing to do

    my $lock;
    unless ( $opts{has_lock} ) {
        while ( 1 ) {
            $lock = LJ::locker()->trylock( 'interests:' . $u->userid );
            last if $lock;

            # pause for 0.0-0.3 seconds to shuffle things up.  generally good behavior
            # when you're contending for locks.
            select undef, undef, undef, rand() * 0.3;
        }
    }

    my %wanted_add = map { $_ => 1 } @$add;
    my %wanted_del = map { $_ => 1 } @$del;

    my %cur_ids = map { $_ => 1 } @{ $u->get_interests( { justids => 1, forceids => 1 } ) };

    # track if we made changes to refresh memcache later.
    my $did_mod = 0;

    # community interests go in a different table than user interests,
    # though the schemas are the same so we can run the same queries on them
    my $uitable = $u->is_community ? 'comminterests' : 'userinterests';
    my $uid = $u->userid;
    my $dbh = LJ::get_db_writer() or die LJ::Lang::ml( "error.nodb" );

    my @filtered_del = grep { delete $cur_ids{$_} && ! $wanted_add{$_} } @$del;
    if ( $del && @filtered_del ) {
        $did_mod = 1;
        my $intid_in = join ',', map { $dbh->quote( $_ ) } @filtered_del;

        $dbh->do( "DELETE FROM $uitable WHERE userid=$uid AND intid IN ($intid_in)" );
        die $dbh->errstr if $dbh->err;
        $dbh->do( "UPDATE interests SET intcount=intcount-1 WHERE intid IN ($intid_in)" );
        die $dbh->errstr if $dbh->err;
    }

    my @filtered_add = grep { ! $cur_ids{$_}++ && ! $wanted_del{$_} } @$add;
    if ( $add && @filtered_add ) {
        # assume we've already checked maxinterests
        $did_mod = 1;
        my $intid_in = join ',', map { $dbh->quote( $_ ) } @filtered_add;
        my $sqlp = join ',', map { "(?,?)" } @filtered_add;
        $dbh->do( "REPLACE INTO $uitable (userid, intid) VALUES $sqlp",
                  undef, map { ( $uid, $_ ) } @filtered_add );
        die $dbh->errstr if $dbh->err;
        # set a zero intcount for any new ints
        $dbh->do( "INSERT IGNORE INTO interests (intid, intcount) VALUES $sqlp",
                  undef, map { ( $_, 0 ) } @filtered_add );
        die $dbh->errstr if $dbh->err;
        # now do the increment for all ints
        $dbh->do( "UPDATE interests SET intcount=intcount+1 WHERE intid IN ($intid_in)" );
        die $dbh->errstr if $dbh->err;
    }

    # do migrations to clean up userinterests vs comminterests conflicts
    # also clears memcache and object cache for intids if needed
    $u->lazy_interests_cleanup( $did_mod );

    return 1;
}


# return hashref with intname => intid
sub interests {
    my ( $u, $opts ) = @_;
    return undef unless LJ::isu( $u );
    delete $opts->{justids} if $opts && ref $opts;
    my $uints = $u->get_interests( $opts );
    my %interests;

    foreach my $int (@$uints) {
        $interests{$int->[1]} = $int->[0];  # $interests{name} = intid
    }

    return \%interests;
}


sub lazy_interests_cleanup {
    my ( $u, $expire ) = @_;

    my $dbh = LJ::get_db_writer();

    if ($u->is_community) {
        $dbh->do("INSERT IGNORE INTO comminterests SELECT * FROM userinterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM userinterests WHERE userid=?", undef, $u->id);
    } else {
        $dbh->do("INSERT IGNORE INTO userinterests SELECT * FROM comminterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM comminterests WHERE userid=?", undef, $u->id);
    }

    # don't expire memcache unless requested
    return 1 unless $expire;

    LJ::memcache_kill( $u, "intids" );
    $u->{_cache_interests} = undef;

    return 1;
}


# des: Change a user's interests.
# des-new: listref of new interests
# returns: 1 on success, undef on failure
sub set_interests {
    my ($u, $new) = @_;

    $u = LJ::want_user( $u ) or return undef;

    return undef unless ref $new eq 'ARRAY';

    my $lock;
    while ( 1 ) {
        $lock = LJ::locker()->trylock( 'interests:' . $u->userid );
        last if $lock;

        # pause for 0.0-0.3 seconds to shuffle things up.  generally good behavior
        # when you're contending for locks.
        select undef, undef, undef, rand() * 0.3;
    }

    my $old = $u->interests( { forceids => 1 } );
    my %int_add = ();
    my %int_del = %$old;  # assume deleting everything, unless in @$new

    my @valid_ints = LJ::validate_interest_list( @$new );
    foreach my $int ( @valid_ints ) {
        $int_add{$int} = 1 unless $old->{$int};
        delete $int_del{$int};
    }

    ### do we have new interests to add?
    my @new_intids = ();  ## existing IDs we'll add for this user
    foreach my $int ( keys %int_add ) {
        my $intid = LJ::get_sitekeyword_id( $int );
        push @new_intids, $intid if $intid;
    }

    # Note this does NOT check against maxinterests, do that in the caller.
    $u->interest_update( add => \@new_intids, del => [ values %int_del ], has_lock => 1 );

    LJ::Hooks::run_hooks("set_interests", $u, \%int_del, \@new_intids); # interest => intid

    return 1;
}


# arguments: hashref of submitted form and list of user's previous intids
# returns: hashref with number of ints added (or toomany) and deleted
sub sync_interests {
    my ( $u, $args, @intids ) = @_;
    warn "sync_interests: invalid arguments" and return undef
        unless LJ::isu( $u ) and ref $args eq "HASH";
    @intids = grep /^\d+$/, @intids;  # numeric

    my %uint = reverse %{ $u->interests };  # intid => interest
    my $rv = {};
    my ( @todel, @toadd );

    foreach my $intid ( @intids ) {
        next unless $intid > 0;    # prevent adding zero or negative intid
        push @todel, $intid if $uint{$intid} && ! $args->{"int_$intid"};
        push @toadd, $intid if ! $uint{$intid} && $args->{"int_$intid"};
    }

    my $addcount = scalar( @toadd );
    my $delcount = scalar( @todel );

    if ( $addcount ) {
        my $intcount = scalar( keys %uint ) + $addcount - $delcount;
        my $maxinterests = $u->count_max_interests;
        if ( $intcount > $maxinterests ) {
            # let the user know they're over the limit
            $rv->{toomany} = $maxinterests;
            @toadd = ();  # deletion still OK
        }
    }

    $u->interest_update( add => \@toadd, del => \@todel );
    $rv->{added} = $addcount;
    $rv->{deleted} = $delcount;

    return $rv;
}


1;
