#!/usr/bin/perl
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

package LJ::Memories;
use strict;

# <LJFUNC>
# name: LJ::Memories::count
# class: web
# des: Returns the number of memories that a user has.
# args: uuobj
# des-uuobj: Userid or user object to count memories of.
# returns: Some number; undef on error.
# </LJFUNC>
sub count {
    my $u = shift;
    $u = LJ::want_user($u);
    return undef unless $u;

    # check memcache first
    my $count = LJ::MemCache::get( [ $u->{userid}, "memct:$u->{userid}" ] );
    return $count if $count;

    # now count
    my $dbcr = LJ::get_cluster_def_reader($u);
    $count = $dbcr->selectrow_array( 'SELECT COUNT(*) FROM memorable2 WHERE userid = ?',
        undef, $u->{userid} );
    return undef if $dbcr->err;

    $count += 0;

    # now put in memcache and return it
    my $expiration = $LJ::MEMCACHE_EXPIRATION{'memct'} || 43200;    # 12 hours
    LJ::MemCache::set( [ $u->{userid}, "memct:$u->{userid}" ], $count, $expiration );
    return $count;
}

# <LJFUNC>
# name: LJ::Memories::create
# class: web
# des: Create a new memory for a user.
# args: uuobj, opts, kwids?
# des-uuobj: User id or user object to insert memory for.
# des-opts: Hashref of options that define the memory; keys = journalid, ditemid, des, security.
# des-kwids: Optional; arrayref of keyword ids to categorize this memory under.
# returns: 1 on success, undef on error
# </LJFUNC>
sub create {
    my ( $u, $opts, $kwids ) = @_;
    $u = LJ::want_user($u);
    return undef unless $u && %{ $opts || {} };

    # make sure we got enough options
    my ( $userid, $journalid, $ditemid, $des, $security ) =
        ( $u->userid, map { $opts->{$_} } qw(journalid ditemid des security) );
    $userid    += 0;
    $journalid += 0;
    $ditemid   += 0;
    $security ||= 'public';
    $kwids    ||= [ $u->get_keyword_id('*') ];    # * means no category
    $des = LJ::trim($des);
    return undef unless $userid && $journalid && $ditemid && $des && $security && @$kwids;
    return undef unless $security =~ /^(?:public|friends|private)$/;

    # we have valid data, now let's insert it
    return undef unless $u->writer;

    # allocate memory id to use
    my $memid = LJ::alloc_user_counter( $u, 'R' );
    return undef unless $memid;

    # insert main memory
    $u->do(
        "INSERT INTO memorable2 (userid, memid, journalid, ditemid, des, security) "
            . "VALUES (?, ?, ?, ?, ?, ?)",
        undef, $userid, $memid, $journalid, $ditemid, $des, $security
    );
    return undef if $u->err;

    # insert keywords
    my $val = join ',', map { "($userid, $memid, $_)" } @$kwids;
    $u->do("REPLACE INTO memkeyword2 (userid, memid, kwid) VALUES $val");

    # Delete the appropriate memcache entries
    LJ::MemCache::delete( [ $userid, "memct:$userid" ] );
    my $filter        = $journalid == $userid ? 'own' : 'other';
    my $filter_char   = _map_filter_to_char($filter);
    my $security_char = _map_security_to_char($security);
    my $memcache_key  = "memkwcnt:$userid:$filter_char:$security_char";
    LJ::MemCache::delete( [ $userid, $memcache_key ] );

    return 1;
}

# <LJFUNC>
# name: LJ::Memories::delete_by_id
# class: web
# des: Deletes a bunch of memories by memid.
# args: uuobj, memids
# des-uuobj: User id or user object to delete memories of.
# des-memids: Arrayref of memids.
# returns: 1 on success; undef on error.
# </LJFUNC>
sub delete_by_id {
    my ( $u, $memids ) = @_;
    $u      = LJ::want_user($u);
    $memids = [$memids] if $memids && !ref $memids;    # so they can just pass a single thing...
    return undef unless $u && @{ $memids || [] };

    # delete actual memory
    my $in = join ',', map { $_ + 0 } @$memids;
    $u->do( "DELETE FROM memorable2 WHERE userid = ? AND memid IN ($in)", undef, $u->{userid} );
    return undef if $u->err;

    # delete keyword associations
    my $euser = "userid = $u->{userid} AND";
    $u->do("DELETE FROM memkeyword2 WHERE $euser memid IN ($in)");

    # delete cache of count and keyword counts
    clear_memcache($u);

    # success at this point, since the first delete succeeded
    return 1;
}

