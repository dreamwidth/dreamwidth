#!/usr/bin/perl
#
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
use DBI::Role;
use DBI;

# need ljconfig to set up database connection
use LJ::Config;
LJ::Config->load;

$LJ::DBIRole = new DBI::Role {
    'timeout' => sub {
        my ($dsn, $user, $pass, $role) = @_;
        return 0 if $role && $role eq "master";
        return $LJ::DB_TIMEOUT;
    },
    'sources' => \%LJ::DBINFO,
    'default_db' => "livejournal",
    'time_check' => 60,
    'time_report' => \&LJ::DB::dbtime_callback,
};

# tables on user databases (ljlib-local should define @LJ::USER_TABLES_LOCAL)
# this is here and no longer in bin/upgrading/update-db-{general|local}.pl
# so other tools (in particular, the inter-cluster user mover) can verify
# that it knows how to move all types of data before it will proceed.
@LJ::USER_TABLES = ("userbio", "birthdays", "dudata",
                    "log2", "logtext2", "logprop2", "logsec2",
                    "talk2", "talkprop2", "talktext2", "talkleft",
                    "userpicblob2", "subs", "subsprop", "has_subs",
                    "ratelog", "loginstall", "sessions", "sessions_data",
                    "modlog", "modblob", "userproplite2", "links",
                    "userpropblob",
                    "clustertrack2", "reluser2",
                    "tempanonips", "inviterecv", "invitesent",
                    "memorable2", "memkeyword2", "userkeywords",
                    "trust_groups", "userpicmap2", "userpic2",
                    "s2stylelayers2", "s2compiled2", "userlog",
                    "logtags", "logtagsrecent", "logkwsum",
                    "usertags", "pendcomments",
                    "loginlog", "active_user", "bannotes",
                    "notifyqueue", "dbnotes", "random_user_set",
                    "poll2", "pollquestion2", "pollitem2",
                    "pollresult2", "pollsubmission2", "vgift_trans",
                    "embedcontent", "usermsg", "usermsgtext", "usermsgprop",
                    "notifyarchive", "notifybookmarks", "embedcontent_preview",
                    "logprop_history", "import_status", "externalaccount",
                    "content_filters", "content_filter_data", "userpicmap3",
                    "media", "collections", "collection_items", "logslugs",
                    "media_versions", "media_props",
                    );

# keep track of what db locks we have out
%LJ::LOCK_OUT = (); # {global|user} => caller_with_lock


package LJ::DB;

use Carp qw(croak);  # import croak into package LJ::DB

sub isdb { return ref $_[0] && (ref $_[0] eq "DBI::db" ||
                                ref $_[0] eq "Apache::DBI::db"); }

sub dbh_by_role {
    return $LJ::DBIRole->get_dbh( @_ );
}

sub root_dbh_by_name {
    my $name = shift;
    my $dbh = dbh_by_role("master")
        or die "Couldn't contact master to find name of '$name'";

    my $fdsn = $dbh->selectrow_array("SELECT rootfdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No rootfdsn found for db name '$name'\n" unless $fdsn;

    return $LJ::DBIRole->get_dbh_conn($fdsn);
}

sub foreach_cluster {
    my $coderef = shift;
    my $opts = shift || {};

    foreach my $cluster_id (@LJ::CLUSTERS) {
        my $dbr = LJ::get_cluster_reader( $cluster_id );
        $coderef->($cluster_id, $dbr);
    }
}

sub bindstr { return join(', ', map { '?' } @_); }

# when calling a supported function (currently: LJ::load_user() or LJ::load_userid*)
# ignores in-process request cache, memcache, and selects directly
# from the global master
#
# called as: require_master(sub { block })
sub require_master {
    my $callback = shift;
    croak "invalid code ref passed to require_master"
        unless ref $callback eq 'CODE';

    # run code in the block with local var set
    local $LJ::_PRAGMA_FORCE_MASTER = 1;
    return $callback->();
}

sub no_cache {
    my $sb = shift;
    local $LJ::MemCache::GET_DISABLED = 1;
    return $sb->();
}

sub cond_no_cache {
    my ($cond, $sb) = @_;
    return no_cache($sb) if $cond;
    return $sb->();
}

# returns the DBI::Role role name of a cluster master given a clusterid
sub master_role {
    my $id = shift;
    my $role = "cluster${id}";
    if (my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$id}) {
        $ab = lc($ab);
        # master-master cluster
        $role = "cluster${id}${ab}" if $ab eq "a" || $ab eq "b";
    }
    return $role;
}

