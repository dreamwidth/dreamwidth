#!/usr/bin/perl
#

use strict;
use lib "$LJ::HOME/cgi-bin";
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
    'time_report' => \&LJ::dbtime_callback,
};

package LJ::DB;

use Carp qw(croak);

# <LJFUNC>
# name: LJ::DB::time_range_to_ids
# des:  Performs a binary search on a table's primary id key looking
#       for time boundaries as specified.  Returns the boundary ids
#       that were found, effectively simulating a key on 'time' for
#       the specified table.
# info: This function shouldn't normally be used, but there are
#       rare instances where it's useful.
# args: opts
# des-opts: A hashref of keys. Keys are:
#           'table' - table name to query;
#           'roles' - arrayref of db roles to use, in order. Defaults to ['slow'];
#           'idcol' - name of 'id' primary key column.
#           'timecol' - name of unixtime column to use for constraint;
#           'starttime' - starting unixtime time of rows to match;
#           'endtime' - ending unixtime of rows to match.
# returns: startid, endid; id boundaries which should be used by
#          the caller.
# </LJFUNC>

sub time_range_to_ids {
    my %args = @_;

    my $table     = delete $args{table}     or croak("no table arg");
    my $idcol     = delete $args{idcol}     or croak("no idcol arg");
    my $timecol   = delete $args{timecol}   or croak("no timecol arg");
    my $starttime = delete $args{starttime} or croak("no starttime arg");
    my $endtime   = delete $args{endtime}   or croak("no endtime arg");
    my $roles     = delete $args{roles};
    unless (ref $roles eq 'ARRAY' && @$roles) {
        $roles = [ 'slow' ];
    }
    croak("bogus args: " . join(",", keys %args))
        if %args;

    my $db = LJ::get_dbh(@$roles)
        or die "unable to acquire db handle, roles=", join(",", @$roles);

    my ($db_min_id, $db_max_id) = $db->selectrow_array
        ("SELECT MIN($idcol), MAX($idcol) FROM $table");
    die $db->errstr if $db->err;
    die "error finding min/max ids: $db_max_id < $db_min_id"
        if $db_max_id < $db_min_id;

    # final output
    my ($startid, $endid);
    my $ct_max = 100;

    foreach my $curr_ref ([$starttime => \$startid], [$endtime => \$endid]) {
        my ($want_time, $dest_ref) = @$curr_ref;

        my ($min_id, $max_id) = ($db_min_id, $db_max_id);

        my $curr_time = 0;
        my $last_time = 0;

        my $ct = 0;
        while ($ct++ < $ct_max) {
            die "unable to find row after $ct tries" if $ct > 100;

            my $curr_id = $min_id + int(($max_id - $min_id) / 2)+0;

            my $sql =
                "SELECT $idcol, $timecol FROM $table " .
                "WHERE $idcol>=$curr_id ORDER BY 1 LIMIT 1";

            $last_time = $curr_time;
            ($curr_id, $curr_time) = $db->selectrow_array($sql);
            die $db->errstr if $db->err;

            # stop condition, two trigger cases:
            #  * we've found exactly the time we want
            #  * we're still narrowing but not finding rows in between, stop here with
            #    the current time being just short of what we were trying to find
            if ($curr_time == $want_time || $curr_time == $last_time) {

                # if we never modified the max id, then we
                # have searched to the end without finding
                # what we were looking for
                if ($max_id == $db_max_id && $curr_time <= $want_time) {
                    $$dest_ref = $max_id;

                # same for min id
                } elsif ($min_id == $db_min_id && $curr_time >= $want_time) {
                    $$dest_ref = $min_id;

                } else {
                    $$dest_ref = $curr_id;
                }
                last;
            }

            # need to traverse into the larger half
            if ($curr_time < $want_time) {
                $min_id = $curr_id;
                next;
            }

            # need to traverse into the smaller half
            if ($curr_time > $want_time) {
                $max_id = $curr_id;
                next;
            }
        }
    }

    return ($startid, $endid);
}

sub dbh_by_role {
    return $LJ::DBIRole->get_dbh( @_ );
}

