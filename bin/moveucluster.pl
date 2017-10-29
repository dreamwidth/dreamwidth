#!/usr/bin/perl
##############################################################################
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

=head1 NAME

moveucluster.pl - Moves a LiveJournal user between database clusters

=head1 SYNOPSIS

  $ moveucluster.pl OPTIONS <user> <dest_clusterid>

=head1 OPTIONS

=over 4

=item -h, --help

Output a help message and exit.

=item --verbose[=<n>]

Verbosity level, 0, 1, or 2.

=item --verify

Verify count of copied rows to ensure accuracy (slower)

=item --ignorebit

Ignore the move in progress bit (force user move)

=item --prelocked

Do not set user readonly and sleep (somebody else did it)

=item --delete

Delete data from source cluster when done moving

=item --destdelete

Delete data from destination cluster before moving

=item --expungedel

The expungedel option is used to indicate that when a user is encountered
with a statusvis of D (deleted journal) and they've been deleted for at
least 31 days, instead of moving their data, mark the user as expunged.

Further, if you specify the delete and expungedel options at the same time,
if the user is expunged, all of their data will be deleted from the source
cluster.  THIS IS IRREVERSIBLE AND YOU WILL NOT BE ASKED FOR CONFIRMATION.

=item --earlyexpunge

Ignore the 31 day delay in --expungedel, so the user will be expunged no
matter how long since they were deleted. This option is allowed on dev
servers only.

=item --jobserver=host:port

Specify a job server to get tasks from.  In this mode, no other
arguments are necessary, and moveucluster.pl just runs in a loop
getting directions from the job server.

=back

=head1 AUTHOR

Brad Fitzpatrick E<lt>brad@danga.comE<gt>
Copyright (c) 2002-2004 Danga Interactive. All rights reserved.

=cut

##############################################################################

use strict;
use Getopt::Long;
use Pod::Usage qw{pod2usage};
use IO::Socket::INET;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm";
    $LJ::_T_CONFIG = $ENV{DW_TEST};
};

# NOTE: these options are used both by Getopt::Long for command-line parsing
# in single user move move, and also set by hand when in --jobserver mode,
# and the jobserver gives us directions, including whether or not users
# are prelocked, need to be source-deleted, verified, etc, etc, etc.
my $opt_del = 0;
my $opt_destdel = 0;
my $opt_verbose = 1;
my $opt_movemaster = 0;
my $opt_prelocked = 0;
my $opt_expungedel = 0;
my $opt_earlyexpunge = 0;
my $opt_ignorebit = 0;
my $opt_verify = 0;
my $opt_help = 0;
my $opt_jobserver = "";

abortWithUsage() unless
    GetOptions('delete' => \$opt_del, # from source
               'destdelete' => \$opt_destdel, # from dest (if exists, before moving)
               'verbose=i' => \$opt_verbose,
               'movemaster|mm' => \$opt_movemaster, # use separate dedicated source
               'prelocked' => \$opt_prelocked, # don't do own locking; master does (harness, ljumover)
               'expungedel' => \$opt_expungedel, # mark as expunged if possible (+del to delete)
               'earlyexpunge' => \$opt_earlyexpunge, # expunge without delay
               'ignorebit' => \$opt_ignorebit, # ignore move in progress bit cap (force)
               'verify' => \$opt_verify,  # slow verification pass (just for debug)
               'jobserver=s' => \$opt_jobserver,
               'help' => \$opt_help,
               );
my $optv = $opt_verbose;

my $dbo;  # original cluster db handle.  (may be a movemaster (a slave))
my $dboa; # the actual master handle, which we delete from if deleting from source

abortWithUsage() if $opt_help;

if ($opt_jobserver) {
    multiMove();
} else {
    singleMove();
}

