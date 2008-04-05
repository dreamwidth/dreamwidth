package LJ::EventLogSink::Database;
use strict;
use base 'LJ::EventLogSink';

sub new {
    my ($class, %opts) = @_;

    my $prefix = $opts{prefix};

    my $self = {
        prefix => $prefix,
    };

    bless $self, $class;
    return $self;
}

sub database_role {
    return "logs";
}

sub prefix {
    my $self = shift;
    return $self->{prefix} || 'eventlog';
}

sub log {
    my ($self, $evt) = @_;

    return 0 unless $self->should_log($evt);

    my $params = $evt->params
        or return 0;

    my $event_type = $params->{_event_type} || 'unknown';

    my $dbl = LJ::get_dbh($self->database_role)
        or return 0;

    my @now = gmtime();

    my $table = $self->prefix .
        sprintf("%04d%02d%02d%02d",
                $now[5]+1900,
                $now[4]+1,
                $now[3],
                $now[2]);

    unless ($LJ::CACHED_LOG_CREATE{"$table"}++) {
        my $sql = "(".
                "event VARCHAR(255) NOT NULL, " .
                "unixtimestamp INT UNSIGNED NOT NULL, " .
                "info BLOB" .
                ")";

        $dbl->do("CREATE TABLE IF NOT EXISTS $table $sql");
        die $dbl->errstr if $dbl->err && $LJ::IS_DEV_SERVER;
        Apache->log_error("error creating log table ($table): Error is: " .
                          $dbl->err . ": ". $dbl->errstr) if $dbl->err;
    }

    my $encoded_params = join '&', map { LJ::eurl($_) . '=' . LJ::eurl($params->{$_}) } keys %$params;
    $dbl->do("INSERT INTO $table (event, unixtimestamp, info) VALUES (?, UNIX_TIMESTAMP(), ?)", undef,
             $event_type, $encoded_params);

    die $dbl->errstr if $dbl->err;

    return 1;
}


sub should_log {
    my ($self, $evt) = @_;
    return 1;
}

1;