sub dbtime_callback {
    my ($dsn, $dbtime, $time) = @_;
    my $diff = abs($dbtime - $time);
    if ($diff > 2) {
        $dsn =~ /host=([^:\;\|]*)/;
        my $db = $1;
        print STDERR "Clock skew of $diff seconds between web($LJ::SERVER_NAME) and db($db)\n";
    }
}

# <LJFUNC>
# name: LJ::DB::get_dbirole_dbh
# class: db
# des: Internal function for get_dbh(). Uses the DBIRole to fetch a dbh, with
#      hooks into db stats-generation if that's turned on.
# info:
# args: opts, role
# des-opts: A hashref of options.
# des-role: The database role.
# returns: A dbh.
# </LJFUNC>
sub get_dbirole_dbh {
    my $dbh = $LJ::DBIRole->get_dbh( @_ ) or return undef;

    return $dbh;
}

# <LJFUNC>
# name: LJ::DB::get_lock
# des: get a MySQL lock on a given key/dbrole combination.
# returns: undef if called improperly, true on success, die() on failure
# args: db, dbrole, lockname, wait_time?
# des-dbrole: the role this lock should be gotten on, either 'global' or 'user'.
# des-lockname: the name to be used for this lock.
# des-wait_time: an optional timeout argument, defaults to 10 seconds.
# </LJFUNC>
sub get_lock
{
    my ($db, $dbrole, $lockname, $wait_time) = @_;
    return undef unless $db && $lockname;
    return undef unless $dbrole eq 'global' || $dbrole eq 'user';

    my $curr_sub = (caller 1)[3]; # caller of current sub

    # die if somebody already has a lock
    die "LOCK ERROR: $curr_sub; can't get lock from: $LJ::LOCK_OUT{$dbrole}\n"
        if exists $LJ::LOCK_OUT{$dbrole};

    # get a lock from mysql
    $wait_time ||= 10;
    $db->do("SELECT GET_LOCK(?,?)", undef, $lockname, $wait_time)
        or return undef;

    # successfully got a lock
    $LJ::LOCK_OUT{$dbrole} = $curr_sub;
    return 1;
}

# <LJFUNC>
# name: LJ::DB::release_lock
# des: release a MySQL lock on a given key/dbrole combination.
# returns: undef if called improperly, true on success, die() on failure
# args: db, dbrole, lockname
# des-dbrole: role on which to get this lock, either 'global' or 'user'.
# des-lockname: the name to be used for this lock
# </LJFUNC>
sub release_lock
{
    my ($db, $dbrole, $lockname) = @_;
    return undef unless $db && $lockname;
    return undef unless $dbrole eq 'global' || $dbrole eq 'user';

    # get a lock from mysql
    $db->do("SELECT RELEASE_LOCK(?)", undef, $lockname);
    delete $LJ::LOCK_OUT{$dbrole};

    return 1;
}

# <LJFUNC>
# name: LJ::DB::disconnect_dbs
# des: Clear cached DB handles
# </LJFUNC>
sub disconnect_dbs {
    # clear cached handles
    $LJ::DBIRole->disconnect_all( { except => [qw(logs)] });
}

# <LJFUNC>
# name: LJ::DB::use_diff_db
# class:
# des: given two DB roles, returns true only if it is certain the two roles are
#      served by different database servers.
# info: This is useful for, say, the moveusercluster script: You would not want
#       to select something from one DB, copy it into another, and then delete it from the
#       source if they were both the same machine.
# args:
# des-:
# returns:
# </LJFUNC>
sub use_diff_db {
    $LJ::DBIRole->use_diff_db(@_);
}

# <LJFUNC>
# name: LJ::DB::get_cluster_description
# des: Get descriptive text for a cluster id.
# args: clusterid
# des-clusterid: id of cluster to get description of.
# returns: string representing the cluster description
# </LJFUNC>
sub get_cluster_description {
    my ( $cid ) = @_;
    $cid += 0;
    my $text = LJ::Hooks::run_hook( 'cluster_description', $cid );
    return $text if $text;

    # default behavior just returns clusterid
    return $cid;
}