sub multiMove {
    # the job server can keep giving us new jobs to move (or a stop command)
    # over and over, so we avoid perl exec times
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

    my $sock;
  ITER:
    while (1) {
        if ($sock && $sock->connected) {
            my $pipe = 0;
            local $SIG{PIPE} = sub { $pipe = 1; };

            LJ::start_request();
            my $dbh = get_validated_role_dbh("master");
            unless ($dbh) {
                print "  master db unavailable\n";
                sleep 2;
                next ITER;
            }

            my $rv = $sock->write("get_job\r\n");

            if ($pipe || ! $rv) {
                $sock = undef;
                sleep 1;
                next ITER;
            }
            my $line = <$sock>;
            unless ($line) {
                $sock = undef;
                sleep 1;
                next ITER;
            }

            if ($line =~ /^OK IDLE/) {
                print "Idling.\n";
                sleep 5;
                next ITER;
            } elsif ($line =~ /^OK JOB (\d+):(\d+):(\d+)\s+([\d.]+)(?:\s+([\w= ]+))?\r?\n/) {
                my ($uid, $srcid, $dstid, $locktime) = ($1, $2, $3, $4);
                my $opts = parseOpts($5);

                print "Got a job: $uid:$srcid:$dstid, locked for=$locktime, opts: [",
                  join(", ", map { "$_=$opts->{$_}" } grep { $opts->{$_} } keys %$opts),
                "]\n";

                my $u = LJ::load_userid($uid, "force");

                next ITER unless $u;
                next ITER unless $u->{clusterid} == $srcid;

                my $verify = sub {
                    my $pipe = 0;
                    local $SIG{PIPE} = sub { $pipe = 1; };
                    my $rv = $sock->write("finish $uid:$srcid:$dstid\r\n");
                    return 0 unless $rv;
                    my $res = <$sock>;
                    return $res =~ /^OK/ ? 1 : 0;
                };

                # If the user is supposed to be prelocked, but the lock didn't
                # happen more than 3 seconds ago, wait until it has time to
                # "settle" and then move the user
                if ( $opts->{prelocked} && $locktime < 3 ) {
                    sleep 3 - $locktime;
                }

                my $rv = eval { moveUser($dbh, $u, $dstid, $verify, $opts); };
                if ($rv) {
                    print "moveUser($u->{user}/$u->{userid}) = 1\n";
                } else {
                    print "moveUser($u->{user}/$u->{userid}) = fail: $@\n";
                }
                LJ::end_request();
                LJ::DB::disconnect_dbs();  # end_request could do this, but we want to force it
            } else {
                die "Unknown response from server: $line\n";
            }
        } else {
            print "Need job server sock...\n";
            $sock = IO::Socket::INET->new(PeerAddr => $opt_jobserver,
                                          Proto    => 'tcp', );
            unless ($sock) {
                print "  failed.\n";
                sleep 1;
                next ITER;
            }
            my $ready = <$sock>;
            if ($ready =~ /Ready/) {
                print "Connected.\n";
            } else {
                print "Bogus greeting.\n";
                $sock = undef;
                sleep 1;
                next ITER;
            }
        }

    }
}

### Parse options from job specs into a hashref
sub parseOpts {
    my $raw = shift || "";
    my $opts = {};

    while ( $raw =~ m{\s*(\w+)=(\w+)}g ) {
        $opts->{ $1 } = $2;
    }

    foreach my $opt (qw(del destdel movemaster prelocked
                        expungedel earlyexpunge ignorebit verify)) {
        next if defined $opts->{$opt};
        $opts->{$opt} = eval "\$opt_$opt";
    }

    # Have the same delete behavior despite of how the input delete parameter is specified: by 'delete=1' or by 'del=1'
    $opts->{del} = $opts->{'delete'} if defined $opts->{'delete'} and not $opts->{del};

    # Forbid use of earlyexpunge except on dev instances
    die "Can't use --earlyexpunge on production servers.\n"
        if $opts->{earlyexpunge} && !$LJ::IS_DEV_SERVER;

    return $opts;
}


sub singleMove {
    my $user = shift @ARGV;
    my $dclust = shift @ARGV;
    $dclust = 0 if !defined $dclust && $opt_expungedel;

    # check arguments
    abortWithUsage() unless defined $user && defined $dclust;

    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

    $user = LJ::canonical_username($user);
    abortWithUsage("Invalid username") unless length($user);

    my $dbh = get_validated_role_dbh("master");
    die "No master db available.\n" unless $dbh;

    my $u = LJ::load_user($user, "force");

    my $opts = parseOpts("");  # gets command-line opts
    my $rv = eval { moveUser($dbh, $u, $dclust, undef, $opts); };

    if ($rv) {
        print "Moved '$user' to cluster $dclust.\n";
        exit 0;
    }
    if ($@) {
        die "Failed to move '$user' to cluster $dclust: $@\n";
    }

    print "ERROR: move failed.\n";
    exit 1;
}

sub get_validated_cluster_dbh {
    my $arg = shift;

    my $clusterid = $arg;
    if (LJ::isu($arg)) {
        $clusterid = $arg->clusterid;
    }

    # revalidate any db that is found in cache
    $LJ::DBIRole->clear_req_cache;

    # get the destination DB handle, with a long timeout
    my $dbch = LJ::get_cluster_master({raw=>1}, $clusterid);
    die "Undefined or down cluster \#$clusterid\n" unless $dbch;

    # make sure any error is a fatal error.  no silent mistakes.
    $dbch->{'RaiseError'} = 1;

    $dbch->do("SET wait_timeout=28800");

    return $dbch;
}

sub get_validated_role_dbh {
    my $role = shift;

    # revalidate any db that is found in cache
    $LJ::DBIRole->clear_req_cache;

    my $db = LJ::get_dbh({raw=>1}, $role);
    die "Couldn't get handle for role: $role" unless $db;

    # make sure any error is a fatal error.  no silent mistakes.
    $db->{'RaiseError'} = 1;

    $db->do("SET wait_timeout=28800");

    return $db;
}

