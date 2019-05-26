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

package LJ::User;
use strict;
no warnings 'uninitialized';

use Carp;

########################################################################
### 5. Database and Memcache Functions

=head2 Database and Memcache Functions
=cut

sub begin_work {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->begin_work;
    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub commit {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->commit;
    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

# $u->do("UPDATE foo SET key=?", undef, $val);
sub do {
    my $u     = shift;
    my $query = shift;

    my $uid = $u->userid + 0
        or croak "Database update called on null user object";

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    $query =~ s!^(\s*\w+\s+)!$1/* uid=$uid */ !;

    my $rv = $dbcm->do( $query, @_ );
    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    $u->{_mysql_insertid} = $dbcm->{'mysql_insertid'} if $dbcm->{'mysql_insertid'};

    return $rv;
}

sub dversion {
    my $u = shift;
    return $u->{dversion};
}

sub err {
    my $u = shift;
    return $u->{_dberr};
}

sub errstr {
    my $u = shift;
    return $u->{_dberrstr};
}

sub is_innodb {
    my $u     = shift;
    my $cluid = $u->clusterid;
    return $LJ::CACHE_CLUSTER_IS_INNO{$cluid}
        if defined $LJ::CACHE_CLUSTER_IS_INNO{$cluid};

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;
    my ( undef, $ctable ) = $dbcm->selectrow_array("SHOW CREATE TABLE log2");
    die "Failed to auto-discover database type for cluster \#$cluid: [$ctable]"
        unless $ctable =~ /^CREATE TABLE/;

    my $is_inno = ( $ctable =~ /=InnoDB/i ? 1 : 0 );
    return $LJ::CACHE_CLUSTER_IS_INNO{$cluid} = $is_inno;
}

# log2_do
# see comments for talk2_do
sub log2_do {
    my ( $u, $errref, $sql, @args ) = @_;
    return undef unless $u->writer;

    my $dbcm = $u->{_dbcm};

    my $memkey  = [ $u->userid, "log2lt:" . $u->userid ];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array( "SELECT GET_LOCK(?,10)", undef, $lockkey );
    my $ret = $u->do( $sql, undef, @args );
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array( "SELECT RELEASE_LOCK(?)", undef, $lockkey );

    LJ::MemCache::delete( $memkey, 0 ) if int($ret);
    return $ret;
}

# simple function for getting something from memcache; this assumes that the
# item being gotten follows the standard format [ $userid, "item:$userid" ]
sub memc_get {
    return LJ::MemCache::get( [ $_[0]->userid, "$_[1]:" . $_[0]->userid ] );
}

# sets a predictably named item. usage:
#   $u->memc_set( key => 'value', [ $timeout ] );
sub memc_set {
    return LJ::MemCache::set( [ $_[0]->userid, "$_[1]:" . $_[0]->userid ], $_[2], $_[3] || 1800 );
}

# deletes a predictably named item. usage:
#   $u->memc_delete( key );
sub memc_delete {
    return LJ::MemCache::delete( [ $_[0]->userid, "$_[1]:" . $_[0]->userid ] );
}

sub mysql_insertid {
    my $u = shift;
    if ( $u->isa("LJ::User") ) {
        return $u->{_mysql_insertid};
    }
    elsif ( LJ::DB::isdb($u) ) {
        my $db = $u;
        return $db->{'mysql_insertid'};
    }
    else {
        die "Unknown object '$u' being passed to LJ::User::mysql_insertid.";
    }
}

sub nodb_err {
    my $u = shift;
    return
          "Database handle unavailable [user: "
        . $u->user
        . "; cluster: "
        . $u->clusterid
        . ", errstr: $DBI::errstr]";
}

# get an $sth from the writer
sub prepare {
    my $u = shift;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->prepare(@_);
    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub quote {
    my ( $u, $text ) = @_;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    return $dbcm->quote($text);
}

# memcache key that holds the number of times a user performed one of the rate-limited actions
sub rate_memkey {
    my ( $u, $rp ) = @_;

    return [ $u->id, "rate:" . $u->id . ":$rp->{id}" ];
}

sub readonly {
    my $u = shift;
    return LJ::get_cap( $u, "readonly" );
}

sub rollback {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->rollback;
    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}

sub selectall_arrayref {
    my $u    = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectall_arrayref(@_);

    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}

sub selectall_hashref {
    my $u    = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectall_hashref(@_);

    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}

sub selectcol_arrayref {
    my $u    = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectcol_arrayref(@_);

    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}

sub selectrow_array {
    my $u    = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $set_err = sub {
        if ( $u->{_dberr} = $dbcm->err ) {
            $u->{_dberrstr} = $dbcm->errstr;
        }
    };

    if ( wantarray() ) {
        my @rv = $dbcm->selectrow_array(@_);
        $set_err->();
        return @rv;
    }

    my $rv = $dbcm->selectrow_array(@_);
    $set_err->();
    return $rv;
}

sub selectrow_hashref {
    my $u    = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectrow_hashref(@_);

    if ( $u->{_dberr} = $dbcm->err ) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}

# do some internal consistency checks on self.  die if problems,
# else returns 1.
sub selfassert {
    my $u = shift;
    LJ::assert_is( $u->userid, $u->{_orig_userid} )
        if $u->{_orig_userid};
    LJ::assert_is( $u->user, $u->{_orig_user} )
        if $u->{_orig_user};
    return 1;
}

# this is for debugging/special uses where you need to instruct
# a user object on what database handle to use.  returns the
# handle that you gave it.
sub set_dbcm {
    my $u = shift;
    return $u->{'_dbcm'} = shift;
}

# class method, returns { clusterid => [ uid, uid ], ... }
sub split_by_cluster {
    my $class = shift;

    my @uids = @_;
    my $us   = LJ::load_userids(@uids);

    my %clusters;
    foreach my $u ( values %$us ) {
        next unless $u;
        push @{ $clusters{ $u->clusterid } }, $u->id;
    }

    return \%clusters;
}

# all reads/writes to talk2 must be done inside a lock, so there's
# no race conditions between reading from db and putting in memcache.
# can't do a db write in between those 2 steps.  the talk2 -> memcache
# is elsewhere (LJ::Talk), but this $dbh->do wrapper is provided
# here because non-talklib things modify the talk2 table, and it's
# nice to centralize the locking rules.
#
# return value is return of $dbh->do.  $errref scalar ref is optional, and
# if set, gets value of $dbh->errstr
#
# write:  (LJ::talk2_do)
#   GET_LOCK
#    update/insert into talk2
#   RELEASE_LOCK
#    delete memcache
#
# read:   (LJ::Talk::get_talk_data)
#   try memcache
#   GET_LOCk
#     read db
#     update memcache
#   RELEASE_LOCK

sub talk2_do {
    my ( $u, $nodetype, $nodeid, $errref, $sql, @args ) = @_;
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;
    return undef unless $u->writer;

    my $dbcm   = $u->{_dbcm};
    my $userid = $u->userid;

    my $memkey  = [ $userid, "talk2:$userid:$nodetype:$nodeid" ];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array( "SELECT GET_LOCK(?,10)", undef, $lockkey );
    my $ret = $u->do( $sql, undef, @args );
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array( "SELECT RELEASE_LOCK(?)", undef, $lockkey );

    LJ::MemCache::delete( $memkey, 0 ) if int($ret);
    return $ret;
}

sub uncache_prop {
    my ( $u, $name ) = @_;
    my $prop   = LJ::get_prop( "user", $name ) or die;    # FIXME: use exceptions
    my $userid = $u->userid;
    LJ::MemCache::delete( [ $userid, "uprop:$userid:$prop->{id}" ] );
    delete $u->{$name};
    return 1;
}

sub update_self {
    my ( $u, $ref ) = @_;
    return LJ::update_user( $u, $ref );
}

# returns self (the $u object which can be used for $u->do) if
# user is writable, else 0
sub writer {
    my $u = shift;
    return $u if $u->{'_dbcm'} ||= LJ::get_cluster_master($u);
    return 0;
}

########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

use Carp;

########################################################################
###  5. Database and Memcache Functions

=head2 Database and Memcache Functions (LJ)
=cut

sub memcache_get_u {
    my @keys = @_;
    my @ret;
    foreach my $ar ( values %{ LJ::MemCache::get_multi(@keys) || {} } ) {
        my $row = LJ::MemCache::array_to_hash( "user", $ar )
            or next;
        my $u = LJ::User->new_from_row($row);
        push @ret, $u;
    }
    return wantarray ? @ret : $ret[0];
}

# <LJFUNC>
# name: LJ::memcache_kill
# des: Kills a memcache entry, given a userid and type.
# args: uuserid, type
# des-uuserid: a userid or u object
# des-type: memcached key type, will be used as "$type:$userid"
# returns: results of LJ::MemCache::delete
# </LJFUNC>
sub memcache_kill {
    my ( $uuid, $type ) = @_;
    my $userid = LJ::want_userid($uuid);
    return undef unless $userid && $type;

    return LJ::MemCache::delete( [ $userid, "$type:$userid" ] );
}

sub memcache_set_u {
    my $u = shift;
    return unless $u;
    my $expire = time() + 1800;
    my $ar     = LJ::MemCache::hash_to_array( "user", $u );
    return unless $ar;
    LJ::MemCache::set( [ $u->userid, "userid:" . $u->userid ], $ar, $expire );
    LJ::MemCache::set( "uidof:" . $u->user, $u->userid );
}

# FIXME: this should go away someday... see bug 2760
sub update_user {
    my ( $u, $ref ) = @_;
    $u = LJ::want_user($u) or return 0;
    my $uid = $u->id;

    my @sets;
    my @bindparams;
    my $used_raw = 0;
    while ( my ( $k, $v ) = each %$ref ) {
        if ( $k eq "raw" ) {
            $used_raw = 1;
            push @sets, $v;
        }
        elsif ( $k eq 'email' ) {
            LJ::set_email( $uid, $v );
        }
        elsif ( $k eq 'password' ) {
            $u->set_password($v);
        }
        else {
            push @sets,       "$k=?";
            push @bindparams, $v;
        }
    }
    return 1 unless @sets;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;
    {
        local $" = ",";
        my $where = "userid=$uid";
        $dbh->do( "UPDATE user SET @sets WHERE $where", undef, @bindparams );
        return 0 if $dbh->err;
    }
    if (@LJ::MEMCACHE_SERVERS) {
        LJ::memcache_kill( $uid, "userid" );
    }

    if ($used_raw) {

        # for a load of userids from the master after update
        # so we pick up the values set via the 'raw' option
        LJ::DB::require_master( sub { LJ::load_userid($uid) } );
    }
    else {
        while ( my ( $k, $v ) = each %$ref ) {
            my $cache = $LJ::REQ_CACHE_USER_ID{$uid} or next;
            $cache->{$k} = $v;
        }
    }

    # log this update
    LJ::Hooks::run_hooks( "update_user", userid => $uid, fields => $ref );

    return 1;
}

# <LJFUNC>
# name: LJ::wipe_major_memcache
# des: invalidate all major memcache items associated with a given user.
# args: u
# returns: nothing
# </LJFUNC>
sub wipe_major_memcache {
    my $u      = shift;
    my $userid = LJ::want_userid($u);
    foreach my $key (
        "userid",  "bio",      "talk2ct",      "talkleftct",
        "log2ct",  "log2lt",   "memkwid",      "dayct2",
        "fgrp",    "wt_edges", "wt_edges_rev", "tu",
        "upicinf", "upiccom",  "upicurl",      "upicdes",
        "intids",  "memct",    "lastcomm",     "user_oauth_consumer",
        "user_oauth_access"
        )
    {
        LJ::memcache_kill( $userid, $key );
    }
}

# <LJFUNC>
# name: LJ::_load_user_raw
# des-db:  $dbh/$dbr
# des-key:  either "userid" or "user"  (the WHERE part)
# des-vals: value or arrayref of values for key to match on
# des-hook: optional code ref to run for each $u
# returns: last $u found
sub _load_user_raw {
    my ( $db, $key, $vals, $hook ) = @_;
    $hook ||= sub { };
    $vals = [$vals] unless ref $vals eq "ARRAY";

    my $use_isam;
    unless ( $LJ::CACHE_NO_ISAM{user} || scalar(@$vals) > 10 ) {
        eval { $db->do("HANDLER user OPEN"); };
        if ( $@ || $db->err ) {
            $LJ::CACHE_NO_ISAM{user} = 1;
        }
        else {
            $use_isam = 1;
        }
    }

    my $last;

    if ($use_isam) {
        $key = "PRIMARY" if $key eq "userid";
        foreach my $v (@$vals) {
            my $sth = $db->prepare("HANDLER user READ `$key` = (?) LIMIT 1");
            $sth->execute($v);
            my $row = $sth->fetchrow_hashref;
            if ($row) {
                my $u = LJ::User->new_from_row($row);
                $hook->($u);
                $last = $u;
            }
        }
        $db->do("HANDLER user close");
    }
    else {
        my $in  = join( ", ", map { $db->quote($_) } @$vals );
        my $sth = $db->prepare("SELECT * FROM user WHERE $key IN ($in)");
        $sth->execute;
        while ( my $row = $sth->fetchrow_hashref ) {
            my $u = LJ::User->new_from_row($row);
            $hook->($u);
            $last = $u;
        }
    }

    return $last;
}

sub _set_u_req_cache {
    my $u = shift or die "no u to set";

    # if we have an existing user singleton, upgrade it with
    # the latested data, but keep using its address
    if ( my $eu = $LJ::REQ_CACHE_USER_ID{ $u->userid } ) {
        LJ::assert_is( $eu->userid, $u->userid );
        $eu->selfassert;
        $u->selfassert;

        $eu->{$_} = $u->{$_} foreach keys %$u;
        $u = $eu;
    }
    $LJ::REQ_CACHE_USER_NAME{ $u->user } = $u;
    $LJ::REQ_CACHE_USER_ID{ $u->userid } = $u;
    return $u;
}

########################################################################
###  23. Relationship Functions

=head2 Relationship Functions (formerly ljrelation.pl)
=cut

# <LJFUNC>
# name: LJ::get_reluser_id
# des: for [dbtable[reluser2]], numbers 1 - 31999 are reserved for
#      livejournal stuff, whereas numbers 32000-65535 are used for local sites.
# info: If you wish to add your own hooks to this, you should define a
#       hook "get_reluser_id" in ljlib-local.pl. No reluser2 [special[reluserdefs]]
#        types can be a single character, those are reserved for
#        the [dbtable[reluser]] table, so we don't have namespace problems.
# args: type
# des-type: the name of the type you're trying to access, e.g. "hide_comm_assoc"
# returns: id of type, 0 means it's not a reluser2 type
# </LJFUNC>
sub get_reluser_id {
    my $type = shift;
    return 0 if length $type == 1;    # must be more than a single character
    my $val = { 'hide_comm_assoc' => 1, }->{$type} + 0;
    return $val if $val;
    return 0 unless $type =~ /^local-/;
    return LJ::Hooks::run_hook( 'get_reluser_id', $type ) + 0;
}

# <LJFUNC>
# name: LJ::load_rel_user
# des: Load user relationship information. Loads all relationships of type 'type' in
#      which user 'userid' participates on the left side (is the source of the
#      relationship).
# args: db?, userid, type
# des-userid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_user {
    my $db = LJ::DB::isdb( $_[0] ) ? shift : undef;
    my ( $userid, $type ) = @_;
    return undef unless $type and $userid;
    my $u = LJ::want_user($userid);
    $userid = LJ::want_userid($userid);
    my $typeid = LJ::get_reluser_id($type) + 0;
    if ($typeid) {

        # clustered reluser2 table
        $db = LJ::get_cluster_reader($u);
        return $db->selectcol_arrayref( "SELECT targetid FROM reluser2 WHERE userid=? AND type=?",
            undef, $userid, $typeid );
    }
    else {
        # non-clustered reluser global table
        $db ||= LJ::get_db_reader();
        return $db->selectcol_arrayref( "SELECT targetid FROM reluser WHERE userid=? AND type=?",
            undef, $userid, $type );
    }
}

# <LJFUNC>
# name: LJ::load_rel_user_cache
# des: Loads user relationship information of the type 'type' where user
#      'targetid' participates on the left side (is the source of the relationship)
#      trying memcache first.  The results from this sub should be
#      <strong>treated as inaccurate and out of date</strong>.
# args: userid, type
# des-userid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_user_cache {
    my ( $userid, $type ) = @_;
    return undef unless $type && $userid;

    my $u = LJ::want_user($userid);
    return undef unless $u;
    $userid = $u->{'userid'};

    my $key = [ $userid, "reluser:$userid:$type" ];
    my $res = LJ::MemCache::get($key);

    return $res if $res;

    $res = LJ::load_rel_user( $userid, $type );

    my $exp = time() + 60 * 30;    # 30 min
    LJ::MemCache::set( $key, $res, $exp );

    return $res;
}

# <LJFUNC>
# name: LJ::load_rel_target
# des: Load user relationship information. Loads all relationships of type 'type' in
#      which user 'targetid' participates on the right side (is the target of the
#      relationship).
# args: db?, targetid, type
# des-targetid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_target {
    my $db = LJ::DB::isdb( $_[0] ) ? shift : undef;
    my ( $targetid, $type ) = @_;
    return undef unless $type and $targetid;
    my $u = LJ::want_user($targetid);
    $targetid = LJ::want_userid($targetid);
    my $typeid = LJ::get_reluser_id($type) + 0;
    if ($typeid) {

        # clustered reluser2 table
        $db = LJ::get_cluster_reader($u);
        return $db->selectcol_arrayref( "SELECT userid FROM reluser2 WHERE targetid=? AND type=?",
            undef, $targetid, $typeid );
    }
    else {
        # non-clustered reluser global table
        $db ||= LJ::get_db_reader();
        return $db->selectcol_arrayref( "SELECT userid FROM reluser WHERE targetid=? AND type=?",
            undef, $targetid, $type );
    }
}