# <LJFUNC>
# name: LJ::DB::new_account_cluster
# des: Which cluster to put a new account on.  $DEFAULT_CLUSTER if it's
#      a scalar, random element from [ljconfig[default_cluster]] if it's arrayref.
#      also verifies that the database seems to be available.
# returns: clusterid where the new account should be created; 0 on error
#          (such as no clusters available).
# </LJFUNC>
sub new_account_cluster
{
    # if it's not an arrayref, put it in an array ref so we can use it below
    my $clusters = ref $LJ::DEFAULT_CLUSTER ? $LJ::DEFAULT_CLUSTER : [ $LJ::DEFAULT_CLUSTER+0 ];

    # select a random cluster from the set we've chosen in $LJ::DEFAULT_CLUSTER
    return LJ::DB::random_cluster(@$clusters);
}

# returns the clusterid of a random cluster which is up
# -- accepts @clusters as an arg to enforce a subset, otherwise
#    uses @LJ::CLUSTERS
sub random_cluster {
    my @clusters = @_ ? @_ : @LJ::CLUSTERS;

    # iterate through the new clusters from a random point
    my $size = @clusters;
    my $start = int(rand() * $size);
    foreach (1..$size) {
        my $cid = $clusters[$start++ % $size];

        # verify that this cluster is in @LJ::CLUSTERS
        my @check = grep { $_ == $cid } @LJ::CLUSTERS;
        next unless scalar(@check) >= 1 && $check[0] == $cid;

        # try this cluster to see if we can use it, return if so
        my $dbcm = LJ::get_cluster_master($cid);
        return $cid if $dbcm;
    }

    # if we get here, we found no clusters that were up...
    return 0;
}


package LJ;

use Carp qw(confess);  # import confess into package LJ

# <LJFUNC>
# name: LJ::get_dbh
# class: db
# des: Given one or more roles, returns a database handle.
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub get_dbh {
    my $opts = ref $_[0] eq "HASH" ? shift : {};

    unless (exists $opts->{'max_repl_lag'}) {
        # for slave or cluster<n>slave roles, don't allow lag
        if ($_[0] =~ /slave$/) {
            $opts->{'max_repl_lag'} = $LJ::MAX_REPL_LAG || 100_000;
        }
    }

    if ($LJ::DEBUG{'get_dbh'} && $_[0] ne "logs") {
        my $errmsg = "get_dbh(@_) at \n";
        my $i = 0;
        while (my ($p, $f, $l) = caller($i++)) {
            next if $i > 3;
            $errmsg .= "  $p, $f, $l\n";
        }
        warn $errmsg;
    }

    my $nodb = sub {
        my $roles = shift;
        my $err = LJ::errobj("Database::Unavailable",
                             roles => $roles);
        return $err->cond_throw;
    };

    foreach my $role (@_) {
        # let site admin turn off global master write access during
        # maintenance
        return $nodb->([@_]) if $LJ::DISABLE_MASTER && $role eq "master";
        my $db = LJ::DB::get_dbirole_dbh( $opts, $role );
        return $db if $db;
    }
    return $nodb->([@_]);
}

sub get_db_reader {
    return LJ::get_dbh("master") if $LJ::_PRAGMA_FORCE_MASTER;
    return LJ::get_dbh("slave", "master");
}

sub get_db_writer {
    return LJ::get_dbh("master");
}

# <LJFUNC>
# name: LJ::get_cluster_reader
# class: db
# des: Returns a cluster slave for a user or clusterid, or cluster master if
#      no slaves exist.
# args: uarg
# des-uarg: Either a clusterid scalar or a user object.
# returns: DB handle.  Or undef if all dbs are unavailable.
# </LJFUNC>
sub get_cluster_reader
{
    my $arg = shift;
    my $id = isu($arg) ? $arg->{'clusterid'} : $arg;
    my @roles = ("cluster${id}slave", "cluster${id}");
    if (my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$id}) {
        $ab = lc($ab);
        # master-master cluster
        @roles = ("cluster${id}${ab}") if $ab eq "a" || $ab eq "b";
    }
    return LJ::get_dbh(@roles);
}

