#!/usr/bin/perl
#

use strict;
use DBI;
use Getopt::Long;

my $help = 0;
my $opt_fh = 0;
my $opt_fix = 0;
my $opt_start = 0;
my $opt_stop = 0;
my $opt_err = 0;
my $opt_all = 0;
my $opt_tablestatus;
my $opt_checkreport = 0;
my $opt_verbose;
my $opt_rates;
my @opt_run;
exit 1 unless GetOptions('help' => \$help,
                         'flushhosts' => \$opt_fh,
                         'start' => \$opt_start,
                         'stop' => \$opt_stop,
                         'checkreport' => \$opt_checkreport,
                         'rates' => \$opt_rates,
                         'fix' => \$opt_fix,
                         'run=s' => \@opt_run,
                         'onlyerrors' => \$opt_err,
                         'all' => \$opt_all,
                         'tablestatus' => \$opt_tablestatus,
                         'verbose' => \$opt_verbose,
                         );

unless (-d $ENV{'LJHOME'}) {
    die "\$LJHOME not set.\n";
}

if ($help) {
    die ("Usage: dbcheck.pl [opts] [[cmd] args...]\n" .
         "    --all           Check all hosts, even those with no weight assigned.\n" .
         "    --help          Get this help\n" .
         "    --flushhosts    Send 'FLUSH HOSTS' to each db as root.\n".
         "    --fix           Fix (once) common problems.\n".
         "    --checkreport   Show tables that haven't been checked in a while.\n".
         "    --stop          Stop replication.\n".
         "    --start         Start replication.\n".
         "    --run <sql>     Run arbitrary SQL.\n".
         "    --onlyerrors    Will be silent unless there are errors.\n".
         "    --tablestatus   Show warnings about full/sparse tables.\n".
         "\n".
         "Commands\n".
         "   (none)           Shows replication status.\n".
         "   queries <host>   Shows active queries on host, sorted by running time.\n"
         );
}

require "$ENV{'LJHOME'}/cgi-bin/ljdb.pl";

debug("Connecting to master...");
my $dbh = LJ::DB::dbh_by_role("master");
die "Can't get master db handle\n" unless $dbh;

my %dbinfo;  # dbid -> hashref
my %name2id; # name -> dbid
my $sth;
my $masterid = 0;

my %subclust;  # id -> name of parent  (pork-85 -> "pork")

$sth = $dbh->prepare("SELECT dbid, name, masterid, rootfdsn FROM dbinfo");
$sth->execute;
while ($_ = $sth->fetchrow_hashref) {
    if ($_->{name} =~ /(.+)\-\d\d$/) {
        $subclust{$_->{dbid}} = $1;
        next;
    }
    next unless $_->{'dbid'};
    $dbinfo{$_->{'dbid'}} = $_;
    $name2id{$_->{'name'}} = $_->{'dbid'};
}

my %role;      # rolename -> dbid -> [ norm, curr ]
my %rolebyid;  # dbid -> rolename -> [ norm, curr ]
$sth = $dbh->prepare("SELECT dbid, role, norm, curr FROM dbweights");
$sth->execute;
while ($_ = $sth->fetchrow_hashref) {
    my $id = $_->{dbid};
    if ($subclust{$id}) {
        $id = $name2id{$subclust{$id}};
    }
    next unless defined $dbinfo{$id};
    $dbinfo{$id}->{'totalweight'} += $_->{'curr'};
    $role{$_->{role}}->{$id} = [ $_->{norm}, $_->{curr} ];
    $rolebyid{$id}->{$_->{role}} = [ $_->{norm}, $_->{curr} ];
}

check_report() if $opt_checkreport;
rate_report() if $opt_rates;

my %root_handle;  # name -> $db
my $root_handle = sub {
    my $name = shift;
    return $root_handle{$name} if exists $root_handle{$name};
    debug("Connecting to '$name' ...");
    $LJ::DB_TIMEOUT = 1;
    my $db = LJ::DB::root_dbh_by_name($name);
    debug("  ($name: failed to connect)") unless $db;
    return $root_handle{$name} = $db;
};

my @errors;
my %master_status;  # dbid -> [ $file, $pos ]

my $check_master_status = sub {
    my $dbid = shift;
    my $d = $dbinfo{$dbid};
    die "Bogus DB: $dbid" unless $d;
    my $db = $root_handle->($d->{name});
    next unless $db;

    my ($masterfile, $masterpos) = $db->selectrow_array("SHOW MASTER STATUS");
    $master_status{$dbid} = [ $masterfile, $masterpos ];
};

