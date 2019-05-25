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
#

package DBI::Role;

use 5.006;
use strict;
use warnings;

BEGIN {
    $DBI::Role::HAVE_HIRES = eval "use Time::HiRes (); 1;";
}

our $VERSION = '1.00';

# $self contains:
#
#  DBINFO --- hashref.  keys = scalar roles, one of which must be 'master'.
#             values contain DSN info, and 'role' => { 'role' => weight, 'role2' => weight }
#
#  DEFAULT_DB -- scalar string.  default db name if none in DSN hashref in DBINFO
#
#  DBREQCACHE -- cleared by clear_req_cache() on each request.
#                fdsn -> dbh
#
#  DBCACHE -- role -> fdsn, or
#             fdsn -> dbh
#
#  DBCACHE_UNTIL -- role -> unixtime
#
#  DB_USED_AT -- fdsn -> unixtime
#
#  DB_DEAD_UNTIL -- fdsn -> unixtime
#
#  TIME_CHECK -- if true, time between localhost and db are checked every TIME_CHECK
#                seconds
#
#  TIME_REPORT -- coderef to pass dsn and dbtime to after a TIME_CHECK occurence
#

sub new {
    my ( $class, $args ) = @_;
    my $self = {};
    $self->{'DBINFO'}         = $args->{'sources'};
    $self->{'TIMEOUT'}        = $args->{'timeout'};
    $self->{'DEFAULT_DB'}     = $args->{'default_db'};
    $self->{'TIME_CHECK'}     = $args->{'time_check'};
    $self->{'TIME_LASTCHECK'} = {};                       # dsn -> last check time
    $self->{'TIME_REPORT'}    = $args->{'time_report'};
    bless $self, ref $class || $class;
    return $self;
}

sub set_sources {
    my ( $self, $newval ) = @_;
    $self->{'DBINFO'} = $newval;
    $self;
}

sub clear_req_cache {
    my $self = shift;
    $self->{'DBREQCACHE'} = {};
}

sub disconnect_all {
    my ( $self, $opts ) = @_;
    my %except;

    if (   $opts
        && $opts->{except}
        && ref $opts->{except} eq 'ARRAY' )
    {
        $except{$_} = 1 foreach @{ $opts->{except} };
    }

    foreach my $cache (qw(DBREQCACHE DBCACHE)) {
        next unless ref $self->{$cache} eq "HASH";
        foreach my $key ( keys %{ $self->{$cache} } ) {
            next if $except{$key};
            my $v = $self->{$cache}->{$key};
            next unless ref $v eq "DBI::db";
            $v->disconnect;
            delete $self->{$cache}->{$key};
        }
    }
    $self->{'DBCACHE'}    = {};
    $self->{'DBREQCACHE'} = {};
}

sub same_cached_handle {
    my $self = shift;
    my ( $role_a, $role_b ) = @_;
    return
           defined $self->{'DBCACHE'}->{$role_a}
        && defined $self->{'DBCACHE'}->{$role_b}
        && $self->{'DBCACHE'}->{$role_a} eq $self->{'DBCACHE'}->{$role_b};
}

sub flush_cache {
    my $self = shift;
    foreach ( keys %{ $self->{'DBCACHE'} } ) {
        my $v = $self->{'DBCACHE'}->{$_};
        next unless ref $v;
        $v->disconnect;
    }
    $self->{'DBCACHE'}    = {};
    $self->{'DBREQCACHE'} = {};
}

# old interface.  does nothing now.
sub trigger_weight_reload {
    my $self = shift;
    return $self;
}

sub use_diff_db {
    my $self = shift;
    my ( $role1, $role2 ) = @_;

    return 0 if $role1 eq $role2;

    # this is implied:  (makes logic below more readable by forcing it)
    $self->{'DBINFO'}->{'master'}->{'role'}->{'master'} = 1;

    foreach ( keys %{ $self->{'DBINFO'} } ) {
        next if /^_/;
        next unless ref $self->{'DBINFO'}->{$_} eq "HASH";
        if (   $self->{'DBINFO'}->{$_}->{'role'}->{$role1}
            && $self->{'DBINFO'}->{$_}->{'role'}->{$role2} )
        {
            return 0;
        }
    }
    return 1;
}