# <LJFUNC>
# name: LJ::get_cluster_def_reader
# class: db
# des: Returns a definitive cluster reader for a given user or clusterid, used
#      when the caller wants the master handle, but will only
#      use it to read.
# args: uarg
# des-uarg: Either a clusterid scalar or a user object.
# returns: DB handle.  Or undef if definitive reader is unavailable.
# </LJFUNC>
sub get_cluster_def_reader
{
    my @dbh_opts = scalar(@_) == 2 ? (shift @_) : ();
    my $arg = shift;
    my $id = isu($arg) ? $arg->{'clusterid'} : $arg;
    return LJ::get_cluster_reader(@dbh_opts, $id) if
        $LJ::DEF_READER_ACTUALLY_SLAVE{$id};
    return LJ::get_dbh( @dbh_opts, LJ::DB::master_role($id) );
}

# <LJFUNC>
# name: LJ::get_cluster_master
# class: db
# des: Returns a cluster master for a given user or clusterid, used when the
#      caller might use it to do a write (insert/delete/update/etc...)
# args: uarg
# des-uarg: Either a clusterid scalar or a user object.
# returns: DB handle.  Or undef if master is unavailable.
# </LJFUNC>
sub get_cluster_master
{
    my @dbh_opts = scalar(@_) == 2 ? (shift @_) : ();
    my $arg = shift;
    my $id = isu($arg) ? $arg->{'clusterid'} : $arg;
    return undef if $LJ::READONLY_CLUSTER{$id};
    return LJ::get_dbh( @dbh_opts, LJ::DB::master_role($id) );
}


# Single-letter domain values are for livejournal-generic code.
#  - 0-9 are reserved for site-local hooks and are mapped from a long
#    (> 1 char) string passed as the $dom to a single digit by the
#    'map_global_counter_domain' hook.
#
# LJ-generic domains:
#  $dom: 'S' == style, 'P' == userpic, 'A' == stock support answer
#        'E' == external user, 'V' == vgifts,
#        'L' == poLL,  'M' == Messaging, 'H' == sHopping cart,
#        'F' == PubSubHubbub subscription id (F for Fred),
#        'K' == sitekeyword, 'I' == shopping cart Item,
#        'X' == sphinX id, 'U' == OAuth ConsUmer, 'N' == seNdmail history
#
sub alloc_global_counter
{
    my ($dom, $recurse) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # $dom can come as a direct argument or as a string to be mapped via hook
    my $dom_unmod = $dom;
    unless ( $dom =~ /^[ESLPAHCMFKIVXUN]$/ ) {
        $dom = LJ::Hooks::run_hook('map_global_counter_domain', $dom);
    }
    return LJ::errobj("InvalidParameters", params => { dom => $dom_unmod })->cond_throw
        unless defined $dom;

    my $newmax;
    my $uid = 0; # userid is not needed, we just use '0'

    my $rs = $dbh->do("UPDATE counter SET max=LAST_INSERT_ID(max+1) WHERE journalid=? AND area=?",
                      undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");
        return $newmax;
    }

    return undef if $recurse;

    # no prior counter rows - initialize one.
    if ($dom eq "S") {
        confess 'Tried to allocate S1 counter.';
    } elsif ($dom eq "P") {
        $newmax = 0;
        foreach my $cid ( @LJ::CLUSTERS ) {
            my $dbcm = LJ::get_cluster_master( $cid ) or return undef;
            my $max = $dbcm->selectrow_array( 'SELECT MAX(picid) FROM userpic2' ) + 0;
            $newmax = $max if $max > $newmax;
        }
    } elsif ($dom eq "E" || $dom eq "M") {
        # if there is no extuser or message counter row
        # start at 'ext_1'  - ( the 0 here is incremented after the recurse )
        $newmax = 0;
    } elsif ($dom eq "A") {
        $newmax = $dbh->selectrow_array("SELECT MAX(ansid) FROM support_answers");
    } elsif ($dom eq "H") {
        $newmax = $dbh->selectrow_array("SELECT MAX(cartid) FROM shop_carts");
    } elsif ($dom eq "L") {
        # pick maximum id from pollowner
        $newmax = $dbh->selectrow_array( "SELECT MAX(pollid) FROM pollowner" );
    } elsif ( $dom eq 'F' ) {
        confess 'Tried to allocate PubSubHubbub counter.';
    } elsif ( $dom eq 'U' ) {
        $newmax = $dbh->selectrow_array( "SELECT MAX(consumer_id) FROM oauth_consumer" );
    } elsif ( $dom eq 'V' ) {
        $newmax = $dbh->selectrow_array( "SELECT MAX(vgiftid) FROM vgift_ids" );
    } elsif ( $dom eq 'N' ) {
        $newmax = $dbh->selectrow_array( "SELECT MAX(msgid) FROM siteadmin_email_history" );
    } elsif ( $dom eq 'K' ) {
        # pick maximum id from sitekeywords & interests
        my $max_sitekeys  = $dbh->selectrow_array( "SELECT MAX(kwid) FROM sitekeywords" );
        my $max_interests = $dbh->selectrow_array( "SELECT MAX(intid) FROM interests" );
        $newmax = $max_sitekeys > $max_interests ? $max_sitekeys : $max_interests;
    } elsif ( $dom eq 'I' ) {
        # if we have no counter, start at 0, as we have no way of determining what
        # the maximum used item id is
        $newmax = 0;
    } elsif ( $dom eq 'X' ) {
        my $dbsx = LJ::get_dbh( 'sphinx_search' )
            or die "Unable to allocate counter type X unless Sphinx is configured.\n";
        $newmax = $dbsx->selectrow_array( 'SELECT MAX(id) FROM items_raw' );
    } else {
        $newmax = LJ::Hooks::run_hook('global_counter_init_value', $dom);
        die "No alloc_global_counter initalizer for domain '$dom'"
            unless defined $newmax;
    }
    $newmax += 0;
    $dbh->do("INSERT IGNORE INTO counter (journalid, area, max) VALUES (?,?,?)",
             undef, $uid, $dom, $newmax) or return LJ::errobj($dbh)->cond_throw;
    return LJ::alloc_global_counter($dom, 1);
}