my $check = sub {
    my $dbid = shift;
    my $d = $dbinfo{$dbid};
    die "Bogus DB: $dbid" unless $d;

    # calculate roles to show
    my $roles;
    {
        my %drole;  # display role -> 1
        foreach my $role (grep { $role{$_}{$dbid}[1] } keys %{$rolebyid{$dbid}}) {
            my $drole = $role;
            $drole =~ s/cluster(\d+)\d/cluster${1}0/;
            $drole{$drole} = 1;
        }
        $roles = join(", ", sort keys %drole);
    }

    my $db = $root_handle->($d->{name});
    unless ($db) {
        printf("%4d %-18s %4s %16s  %14s  ($roles)\n",
               $dbid,
               $d->{name},
               $d->{masterid} ? $d->{masterid} : "",
               ) unless $opt_err;
        push @errors, "Can't connect to $d->{'name'}";
        return 0;
    }

    my $tzone;
    (undef, $tzone) = $db->selectrow_array("show variables like 'timezone'");
    $tzone ||= "???";

    $sth = $db->prepare("SHOW PROCESSLIST");
    $sth->execute;
    my $pcount_total = 0;
    my $pcount_busy = 0;
    while (my $r = $sth->fetchrow_hashref) {
        next if $r->{'State'} =~ /waiting for/i;
        next if $r->{'State'} eq "Reading master update";
        next if $r->{'State'} =~ /^(Has (sent|read) all)|(Sending binlog)/;
        $pcount_total++;
        $pcount_busy++ if $r->{'State'};
    }

    my @master_logs;
    my $log_count = 0;
    if ($master_status{$dbid} && $master_status{$dbid}->[1]) {
        $sth = $db->prepare("SHOW MASTER LOGS");
        $sth->execute;
        while (my ($log) = $sth->fetchrow_array) {
            push @master_logs, $log;
            $log_count++;
        }
    }

    my $ss = $db->selectrow_hashref("show slave status");
    if ($ss) {
        foreach my $k (sort keys %$ss) {
            $ss->{lc $k} = $ss->{$k};
        }
    }

    my $diff;
    if ($ss) {
        if ($ss->{'slave_io_running'} eq "Yes" && $ss->{'slave_sql_running'} eq "Yes") {
            if ($ss->{'master_log_file'} eq $ss->{'relay_master_log_file'}) {
                $diff = $ss->{'read_master_log_pos'} - $ss->{'exec_master_log_pos'};
            } else {
                $diff = "XXXXXXX";
                push @errors, "Wrong log file: $d->{name}";
            }
        } else {
            $diff = "XXXXXXX";
            $ss->{last_error} =~ s/[^\n\r\t\x20-\x7e]//g;
            push @errors, "Slave not running: $d->{name}: $ss->{last_error}";
        }

        my $ms = $master_status{$d->{masterid}} || [];
        #print "  master: [@$ms], slave at: [$ss->{master_log_file}, $ss->{read_master_log_pos}]\n";
        if ($ss->{master_log_file} ne $ms->[0] || $ss->{read_master_log_pos} < $ms->[1] - 20_000) {
            push @errors, "$d->{name}: Relay log behind: master=[@$ms], $d->{name}=[$ss->{master_log_file}, $ss->{read_master_log_pos}]";
        }

    } else {
        $diff = "-";  # not applicable
    }

    my $extra_version = "";
    my $ver = $db->selectrow_array('SELECT VERSION()');
    if ($ver) {
        $ver =~ s/^(\d\.\d+\.\d+).*$/$1/;
        $extra_version = $ver;
    } else {
        $extra_version = "unknown";
    }

    #print "$dbid of $d->{masterid}: $d->{name} ($roles)\n";
    printf("%4d %-18s %4s repl:%7s %4s conn:%4d/%4d  $tzone \%s ($roles)\n",
           $dbid,
           $d->{name},
           $d->{masterid} ? $d->{masterid} : "",
           $diff,
           $log_count ? sprintf("<%2s>", $log_count) : "",
           $pcount_busy, $pcount_total,
       $extra_version) unless $opt_err;
};

$check_master_status->($_) foreach (sorted_dbids());

$check->($_) foreach (sorted_dbids());

