#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal
#
# Importer worker for LiveJournal-based sites.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
# The entry and comment fetching code have been copied and modified from jbackup.pl

package DW::Worker::ContentImporter::LiveJournal;

=head1 NAME

DW::Worker::ContentImporter::LiveJournal - Importer worker for LiveJournal-based sites.

=head1 API

=cut

use strict;
use base 'DW::Worker::ContentImporter';

use DW::Importer::Source::LiveJournal;
use DW::Importer::Source::LiveJournal::Transport;

sub keep_exit_status_for { 0 }
sub grab_for             { 600 }
sub max_retries          { 5 }

sub retry_delay {
    my ( $class, $fails ) = @_;
    return ( 10, 30, 60, 300, 600 )[$fails];
}

=head2 C<< $class->transport_for( $data, [ dry_run => 1 ] ) >>

The transport a job talks to the remote site through: the real one.

=cut

sub transport_for {
    my ( $class, $data, %opts ) = @_;
    return DW::Importer::Source::LiveJournal::Transport->new( data => $data, %opts );
}

=head2 C<< $class->source_for( $ctx ) >>

The source adapter for this job, made once per job.

=cut

sub source_for {
    my ( $class, $ctx ) = @_;

    return $ctx->cache->{source} ||= DW::Importer::Source::LiveJournal->new(
        data      => $ctx->data,
        transport => $ctx->transport
            || $class->transport_for( $ctx->data, dry_run => $ctx->dry_run ),
    );
}

=head2 C<< $class->groupmap( $ctx ) >>

The map from the remote site's group ids to local ones that the friend groups job saved
for this import (empty if it hasn't run). Read once per job.

=cut

sub groupmap_state {
    my ( $class, $ctx ) = @_;
    unless ( exists $ctx->cache->{fg_state} ) {
        my $sink = $ctx->sink;
        my ( $map, $rev ) =
              $sink->can('groupmap_with_revision')
            ? $sink->groupmap_with_revision
            : ( $sink->groupmap, undef );
        $ctx->cache->{fg_map}   = $map;
        $ctx->cache->{fg_state} = [ $map, $rev ];
    }
    return @{ $ctx->cache->{fg_state} };
}

sub groupmap {
    my ( $class, $ctx ) = @_;
    my ($map) = $class->groupmap_state($ctx);
    return $map;
}

=head2 C<< $class->remap_groupmask( $ctx, $allowmask ) >>

Converts a remote groupmask into a local groupmask, using the group map the friend
groups job saved for this import. The map is read once per job and kept in the
job's context.

=cut

sub remap_groupmask {
    my ( $class, $ctx, $allowmask ) = @_;

    my $newmask = 0;
    my $fg_map  = $class->groupmap($ctx);

    # trust/friends hasn't changed bits so just copy that over
    $newmask = 1
        if ( $allowmask & 1 ) == 1;

    foreach my $oid ( keys %$fg_map ) {
        my $nid     = $fg_map->{$oid};
        my $old_bit = ( 2**$oid );

        if ( ( $allowmask & $old_bit ) == $old_bit ) {
            $newmask |= ( 2**$nid );
        }
    }

    return $newmask;
}

=head2 C<< $class->get_remapped_userids( $ctx, $user, $log ) >>

Remaps a remote user to local userids.

( $access_uid, $read_uid )

Answers are kept in the job's context, so each remote user is looked up once per job.

=cut

sub get_remapped_userids {
    my ( $class, $ctx, $user, $log ) = @_;
    my $data = $ctx->data;

    $log ||= sub {
        warn @_;
    };

    # some users we can't map, because the process of loading their FOAF data or journal
    # does really weird things (DNS!)
    return ( undef, undef )
        if $user eq 'status';

    my $mapped = $ctx->cache->{remapped_users} ||= {};
    return @{ $mapped->{$user} }
        if exists $mapped->{$user};

    my ( $oid, $fid ) = $ctx->sink->usermap_lookup( $data->{hostname}, $user );

    unless ($oid) {
        $log->("[$$] Remapping identity userid of $data->{hostname}:$user");
        $oid = $class->remap_username_friend( $ctx, $user );
        $log->("     IDENTITY USERID STILL DOESN'T EXIST")
            unless $oid;

        # remember who this is, so we don't have to ask the remote site again
        $ctx->sink->save_usermap( $data->{hostname}, $user, $oid, $fid );
    }

    # load this user and determine if they've been claimed. if so, we want to post
    # all content as from the claimant.
    my $ou = LJ::load_userid($oid);
    if ( defined $ou ) {
        if ( my $cu = $ou->claimed_by ) {
            $oid = $cu->id;
        }
    }

    $mapped->{$user} = [ $oid, $fid ];
    return ( $oid, $fid );
}

=head2 C<< $class->remap_username_friend( $ctx, $username ) >>

Remaps a remote user to a local userid: the account itself if it is one of ours,
otherwise a local OpenID user for their identity (made if need be).

=cut

sub remap_username_friend {
    my ( $class, $ctx, $username ) = @_;

    my $identity = $class->source_for($ctx)->identity_for($username)
        or return undef;
    return $identity->{local_user} if $identity->{local_user};

    # build the identity account (or return it if it exists)
    return $ctx->sink->identity_user( $identity->{openid} );
}

=head1 AUTHORS

=over

=item Andrea Nall <anall@andreanall.com>

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