# $dom: 'L' == log, 'T' == talk, 'M' == modlog, 'S' == session,
#       'R' == memory (remembrance), 'K' == keyword id,
#       'C' == pending comment
#       'V' == 'vgift', 'E' == ESN subscription id
#       'Q' == Notification Inbox,
#       'D' == 'moDule embed contents', 'I' == Import data block
#       'Z' == import status item, 'X' == eXternal account
#       'F' == filter id, 'Y' = pic/keYword mapping id
#       'A' == mediA item id, 'O' == cOllection id,
#       'N' == collectioN item id
#
sub alloc_user_counter
{
    my ($u, $dom, $opts) = @_;
    $opts ||= {};

    ##################################################################
    # IF YOU UPDATE THIS MAKE SURE YOU ADD INITIALIZATION CODE BELOW #
    return undef unless $dom =~ /^[LTMPSRKCOVEQGDIZXFYA]$/;          #
    ##################################################################

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $newmax;
    my $uid = $u->userid + 0;
    return undef unless $uid;
    my $memkey = [$uid, "auc:$uid:$dom"];

    # in a master-master DB cluster we need to be careful that in
    # an automatic failover case where one cluster is slightly behind
    # that the same counter ID isn't handed out twice.  use memcache
    # as a sanity check to record/check latest number handed out.
    my $memmax = int(LJ::MemCache::get($memkey) || 0);

    my $rs = $dbh->do("UPDATE usercounter SET max=LAST_INSERT_ID(GREATEST(max,$memmax)+1) ".
                      "WHERE journalid=? AND area=?", undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");

        # if we've got a supplied callback, lets check the counter
        # number for consistency.  If it fails our test, wipe
        # the counter row and start over, initializing a new one.
        # callbacks should return true to signal 'all is well.'
        if ($opts->{callback} && ref $opts->{callback} eq 'CODE') {
            my $rv = 0;
            eval { $rv = $opts->{callback}->($u, $newmax) };
            if ($@ or ! $rv) {
                $dbh->do("DELETE FROM usercounter WHERE " .
                         "journalid=? AND area=?", undef, $uid, $dom);
                return LJ::alloc_user_counter($u, $dom);
            }
        }

        LJ::MemCache::set($memkey, $newmax);
        return $newmax;
    }

    if ($opts->{recurse}) {
        # We shouldn't ever get here if all is right with the world.
        return undef;
    }

    my $qry_map = {
        # for entries:
        'log'         => "SELECT MAX(jitemid) FROM log2     WHERE journalid=?",
        'logtext'     => "SELECT MAX(jitemid) FROM logtext2 WHERE journalid=?",
        'talk_nodeid' => "SELECT MAX(nodeid)  FROM talk2    WHERE nodetype='L' AND journalid=?",
        # for comments:
        'talk'     => "SELECT MAX(jtalkid) FROM talk2     WHERE journalid=?",
        'talktext' => "SELECT MAX(jtalkid) FROM talktext2 WHERE journalid=?",
    };

    my $consider = sub {
        my @tables = @_;
        foreach my $t (@tables) {
            my $res = $u->selectrow_array($qry_map->{$t}, undef, $uid);
            $newmax = $res if $res > $newmax;
        }
    };

    # Make sure the counter table is populated for this uid/dom.
    if ($dom eq "L") {
        # back in the ol' days IDs were reused (because of MyISAM)
        # so now we're extra careful not to reuse a number that has
        # foreign junk "attached".  turns out people like to delete
        # each entry by hand, but we do lazy deletes that are often
        # too lazy and a user can see old stuff come back alive
        $consider->("log", "logtext", "talk_nodeid");
    } elsif ($dom eq "T") {
        # just paranoia, not as bad as above.  don't think we've ever
        # run into cases of talktext without a talk, but who knows.
        # can't hurt.
        $consider->("talk", "talktext");
    } elsif ($dom eq "M") {
        $newmax = $u->selectrow_array("SELECT MAX(modid) FROM modlog WHERE journalid=?",
                                      undef, $uid);
    } elsif ($dom eq "S") {
        $newmax = $u->selectrow_array("SELECT MAX(sessid) FROM sessions WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "R") {
        $newmax = $u->selectrow_array("SELECT MAX(memid) FROM memorable2 WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "K") {
        $newmax = $u->selectrow_array("SELECT MAX(kwid) FROM userkeywords WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "C") {
        $newmax = $u->selectrow_array("SELECT MAX(pendcid) FROM pendcomments WHERE jid=?",
                                      undef, $uid);
    } elsif ($dom eq "V") {
        $newmax = $u->selectrow_array("SELECT MAX(transid) FROM vgift_trans WHERE rcptid=?",
                                      undef, $uid);
    } elsif ($dom eq "E") {
        $newmax = $u->selectrow_array("SELECT MAX(subid) FROM subs WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "Q") {
        $newmax = $u->selectrow_array("SELECT MAX(qid) FROM notifyqueue WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "D") {
        $newmax = $u->selectrow_array("SELECT MAX(moduleid) FROM embedcontent WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "I") {
        $newmax = $dbh->selectrow_array("SELECT MAX(import_data_id) FROM import_data WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "Z") {
        $newmax = $dbh->selectrow_array("SELECT MAX(import_status_id) FROM import_status WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "X") {
        $newmax = $u->selectrow_array("SELECT MAX(acctid) FROM externalaccount WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "F") {
        $newmax = $u->selectrow_array("SELECT MAX(filterid) FROM watch_filters WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "Y") {
        $newmax = $u->selectrow_array("SELECT MAX(mapid) FROM userpicmap3 WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "A") {
        $newmax = $u->selectrow_array("SELECT MAX(mediaid) FROM media WHERE userid = ?",
                                      undef, $uid);
    } elsif ($dom eq "O") {
        $newmax = $u->selectrow_array("SELECT MAX(colid) FROM collections WHERE userid = ?",
                                      undef, $uid);
    } elsif ($dom eq "N") {
        $newmax = $u->selectrow_array("SELECT MAX(colitemid) FROM collection_items WHERE userid = ?",
                                      undef, $uid);
    } else {
        die "No user counter initializer defined for area '$dom'.\n";
    }
    $newmax += 0;
    $dbh->do("INSERT IGNORE INTO usercounter (journalid, area, max) VALUES (?,?,?)",
             undef, $uid, $dom, $newmax) or return undef;

    # The 2nd invocation of the alloc_user_counter sub should do the
    # intended incrementing.
    return LJ::alloc_user_counter($u, $dom, { recurse => 1 });
}


package LJ::Error::Database::Unavailable;
sub fields { qw(roles) }  # arrayref of roles requested

sub as_string {
    my $self = shift;
    my $ct = @{$self->field('roles')};
    my $clist = join(", ", @{$self->field('roles')});
    return $ct == 1 ?
        "Database unavailable for role $clist" :
        "Database unavailable for roles $clist";
}


package LJ::Error::Database::Failure;
sub fields { qw(db) }

sub user_caused { 0 }

sub as_string {
    my $self = shift;
    my $code = $self->err;
    my $txt  = $self->errstr;
    return "Database error code $code: $txt";
}

sub err {
    my $self = shift;
    return $self->field('db')->err;
}

sub errstr {
    my $self = shift;
    return $self->field('db')->errstr;
}

1;