# <LJFUNC>
# name: LJ::load_rel_target_cache
# des: Loads user relationship information of the type 'type' where user
#      'targetid' participates on the right side (is the target of the relationship)
#      trying memcache first.  The results from this sub should be
#      <strong>treated as inaccurate and out of date</strong>.
# args: targetid, type
# des-userid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_target_cache {
    my ( $userid, $type ) = @_;
    return undef unless $type && $userid;

    my $u = LJ::want_user($userid);
    return undef unless $u;
    $userid = $u->{'userid'};

    my $key = [ $userid, "reluser_rev:$userid:$type" ];
    my $res = LJ::MemCache::get($key);

    return $res if $res;

    $res = LJ::load_rel_target( $userid, $type );

    my $exp = time() + 60 * 30;    # 30 min
    LJ::MemCache::set( $key, $res, $exp );

    return $res;
}

# <LJFUNC>
# name: LJ::_get_rel_memcache
# des: Helper function: returns memcached value for a given (userid, targetid, type) triple, if valid.
# args: userid, targetid, type
# des-userid: source userid, nonzero
# des-targetid: target userid, nonzero
# des-type: type (reluser) or typeid (rel2) of the relationship
# returns: undef on failure, 0 or 1 depending on edge existence
# </LJFUNC>
sub _get_rel_memcache {
    return undef unless @LJ::MEMCACHE_SERVERS;
    return undef unless LJ::is_enabled('memcache_reluser');

    my ( $userid, $targetid, $type ) = @_;
    return undef unless $userid && $targetid && defined $type;

    # memcache keys
    my $relkey  = [ $userid,   "rel:$userid:$targetid:$type" ];    # rel $uid->$targetid edge
    my $modukey = [ $userid,   "relmodu:$userid:$type" ];          # rel modtime for uid
    my $modtkey = [ $targetid, "relmodt:$targetid:$type" ];        # rel modtime for targetid

    # do a get_multi since $relkey and $modukey are both hashed on $userid
    my $memc = LJ::MemCache::get_multi( $relkey, $modukey );
    return undef unless $memc && ref $memc eq 'HASH';

    # [{0|1}, modtime]
    my $rel = $memc->{ $relkey->[1] };
    return undef unless $rel && ref $rel eq 'ARRAY';

    # check rel modtime for $userid
    my $relmodu = $memc->{ $modukey->[1] };
    return undef if !$relmodu || $relmodu > $rel->[1];

    # check rel modtime for $targetid
    my $relmodt = LJ::MemCache::get($modtkey);
    return undef if !$relmodt || $relmodt > $rel->[1];

    # return memcache value if it's up-to-date
    return $rel->[0] ? 1 : 0;
}

