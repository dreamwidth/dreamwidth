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
#
# Monitoring uses the application login from %LJ::DBINFO on each server.
# On MySQL, it needs REPLICATION CLIENT for replication and binary log status.
# PROCESS is needed for server-wide connection counts; without it, SHOW
# PROCESSLIST only shows the configured login's own connections.

use strict;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use LJ::DB;

use DBI;
use Getopt::Long;
use Time::HiRes ();

my ( $help,            $opt_err,     $opt_all )   = ( 0, 0,     0 );
my ( $opt_checkreport, $opt_verbose, $opt_rates ) = ( 0, undef, undef );

exit 1
    unless GetOptions(
    'help'        => \$help,
    'checkreport' => \$opt_checkreport,
    'rates'       => \$opt_rates,
    'onlyerrors'  => \$opt_err,
    'all'         => \$opt_all,
    'verbose'     => \$opt_verbose,
    );

if ($help) {
    die(      "Usage: dbcheck.pl [opts] [[cmd] args...]\n"
            . "    --all           Check all hosts, even those with no weight assigned.\n"
            . "    --help          Get this help\n"
            . "    --checkreport   Show tables that haven't been checked in a while.\n"
            . "    --onlyerrors    Will be silent unless there are errors.\n" . "\n"
            . "Commands\n"
            . "   (none)           Shows replication status.\n"
            . "   queries <host>   Shows active queries on host, sorted by running time.\n\n"
            . "MySQL privileges for the %LJ::DBINFO login on each server:\n"
            . "   REPLICATION CLIENT is required for replication and binary log checks.\n"
            . "   PROCESS is required to see all connections in SHOW PROCESSLIST.\n"
            . "   Without PROCESS, connection counts only cover that login's own connections.\n" );
}

# every database server the site connects to is listed in %LJ::DBINFO, along
# with the roles it serves and their weights; the entry named 'master' is the
# global master (DBI::Role implies its master role)
my %dbinfo;        # name -> DBINFO hashref
my %rolebyname;    # name -> rolename -> weight

foreach my $name ( keys %LJ::DBINFO ) {
    next if $name =~ /^_/;
    my $src = $LJ::DBINFO{$name};
    next unless ref $src eq "HASH";

    $dbinfo{$name} = $src;
    my %weights = %{ $src->{role} || {} };
    $weights{master} = 1 if $name eq "master";
    $rolebyname{$name} = \%weights;
}
die "No master database is configured in %LJ::DBINFO\n" unless $dbinfo{master};

my %handle;    # name -> $db
my $get_handle = sub {
    my $name = shift;
    return $handle{$name} if exists $handle{$name};
    debug("Connecting to '$name' ...");
    $LJ::DB_TIMEOUT = 1;
    my $db = $LJ::DBIRole->get_dbh_conn( { unshared => 1 },
        $LJ::DBIRole->make_dbh_fdsn( $dbinfo{$name} ) );
    if ($db) {
        $db->{ShowErrorStatement} = 1;
        $db->{HandleError}        = sub { die "$name: $_[0]\n" };
    }
    else {
        debug("  ($name: failed to connect)");
    }
    return $handle{$name} = $db;
};