# some might call this $dboa
sub get_definitive_source_dbh {
    my $u = shift;

    # the actual master handle, which we delete from if deleting from source
    my $db = get_validated_cluster_dbh($u);
    die "Can't get source cluster handle.\n" unless $db;

    return $db;
}

# some might call this $dbo
sub get_move_source_dbh {
    my $u = shift;

    # $opt_movemaster comes from GetOpt when this script is called...
    # Generally it's accessed as $opts->{movemaster}, but that's because
    # it's in a hashref to pass to moveUser.  In any case, the definitive
    # value is in $opt_movemaster
    if ($opt_movemaster) {
        # if an a/b cluster, the movemaster (the source for moving) is
        # the opposite side.  if not a/b, then look for a special "movemaster"
        # role for that clusterid
        my $mm_role = "cluster$u->{clusterid}";
        my $ab = lc($LJ::CLUSTER_PAIR_ACTIVE{$u->{clusterid}});
        if ($ab eq "a") {
            $mm_role .= "b";
        } elsif  ($ab eq "b") {
            $mm_role .= "a";
        } else {
            $mm_role .= "movemaster";
        }

        my $db = get_validated_role_dbh($mm_role);

        my $ss = $db->selectrow_hashref("show slave status");
        die "Move master not a slave?" unless $ss;

        return $db;
    }

    # otherwise use the definitive source
    return get_definitive_source_dbh($u);
}