# <LJFUNC>
# name: LJ::_set_rel_memcache
# des: Helper function: sets memcache values for a given (userid, targetid, type) triple
# args: userid, targetid, type
# des-userid: source userid, nonzero
# des-targetid: target userid, nonzero
# des-type: type (reluser) or typeid (rel2) of the relationship
# returns: 1 on success, undef on failure
# </LJFUNC>
sub _set_rel_memcache {
    return 1 unless @LJ::MEMCACHE_SERVERS;

    my ( $userid, $targetid, $type, $val ) = @_;
    return undef unless $userid && $targetid && defined $type;
    $val = $val ? 1 : 0;

    # memcache keys
    my $relkey  = [ $userid,   "rel:$userid:$targetid:$type" ];    # rel $uid->$targetid edge
    my $modukey = [ $userid,   "relmodu:$userid:$type" ];          # rel modtime for uid
    my $modtkey = [ $targetid, "relmodt:$targetid:$type" ];        # rel modtime for targetid

    my $now = time();
    my $exp = $now + 3600 * 6;                                     # 6 hour
    LJ::MemCache::set( $relkey, [ $val, $now ], $exp );
    LJ::MemCache::set( $modukey, $now, $exp );
    LJ::MemCache::set( $modtkey, $now, $exp );

    # Also, delete these keys, since the contents have changed.
    LJ::MemCache::delete( [ $userid,   "reluser:$userid:$type" ] );
    LJ::MemCache::delete( [ $targetid, "reluser_rev:$targetid:$type" ] );

    return 1;
}

