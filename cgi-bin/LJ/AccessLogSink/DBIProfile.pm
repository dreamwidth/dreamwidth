package LJ::AccessLogSink::DBIProfile;
use strict;
use base 'LJ::AccessLogSink';

sub new {
    my ($class, %opts) = @_;
    return bless {}, $class;
}

sub log {
    my ($self, $rec) = @_;

    # Send out DBI profiling information
    return 0 unless $LJ::DB_LOG_HOST && $LJ::HAVE_DBI_PROFILE;

    my ( $host, $dbh );

    while ( ($host,$dbh) = each %LJ::DB_REPORT_HANDLES ) {
        $host =~ s{^(.*?);.*}{$1};

        # For testing: append a random character to simulate different
        # connections.
        if ( $LJ::IS_DEV_SERVER ) {
            $host .= "_" . substr( "abcdefghijklmnopqrstuvwxyz", int rand(26), 1 );
        }

        # From DBI::Profile:
        #   Profile data is stored at the `leaves' of the tree as references
        #   to an array of numeric values. For example:
        #   [
        #     106,                    # count
        #     0.0312958955764771,     # total duration
        #     0.000490069389343262,   # first duration
        #     0.000176072120666504,   # shortest duration
        #     0.00140702724456787,    # longest duration
        #     1023115819.83019,       # time of first event
        #     1023115819.86576,       # time of last event
        #   ]

        # The leaves are stored as values in the hash keyed by statement
        # because LJ::get_dbirole_dbh() sets the profile to
        # "2/DBI::Profile". The 2 part is the DBI::Profile magic number
        # which means split the times by statement.
        my $data = $dbh->{Profile}{Data};

        # Make little arrayrefs out of the statement and longest
        # running-time for this handle so they can be sorted. Then sort them
        # by running-time so the longest-running one can be send to the
        # stats collector.
        my @times =
            sort { $a->[0] <=> $b->[0] }
        map  {[ $data->{$_}[4], $_ ]} keys %$data;

        # ( host, class, time, notes )
        LJ::blocking_report( $host, 'db', @{$times[0]} );
    }

    # Now clear the profiling data for each handle we're profiling at the last
    # possible second to avoid the next request's data being skewed by
    # requests that happen above.
    for my $dbh ( values %LJ::DB_REPORT_HANDLES ) {
        # DBI::Profile-recommended way of resetting profile data
        $dbh->{Profile}{Data} = undef;
    }
    %LJ::DB_REPORT_HANDLES = ();
}


1;