sub moveUser {
    my ($dbh, $u, $dclust, $verify_code, $opts) = @_;
    die "Non-existent db.\n" unless $dbh;
    die "Non-existent user.\n" unless $u && $u->{userid};

    my $user = $u->{user};
    my $userid = $u->{userid};

    # get lock
    die "Failed to get move lock.\n"
        unless $dbh->selectrow_array("SELECT GET_LOCK('moveucluster-$u->{userid}', 5)");

    # we can't move to the same cluster
    my $sclust = $u->{'clusterid'};
    if ($sclust == $dclust) {
        die "User '$user' is already on cluster $dclust\n";
    }

    # we don't support "cluster 0" (the really old format)
    die "This mover tool doesn't support moving from cluster 0.\n" unless $sclust;
    die "Can't move back to legacy cluster 0\n" unless $dclust || $opts->{expungedel};

    # for every DB handle we touch, make a signature of a sorted
    # comma-delimited signature onto this list.  likewise with the
    # list of tables this mover script knows about. if ANY signature
    # in this list isn't identical, we just abort.  perhaps this
    # script wasn't updated, or a long-running mover job wasn't
    # restarted and new tables were added to the schema.
    my @alltables = (@LJ::USER_TABLES, @LJ::USER_TABLES_LOCAL);
    my $mover_sig = join(",", sort @alltables);

    my $get_sig = sub {
        my $hnd = shift;
        return join(",", sort
                    @{ $hnd->selectcol_arrayref("SHOW TABLES") });
    };

    my $global_sig = $get_sig->($dbh);

    my $check_sig = sub {
        my $hnd = shift;
        my $name = shift;

        # no signature checks on expunges
        return if ! $hnd && $opts->{expungedel};

        my $sig = $get_sig->($hnd);

        # special case:  signature can be that of the global
        return if $sig eq $global_sig;

        if ($sig ne $mover_sig) {
            my %sigt = map { $_ => 1 } split(/,/, $sig);
            my @err;
            foreach my $tbl (@alltables) {
                unless ($sigt{$tbl}) {
                    # missing a table the mover knows about
                    push @err, "-$tbl";
                    next;
                }
                delete $sigt{$tbl};
            }
            foreach my $tbl (sort keys %sigt) {
                push @err, "?$tbl";
            }
            if (@err) {
                die "Table signature for $name doesn't match!  Stopping.  [@err]\n";
            }
        }
    };

    # if we want to delete the user, we don't need a destination cluster, so only get
    # one if we have a real valid destination cluster
    my $dbch;
    if ($dclust) {
        $dbch = get_validated_cluster_dbh($dclust);
    }

    # this is okay to call even if ! $dclust above
    $check_sig->($dbch, "dbch(database dst)");

    # get a definitive source handle where deletes should happen in
    # cases of sourcedel, etc
    $dboa = get_definitive_source_dbh($u);
    $check_sig->($dboa, "dboa(database src)");

    # get a source handle to move from, which is not necessarily a
    # definitive copy of the source data... it could just be a
    # movemaster slave
    $dbo = get_move_source_dbh($u);
    $check_sig->($dbo, "dbo(movemaster)");

    # load the info on how we'll move each table.  this might die (if new tables
    # with bizarre layouts are added which this thing can't auto-detect) so want
    # to do it early.
    my $tinfo;   # hashref of $table -> {
                 #   'idx' => $index_name   # which we'll be using to iterate over
                 #   'idxcol' => $col_name  # first part of index
                 #   'cols' => [ $col1, $col2, ]
                 #   'pripos' => $idxcol_pos,   # what field in 'cols' is $col_name
                 #   'verifykey' => $col        # key used in the debug --verify pass
                 # }
    $tinfo = fetchTableInfo();

    # see hack below
    my $prop_icon = LJ::get_prop("talk", "subjecticon");
    my %rows_skipped;  #  $tablename -> $skipped_rows_count

    # find readonly cap class, complain if not found
    my $readonly_bit = undef;
    foreach (keys %LJ::CAP) {
        if ($LJ::CAP{$_}->{'_name'} eq "_moveinprogress" &&
            $LJ::CAP{$_}->{'readonly'} == 1) {
            $readonly_bit = $_;
            last;
        }
    }
    unless (defined $readonly_bit) {
        die "Won't move user without %LJ::CAP capability class named '_moveinprogress' with readonly => 1\n";
    }

    # make sure a move isn't already in progress
    if ($opts->{prelocked}) {
        unless (($u->{'caps'}+0) & (1 << $readonly_bit)) {
            die "User '$user' should have been prelocked.\n";
        }
    } else {
        if (($u->{'caps'}+0) & (1 << $readonly_bit)) {
            die "User '$user' is already in the process of being moved? (cap bit $readonly_bit set)\n"
                unless $opts->{ignorebit};
        }
    }

    if ($opts->{expungedel} && $u->{'statusvis'} eq "D" &&
        ( LJ::mysqldate_to_time($u->{'statusvisdate'}) < time() - 86400*31 || $opts->{earlyexpunge} ) &&
        !$u->is_identity) {

        print "Expunging user '$u->{'user'}'\n";
        $dbh->do("INSERT INTO clustermove (userid, sclust, dclust, timestart, timedone) ".
                 "VALUES (?,?,?,UNIX_TIMESTAMP(),UNIX_TIMESTAMP())", undef,
                 $userid, $sclust, 0);

        $u->update_self( { clusterid => 0,
                           statusvis => 'X',
                           raw => "caps=caps&~(1<<$readonly_bit), statusvisdate=NOW()" } )
            or die "Couldn't update user to expunged";

        # note that we've expunged this user in the "expunged_users" db table
        $dbh->do("REPLACE INTO expunged_users SET userid=?, user=?, expunge_time=UNIX_TIMESTAMP()",
                 undef, $u->{userid}, $u->{user});

        # now delete all content from user cluster for this user
        if ($opts->{del}) {
            print "Deleting expungeable user data...\n" if $optv;

            $u->delete_email_alias;
            $dbh->do("DELETE FROM userinterests WHERE userid = ?", undef, $u->id);
            $dbh->do("DELETE FROM comminterests WHERE userid = ?", undef, $u->id);
            $dbh->do("DELETE FROM syndicated WHERE userid = ?", undef, $u->id);
            $dbh->do("DELETE FROM supportnotify WHERE userid = ?", undef, $u->id);
            $dbh->do("DELETE FROM reluser WHERE userid = ?", undef, $u->id);
            $dbh->do("DELETE FROM wt_edges WHERE from_userid = ?", undef, $u->id);

            # no need for other users to ban this user any more
            while ($dbh->do("DELETE FROM reluser WHERE targetid = ? AND type = 'B' LIMIT 1000", undef, $u->id) > 0) {
                print "  deleted bans from reluser\n" if $optv;
            }

            # now delete from the main tables
            foreach my $table (keys %$tinfo) {
                my $pri = $tinfo->{$table}->{idxcol};
                while ($dboa->do("DELETE FROM $table WHERE $pri=$userid LIMIT 1000") > 0) {
                    print "  deleted from $table\n" if $optv;
                }
            }

            $dboa->do("DELETE FROM clustertrack2 WHERE userid=?", undef, $userid);
        }

        # fire event noting this user was expunged
        if (eval "use LJ::Event::UserExpunged; 1;") {
            LJ::Event::UserExpunged->new($u)->fire;
        } else {
            die "Could not load module LJ::Event::UserExpunged: $@";
        }
        LJ::Hooks::run_hooks('purged_user', $u);

        return 1;
    }

    # if we get to this point we have to enforce that there's a destination cluster, because
    # apparently the user failed the expunge test
    if (!defined $dclust || !defined $dbch) {
        die "User is not eligible for expunging.\n" if $opts->{expungedel};
    }


    # returns state string, with a/b, readonly, and flush states.
    # string looks like:
    #   "src(34)=a,dst(42)=b,readonly(34)=0,readonly(42)=0,src_flushes=32
    # because if:
    #   src a/b changes:  lose readonly lock?
    #   dst a/b changes:  suspect.  did one side crash?  was other side caught up?
    #   read-only changes:  signals maintenance
    #   flush counts change: causes HANDLER on src to lose state and reset
    my $stateString = sub {
        my $post = shift;  # false for before, true for "after", which forces a config reload

        if ($post) {
            LJ::Config->reload;
        }

        my @s;
        push @s, "src($sclust)=" . $LJ::CLUSTER_PAIR_ACTIVE{$sclust};
        push @s, "dst($dclust)=" . $LJ::CLUSTER_PAIR_ACTIVE{$dclust};
        push @s, "readonly($sclust)=" . ($LJ::READONLY_CLUSTER{$sclust} ? 1 : 0);
        push @s, "readonly($dclust)=" . ($LJ::READONLY_CLUSTER{$dclust} ? 1 : 0);

        my $flushes = 0;
        my $sth = $dbo->prepare("SHOW STATUS LIKE '%flush%'");
        $sth->execute;
        while (my $r = $sth->fetchrow_hashref) {
            $flushes += $r->{Value} if $r->{Variable_name} =~ /^Com_flush|Flush_commands$/;
        }
        push @s, "src_flushes=" . $flushes;

        return join(",", @s);
    };

    print "Moving '$u->{'user'}' from cluster $sclust to $dclust\n" if $optv >= 1;
    my $pre_state = $stateString->();

    # mark that we're starting the move
    $dbh->do("INSERT INTO clustermove (userid, sclust, dclust, timestart) ".
             "VALUES (?,?,?,UNIX_TIMESTAMP())", undef, $userid, $sclust, $dclust);
    my $cmid = $dbh->{'mysql_insertid'};

    # set readonly cap bit on user
    unless ( $opts->{prelocked} ||
             $u->update_self( { raw => "caps=caps|(1<<$readonly_bit)" } ) )
    {
        die "Failed to set readonly bit on user: $user\n";
    }
    $dbh->do("SELECT RELEASE_LOCK('moveucluster-$u->{userid}')");

    unless ($opts->{prelocked}) {
        # wait a bit for writes to stop if journal is somewhat active (last week update)
        my $secidle = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()-UNIX_TIMESTAMP(timeupdate) ".
                                            "FROM userusage WHERE userid=$userid");
        if ($secidle) {
            sleep(2) unless $secidle > 86400*7;
            sleep(1) unless $secidle > 86400;
        }
    }

    if ($opts->{movemaster}) {
        my $diff = 999_999;
        my $tolerance = 50_000;
        while ($diff > $tolerance) {
            my $ss = $dbo->selectrow_hashref("show slave status");
            if ($ss->{'Slave_IO_Running'} eq "Yes" && $ss->{'Slave_SQL_Running'} eq "Yes") {
                if ($ss->{'Master_Log_File'} eq $ss->{'Relay_Master_Log_File'}) {
                    $diff = $ss->{'Read_Master_Log_Pos'} - $ss->{'Exec_master_log_pos'};
                    print "  diff: $diff\n" if $optv >= 1;
                    sleep 1 if $diff > $tolerance;
                } else {
                    print "  (Wrong log file):  $ss->{'Relay_Master_Log_File'}($ss->{'Exec_master_log_pos'}) not $ss->{'Master_Log_File'}($ss->{'Read_Master_Log_Pos'})\n" if $optv >= 1;
                }
            } else {
                die "Movemaster slave not running";
            }
        }
    }

    print "Moving away from cluster $sclust\n" if $optv;

    # setup dependencies (we can skip work by not checking a table if we know
    # its dependent table was empty).  then we have to order things so deps get
    # processed first.
    my %was_empty;  # $table -> bool, table was found empty
    my %dep = (
               "logtext2" => "log2",
               "logprop2" => "log2",
               "logsec2" => "log2",
               "talkprop2" => "talk2",
               "talktext2" => "talk2",
               "modblob" => "modlog",
               "sessions_data" => "sessions",
               "memkeyword2" => "memorable2",
               "userpicmap2" => "userpic2",
               "logtagsrecent" => "usertags",
               "logtags" => "usertags",
               "logkwsum" => "usertags",
               );

    # all tables we could be moving.  we need to sort them in
    # order so that we check dependant tables first
    my @tables;
    push @tables, grep { ! $dep{$_} } @alltables;
    push @tables, grep { $dep{$_} } @alltables;

    # these are ephemeral or handled elsewhere
    my %skip_table = (
                      "cmdbuffer" => 1,       # pre-flushed
                      "events" => 1,          # handled by qbufferd (not yet used)
                      "tempanonips" => 1,     # temporary ip storage for spam reports
                      "pendcomments" => 1,    # don't need to copy these
                      "active_user"  => 1,    # don't need to copy these
                      "random_user_set" => 1, # "
                      "dbnotes" => 1,         # No need to handle this, used for database migrations
                     );

    $skip_table{'inviterecv'} = 1 unless $u->is_person; # if not person, skip invites received
    $skip_table{'invitesent'} = 1 unless $u->is_community; # if not community, skip invites sent

    # we had a concern at the time of writing this dependency optization
    # that we might use "log3" and "talk3" tables in the future with the
    # old talktext2/etc tables.  if that happens and we forget about this,
    # this code will trip it up and make us remember:
    if (grep { $_ eq "log3" || $_ eq "talk3" } @tables) {
        die "This script needs updating.\n";
    }

    #
    # NOTE: this is the start of long reads from the largest user tables!
    #
    #    db handles used during this block are:
    #       $dbo  -- validated source cluster handle for reading
    #       $dbch -- validated destination cluster handle
    #

    # check if dest has existing data for this user.  (but only check a few key tables)
    # if anything else happens to have data, we'll just fail later.  but unlikely.
    print "Checking for existing data on target cluster...\n" if $optv > 1;
    foreach my $table (qw(userbio talkleft log2 talk2 sessions userproplite2)) {
        my $ti = $tinfo->{$table} or die "No table info for $table.  Aborting.";

        eval { $dbch->do("HANDLER $table OPEN"); };
        if ($@) {
            die "This mover currently only works on MySQL 4.x and above.\n" .
                $@;
        }

        my $idx = $ti->{idx};
        my $is_there = $dbch->selectrow_array("HANDLER $table READ `$idx` = ($userid) LIMIT 1");
        $dbch->do("HANDLER $table CLOSE");
        next unless $is_there;

        if ($opts->{destdel}) {
            foreach my $table (@tables) {
                # these are ephemeral or handled elsewhere
                next if $skip_table{$table};
                my $ti = $tinfo->{$table} or die "No table info for $table.  Aborting.";
                my $pri = $ti->{idxcol};
                while ($dbch->do("DELETE FROM $table WHERE $pri=$userid LIMIT 500") > 0) {
                    print "  deleted from $table\n" if $optv;
                }
            }
            last;
        } else {
            die "  Existing data on destination cluster\n";
        }
    }

    # start copying from source to dest.
    my $rows = 0;
    my @to_delete;  # array of [ $table, $prikey ]

    foreach my $table (@tables) {
        next if $skip_table{$table};

        # people accounts don't have moderated posts
        next if $u->is_person && ($table eq "modlog" || $table eq "modblob");

        # don't waste time looking at dependent tables with empty parents
        next if $dep{$table} && $was_empty{$dep{$table}};

        my $ti = $tinfo->{$table} or die "No table info for $table.  Aborting.";
        my $idx = $ti->{idx};
        my $idxcol = $ti->{idxcol};
        my $cols = $ti->{cols};
        my $pripos = $ti->{pripos};

        # if we're going to be doing a verify operation later anyway, let's do it
        # now, so we can use the knowledge of rows per table to hint our $batch_size
        my $expected_rows = undef;
        my $expected_remain = undef;  # expected rows remaining (unread)
        my $verifykey = $ti->{verifykey};
        my %pre;

        if ($opts->{verify} && $verifykey) {
            $expected_rows = 0;
            if ($table eq "dudata" || $table eq "ratelog") {
                $expected_rows = $dbo->selectrow_array("SELECT COUNT(*) FROM $table WHERE $idxcol=$userid");
            } else {
                my $sth;
                $sth = $dbo->prepare("SELECT $verifykey FROM $table WHERE $idxcol=$userid");
                $sth->execute;
                while (my @ar = $sth->fetchrow_array) {
                    $_ = join(",",@ar);
                    $pre{$_} = 1;
                    $expected_rows++;
                }
            }

            # no need to continue with tables that don't have any data
            unless ($expected_rows) {
                $was_empty{$table} = 1;
                next;
            }

            $expected_remain = $expected_rows;
        }

        eval { $dbo->do("HANDLER $table OPEN"); };
        if ($@) {
            die "This mover currently only works on MySQL 4.x and above.\n".
                $@;
        }

        my $tct = 0;            # total rows read for this table so far.
        my $hit_otheruser = 0;  # bool, set to true when we encounter data from a different userid
        my $batch_size;         # how big of a LIMIT we'll be doing
        my $ct = 0;             # rows read in latest batch
        my $did_start = 0;      # bool, if process has started yet (used to enter loop, and control initial HANDLER commands)
        my $pushed_delete = 0;  # bool, if we've pushed this table on the delete list (once we find it has something)

        my $sqlins = "";
        my $sqlvals = 0;
        my $flush = sub {
            return unless $sqlins;
            print "# Flushing $table ($sqlvals recs, ", length($sqlins), " bytes)\n" if $optv;
            $dbch->do($sqlins);
            $sqlins = "";
            $sqlvals = 0;
        };

        my $insert = sub {
            my $r = shift;

            # there was an old bug where we'd populate in the database
            # the choice of "none" for comment subject icon, instead of
            # just storing nothing.  this hack prevents migrating those.
            if ($table  eq "talkprop2" &&
                $r->[2] == $prop_icon->{id} &&
                $r->[3] eq "none") {
                $rows_skipped{"talkprop2"}++;
                return;
            }

            # now that we know it has something to delete (many tables are empty for users)
            unless ($pushed_delete++) {
                push @to_delete, [ $table, $idxcol ];
            }

            if ($sqlins) {
                $sqlins .= ", ";
            } else {
                $sqlins = "INSERT INTO $table (" . join(', ', @{$cols}) . ") VALUES ";
            }
            $sqlins .= "(" . join(", ", map { $dbo->quote($_) } @$r) . ")";

            $sqlvals++;
            $flush->() if $sqlvals > 5000 || length($sqlins) > 800_000;
        };

        # let tables perform extra processing on the $r before it's
        # sent off for inserting.
        my $magic;

        # we know how to compress these two tables (currently the only two)
        if ($table eq "logtext2" || $table eq "talktext2") {
            $magic = sub {
                my $r = shift;
                return unless length($r->[3]) > 200;
                LJ::text_compress(\$r->[3]);
            };
        }

        # calculate the biggest batch size that can reasonably fit in memory
        my $max_batch = 10000;
        $max_batch = 1000 if $table eq "logtext2" || $table eq "talktext2";

        while (! $hit_otheruser && ($ct == $batch_size || ! $did_start)) {
            my $qry;
            if ($did_start) {
                # once we've done the initial big read, we want to walk slowly, because
                # a LIMIT of 1000 will read 1000 rows, regardless, which may be 995
                # seeks into somebody else's journal that we don't care about.
                # on the other hand, if we did a --verify check above, we have a good
                # idea what to expect still, so we'll use that instead of just 25 rows.
                $batch_size = $expected_remain > 0 ? $expected_remain + 1 : 25;
                if ($batch_size > $max_batch) { $batch_size = $max_batch; }
                $expected_remain -= $batch_size;

                $qry = "HANDLER $table READ `$idx` NEXT LIMIT $batch_size";
            } else {
                # when we're first starting out, though, let's LIMIT as high as possible,
                # since MySQL (with InnoDB only?) will only return rows matching the primary key,
                # so we'll try as big as possible.  but not with myisam -- need to start
                # small there too, unless we have a guess at the number of rows remaining.

                my $src_is_innodb = 0;  # FIXME: detect this.  but first verify HANDLER differences.
                if ($src_is_innodb) {
                    $batch_size = $max_batch;
                } else {
                    # MyISAM's HANDLER behavior seems to be different.
                    # it always returns batch_size, so we keep it
                    # small to avoid seeks, even on the first query
                    # (where InnoDB differs and stops when primary key
                    # doesn't match)
                    $batch_size = 25;
                    if ($table eq "clustertrack2" || $table eq "userbio") {
                        # we know these only have 1 row, so 2 will be enough to show
                        # in one pass that we're done.
                        $batch_size = 2;
                    } elsif (defined $expected_rows) {
                        # if we know how many rows remain, let's try to use that (+1 to stop it)
                        $batch_size = $expected_rows + 1;
                        if ($batch_size > $max_batch) { $batch_size = $max_batch; }
                        $expected_remain -= $batch_size;
                    }
                }

                $qry = "HANDLER $table READ `$idx` = ($userid) LIMIT $batch_size";
                $did_start = 1;
            }

            my $sth = $dbo->prepare($qry);
            $sth->execute;

            $ct = 0;
            while (my $r = $sth->fetchrow_arrayref) {
                if ($r->[$pripos] != $userid) {
                    $hit_otheruser = 1;
                    last;
                }
                $magic->($r) if $magic;
                $insert->($r);
                $tct++;
                $ct++;
            }
        }
        $flush->();

        $dbo->do("HANDLER $table CLOSE");

        # verify the important tables, even if --verify is off.
        if (! $opts->{verify} && $table =~ /^(talk|log)(2|text2)$/) {
            my $dblcheck = $dbo->selectrow_array("SELECT COUNT(*) FROM $table WHERE $idxcol=$userid");
            die "# Expecting: $dblcheck, but got $tct\n" unless $dblcheck == $tct;
        }

        if ($opts->{verify} && $verifykey) {
            if ($table eq "dudata" || $table eq "ratelog") {
                print "# Verifying $table on size\n";
                my $post = $dbch->selectrow_array("SELECT COUNT(*) FROM $table WHERE $idxcol=$userid");
                die "Moved sized is smaller" if $post < $expected_rows;
            } else {
                print "# Verifying $table on key $verifykey\n";
                my %post;
                my $sth;

                $sth = $dbch->prepare("SELECT $verifykey FROM $table WHERE $idxcol=$userid");
                $sth->execute;
                while (my @ar = $sth->fetchrow_array) {
                    $_ = join(",",@ar);
                    unless (delete $pre{$_}) {
                        die "Mystery row showed up in $table: uid=$userid, $verifykey=$_";
                    }
                }
                my $count = scalar keys %pre;
                die "Rows not moved for uid=$userid, table=$table.  unmoved count = $count"
                    if $count && $count != $rows_skipped{$table};
            }
        }

        $was_empty{$table} = 1 unless $tct;
        $rows += $tct;
    }

    print "# Rows done for '$user': $rows\n" if $optv;

    #
    # NOTE:  we've just finished moving a bunch of rows form $dbo to $dbch,
    #        which could have potentially been a very slow process since the
    #        time for the copy is directly proportional to the data a user
    #        had to move.  We'll revalidate handles now to ensure that they
    #        haven't died due to (insert eleventy billion circumstances here).
    #

    $dbh  = get_validated_role_dbh("master");
    $dboa = get_definitive_source_dbh($u);
    $dbo  = get_move_source_dbh($u);

    # db handles should be good to go now

    my $post_state = $stateString->("post");
    if ($post_state ne $pre_state) {
        die "Move aborted due to state change during move: Before: [$pre_state], After: [$post_state]\n";
    }
    $check_sig->($dbo, "dbo(aftermove)");

    my $unlocked;
    if (! $verify_code || $verify_code->()) {
        # unset readonly and move to new cluster in one update
        $unlocked = $u->update_self( { clusterid => $dclust, raw => "caps=caps&~(1<<$readonly_bit)" } );
        print "Moved.\n" if $optv;
    } else {
        # job server went away or we don't have permission to flip the clusterid attribute
        # so just unlock them
        $unlocked = $u->update_self( { raw => "caps=caps&~(1<<$readonly_bit)" } );
        die "Job server said no.\n";
    }

    # delete from the index of who's read-only.  if this fails we don't really care
    # (not all sites might have this table anyway) because it's not used by anything
    # except the readonly-cleaner which can deal with all cases.
    if ($unlocked) {
        eval {
            $dbh->do("DELETE FROM readonly_user WHERE userid=?", undef, $userid);
        };
    }

    # delete from source cluster
    if ($opts->{del}) {
        print "Deleting from source cluster...\n" if $optv;
        foreach my $td (@to_delete) {
            my ($table, $pri) = @$td;
            while ($dboa->do("DELETE FROM $table WHERE $pri=$userid LIMIT 1000") > 0) {
                print "  deleted from $table\n" if $optv;
            }
        }
    } else {
        # at minimum, we delete the clustertrack2 row so it doesn't get
        # included in a future ljumover.pl query from that cluster.
        $dboa->do("DELETE FROM clustertrack2 WHERE userid=$userid");
    }

    $dbh->do("UPDATE clustermove SET sdeleted=?, timedone=UNIX_TIMESTAMP() ".
             "WHERE cmid=?", undef, $opts->{del} ? 1 : 0, $cmid);

    return 1;
}