# <LJFUNC>
# name: LJ::check_rel
# des: Checks whether two users are in a specified relationship to each other.
# args: userid, targetid, type
# des-userid: source userid, nonzero; may also be a user hash.
# des-targetid: target userid, nonzero; may also be a user hash.
# des-type: type of the relationship
# returns: 1 if the relationship exists, 0 otherwise
# </LJFUNC>
sub check_rel {
    my ( $userid, $targetid, $type ) = @_;
    return undef unless $type && $userid && $targetid;

    my $u = LJ::want_user($userid);
    $userid   = LJ::want_userid($userid);
    $targetid = LJ::want_userid($targetid);

    my $typeid   = LJ::get_reluser_id($type) + 0;
    my $eff_type = $typeid || $type;

    my $key = "$userid-$targetid-$eff_type";
    return $LJ::REQ_CACHE_REL{$key} if defined $LJ::REQ_CACHE_REL{$key};

    # did we get something from memcache?
    my $memval = LJ::_get_rel_memcache( $userid, $targetid, $eff_type );
    return $memval if defined $memval;

    # are we working on reluser or reluser2?
    my ( $db, $table );
    if ($typeid) {

        # clustered reluser2 table
        $db    = LJ::get_cluster_reader($u);
        $table = "reluser2";
    }
    else {
        # non-clustered reluser table
        $db    = LJ::get_db_reader();
        $table = "reluser";
    }

    # get data from db, force result to be {0|1}
    my $dbval = $db->selectrow_array(
        "SELECT COUNT(*) FROM $table " . "WHERE userid=? AND targetid=? AND type=? ",
        undef, $userid, $targetid, $eff_type ) ? 1 : 0;

    # set in memcache
    LJ::_set_rel_memcache( $userid, $targetid, $eff_type, $dbval );

    # return and set request cache
    return $LJ::REQ_CACHE_REL{$key} = $dbval;
}