if (@errors) {
    if ($opt_err) {
        my %ignore;
        open(EX, "$ENV{'HOME'}/.dbcheck.ignore");
        while (<EX>) {
            s/\s+$//;
            $ignore{$_} = 1;
        }
        close EX;
        @errors = grep { ! $ignore{$_} } @errors;
    }
    print STDERR "\nERRORS:\n" if @errors;
    foreach (@errors) {
        print STDERR "  * $_\n";
    }
}

my $sorted_cache;
sub sorted_dbids {
    return @$sorted_cache if $sorted_cache;
    $sorted_cache = [ _sorted_dbids() ];
    return @$sorted_cache;
}

sub _sorted_dbids {
    my @ids;
    my %added;  # dbid -> 1

    my $add = sub {
        my $dbid = shift;
        $added{$dbid} = 1;
        push @ids, $dbid;
    };

    my $masterid = (keys %{$role{'master'}})[0];
    $add->($masterid);

    # then slaves
    foreach my $id (sort { $dbinfo{$a}->{name} cmp $dbinfo{$b}->{name} }
                    grep { ! $added{$_} && $rolebyid{$_}->{slave} } keys %dbinfo) {
        $add->($id);
    }

    # now, figure out which remaining are associated with cluster roles (user clusters)
    my %minclust;   # dbid -> minimum cluster number associated
    my %is_master;  # dbid -> bool (is cluster master)
    foreach my $dbid (grep { ! $added{$_} } keys %dbinfo) {
        foreach my $role (keys %{ $rolebyid{$dbid} || {} }) {
            next unless $role =~ /^cluster(\d+)(.*)/;
            $minclust{$dbid} = $1 if ! $minclust{$dbid} || $1 < $minclust{$dbid};
            $is_master{$dbid} ||= $2 eq "" || $2 eq "a" || $2 eq "b";
        }
    }

    # then misc
    foreach my $id (sort { $dbinfo{$a}->{name} cmp $dbinfo{$b}->{name} }
                    grep { ! $added{$_} && ! $minclust{$_} } keys %dbinfo) {
        $add->($id);
    }


    # then clusters, in order
    foreach my $id (sort { $minclust{$a} <=> $minclust{$b} ||
                               $is_master{$b} <=> $is_master{$a} }
                    grep { ! $added{$_} && $minclust{$_} } keys %dbinfo) {
        $add->($id);
    }
    return @ids;
}

sub check_report {
    foreach my $dbid (sort { $dbinfo{$a}->{name} cmp $dbinfo{$b}->{name} }
                      keys %dbinfo) {
        my $d = $dbinfo{$dbid};
        die "Bogus DB: $dbid" unless $d;
        my $db = $root_handle->($d->{name});

        unless ($db) {
            print "$d->{name}\t?\t?\t?\n";
            next;
        }

        my $dbs = $db->selectcol_arrayref("SHOW DATABASES");
        foreach my $dbname (@$dbs) {
            $db->do("USE $dbname");
            my $ts = $db->selectall_hashref("SHOW TABLE STATUS", "Name");
            foreach my $tn (sort keys %$ts) {
                my $v = $ts->{$tn};
                my $ut = $v->{Check_time} || "0000-00-00 00:00:00";
                $ut =~ s/ /,/;
                print "$d->{name}\t$dbname\t$tn\t$ut\t$v->{Type}-$v->{Row_format}\t$v->{Rows}\n";
            }

        }
    }
    exit 0;
}

use Time::HiRes ();

sub rate_report {
    my %prev;  # dbid -> [ time, questions ]

    while (1) {
        print "\n";
        my $sum = 0;
        foreach my $dbid (sorted_dbids()) {
            my $d = $dbinfo{$dbid};
            die "Bogus DB: $dbid" unless $d;
            my $db = $root_handle->($d->{name});

            next unless $db;
            my (undef, $qs) = $db->selectrow_array("SHOW STATUS LIKE 'Questions'");
            my $now = Time::HiRes::time();
            my $cur = [ $now, $qs ];
            if (my $old = $prev{$dbid}) {
                my $dt = $now - $old->[0];
                my $qnew = $qs - $old->[1];
                my $rate = ($qnew / $dt);
                $sum += $rate;
                printf "%20s: %7.01f q/s\n", $d->{name}, $rate;
            }
            $prev{$dbid} ||= $cur;
        }
        printf "%20s: %7.01f q/s\n", "SUM", $sum;

        sleep 1;
    }
}

sub debug {
    return unless $opt_verbose;
    warn $_[0], "\n";
}
