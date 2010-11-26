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
use LJ::Constants;

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
    return 0 unless $kw =~ /\S/;
    $kw = LJ::text_trim( $kw, LJ::BMAX_SITEKEYWORD, LJ::CMAX_SITEKEYWORD );
    $kw = LJ::utf8_lc( $kw ) unless $opts{allowmixedcase};

    # get the keyword and insert it if necessary
    my $dbr = LJ::get_db_reader();
    my $kwid = $dbr->selectrow_array( "SELECT kwid FROM sitekeywords WHERE keyword=?", undef, $kw ) + 0;
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
            $kwid = $dbh->selectrow_array( "SELECT kwid FROM sitekeywords WHERE keyword=?", undef, $kw ) + 0;
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
    my $u = shift;

    my $dbh = LJ::get_db_writer();

    if ($u->is_community) {
        $dbh->do("INSERT IGNORE INTO comminterests SELECT * FROM userinterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM userinterests WHERE userid=?", undef, $u->id);
    } else {
        $dbh->do("INSERT IGNORE INTO userinterests SELECT * FROM comminterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM comminterests WHERE userid=?", undef, $u->id);
    }

    LJ::memcache_kill($u, "intids");
    return 1;
}


# des: Change a user's interests.
# des-old: hashref of old interests (hashing being interest => intid)
# des-new: listref of new interests
# returns: 1 on success, undef on failure
sub set_interests {
    my ($u, $old, $new) = @_;

    $u = LJ::want_user($u);
    my $userid = $u->userid;
    return undef unless $userid;

    return undef unless ref $old eq 'HASH';
    return undef unless ref $new eq 'ARRAY';

    my $dbh = LJ::get_db_writer();
    my %int_new = ();
    my %int_del = %$old;  # assume deleting everything, unless in @$new

    # community interests go in a different table than user interests,
    # though the schemas are the same so we can run the same queries on them
    my $uitable = $u->is_community ? 'comminterests' : 'userinterests';

    # track if we made changes to refresh memcache later.
    my $did_mod = 0;

    my @valid_ints = LJ::validate_interest_list(@$new);
    foreach my $int ( @valid_ints ) {
        $int_new{$int} = 1 unless $old->{$int};
        delete $int_del{$int};
    }

    ### were interests removed?
    if ( %int_del ) {
        ## easy, we know their IDs, so delete them en masse
        my $intid_in = join(", ", values %int_del);
        $dbh->do("DELETE FROM $uitable WHERE userid=$userid AND intid IN ($intid_in)");
        $dbh->do("UPDATE interests SET intcount=intcount-1 WHERE intid IN ($intid_in)");
        $did_mod = 1;
    }

    ### do we have new interests to add?
    my @new_intids = ();  ## existing IDs we'll add for this user
    if ( %int_new ) {
        $did_mod = 1;

        my $int_in = join(", ", map { $dbh->quote($_); } keys %int_new);

        ## find existing IDs
        my $sth = $dbh->prepare( "SELECT keyword, kwid FROM sitekeywords " .
                                 "WHERE keyword IN ($int_in)" );
        $sth->execute;
        while (my ($intr, $intid) = $sth->fetchrow_array) {
            push @new_intids, $intid;       # - we'll add this later.
            delete $int_new{$intr};         # - so we don't have to make a new intid for
                                            #   this next pass.
        }

        ## do updating en masse for interests that already exist
        if ( @new_intids ) {
            my $sql = "REPLACE INTO $uitable (userid, intid) VALUES ";
            $sql .= join( ", ", map { "($userid, $_)" } @new_intids );
            $dbh->do( $sql );

            my $intid_in = join(", ", @new_intids);
            $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid IN ($intid_in)");
        }
    }

    ### do we STILL have interests to add?  (must make new intids)
    if ( %int_new ) {
        foreach my $int ( keys %int_new ) {
            my $intid = LJ::get_sitekeyword_id( $int );
            next unless $intid;

            my $rows = $dbh->do( "UPDATE interests SET intcount=intcount+1 WHERE intid=?",
                                 undef, $intid );
            if ( $rows eq "0E0") {
                # newly created
                $dbh->do( "INSERT INTO interests (intid, intcount) VALUES (?,?)",
                          undef, $intid, 1 );
            }
            next if $dbh->err;
            ## now we can actually insert it into the userinterests table:
            $dbh->do( "INSERT INTO $uitable (userid, intid) VALUES (?,?)",
                      undef, $userid, $intid );
            push @new_intids, $intid;
        }
    }
    LJ::Hooks::run_hooks("set_interests", $u, \%int_del, \@new_intids); # interest => intid

    # do migrations to clean up userinterests vs comminterests conflicts
    $u->lazy_interests_cleanup;

    LJ::memcache_kill($u, "intids") if $did_mod;
    $u->{_cache_interests} = undef if $did_mod;

    return 1;
}


1;