# <LJFUNC>
# name: LJ::set_rel
# des: Sets relationship information for two users.
# args: dbs?, userid, targetid, type
# des-dbs: Deprecated; optional, a master/slave set of database handles.
# des-userid: source userid, or a user hash
# des-targetid: target userid, or a user hash
# des-type: type of the relationship
# returns: 1 if set succeeded, otherwise undef
# </LJFUNC>
sub set_rel {
    my ( $userid, $targetid, $type ) = @_;
    return undef unless $type and $userid and $targetid;

    my $u = LJ::want_user($userid);
    $userid   = LJ::want_userid($userid);
    $targetid = LJ::want_userid($targetid);

    my $typeid   = LJ::get_reluser_id($type) + 0;
    my $eff_type = $typeid || $type;

    # working on reluser or reluser2?
    my ( $db, $table );
    if ($typeid) {

        # clustered reluser2 table
        $db    = LJ::get_cluster_master($u);
        $table = "reluser2";
    }
    else {
        # non-clustered reluser global table
        $db    = LJ::get_db_writer();
        $table = "reluser";
    }
    return undef unless $db;

    # set in database
    $db->do( "REPLACE INTO $table (userid, targetid, type) VALUES (?, ?, ?)",
        undef, $userid, $targetid, $eff_type );
    return undef if $db->err;

    # set in memcache
    LJ::_set_rel_memcache( $userid, $targetid, $eff_type, 1 );

    return 1;
}

