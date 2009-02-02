package LJ::AccessLogSink::Database;
use strict;
use base 'LJ::AccessLogSink';
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;

    my $percent = delete $opts{percent};
    $percent = $LJ::LOG_PERCENTAGE unless defined $percent;

    my $prefix = delete $opts{prefix};
    $prefix ||= "access";

    my $self = bless {
        percent => $percent,
        prefix  => $prefix,
    }, $class;

    croak("Unknown options: " . join(", ", keys %opts)) if %opts;
    return $self;
}

sub should_log {
    my ($self, $rec) = @_;
    return 0
        if defined $self->{percent} && rand(100) > $self->{percent};
    return 1;
}

sub database_role {
    return "logs";
}

sub extra_columns {
    return '';
}

sub extra_values {
}

sub log {
    my ($self, $rec) = @_;

    return 0 unless $self->should_log($rec);

    my $dbl = LJ::get_dbh($self->database_role)
        or return 0;

    my $table = $rec->table($self->{prefix});

    unless ($LJ::CACHED_LOG_CREATE{"$table"}++) {
        my $index = "INDEX(whn),";
        my $delaykeywrite = "DELAY_KEY_WRITE = 1";
        my $sql;
        my $gen_sql = sub {
            my $extra = $self->extra_columns;
            $sql = "(".
                "whn TIMESTAMP(14) NOT NULL, $index".
                "whnunix INT UNSIGNED,".
                "server VARCHAR(30),".
                "addr VARCHAR(15) NOT NULL,".
                "ljuser VARCHAR(25),".
                "remotecaps INT UNSIGNED,".
                "journalid INT UNSIGNED,". # userid of what's being looked at
                "journaltype CHAR(1),".   # journalid's journaltype
                "journalcaps INT UNSIGNED,".
                "remoteid INT UNSIGNED,". # remote user's userid
                "codepath VARCHAR(80),".  # protocol.getevents / s[12].friends / bml.update / bml.friends.index
                "anonsess INT UNSIGNED,".
                "langpref VARCHAR(5),".
                "uniq VARCHAR(15),".
                "method VARCHAR(10) NOT NULL,".
                "uri VARCHAR(255) NOT NULL,".
                "args VARCHAR(255),".
                "status SMALLINT UNSIGNED NOT NULL,".
                "ctype VARCHAR(30),".
                "bytes MEDIUMINT UNSIGNED NOT NULL,".
                "browser VARCHAR(100),".
                "clientver VARCHAR(100),".
                "secs TINYINT UNSIGNED,".
                "ref VARCHAR(200),".
                "pid SMALLINT UNSIGNED,".
                "cpu_user FLOAT UNSIGNED,".
                "cpu_sys FLOAT UNSIGNED,".
                "cpu_total FLOAT UNSIGNED,".
                "mem_vsize INT,".
                "mem_share INT,".
                "mem_rss INT,".
                "mem_unshared INT $extra) $delaykeywrite";
        };

        $gen_sql->();
        $dbl->do("CREATE TABLE IF NOT EXISTS $table $sql");

        # too many keys specified.  (archive table engine)
        if ($dbl->err == 1069) {
            $index = "";
            $gen_sql->();
            $dbl->do("CREATE TABLE IF NOT EXISTS $table $sql");
        }

        Apache->log_error("error creating log table ($table): Error is: " .
                          $dbl->err . ": ". $dbl->errstr) if $dbl->err;
    }

    my $copy = {};
    $copy->{$_} = $rec->{$_} foreach $rec->keys;
    $self->extra_values($rec, $copy);

    my $ins = sub {
        my $delayed = $LJ::IMMEDIATE_LOGGING ? "" : "DELAYED";
        $dbl->do("INSERT $delayed INTO $table (" . join(',', keys %$copy) . ") ".
                 "VALUES (" . join(',', map { $dbl->quote($copy->{$_}) } keys %$copy) . ")");
    };

    # support for widening the schema at runtime.  if we detect a bogus column,
    # we just don't log that column until the next (wider) table is made at next
    # hour boundary.
    $ins->();
    while ($dbl->err && $dbl->errstr =~ /Unknown column \'(\w+)/) {
        my $col = $1;
        delete $copy->{$col};
        $ins->();
    }

    $dbl->disconnect if $LJ::DISCONNECT_DB_LOG;
}


1;
