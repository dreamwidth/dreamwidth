#!/usr/bin/perl
#
# DW::Worker::ContentImporter::UserPictures
#
# Importer worker for importing a number of user-selected icons.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::UserPictures;

use strict;
use Storable qw(thaw);

use DW::BlobStore;
use DW::Worker::ContentImporter;

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

use base 'TheSchwartz::Worker';

sub work {
    my ( $class, $job ) = @_;

    my $opts = $job->arg;
    my $u;

    $opts->{'_rl_requests'} = 3;
    $opts->{'_rl_seconds'} = 1;

    # failure closer for permanent errors
    my $fail = sub {
        my $msg = sprintf( shift(), @_ );

        $u->set_prop( "import_job",'' ) if $u;
        $job->permanent_failure( $msg );
        return;
    };

    # failure closer for temporary errors
    my $temp_fail = sub {
        my $msg = sprintf( shift(), @_ );

        $job->failed( $msg );
        return;
    };
    my $r;

    $opts->{errors} = [] unless defined $opts->{errors};

    $u = LJ::load_userid($opts->{target});

    return $fail->( "No Such User" ) unless $u;

    my $raw_data = DW::BlobStore->retrieve( temp => "import_upi:$u->{userid}" );
    return $fail->( "Data missing" ) unless $raw_data;

    my $data = thaw $$raw_data;

    foreach my $upi ( @{$data->{pics}} ) {
        next unless $opts->{selected}->{$upi->{id}};
        DW::Worker::ContentImporter->ratelimit_request( $opts );
        DW::Worker::ContentImporter->import_userpic( $u, $opts, $upi );
    }

    DW::BlobStore->delete( temp => "import_upi:$u->{userid}" );
    my $email = <<EOF;
Dear $u->{user},

Your user pictures have been imported.

EOF
    if ( scalar @{$opts->{errors}} ) {
        $email .= "\n\nHowever, we were unfortunately unable to import the following items, and you will have to do them manually:\n";
        foreach my $item ( @{$opts->{errors}} ) {
            $email .= " * $item\n";
        }
    }
    $email .= <<EOF;

Regards,
The $LJ::SITENAME Team
EOF
    LJ::send_mail( {
            to => $u->email_raw,
            from => $LJ::BOGUS_EMAIL,
            body => $email
        } );
    $u->set_prop("import_job",'');
    $job->completed;
}

sub keep_exit_status_for { 0 }
sub grab_for { 600 }
sub max_retries { 5 }
sub retry_delay {
    my ( $class, $fails ) = @_;
    return ( 10, 30, 60, 300, 600 )[$fails];
}

1;