sub dbh_by_name {
    my $name = shift;
    my $dbh = dbh_by_role("master")
        or die "Couldn't contact master to find name of '$name'\n";

    my $fdsn = $dbh->selectrow_array("SELECT fdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No fdsn found for db name '$name'\n" unless $fdsn;

    return $LJ::DBIRole->get_dbh_conn($fdsn);

}

sub dbh_by_fdsn {
    my $fdsn = shift;
    return $LJ::DBIRole->get_dbh_conn($fdsn);
}

sub root_dbh_by_name {
    my $name = shift;
    my $dbh = dbh_by_role("master")
        or die "Couldn't contact master to find name of '$name'";

    my $fdsn = $dbh->selectrow_array("SELECT rootfdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No rootfdsn found for db name '$name'\n" unless $fdsn;

    return $LJ::DBIRole->get_dbh_conn($fdsn);
}

sub backup_in_progress {
    my $name = shift;
    my $dbh = dbh_by_role("master")
        or die "Couldn't contact master to find name of '$name'";

    # return 0 if this a/b is the active side, as wecan't ever have a backup of active side in progress
    my ($cid, $is_a_or_b) = user_cluster_details($name);
    if ($cid) {
        my $active_ab = $LJ::CLUSTER_PAIR_ACTIVE{$cid} or
            die "Neither 'a' nor 'b' is active for clusterid $cid?\n";
        die "Bogus active side" unless $active_ab =~ /^[ab]$/;

        # can't have a backup in progress for an active a/b side.  short-circuit
        # and don't even ask the database, as it might lie if the process
        # was killed or something
        return 0 if $active_ab eq $is_a_or_b;
    }

    my $fdsn = $dbh->selectrow_array("SELECT rootfdsn FROM dbinfo WHERE name=?", undef, $name);
    die "No rootfdsn found for db name '$name'\n" unless $fdsn;
    $fdsn =~ /\bhost=([\w\.\-]+)/ or die "Can't find host for database '$name'";
    my $host = $1;

    eval "use IO::Socket::INET; 1;" or die;
    my $sock = IO::Socket::INET->new(PeerAddr => "$host:7602")  or return 0;
    print $sock "is_backup_in_progress\r\n";
    my $answer = <$sock>;
    chomp $answer;
    return $answer eq "1";
}

sub user_cluster_details {
    my $name = shift;
    my $dbh = dbh_by_role("master") or die;

    my $role = $dbh->selectrow_array("SELECT role FROM dbweights w, dbinfo i WHERE i.name=? AND i.dbid=w.dbid",
                                     undef, $name);
    return () unless $role && $role =~ /^cluster(\d+)([ab])$/;
    return ($1, $2);
}

package LJ;

use Carp qw(croak);

# when calling a supported function (currently: LJ::load_user() or LJ::load_userid*), LJ::SMS::load_mapping()
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

sub no_ml_cache {
    my $sb = shift;
    local $LJ::NO_ML_CACHE = 1;
    return $sb->();
}

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
        my $db = LJ::get_dbirole_dbh($opts, $role);
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
    return LJ::get_dbh(@dbh_opts, LJ::master_role($id));
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
    return LJ::get_dbh(@dbh_opts, LJ::master_role($id));
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

# <LJFUNC>
# name: LJ::get_dbirole_dbh
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

    if ( $LJ::DB_LOG_HOST && $LJ::HAVE_DBI_PROFILE ) {
        $LJ::DB_REPORT_HANDLES{ $dbh->{Name} } = $dbh;

        # :TODO: Explain magic number
        $dbh->{Profile} ||= "2/DBI::Profile";

        # And turn off useless (to us) on_destroy() reports, too.
        undef $DBI::Profile::ON_DESTROY_DUMP;
    }

    return $dbh;
}

# <LJFUNC>
# name: LJ::get_lock
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
# name: LJ::may_lock
# des: see if we <strong>could</strong> get a MySQL lock on
#       a given key/dbrole combination, but don't actually get it.
# returns: undef if called improperly, true on success, die() on failure
# args: db, dbrole
# des-dbrole: the role this lock should be gotten on, either 'global' or 'user'.
# </LJFUNC>
sub may_lock
{
    my ($db, $dbrole) = @_;
    return undef unless $db && ($dbrole eq 'global' || $dbrole eq 'user');

    # die if somebody already has a lock
    if ($LJ::LOCK_OUT{$dbrole}) {
        my $curr_sub = (caller 1)[3]; # caller of current sub
        die "LOCK ERROR: $curr_sub; can't get lock from $LJ::LOCK_OUT{$dbrole}\n";
    }

    # see if a lock is already out
    return undef if exists $LJ::LOCK_OUT{$dbrole};

    return 1;
}

# <LJFUNC>
# name: LJ::release_lock
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
# name: LJ::disconnect_dbs
# des: Clear cached DB handles
# </LJFUNC>
sub disconnect_dbs {
    # clear cached handles
    $LJ::DBIRole->disconnect_all( { except => [qw(logs)] });
}

# <LJFUNC>
# name: LJ::use_diff_db
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

# to be called as &nodb; (so this function sees caller's @_)
sub nodb {
    shift @_ if
        ref $_[0] eq "LJ::DBSet" || ref $_[0] eq "DBI::db" ||
        ref $_[0] eq "Apache::DBI::db";
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

sub foreach_cluster {
    my $coderef = shift;
    my $opts = shift || {};

    # have to include this via an eval so it doesn't actually get included
    # until someone calls foreach cluster.  at which point, if they're in web
    # context, it will fail.
    eval "use LJ::DBUtil; 1;";
    die $@ if $@;
    
    foreach my $cluster_id (@LJ::CLUSTERS) {
        my $dbr = ($LJ::IS_DEV_SERVER) ?
            LJ::get_cluster_reader($cluster_id) : LJ::DBUtil->get_inactive_db($cluster_id, $opts->{verbose});
        $coderef->($cluster_id, $dbr);
    }
}


sub isdb { return ref $_[0] && (ref $_[0] eq "DBI::db" ||
                                ref $_[0] eq "Apache::DBI::db"); }


sub bindstr { return join(', ', map { '?' } @_); }

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