sub get_dbh {
    my $self = shift;
    my $opts = ref $_[0] eq "HASH" ? shift : {};

    my @roles = @_;
    my $role  = shift @roles;
    return undef unless $role;

    my $now = time();

    # if 'nocache' flag is passed, clear caches now so we won't return
    # a cached database handle later
    $self->clear_req_cache if $opts->{'nocache'};

    # otherwise, see if we have a role -> full DSN mapping already
    my ( $fdsn, $dbh );
    if ( $role eq "master" ) {
        $fdsn = make_dbh_fdsn( $self, $self->{'DBINFO'}->{'master'} );
    }
    else {
        if ( $self->{'DBCACHE'}->{$role} && !$opts->{'unshared'} ) {
            $fdsn = $self->{'DBCACHE'}->{$role};
            if ( $now > $self->{'DBCACHE_UNTIL'}->{$role} ) {

                # this role -> DSN mapping is too old.  invalidate,
                # and while we're at it, clean up any connections we have
                # that are too idle.
                undef $fdsn;

                foreach ( keys %{ $self->{'DB_USED_AT'} } ) {
                    next if $self->{'DB_USED_AT'}->{$_} > $now - 60;
                    delete $self->{'DB_USED_AT'}->{$_};
                    delete $self->{'DBCACHE'}->{$_};
                }
            }
        }
    }

    if ($fdsn) {
        $dbh = $self->get_dbh_conn( $opts, $fdsn, $role );
        return $dbh if $dbh;
        delete $self->{'DBCACHE'}->{$role};    # guess it was bogus
    }
    return undef if $role eq "master";         # no hope now

    # time to randomly weightedly select one.
    my @applicable;
    my $total_weight;
    foreach ( keys %{ $self->{'DBINFO'} } ) {
        next if /^_/;
        next unless ref $self->{'DBINFO'}->{$_} eq "HASH";
        my $weight = $self->{'DBINFO'}->{$_}->{'role'}->{$role};
        next unless $weight;
        push @applicable, [ $self->{'DBINFO'}->{$_}, $weight ];
        $total_weight += $weight;
    }

    while (@applicable) {
        my $rand = rand($total_weight);
        my ( $i, $t ) = ( 0, 0 );
        for ( ; $i < @applicable ; $i++ ) {
            $t += $applicable[$i]->[1];
            last if $t > $rand;
        }
        my $fdsn = make_dbh_fdsn( $self, $applicable[$i]->[0] );
        $dbh = $self->get_dbh_conn( $opts, $fdsn );
        if ($dbh) {
            $self->{'DBCACHE'}->{$role}       = $fdsn;
            $self->{'DBCACHE_UNTIL'}->{$role} = $now + 5 + int( rand(10) );
            return $dbh;
        }

        # otherwise, discard that one.
        $total_weight -= $applicable[$i]->[1];
        splice( @applicable, $i, 1 );
    }

    # try others
    return get_dbh( $self, $opts, @roles );
}

sub make_dbh_fdsn {
    my $self = shift;
    my $db   = shift;    # hashref with DSN info
    return $db->{'_fdsn'} if $db->{'_fdsn'};    # already made?

    my $fdsn = "DBI:mysql";    # join("|",$dsn,$user,$pass) (because no refs as hash keys)
    $db->{'dbname'} ||= $self->{'DEFAULT_DB'} if $self->{'DEFAULT_DB'};
    $fdsn .= ":$db->{'dbname'}";
    $fdsn .= ";host=$db->{'host'}" if $db->{'host'};
    $fdsn .= ";port=$db->{'port'}" if $db->{'port'};
    $fdsn .= ";mysql_socket=$db->{'sock'}" if $db->{'sock'};
    $fdsn .= "|$db->{'user'}|$db->{'pass'}";

    $db->{'_fdsn'} = $fdsn;
    return $fdsn;
}