sub fetchTableInfo
{
    my @tables = (@LJ::USER_TABLES, @LJ::USER_TABLES_LOCAL);
    my $memkey = "moveucluster:" . Digest::MD5::md5_hex(join(",",@tables));
    my $tinfo = LJ::MemCache::get($memkey) || {};
    foreach my $table (@tables) {
        next if grep { $_ eq $table } qw(events cmdbuffer pendcomments active_user random_user_set dbnotes);
        next if $tinfo->{$table};  # no need to load this one

        # find the index we'll use
        my $idx;     # the index name we'll be using
        my $idxcol;  # "userid" or "journalid"

        my $sth = $dbo->prepare("SHOW INDEX FROM $table");
        $sth->execute;
        my @pris;

        my %userid_primary_columns = map { $_ => 1 } qw( journalid userid commid rcptid );
        while (my $r = $sth->fetchrow_hashref) {
            push @pris, $r->{'Column_name'} if $r->{'Key_name'} eq "PRIMARY";
            next unless $r->{'Seq_in_index'} == 1;
            next if $idx;
            if ( $userid_primary_columns{$r->{'Column_name'}} ) {
                $idx = $r->{'Key_name'};
                $idxcol = $r->{'Column_name'};
            }
        }

        shift @pris if @pris && $userid_primary_columns{$pris[0]};
        my $verifykey = join(",", @pris);

        die "can't find index for table $table\n" unless $idx;

        $tinfo->{$table}{idx} = $idx;
        $tinfo->{$table}{idxcol} = $idxcol;
        $tinfo->{$table}{verifykey} = $verifykey;

        my $cols = $tinfo->{$table}{cols} = [];
        my $colnum = 0;
        $sth = $dboa->prepare("DESCRIBE $table");
        $sth->execute;
        while (my $r = $sth->fetchrow_hashref) {
            push @$cols, $r->{'Field'};
            if ($r->{'Field'} eq $idxcol) {
                $tinfo->{$table}{pripos} = $colnum;
            }
            $colnum++;
        }
    }
    LJ::MemCache::set($memkey, $tinfo, 90);  # not for long, but quick enough to speed a series of moves
    return $tinfo;
}

### FUNCTION: abortWithUsage( $message )
### Abort the program showing usage message.
sub abortWithUsage {
    my $msg = join '', @_;

    if ( $msg ) {
        pod2usage( -verbose => 1, -exitval => 1, -message => "$msg" );
    } else {
        pod2usage( -verbose => 1, -exitval => 1 );
    }
}