# <LJFUNC>
# name: LJ::set_rel_multi
# des: Sets relationship edges for lists of user tuples.
# args: edges
# des-edges: array of arrayrefs of edges to set: [userid, targetid, type].
#            Where:
#            userid: source userid, or a user hash;
#            targetid: target userid, or a user hash;
#            type: type of the relationship.
# returns: 1 if all sets succeeded, otherwise undef
# </LJFUNC>
sub set_rel_multi {
    return _mod_rel_multi( { mode => 'set', edges => \@_ } );
}

# <LJFUNC>
# name: LJ::clear_rel_multi
# des: Clear relationship edges for lists of user tuples.
# args: edges
# des-edges: array of arrayrefs of edges to clear: [userid, targetid, type].
#            Where:
#            userid: source userid, or a user hash;
#            targetid: target userid, or a user hash;
#            type: type of the relationship.
# returns: 1 if all clears succeeded, otherwise undef
# </LJFUNC>
sub clear_rel_multi {
    return _mod_rel_multi( { mode => 'clear', edges => \@_ } );
}

# <LJFUNC>
# name: LJ::_mod_rel_multi
# des: Sets/Clears relationship edges for lists of user tuples.
# args: keys, edges
# des-keys: keys: mode  => {clear|set}.
# des-edges: edges =>  array of arrayrefs of edges to set: [userid, targetid, type]
#            Where:
#            userid: source userid, or a user hash;
#            targetid: target userid, or a user hash;
#            type: type of the relationship.
# returns: 1 if all updates succeeded, otherwise undef
# </LJFUNC>
sub _mod_rel_multi {
    my $opts = shift;
    return undef unless @{ $opts->{edges} };

    my $mode   = $opts->{mode} eq 'clear' ? 'clear' : 'set';
    my $memval = $mode eq 'set'           ? 1       : 0;

    my @reluser  = ();    # [userid, targetid, type]
    my @reluser2 = ();
    foreach my $edge ( @{ $opts->{edges} } ) {
        my ( $userid, $targetid, $type ) = @$edge;
        $userid   = LJ::want_userid($userid);
        $targetid = LJ::want_userid($targetid);
        next unless $type && $userid && $targetid;

        my $typeid   = LJ::get_reluser_id($type) + 0;
        my $eff_type = $typeid || $type;

        # working on reluser or reluser2?
        push @{ $typeid ? \@reluser2 : \@reluser }, [ $userid, $targetid, $eff_type ];
    }

    # now group reluser2 edges by clusterid
    my %reluser2 = ();                                             # cid => [userid, targetid, type]
    my $users    = LJ::load_userids( map { $_->[0] } @reluser2 );
    foreach (@reluser2) {
        my $cid = $users->{ $_->[0] }->{clusterid} or next;
        push @{ $reluser2{$cid} }, $_;
    }
    @reluser2 = ();

    # try to get all required cluster masters before we start doing database updates
    my %cache_dbcm = ();
    foreach my $cid ( keys %reluser2 ) {
        next unless @{ $reluser2{$cid} };

        # return undef immediately if we won't be able to do all the updates
        $cache_dbcm{$cid} = LJ::get_cluster_master($cid)
            or return undef;
    }

    # if any error occurs with a cluster, we'll skip over that cluster and continue
    # trying to process others since we've likely already done some amount of db
    # updates already, but we'll return undef to signify that everything did not
    # go smoothly
    my $ret = 1;

    # do clustered reluser2 updates
    foreach my $cid ( keys %cache_dbcm ) {

        # array of arrayrefs: [userid, targetid, type]
        my @edges = @{ $reluser2{$cid} };

        # set in database, then in memcache.  keep the two atomic per clusterid
        my $dbcm = $cache_dbcm{$cid};

        my @vals = map { @$_ } @edges;

        if ( $mode eq 'set' ) {
            my $bind = join( ",", map { "(?,?,?)" } @edges );
            $dbcm->do( "REPLACE INTO reluser2 (userid, targetid, type) VALUES $bind",
                undef, @vals );
        }

        if ( $mode eq 'clear' ) {
            my $where = join( " OR ", map { "(userid=? AND targetid=? AND type=?)" } @edges );
            $dbcm->do( "DELETE FROM reluser2 WHERE $where", undef, @vals );
        }

        # don't update memcache if db update failed for this cluster
        if ( $dbcm->err ) {
            $ret = undef;
            next;
        }

        # updates to this cluster succeeded, set memcache
        LJ::_set_rel_memcache( @$_, $memval ) foreach @edges;
    }

    # do global reluser updates
    if (@reluser) {

        # nothing to do after this block but return, so we can
        # immediately return undef from here if there's a problem
        my $dbh = LJ::get_db_writer()
            or return undef;

        my @vals = map { @$_ } @reluser;

        if ( $mode eq 'set' ) {
            my $bind = join( ",", map { "(?,?,?)" } @reluser );
            $dbh->do( "REPLACE INTO reluser (userid, targetid, type) VALUES $bind", undef, @vals );
        }

        if ( $mode eq 'clear' ) {
            my $where = join( " OR ", map { "userid=? AND targetid=? AND type=?" } @reluser );
            $dbh->do( "DELETE FROM reluser WHERE $where", undef, @vals );
        }

        # don't update memcache if db update failed for this cluster
        return undef if $dbh->err;

        # $_ = [userid, targetid, type] for each iteration
        LJ::_set_rel_memcache( @$_, $memval ) foreach @reluser;
    }

    return $ret;
}