my %server_id;
my $master_of = sub {
    my $ss         = shift;
    my @candidates = sort keys %dbinfo;
    if ( my $master_id = $ss->{master_server_id} ) {
        my @matches = grep { ( $server_id{$_} || 0 ) == $master_id } @candidates;
        return $matches[0] if @matches == 1;
        @candidates = @matches ? @matches : grep { !$server_id{$_} } @candidates;
    }

    return "" unless $ss->{master_host};
    foreach my $name (@candidates) {
        my $src = $dbinfo{$name};
        next unless lc( $src->{host} // "" ) eq lc( $ss->{master_host} );
        next unless ( $src->{port} || 3306 ) == ( $ss->{master_port} || 3306 );
        return $name;
    }
    return "";
};

my @errors;
my %master_status;    # name -> [ $file, $pos ]

my $check_master_status = sub {
    my $name = shift;
    die "Bogus DB: $name" unless $dbinfo{$name};
    my $db = $get_handle->($name);
    return unless $db;

    my ( $masterfile, $masterpos ) = $db->selectrow_array("SHOW MASTER STATUS");
    $master_status{$name} = [ $masterfile, $masterpos ];
    my ($id) = eval { $db->selectrow_array('SELECT @@server_id') };
    $server_id{$name} = $id if $id;
};

my $check = sub {
    my $name = shift;
    die "Bogus DB: $name" unless $dbinfo{$name};

    # calculate roles to show
    my $roles;
    {
        my %drole;    # display role -> 1
        foreach my $role ( grep { $rolebyname{$name}{$_} } keys %{ $rolebyname{$name} } ) {
            my $drole = $role;
            $drole{$drole} = 1;
        }
        $roles = join( ", ", sort keys %drole );
    }

    my $db = $get_handle->($name);
    unless ($db) {
        printf( "%-18s %-18s ($roles)\n", $name, "" ) unless $opt_err;
        push @errors, "Can't connect to $name";
        return 0;
    }

    my $tzone;
    ( undef, $tzone ) = $db->selectrow_array("show variables like 'system_time_zone'");
    $tzone ||= "???";

    my $sth = $db->prepare("SHOW PROCESSLIST");
    $sth->execute;
    my $pcount_total = 0;
    my $pcount_busy  = 0;
    while ( my $r = $sth->fetchrow_hashref ) {
        next if $r->{'State'} =~ /waiting for/i;
        next if $r->{'State'} eq "Reading master update";
        next if $r->{'State'} =~ /^(Has (sent|read) all)|(Sending binlog)/;
        $pcount_total++;
        $pcount_busy++ if $r->{'State'};
    }

    my $log_count = 0;
    if ( $master_status{$name} && $master_status{$name}->[1] ) {
        $sth = $db->prepare("SHOW MASTER LOGS");
        $sth->execute;
        while ( my ($log) = $sth->fetchrow_array ) {
            $log_count++;
        }
    }

    my $ss = $db->selectrow_hashref("show slave status");
    if ($ss) {
        foreach my $k ( sort keys %$ss ) {
            $ss->{ lc $k } = $ss->{$k};
        }
    }

    my ( $diff, $master );
    if ($ss) {
        if ( $ss->{'slave_io_running'} eq "Yes" && $ss->{'slave_sql_running'} eq "Yes" ) {
            if ( $ss->{'master_log_file'} eq $ss->{'relay_master_log_file'} ) {
                $diff = $ss->{'read_master_log_pos'} - $ss->{'exec_master_log_pos'};
            }
            else {
                $diff = "XXXXXXX";
                push @errors, "Wrong log file: $name";
            }
        }
        else {
            $diff = "XXXXXXX";
            $ss->{last_error} =~ s/[^\n\r\t\x20-\x7e]//g;
            push @errors, "Slave not running: $name: $ss->{last_error}";
        }

        $master = $master_of->($ss);
        if ( !$master && ( $ss->{master_host} || $ss->{master_server_id} ) ) {
            my $endpoint =
                $ss->{master_host}
                ? "$ss->{master_host}:" . ( $ss->{master_port} || 3306 )
                : "unknown host";
            my $id = $ss->{master_server_id} || "unknown";
            push @errors, "$name: Unresolved master: $endpoint (server ID $id)";
        }
        my $ms = $master_status{$master} || [];

        #print "  master: [@$ms], slave at: [$ss->{master_log_file}, $ss->{read_master_log_pos}]\n";
        if (
            $master
            && (   $ss->{master_log_file} ne $ms->[0]
                || $ss->{read_master_log_pos} < $ms->[1] - 20_000 )
            )
        {
            push @errors,
"$name: Relay log behind: master=[@$ms], $name=[$ss->{master_log_file}, $ss->{read_master_log_pos}]";
        }

    }
    else {
        $diff = "-";    # not applicable
    }

    my $extra_version = "";
    my $ver           = $db->selectrow_array('SELECT VERSION()');
    if ($ver) {
        $ver =~ s/^(\d\.\d+\.\d+).*$/$1/;
        $extra_version = $ver;
    }
    else {
        $extra_version = "unknown";
    }

    #print "$name of $master: ($roles)\n";
    printf(
        "%-18s %-18s repl:%7s %4s conn:%4d/%4d  $tzone \%s ($roles)\n",
        $name, $master // "",
        $diff, $log_count ? sprintf( "<%2s>", $log_count ) : "",
        $pcount_busy, $pcount_total, $extra_version
    ) unless $opt_err;
};

check_report() if $opt_checkreport;
rate_report()  if $opt_rates;

$check_master_status->($_) foreach ( sorted_names() );
$check->($_)               foreach ( sorted_names() );

if (@errors) {
    if ($opt_err) {
        my %ignore;
        open( EX, "$ENV{'HOME'}/.dbcheck.ignore" );
        while (<EX>) {
            s/\s+$//;
            $ignore{$_} = 1;
        }
        close EX;
        @errors = grep { !$ignore{$_} } @errors;
    }
    print STDERR "\nERRORS:\n" if @errors;
    foreach (@errors) {
        print STDERR "  * $_\n";
    }
}

my $sorted_cache;

sub sorted_names {
    return @$sorted_cache if $sorted_cache;
    $sorted_cache = [ _sorted_names() ];
    return @$sorted_cache;
}

sub _sorted_names {
    my @names;
    my %added;    # name -> 1

    my $add = sub {
        my $name = shift;
        $added{$name} = 1;
        push @names, $name;
    };

    # master first
    $add->("master");

    # then slaves
    foreach my $name ( sort grep { !$added{$_} && $rolebyname{$_}->{slave} } keys %dbinfo ) {
        $add->($name);
    }

    # now, figure out which remaining are associated with cluster roles (user clusters)
    my %minclust;     # name -> minimum cluster number associated
    my %is_master;    # name -> bool (is cluster master)
    foreach my $name ( grep { !$added{$_} } keys %dbinfo ) {
        foreach my $role ( keys %{ $rolebyname{$name} || {} } ) {
            next unless $role =~ /^cluster(\d+)(.*)/;
            $minclust{$name} = $1 if !$minclust{$name} || $1 < $minclust{$name};
            $is_master{$name} ||= $2 eq "" || $2 eq "a" || $2 eq "b";
        }
    }

    # then misc
    foreach my $name ( sort grep { !$added{$_} && !$minclust{$_} } keys %dbinfo ) {
        $add->($name);
    }

    # then clusters, in order
    foreach my $name (
        sort { $minclust{$a} <=> $minclust{$b} || $is_master{$b} <=> $is_master{$a} || $a cmp $b }
        grep { !$added{$_} && $minclust{$_} } keys %dbinfo
        )
    {
        $add->($name);
    }
    return @names;
}

sub check_report {
    foreach my $name ( sort keys %dbinfo ) {
        my $db = $get_handle->($name);

        unless ($db) {
            print "$name\t?\t?\t?\n";
            next;
        }

        my $dbs = $db->selectcol_arrayref("SHOW DATABASES");
        foreach my $dbname (@$dbs) {
            $db->do("USE $dbname");
            my $ts = $db->selectall_hashref( "SHOW TABLE STATUS", "Name" );
            foreach my $tn ( sort keys %$ts ) {
                my $v  = $ts->{$tn};
                my $ut = $v->{Check_time} || "0000-00-00 00:00:00";
                $ut =~ s/ /,/;
                print "$name\t$dbname\t$tn\t$ut\t$v->{Type}-$v->{Row_format}\t$v->{Rows}\n";
            }

        }
    }
    exit 0;
}

sub rate_report {
    my %prev;    # name -> [ time, questions ]

    while (1) {
        print "\n";
        my $sum = 0;
        foreach my $name ( sorted_names() ) {
            my $db = $get_handle->($name);

            next unless $db;
            my ( undef, $qs ) = $db->selectrow_array("SHOW STATUS LIKE 'Questions'");
            my $now = Time::HiRes::time();
            my $cur = [ $now, $qs ];
            if ( my $old = $prev{$name} ) {
                my $dt   = $now - $old->[0];
                my $qnew = $qs - $old->[1];
                my $rate = ( $qnew / $dt );
                $sum += $rate;
                printf "%20s: %7.01f q/s\n", $name, $rate;
            }
            $prev{$name} ||= $cur;
        }
        printf "%20s: %7.01f q/s\n", "SUM", $sum;

        sleep 1;
    }
}

sub debug {
    return unless $opt_verbose;
    warn $_[0], "\n";
}