# <LJFUNC>
# name: LJ::Memories::get_keyword_counts
# class: web
# des: Get a list of keywords and the counts for memories, showing how many memories are under
#      each keyword.
# args: uuobj, opts?
# des-uuobj: User id or object of user.
# des-opts: Optional; hashref passed to _memory_getter, suggested keys are security and filter
#           if you want to get only certain memories in the keyword list.
# returns: Hashref { kwid => count }; undef on error
# </LJFUNC>
sub get_keyword_counts {
    my ( $u, $opts ) = @_;
    $u = LJ::want_user($u);
    return undef unless $u;
    my $userid = $u->{userid};

    my $filter_parm   = $opts->{filter};
    my @security_parm = $opts->{security} ? @{ $opts->{security} } : ();

    my ( $cache_counts, $missing_keys ) =
        _get_memcache_keyword_counts( $userid, $filter_parm, @security_parm );
    return $cache_counts unless @$missing_keys;

    # Get the user's memories based on filter and security
    $opts->{filter_security_pairs} = $missing_keys;
    $opts->{notext}                = 1;
    my $memories = LJ::Memories::_memory_getter( $u, $opts );
    return undef unless defined $memories;    # error case

    # Generate mapping of memid to filter (e.g. own) and security (e.g. private)
    my ( %mem_filter, @all_memids );
    foreach my $memid ( keys %$memories ) {
        push @all_memids, $memid;
        my $memory_filter   = $memories->{$memid}->{journalid} == $userid ? 'own' : 'other';
        my $memory_security = $memories->{$memid}->{security};
        $mem_filter{$memid} = [ $memory_filter, $memory_security ];
    }

    # now let's get the keywords these memories use
    my $mem_kw_rows;

    if (@all_memids) {
        my $in   = join ',', @all_memids;
        my $dbcr = LJ::get_cluster_reader($u);
        my $sql  = "SELECT kwid, memid FROM memkeyword2 WHERE userid = $userid AND memid IN ($in)";
        $mem_kw_rows = $dbcr->selectall_arrayref($sql);
        return undef if $dbcr->err;
    }

    # Filter and Sum
    my %counts;
    foreach my $row ( @{ $mem_kw_rows || [] } ) {
        my ( $kwid,   $memid )    = @$row;
        my ( $filter, $security ) = @{ $mem_filter{$memid} };
        $counts{$filter}{$security}{$kwid}++;
    }

    # Add these new counts to our memcache counts to get totals
    my $output_counts = $cache_counts;
    foreach my $filter ( keys %counts ) {
        foreach my $security ( keys %{ $counts{$filter} } ) {
            if ( $counts{$filter}{$security} ) {
                add_hash( $output_counts, $counts{$filter}{$security} );
            }
        }
    }

    # Create empty anonymous hashes for missing key combos
    foreach my $missing_key (@$missing_keys) {
        my ( $missing_filter, $missing_security ) = split /-/, $missing_key;
        next if exists $counts{$missing_filter}{$missing_security};
        $counts{$missing_filter}{$missing_security} = {};
    }

    # Store memcache entries with counts
    foreach my $filter (qw/own other/) {
        foreach my $security (qw/friends private public/) {
            next unless exists $counts{$filter}{$security};
            my $filter_char   = _map_filter_to_char($filter);
            my $security_char = _map_security_to_char($security);
            my $memcache_key  = "memkwcnt:$userid:$filter_char:$security_char";
            my $expiration    = $LJ::MEMCACHE_EXPIRATION{'memkwcnt'} || 86400;
            LJ::MemCache::set( [ $userid, $memcache_key ],
                $counts{$filter}{$security}, $expiration );
        }
    }

    return $output_counts;
}

