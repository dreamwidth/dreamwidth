#!/usr/bin/perl
#
# DW::Worker::ContentImporter
#
# Generic helper functions for Content Importers
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

package DW::Worker::ContentImporter;

=head1 NAME

DW::Worker::ContentImporter - Generic helper functions for Content Importers

=cut

use strict;
use Time::HiRes qw/ sleep time /;
use Carp qw/ croak confess /;
use Encode qw/ encode_utf8 /;
use Storable qw/ freeze /;
use LWP::UserAgent;
use XMLRPC::Lite;
use Digest::MD5 qw/ md5_hex /;

require 'ljprotocol.pl';
require 'talklib.pl';

use base 'TheSchwartz::Worker';

=head1 Saving API

All Saving API functions take as the first two options the target user
option, followed by a consistent hashref passed to every function.

=head2 C<< $class->merge_trust( $user, $hashref, $friends ) >>

$friends is a reference to an array of hashrefs, with each hashref with the following format:

  {
      userid => ...,        # local userid of the friend
      groupmask => 1,       # groupmask
  }

=cut
sub merge_trust {
    my ( $class, $u, $opts, $friends ) = @_;
    foreach my $friend ( @$friends ) {
        my $to_u = LJ::load_userid( $friend->{userid} );
        $u->add_edge( $to_u, trust => { mask => $friend->{groupmask}, nonotify => 1, } );
    }
}

=head2 C<< $class->merge_watch( $user, $hashref, $friends ) >>

$friends is a reference to an array of hashrefs, with each hashref with the following format:

  {
      userid => ...,        # local userid of the friend
      fgcolor => '#ff0000', # foreground color
      bgcolor => '#00ff00', # background color
  }

=cut
sub merge_watch {
    my ( $class, $u, $opts, $friends ) = @_;
    foreach my $friend ( @$friends ) {
        my $to_u = LJ::load_userid( $friend->{userid} );
        $u->add_edge( $to_u, watch => {
            nonotify => 1,
            fgcolor => LJ::color_todb( $friend->{fgcolor} ),
            bgcolor => LJ::color_todb( $friend->{bgcolor} ),
        } );
    }
}


=head2 C<< $class->post_event( $user, $hashref, $comment ) >>

$event is a hashref representation of a single comment, with the following format:

  {
    subject => "Comment",
    body => 'I DID STUFF!!!!!',
    posterid => $local_userid,

    jitemid => $local_jitemid,

    parentid => $local_parent,

    state => 'A',
  }

=cut
sub insert_comment {
    my ( $class, $u, $opts, $_comment ) = @_;

    my $errref;

    my $jitem = LJ::Entry->new( $u, jitemid=>$_comment->{jitemid} );
    my $user = undef;
    my $source = $jitem->prop( "import_source" ) . "?thread=" . ( $_comment->{id} << 8 );
    $user = LJ::load_userid( $_comment->{posterid} ) if $_comment->{posterid};

    my $date = $_comment->{date};
    $date =~ s/T/ /;
    $date =~ s/Z//;

    my $comment = {
        subject => $_comment->{subject},
        body => $_comment->{body},

        state => $_comment->{state},
        u => $user,

        props => {
            import_source => $source,
        },

        no_urls => 1,
        no_esn => 1,
    };
    my $item = {
        itemid => $_comment->{jitemid},
    };
    my $parent = {
        talkid => $_comment->{parentid},
    };

    unless ($date) {
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime();
        $date = sprintf( "%4i-%2i-%2i %2i:%2i:%2i", 1900+$year, $mday, $mon, $hour, $min, $sec );
    }

    my $jtalkid = LJ::Talk::Post::enter_imported_comment( $u, $parent, $item, $comment, $date, \$errref );
    return undef unless $jtalkid;
    return $jtalkid;
}

=head2 C<< $class->get_comment_map( $user, $hashref )

Returns a hashref mapping import_source keys to jtalkids

=cut
sub get_comment_map {
    my ( $class, $u, $opts ) = @_;
    return $opts->{talk_map} if $opts->{talk_map};

    my $p = LJ::get_prop( "talk", "import_source" );
    return {} unless $p;

    my $dbr = LJ::get_cluster_reader( $u );
    my %map;
    my $sth = $dbr->prepare( "SELECT jtalkid, value FROM talkprop2 WHERE journalid = ? AND tpropid = ?" );

    $sth->execute( $u->id, $p->{id} );

    while ( my ($jitemid,$value) = $sth->fetchrow_array ) {
        $map{$value} = $jitemid;
    }

    return \%map;
}

=head1 Helper Functions

=head2 C<< $class->ratelimit_request( $hashref ) >>