# <LJFUNC>
# name: LJ::clear_rel
# des: Deletes a relationship between two users or all relationships of a particular type
#      for one user, on either side of the relationship.
# info: One of userid,targetid -- bit not both -- may be '*'. In that case,
#       if, say, userid is '*', then all relationship edges with target equal to
#       targetid and of the specified type are deleted.
#       If both userid and targetid are numbers, just one edge is deleted.
# args: dbs?, userid, targetid, type
# des-dbs: Deprecated; optional, a master/slave set of database handles.
# des-userid: source userid, or a user hash, or '*'
# des-targetid: target userid, or a user hash, or '*'
# des-type: type of the relationship
# returns: 1 if clear succeeded, otherwise undef
# </LJFUNC>
sub clear_rel {
    my ( $userid, $targetid, $type ) = @_;
    return undef if $userid eq '*' and $targetid eq '*';

    my $u;
    $u        = LJ::want_user($userid)     unless $userid eq '*';
    $userid   = LJ::want_userid($userid)   unless $userid eq '*';
    $targetid = LJ::want_userid($targetid) unless $targetid eq '*';
    return undef unless $type && $userid && $targetid;

    my $typeid = LJ::get_reluser_id($type) + 0;

    if ($typeid) {

        # clustered reluser2 table
        return undef unless $u->writer;

        $u->do(   "DELETE FROM reluser2 WHERE "
                . ( $userid ne '*'   ? "userid=$userid AND "     : "" )
                . ( $targetid ne '*' ? "targetid=$targetid AND " : "" )
                . "type=$typeid" );

        return undef if $u->err;
    }
    else {
        # non-clustered global reluser table
        my $dbh = LJ::get_db_writer()
            or return undef;

        my $qtype = $dbh->quote($type);
        $dbh->do( "DELETE FROM reluser WHERE "
                . ( $userid ne '*'   ? "userid=$userid AND "     : "" )
                . ( $targetid ne '*' ? "targetid=$targetid AND " : "" )
                . "type=$qtype" );

        return undef if $dbh->err;
    }

    # if one of userid or targetid are '*', then we need to note the modtime
    # of the reluser edge from the specified id (the one that's not '*')
    # so that subsequent gets on rel:userid:targetid:type will know to ignore
    # what they got from memcache
    my $eff_type = $typeid || $type;
    if ( $userid eq '*' ) {
        LJ::MemCache::set( [ $targetid, "relmodt:$targetid:$eff_type" ], time() );
    }
    elsif ( $targetid eq '*' ) {
        LJ::MemCache::set( [ $userid, "relmodu:$userid:$eff_type" ], time() );

        # if neither userid nor targetid are '*', then just call _set_rel_memcache
        # to update the rel:userid:targetid:type memcache key as well as the
        # userid and targetid modtime keys
    }
    else {
        LJ::_set_rel_memcache( $userid, $targetid, $eff_type, 0 );
    }

    return 1;
}

1;