#
# Name: _map_security_to_char
# API: Private to this module
# Description: Map a verbose security name to a single character
# Parameter: Verbose security name
# Return: Single character representation of security
#
sub _map_security_to_char {
    my $verbose_security = shift;
    my %security_map     = ( friends => 'f', private => 'v', public => 'u' );
    return $security_map{$verbose_security}
        || die "Can't map security '" . LJ::ehtml($verbose_security) . "' to character";
}

#
# Name: _map_filter_to_char
# API: Private to this module
# Description: Map a verbose filter name to a single character
# Parameter: Verbose filter name
# Return: Single character representation of filter
#
sub _map_filter_to_char {
    my $verbose_filter = shift;
    my %filter_map     = ( own => 'w', other => 't' );
    return $filter_map{$verbose_filter}
        || die "Can't map filter '" . LJ::ehtml($verbose_filter) . "' to character";
}

#
# Name: _get_memcache_keyword_counts
#
# API: Private to this module
#
# Description:
# - Get keyword counts from memcache based on user, filter, and security
# - Return hash of counts and array of missing keys
#
# Parameters:
# - $userid = ID of the User
# - $filter_parm = {own|other}
# - @security_parm = array of values {friends|private|public} - () = all
#
# Return Values:
# - HashRef of counts by Keyword ID
# - ArrayRef of missing keys (e.g. 'owner-private')
#
sub _get_memcache_keyword_counts {
    my ( $userid, $filter_parm, @security_parm ) = @_;

    # Build up the memcache keys that we're looking for
    my @memcache_keys;
    my %filter_security_map;
    foreach my $filter (qw/own other/) {
        foreach my $security (qw/friends private public/) {
            my $filter_matches = ( $filter_parm eq $filter ) || ( $filter_parm eq 'all' );
            my $security_matches = @security_parm == 0 || grep( /$security/, @security_parm );
            next unless $filter_matches && $security_matches;
            my $filter_char   = _map_filter_to_char($filter);
            my $security_char = _map_security_to_char($security);
            my $memcache_key  = "memkwcnt:$userid:$filter_char:$security_char";
            push @memcache_keys, $memcache_key;
            $filter_security_map{"$filter_char:$security_char"} = [ $filter, $security ];
        }
    }

    # Loop over our memcache results, get counts and total them as we go
    my ( %output_counts, @missing_keys );
    my $memcache_counts =
          LJ::is_enabled('memkwcnt_memcaching')
        ? LJ::MemCache::get_multi( map { [ $userid, $_ ] } @memcache_keys )
        : {};
    foreach my $memcache_key (@memcache_keys) {
        my $counts = $memcache_counts->{$memcache_key};
        if ($counts) {    # Add these memcache counts to totals
            add_hash( \%output_counts, $counts );
        }
        else {
            my ($filter_security_chars) = $memcache_key =~ /$userid:(.:.)$/;
            my ( $filter, $security ) = @{ $filter_security_map{$filter_security_chars} };
            push @missing_keys, $filter . '-' . $security;
        }
    }

    return \%output_counts, \@missing_keys;
}

# <LJFUNC>
# name: LJ::Memories::add_hash
# class: web
# des: Add values of one hash, to the corresponding entries in another.
# args: HashRef1, HashRef2
# returns: Values are added to the first parameter hash.
# </LJFUNC>
sub add_hash {
    my ( $hash1, $hash2 ) = @_;

    while ( my ( $key, $value ) = each %$hash2 ) {
        $hash1->{$key} += $value;
    }
}

# <LJFUNC>
# name: LJ::Memories::get_keywordids
# class: web
# des: Get all keyword ids a user has used for a certain memory.
# args: uuobj, memid
# des-uuobj: User id or user object to check memory of.
# des-memid: Memory id to get keyword ids for.
# returns: Arrayref of keywordids; undef on error.
# </LJFUNC>
sub get_keywordids {
    my ( $u, $memid ) = @_;
    $u = LJ::want_user($u);
    $memid += 0;
    return undef unless $u && $memid;

    # definitive reader/master because this function is usually called when
    # someone is on an edit page.
    my $dbcr = LJ::get_cluster_def_reader($u);
    my $kwids =
        $dbcr->selectcol_arrayref( 'SELECT kwid FROM memkeyword2 WHERE userid = ? AND memid = ?',
        undef, $u->userid, $memid );
    return undef if $dbcr->err;

    # all good, return
    return $kwids;
}