Imposes a ratelimit on the number of times this function can be called

$hashref *must* be the same hash between calls, and must have a _rl_requests and _rl_seconds member.

=cut
sub ratelimit_request {
    my ( $class, $hashref ) = @_;

    # the next two lines load in the ratio - for example, a maximum of 4 requests in 1 second
    my $num_requests = $hashref->{'_rl_requests'};
    my $num_seconds  = $hashref->{'_rl_seconds'};

    # $state is an arrayref containing timestamps
    my $state = $hashref->{'_rl_delay_state'};
    if ( !defined( $state ) ) {
        $state = [];
        $hashref->{'_rl_delay_state'} = $state;
    }

    my $now = time();
    push( @{$state}, $now );
    return if @{$state} < $num_requests;   # we haven't done enough requests to justify a wait yet

    my $oldest = shift( @{$state} );
    if ( ( $now - $oldest ) < $num_seconds ) {
        sleep( $num_seconds - ( $now - $oldest ) );
    }
    return;
}

=head2 C<< $class->import_data( $userid, $import_data_id ) >>

Returns a hash of the data we're using as source.

=cut

sub import_data {
    my ( $class, $userid, $impid ) = @_;

    my $dbh = LJ::get_db_writer()
        or croak 'unable to get global database master';
    my $hr = $dbh->selectrow_hashref( 'SELECT userid, hostname, username, password_md5, import_data_id ' .
                                      'FROM import_data WHERE userid = ? AND import_data_id = ?', undef, $userid, $impid );
    croak $dbh->errstr if $dbh->err;

    return $hr;
}

=head2 C<< $class->fail( $import_data, $item, $job, "text", [arguments, ...] ) >>

Permanently fail this import job.

=cut

sub fail {
    my ( $class, $imp, $item, $job, $msgt, @args ) = @_;

    if ( my $dbh = LJ::get_db_writer() ) {
        $dbh->do( "UPDATE import_items SET status = 'failed', last_touch = UNIX_TIMESTAMP() ".
                  "WHERE userid = ? AND item = ? AND import_data_id = ?",
                  undef, $imp->{userid}, $item, $imp->{import_data_id} );
        warn "IMPORTER ERROR: " . $dbh->errstr . "\n" if $dbh->err;
    }

    my $msg = sprintf( $msgt, @args );
    warn "Permanent failure: $msg\n"
        if $LJ::IS_DEV_SERVER;

    # fire an event for the user to know that it failed
    LJ::Event::ImportStatus->new( $imp->{userid}, $item, { type => 'fail', msg => $msg } )->fire;

    $job->permanent_failure( $msg );
    return;
}

=head2 C<< $class->temp_fail( $job, "text", [arguments, ...] ) >>

Temporarily fail this import job, it will get retried if it hasn't failed too many times.

=cut

sub temp_fail {
    my ( $class, $imp, $item, $job, $msgt, @args ) = @_;

    my $msg = sprintf( $msgt, @args );
    warn "Temporary failure: $msg\n"
        if $LJ::IS_DEV_SERVER;

    # fire an event for the user to know that it failed (temporarily)
    LJ::Event::ImportStatus->new( $imp->{userid}, $item,
        {
            type     => 'temp_fail',
            msg      => $msg,
            failures => $job->failures,
            retries  => $job->funcname->max_retries,
        }
    )->fire;

    $job->failed( $msg );
    return;
}

=head2 C<< $class->ok( $import_data, $item, $job )>>

Successfully end this import job.

=cut

sub ok {
    my ( $class, $imp, $item, $job ) = @_;

    if ( my $dbh = LJ::get_db_writer() ) {
        $dbh->do( "UPDATE import_items SET status = 'succeeded', last_touch = UNIX_TIMESTAMP() " .
                  "WHERE userid = ? AND item = ? AND import_data_id = ?",
                  undef, $imp->{userid}, $item, $imp->{import_data_id} );
        warn "IMPORTER ERROR: " . $dbh->errstr . "\n" if $dbh->err;
    }

    # advise the user this finished
    LJ::Event::ImportStatus->new( $imp->{userid}, $item, { type => 'ok' } )->fire;

    $job->completed;
    return;
}

=head2 C<< $class->status( $import_data, $item, $args ) >>

This creates an LJ::Event::ImportStatus item for the user to look at.  Note that $args
is a hashref that is passed straight through in the item.

=cut

sub status {
    my ( $class, $imp, $item, $args ) = @_;
    return LJ::Event::ImportStatus->new( $imp->{userid}, $item, { type => 'status', %{ $args || {} } } )->fire;
}


1;
