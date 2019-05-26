#!/usr/bin/perl
#
# DW::Worker::ContentImporter::Local::Entries
#
# Local data utilities to handle importing of entries into the local site.
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

package DW::Worker::ContentImporter::Local::Entries;
use strict;

use Carp qw/ croak /;
use Encode qw/ encode_utf8 /;

=head1 NAME

DW::Worker::ContentImporter::Local::Entries - Local data utilities for entries

=head1 Entries

These functions are part of the Saving API for entries.

=head2 C<< $class->get_entry_map( $user, $hashref ) >>

Returns a hashref mapping import_source keys to jitemids

=cut

sub get_entry_map {
    my ( $class, $u ) = @_;

    my $p = LJ::get_prop( log => 'import_source' )
        or croak 'unable to load logprop';
    my $dbcr = LJ::get_cluster_reader($u)
        or croak 'unable to connect to database';
    my $sth =
        $dbcr->prepare("SELECT jitemid, value FROM logprop2 WHERE journalid = ? AND propid = ?")
        or croak 'unable to prepare SQL';

    $sth->execute( $u->id, $p->{id} );
    croak 'database error: ' . $sth->errstr
        if $sth->err;

    my %map;
    while ( my ( $jitemid, $value ) = $sth->fetchrow_array ) {
        while ( exists $map{$value} ) {
            $value .= "/x";
        }
        $map{$value} = $jitemid;
    }
    return \%map;
}

=head2 C<< $class->get_duplicates_map( $u ) >>

Returns a hashref mapping identifying entry metadata to jitemids.
We assume that an exact match on subject and timestamp will be sufficient
to identify duplicates

=cut

sub get_duplicates_map {
    my ( $class, $u ) = @_;

    my $dbr = LJ::get_cluster_reader($u)
        or croak 'unable to connect to database';

    my $sth =
        $dbr->prepare( "SELECT l.jitemid, UNIX_TIMESTAMP(l.logtime), lt.subject"
            . " FROM log2 l LEFT JOIN logtext2 lt ON ( l.jitemid = lt.jitemid  AND l.journalid=lt.journalid )"
            . " WHERE l.journalid=?" )
        or croak 'unable to prepare SQL';
    $sth->execute( $u->id );
    croak 'database error: ' . $sth->errstr
        if $sth->err;

    my %dupes_map;
    while ( my ( $id, $logtime, $subject ) = $sth->fetchrow_array ) {
        $dupes_map{"$logtime-$subject"} = $id;
    }

    return \%dupes_map;
}

=head2 C<< $class->post_event( $hashref, $u, $event, $item_errors ) >>

$event is a hashref representation of a single entry, with the followinginx.confng format:

  {
    # standard event values
    subject => 'My Entry',
    event => 'I DID STUFF!!!!!',
    security => 'usemask',
    allowmask => 1,
    eventtime => 'yyyy-mm-dd hh:mm:ss',
    props => {
        heres_a_userprop => "there's a userprop",
        and_another_little => "userprop",
    }

    # the key is a uniquely opaque string that identifies this entry.  this must be
    # unique across all possible import sources.  the permalink may work best.
    key => 'some_unique_key',

    # a url to this entry's original location
    url => 'http://permalink.tld/',
  }

$item_errors is an arrayref of errors to be formatted nicely with a link to old and new entries.

Returns (1, $res) on success, (undef, $res) on error.

=cut

sub post_event {
    my ( $class, $data, $map, $u, $posteru, $evt, $errors ) = @_;

    return if $map->{ $evt->{key} };

    my ( $yr, $month, $day, $hr, $min, $sec );
    ( $yr, $month, $day, $hr, $min, $sec ) = ( $1, $2, $3, $4, $5, $6 )
        if $evt->{eventtime} =~ m/(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;

    # Rarely, we will get text that isn't valid UTF-8. If that's the case, shove it through the
    # encoder and hope for the best. Don't double-encode if it's already valid, though.
    foreach my $key (qw/ subject event /) {
        $evt->{$key} = encode_utf8( $evt->{$key} )
            unless LJ::text_in( $evt->{$key} );
    }
    foreach my $prop ( keys %{ $evt->{props} } ) {
        $evt->{props}->{$prop} = encode_utf8( $evt->{props}->{$prop} )
            unless LJ::text_in( $evt->{props}->{$prop} );
    }

    my %proto = (
        lineendings => 'unix',
        subject     => $evt->{subject},
        event       => $evt->{event},
        security    => $evt->{security},
        allowmask   => $evt->{allowmask},

        year => $yr,
        mon  => $month,
        day  => $day,
        hour => $hr,
        min  => $min,
    );

    my $props = $evt->{props};

    # this is a list of props that actually exist on this site
    # but have been shown to cause failures importing that entry.
    my %bad_props = (
        current_coords       => 1,
        personifi_word_count => 1,
        personifi_lang       => 1,
        personifi_tags       => 1,
        give_features        => 1,
        spam_counter         => 1,
        poster_ip            => 1,
        uniq                 => 1,
    );
    foreach my $prop ( keys %$props ) {
        next if $bad_props{$prop};

        my $p = LJ::get_prop( "log", $prop )
            or next;
        next if $p->{ownership} eq 'system';

        $proto{"prop_$prop"} = $props->{$prop};
    }

    # Overwrite these here in case we're importing from an imported journal (hey, it could happen)
    $proto{prop_import_source} = $evt->{key};
    if ( defined $posteru ) {
        delete $proto{prop_opt_backdated};
    }
    else {
        $proto{prop_opt_backdated} = 1;
    }

    my %res;
    LJ::do_request(
        {
            mode       => 'postevent',
            user       => $posteru ? $posteru->user : $u->user,
            usejournal => $posteru ? $u->user : undef,
            ver        => $LJ::PROTOCOL_VER,
            %proto,
        },
        \%res,
        {
            u                       => $posteru || $u,
            u_owner                 => $u,
            importer_bypass         => 1,
            allow_truncated_subject => 1,
        }
    );

    if ( $res{success} eq 'FAIL' ) {
        push @$errors, "Failed to post: $res{errmsg}";
        return ( undef, \%res );

    }
    else {
        $u->do( "UPDATE log2 SET logtime = ? where journalid = ? and jitemid = ?",
            undef, $evt->{logtime}, $u->userid, $res{itemid} );
        $map->{ $evt->{key} } = $res{itemid};
        return ( 1, \%res );

    }

    # flow will never get here
}

=head1 AUTHORS

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