# <LJFUNC>
# name: LJ::Memories::update_memory
# class: web
# des: Updates the description and security of a memory.
# args: uuobj, memid, updopts
# des-uuobj: User id or user object to update memory of.
# des-memid: Memory id to update.
# des-updopts: Update options; hashref with keys 'des' and 'security', values being what
#              you want to update the memory to have.
# returns: 1 on success, undef on error
# </LJFUNC>
# sub update_memory {
#     my ($u, $memid, $upd) = @_;
#     $u = LJ::want_user($u);
#     $memid += 0;
#     return unless $u && $memid && %{$upd || {}};
#
#     # get database handle
#     my ($db, $table) = ($u, '2');
#     return undef unless $db;
#
#     # construct update lines... only valid things we can update are des and security
#     my @updates;
#     my $security_updated;
#     foreach my $what (keys %$upd) {
#         next unless $what =~ m/^(?:des|security)$/;
#         $security_updated = 1 if $what eq 'security';
#         push @updates, "$what=" . $db->quote($upd->{$what});
#     }
#     my $updstr = join ',', @updates;
#
#     # now perform update
#     $db->do("UPDATE memorable$table SET $updstr WHERE userid = ? AND memid = ?",
#             undef, $u->{userid}, $memid);
#     return undef if $db->err;
#
#     # Delete memcache entries if the security of the memory was updated
#     clear_memcache($u) if $security_updated;
#
#     return 1;
# }

# this messy function gets memories based on an options hashref.  this is an
# API API and isn't recommended for use by BML etc... add to the API and have
# API functions call this if needed.
#
# options in $opts hashref:
#   security => [ 'public', 'private', ... ], or some subset thereof
#   filter => 'all' | 'own' | 'other', filter -- defaults to all
#   filter_security_pairs => [ 'own-private', ... ], Pairs of filter/security
#   notext => 1/0, if on, do not load/return description field
#   byid => [ 1, 2, 3, ... ], load memories by *memid*
#   byditemid => [ 1, 2, 3 ... ], load by ditemid (MUST specify journalid too)
#   journalid => 1, find memories by ditemid (see above) for this journalid
#
# note that all memories are loaded from a single user, specified as the first
# parameter.  does not let you load memories from more than one user.
sub _memory_getter {
    my ( $u, $opts ) = @_;
    $u = LJ::want_user($u);
    $opts ||= {};
    return undef unless $u;

    # Specify filter/security by pair, or individually
    my $secwhere   = '';
    my $extrawhere = '';
    if ( $opts->{filter_security_pairs} ) {
        my @pairs;
        foreach my $filter_security_pair ( @{ $opts->{filter_security_pairs} } ) {
            my ( $filter, $security ) = $filter_security_pair =~ /^(\w+)-(\w+)$/;
            my $filter_predicate =
                ( $filter eq 'all' )
                ? ''
                : 'journalid' . ( $filter eq 'own' ? '=' : '<>' ) . $u->{userid};
            push @pairs, "($filter_predicate AND security='$security')";
        }
        $secwhere = 'AND (' . join( ' OR ', @pairs ) . ')';
    }
    else {
        if ( @{ $opts->{security} || [] } ) {
            my @secs;
            foreach my $sec ( @{ $opts->{security} } ) {
                push @secs, $sec
                    if $sec =~ /^(?:public|friends|private)$/;
            }
            $secwhere = "AND security IN (" . join( ',', map { "'$_'" } @secs ) . ")";
        }
        if    ( $opts->{filter} eq 'all' )   { $extrawhere = ''; }
        elsif ( $opts->{filter} eq 'own' )   { $extrawhere = "AND journalid = $u->{userid}"; }
        elsif ( $opts->{filter} eq 'other' ) { $extrawhere = "AND journalid <> $u->{userid}"; }
    }

    my $des      = $opts->{notext} ? '' : 'des, ';
    my $selwhere = '';
    if ( @{ $opts->{byid} || [] } ) {

        # they want to get some explicit memories by memid
        my $in = join ',', map { $_ + 0 } @{ $opts->{byid} };
        $selwhere = "AND memid IN ($in)";
    }
    elsif ( $opts->{byditemid} && $opts->{journalid} ) {

        # or, they want to see if a memory exists for a particular item
        my $selitemid = "ditemid";
        $opts->{byditemid} += 0;
        $opts->{journalid} += 0;
        $selwhere = "AND journalid = $opts->{journalid} AND $selitemid = $opts->{byditemid}";
    }
    elsif ( $opts->{byditemid} ) {

        # get memory, OLD STYLE so journalid is 0
        my $selitemid = "ditemid";
        $opts->{byditemid} += 0;
        $selwhere = "AND journalid = 0 AND $selitemid = $opts->{byditemid}";
    }

    # load up memories into hashref
    my ( %memories, $sth );
    my $dbcr = LJ::get_cluster_reader($u);
    my $sql  = "SELECT memid, userid, journalid, ditemid, $des security "
        . "FROM memorable2 WHERE userid = ? $selwhere $secwhere $extrawhere";
    $sth = $dbcr->prepare($sql);

    # general execution and fetching for return
    $sth->execute( $u->{userid} );
    return undef if $sth->err;
    while ( $_ = $sth->fetchrow_hashref() ) {

        # we have to do this ditemid->jitemid to make old code work,
        # but this can probably go away at some point...
        if ( defined $_->{ditemid} ) {
            $_->{jitemid} = $_->{ditemid};
        }
        else {
            $_->{ditemid} = $_->{jitemid};
        }
        $memories{ $_->{memid} } = $_;
    }

    my @jids = map { $_->{journalid} } values %memories;
    my $us   = LJ::load_userids(@jids);
    foreach my $mem ( values %memories ) {
        next unless $mem->{journalid};
        $mem->{user} = $us->{ $mem->{journalid} }->user;
    }

    return \%memories;
}