sub get_dbh_conn {
    my $self = shift;
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    my $fdsn = shift;
    my $role = shift;                              # optional.
    my $now  = time();

    my $retdb = sub {
        my $db = shift;
        $self->{'DBREQCACHE'}->{$fdsn} = $db;
        $self->{'DB_USED_AT'}->{$fdsn} = $now;
        return $db;
    };

    # have we already created or verified a handle this request for this DSN?
    return $retdb->( $self->{'DBREQCACHE'}->{$fdsn} )
        if $self->{'DBREQCACHE'}->{$fdsn} && !$opts->{'unshared'};

    # check to see if we recently tried to connect to that dead server
    return undef if $self->{'DB_DEAD_UNTIL'}->{$fdsn} && $now < $self->{'DB_DEAD_UNTIL'}->{$fdsn};

    # if not, we'll try to find one we used sometime in this process lifetime
    my $dbh = $self->{'DBCACHE'}->{$fdsn};

    # if it exists, verify it's still alive and return it.  (but not
    # if we're wanting an unshared connection)
    if ( $dbh && !$opts->{'unshared'} ) {
        return $retdb->($dbh) unless connection_bad( $dbh, $opts );
        undef $dbh;
        undef $self->{'DBCACHE'}->{$fdsn};
    }

    # time to make one!
    my ( $dsn, $user, $pass ) = split( /\|/, $fdsn );
    my $timeout = $self->{'TIMEOUT'} || 2;
    if ( ref $timeout eq "CODE" ) {
        $timeout = $timeout->( $dsn, $user, $pass, $role );
    }
    $dsn .= ";mysql_connect_timeout=$timeout" if $timeout;

    my $loop  = 1;
    my $tries = $DBI::Role::HAVE_HIRES ? 8 : 2;
    while ($loop) {
        $loop = 0;

        my $connection_opts;
        if ( $opts->{'connection_opts'} ) {
            $connection_opts = $opts->{'connection_opts'};
        }
        else {
            $connection_opts = {
                PrintError => 0,
                AutoCommit => 1,
            };
        }

        $dbh = DBI->connect( $dsn, $user, $pass, $connection_opts );

        $dbh->{private_role} = $role if $dbh;

        # if max connections, try again shortly.
        if ( !$dbh && $DBI::err == 1040 && $tries ) {
            $tries--;
            $loop = 1;
            if ($DBI::Role::HAVE_HIRES) {
                Time::HiRes::usleep(250_000);
            }
            else {
                sleep 1;
            }
            next;
        }

        # if lost connection to server (had prior connection?) error
        # (MySQL server has gone away)
        if ( !$dbh && $DBI::err == 2013 && $tries ) {
            $tries--;
            $loop = 1;
            next;
        }
    }

    my $DBI_err = $DBI::err || 0;
    if ( $DBI_err && $DBI::Role::VERBOSE ) {
        $role ||= "";
        my $str = $DBI::errstr || "(no DBI::errstr)";
        print STDERR
            "DBI::Role connect error $DBI_err for role '$role': dsn='$dsn', user='$user': $str\n";
    }

    # check replication/busy processes... see if we should not use
    # this one
    undef $dbh if connection_bad( $dbh, $opts );

    # mark server as dead if dead.  won't try to reconnect again for 5 seconds.
    if ($dbh) {

        # default wait_timeout is 60 seconds.
        $dbh->do("SET SESSION wait_timeout = 600");

        # if this is an unshared connection, we don't want to put it
        # in the cache for somebody else to use later. (which happens below)
        return $dbh if $opts->{'unshared'};

        $self->{'DB_USED_AT'}->{$fdsn} = $now;
        if ( $self->{'TIME_CHECK'} && ref $self->{'TIME_REPORT'} eq "CODE" ) {
            my $now = time();
            $self->{'TIME_LASTCHECK'}->{$dsn} ||= 0;    # avoid warnings
            if ( $self->{'TIME_LASTCHECK'}->{$dsn} < $now - $self->{'TIME_CHECK'} ) {
                $self->{'TIME_LASTCHECK'}->{$dsn} = $now;
                my $db_time = $dbh->selectrow_array("SELECT UNIX_TIMESTAMP()");
                $self->{'TIME_REPORT'}->( $dsn, $db_time, $now );
            }
        }
    }
    else {
        # mark the database as dead for a bit, unless it was just because of max connections
        $self->{'DB_DEAD_UNTIL'}->{$fdsn} = $now + 5
            unless $DBI_err == 1040 || $DBI_err == 2013;

    }

    return $self->{'DBREQCACHE'}->{$fdsn} = $self->{'DBCACHE'}->{$fdsn} = $dbh;
}

sub connection_bad {
    my ( $dbh, $opts ) = @_;

    return 1 unless $dbh;

    my $ss = eval { $dbh->selectrow_hashref("SHOW SLAVE STATUS"); };

    # if there was an error, and it wasn't a permission problem (1227)
    # then treat this connection as bogus
    if ( $dbh->err && $dbh->err != 1227 ) {
        return 1;
    }

    # connection is good if $ss is undef (not a slave)
    return 0 unless $ss;

    # otherwise, it's okay if not MySQL 4
    return 0 if !$ss->{'Master_Log_File'} || !$ss->{'Relay_Master_Log_File'};

    # all good if within 100 k
    if ( $opts->{'max_repl_lag'} ) {

        # MySQL 4.0 uses Exec_master_log_pos, 5.0 uses Exec_Master_Log_Pos
        my $emlp = $ss->{'Exec_master_log_pos'} || $ss->{'Exec_Master_Log_Pos'} || undef;
        return 0
            if $ss->{'Master_Log_File'} eq $ss->{'Relay_Master_Log_File'}
            && ( $ss->{'Read_Master_Log_Pos'} - $emlp ) < $opts->{'max_repl_lag'};

        # guess we're behind
        return 1;
    }
    else {
        # default to assuming it's good
        return 0;
    }
}

1;
__END__

=head1 NAME

DBI::Role - Get DBI cached handles by role, with weighting & failover.

=head1 SYNOPSIS

  use DBI::Role;
  my $DBIRole = new DBI::Role {
    'sources' => \%DBINFO,
    'default_db' => "somedbname", # opt.
  };
  my $dbh = $DBIRole->get_dbh("master");

=head1 DESCRIPTION

To be written.

=head2 EXPORT

None by default.

=head1 AUTHOR

Brad Fitzparick, E<lt>brad@danga.comE<gt>

=head1 SEE ALSO

L<DBI>.

