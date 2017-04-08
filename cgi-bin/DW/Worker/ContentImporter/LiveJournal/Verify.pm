#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::Verify
#
# Importer worker for LiveJournal-based site verification of logins and
# passwords.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::LiveJournal::Verify;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use Carp qw/ croak confess /;

sub work {

    # VITALLY IMPORTANT THAT THIS IS CLEARED BETWEEN JOBS
    %DW::Worker::ContentImporter::LiveJournal::MAPS = ();

    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    return $class->decline( $job ) unless $class->enabled( $data );

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;
        return $class->temp_fail( $data, 'lj_verify', $job, 'Failure running job: %s', $msg );
    }
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_verify', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_verify', $job, @_ ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_verify', $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );
    $0 = sprintf( 'content-importer [verify: %s(%d)]', $u->user, $u->id );

    # we verify by doing a simple tags call.  yes, this means that we end up
    # getting a user's tags twice... but I'm okay with that, we'll live
    my $r = $class->call_xmlrpc( $data, 'getusertags' );

    # now, we have to see if the error contains 'Invalid password' or something else
    if ( $r && $r->{fault} && $r->{faultString} =~ /Invalid password/ ) {
        # mark the rest of the import as aborted, since something went wrong
        my $dbh = LJ::get_db_writer();
        $dbh->do(
            q{UPDATE import_items SET status = 'aborted'
              WHERE userid = ? AND item <> 'lj_verify'
              AND import_data_id = ? AND status = 'init'},
            undef, $u->id, $opts->{import_data_id}
        );

        # this is a permanent failure.  if the password is bad, we're not going to ever
        # bother retrying.  that's life.
        return $fail->( "Username or password for $data->{username} rejected by $data->{hostname}." );
    }

    # if we got any other type of failure, call it temporary...
    return $temp_fail->( 'XMLRPC failure: ' . $r->{faultString} )
        if ! $r || $r->{fault};

    # If this is a community import, we have to do a second step now to make sure
    # that the user is an administrator of the remote community. The best way I can
    # come up with is try to unban the owner -- if it works, you're an admin.
    if ( $data->{usejournal} ) {
        $r = $class->call_xmlrpc( $data, 'consolecommand', {
            commands => [ "ban_unset $data->{username} from $data->{usejournal}" ],
        } );

        my $xmlrpc_fail = 'XMLRPC failure: ' . ( $r ? $r->{faultString} : '[unknown]' );
        $xmlrpc_fail .=  " (community: $data->{usejournal})";
        return $temp_fail->( $xmlrpc_fail ) if ! $r || $r->{fault};
        return $fail->( 'You are not an administrator/maintainer of the remote' .
                        ' community named ' . $data->{usejournal} . '.' )
            unless $r->{results}->[0]->{output}->[0]->[0] eq 'success';
    }

    # mark the next group as ready to schedule
    my $dbh = LJ::get_db_writer();
    $dbh->do(
        q{UPDATE import_items SET status = 'ready'
          WHERE userid = ? AND item IN ('lj_bio', 'lj_userpics', 'lj_friendgroups', 'lj_tags')
          AND import_data_id = ? AND status = 'init'},
        undef, $u->id, $opts->{import_data_id}
    );

    # okay, but don't fire off a message to say it's done, this job doesn't matter to
    # the user unless it fails
    return $ok->( 0 );
}


1;