# <LJFUNC>
# name: LJ::Memories::get_by_id
# class: web
# des: Get memories given some memory ids.
# args: uuobj, memids
# des-uuobj: User id or user object to get memories for.
# des-memids: The rest of the memory ids.  Array.  (Pass them in as individual parameters...)
# returns: Hashref of memories with keys being memid; undef on error.
# </LJFUNC>
# sub get_by_id {
#     my $u = shift;
#     return {} unless @_; # make sure they gave us some ids
#
#     # pass to getter to get by id
#     return LJ::Memories::_memory_getter($u, { byid => [ map { $_+0 } @_ ] });
# }

# <LJFUNC>
# name: LJ::Memories::get_by_ditemid
# class: web
# des: Get memory for a given journal entry.
# args: uuobj, journalid, ditemid
# des-uuobj: User id or user object to get memories for.
# des-journalid: Userid for journal entry is in.
# des-ditemid: Display itemid of entry.
# returns: Hashref of individual memory.
# </LJFUNC>
sub get_by_ditemid {
    my ( $u, $jid, $ditemid ) = @_;
    $jid     += 0;
    $ditemid += 0;
    return undef unless $ditemid;    # _memory_getter checks $u and $jid isn't necessary
                                     # because this might be an old-style memory

    # pass to getter with appropriate options
    my $memhash = LJ::Memories::_memory_getter( $u, { byditemid => $ditemid, journalid => $jid } );
    return undef unless %{ $memhash || {} };
    return [ values %$memhash ]->[0];    # ugly
}

# <LJFUNC>
# name: LJ::Memories::get_by_user
# class: web
# des: Get memories given a user.
# args: uuobj
# des-uuobj: User id or user object to get memories for.
# returns: Hashref of memories with keys being memid; undef on error.
# </LJFUNC>
# sub get_by_user {
#     # simply passes through to _memory_getter
#     return LJ::Memories::_memory_getter(@_);
# }

# <LJFUNC>
# name: LJ::Memories::get_by_keyword
# class: web
# des: Get memories given a user and a keyword/keyword id.
# args: uuobj, kwoid, opts
# des-uuobj: User id or user object to get memories for.
# des-kwoid: Keyword (string) or keyword id (number) to get memories for.
# des-opts: Hashref of extra options to pass through to memory getter.  Suggested options
#           are filter and security for limiting the memories returned.
# returns: Hashref of memories with keys being memid; undef on error.
# </LJFUNC>
sub get_by_keyword {
    my ( $u, $kwoid, $opts ) = @_;
    $u = LJ::want_user($u);
    my $kwid = $kwoid + 0;
    my $kw   = defined $kwoid && !$kwid ? $kwoid : undef;
    return undef unless $u && ( $kwid || defined $kw );

    my $memids;
    my $dbcr = LJ::get_cluster_reader($u);
    return undef unless $dbcr;

    # get keyword id if we don't have it
    if ( defined $kw ) {
        $kwid = $dbcr->selectrow_array(
            'SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
            undef, $u->userid, $kw ) + 0;
    }
    return undef unless $kwid;

    # now get the actual memory ids
    $memids =
        $dbcr->selectcol_arrayref( 'SELECT memid FROM memkeyword2 WHERE userid = ? AND kwid = ?',
        undef, $u->{userid}, $kwid );
    return undef if $dbcr->err;

    # return
    $memids = [] unless defined($memids);
    my $memories =
        @$memids > 0
        ? LJ::Memories::_memory_getter( $u, { %{ $opts || {} }, byid => $memids } )
        : {};
    return $memories;
}

# <LJFUNC>
# name: LJ::Memories::get_keywords
# class:
# des: Retrieves keyword/keyids without big joins, returns a hashref.
# args: uobj
# des-uobj: User object to get keyword pairs for.
# returns: Hashref; { keywordid => keyword }
# </LJFUNC>
sub get_keywords {
    my $u = shift;
    $u = LJ::want_user($u);
    return undef unless $u;

    my $use_reader = 0;
    my $memkey     = [ $u->{userid}, "memkwid:$u->{userid}" ];
    my $ret        = LJ::MemCache::get($memkey);
    return $ret if defined $ret;
    $ret = {};

    my $dbcm = LJ::get_cluster_def_reader($u);
    unless ($dbcm) {
        $use_reader = 1;
        $dbcm       = LJ::get_cluster_reader($u);
    }
    my $ids = $dbcm->selectcol_arrayref( 'SELECT DISTINCT kwid FROM memkeyword2 WHERE userid = ?',
        undef, $u->userid );
    if ( @{ $ids || [] } ) {
        my $in   = join ",", @$ids;
        my $rows = $dbcm->selectall_arrayref(
            'SELECT kwid, keyword FROM userkeywords ' . "WHERE userid = ? AND kwid IN ($in)",
            undef, $u->userid );
        $ret->{ $_->[0] } = $_->[1] foreach @{ $rows || [] };
    }

    my $expiration = $LJ::MEMCACHE_EXPIRATION{'memkwid'} || 86400;
    LJ::MemCache::set( $memkey, $ret, $expiration ) unless $use_reader;
    return $ret;
}

# <LJFUNC>
# name: LJ::Memories::updated_keywords
# class: web
# des: Deletes memcached keyword data.
# args: uobj
# des-uobj: User object to clear memcached keywords for.
# returns: undef.
# </LJFUNC>
sub updated_keywords {
    return clear_memcache(shift);
}

# <LJFUNC>
# name: LJ::Memories::clear_memcache
# class: web
# des: Deletes memcached keyword data.
# args: uobj
# des-uobj: User object to clear memcached keywords for.
# returns: undef.
# </LJFUNC>
sub clear_memcache {
    my $u = shift;
    return unless ref $u;
    my $userid = $u->{userid};

    LJ::MemCache::delete( [ $userid, "memct:$userid" ] );

    LJ::MemCache::delete( [ $userid, "memkwid:$userid" ] );

    # Delete all memkwcnt entries
    LJ::MemCache::delete( [ $userid, "memkwcnt:$userid:w:f" ] );
    LJ::MemCache::delete( [ $userid, "memkwcnt:$userid:w:v" ] );
    LJ::MemCache::delete( [ $userid, "memkwcnt:$userid:w:u" ] );
    LJ::MemCache::delete( [ $userid, "memkwcnt:$userid:t:f" ] );
    LJ::MemCache::delete( [ $userid, "memkwcnt:$userid:t:v" ] );
    LJ::MemCache::delete( [ $userid, "memkwcnt:$userid:t:u" ] );

    return undef;
}

1;
