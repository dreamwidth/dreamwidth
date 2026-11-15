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

use Carp qw/ croak confess /;
use Storable qw/ thaw /;
use DW::External::Account;
use DW::Importer::Source::LiveJournal;
use DW::Importer::Source::LiveJournal::Transport;

sub keep_exit_status_for { 0 }
sub grab_for             { 600 }
sub max_retries          { 5 }

sub retry_delay {
    my ( $class, $fails ) = @_;
    return ( 10, 30, 60, 300, 600 )[$fails];
}

=head2 C<< $class->transport_for( $data ) >>

The transport a job talks to the remote site through: the real one.

=cut

sub transport_for {
    my ( $class, $data ) = @_;
    return DW::Importer::Source::LiveJournal::Transport->new( data => $data );
}

=head2 C<< $class->source_for( $ctx ) >>

The source adapter for this job, made once per job.

=cut

sub source_for {
    my ( $class, $ctx ) = @_;

    return $ctx->cache->{source} ||= DW::Importer::Source::LiveJournal->new(
        data      => $ctx->data,
        transport => $ctx->transport || $class->transport_for( $ctx->data ),
    );
}

=head2 C<< $class->groupmap( $ctx ) >>

The map from the remote site's group ids to local ones that the friend groups job saved
for this import (empty if it hasn't run). Read once per job.

=cut

sub groupmap {
    my ( $class, $ctx ) = @_;

    unless ( $ctx->cache->{fg_map} ) {
        my $data = $ctx->data;
        my $dbh  = LJ::get_db_writer()
            or croak 'unable to get global database handle';
        my $row = $dbh->selectrow_array(
            'SELECT groupmap FROM import_data WHERE userid = ? AND import_data_id = ?',
            undef, $data->{userid}, $data->{import_data_id} );
        $ctx->cache->{fg_map} = $row ? thaw($row) : {};
    }
    return $ctx->cache->{fg_map};
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

    my $dbh = LJ::get_db_writer()
        or return;
    my ( $oid, $fid ) = $dbh->selectrow_array(
'SELECT identity_userid, feed_userid FROM import_usermap WHERE hostname = ? AND username = ?',
        undef, $data->{hostname}, $user
    );

    unless ($oid) {
        $log->("[$$] Remapping identity userid of $data->{hostname}:$user");
        $oid = $class->remap_username_friend( $ctx, $user );
        $log->("     IDENTITY USERID STILL DOESN'T EXIST")
            unless $oid;
    }

    $dbh->do(
'REPLACE INTO import_usermap (hostname, username, identity_userid, feed_userid) VALUES (?, ?, ?, ?)',
        undef, $data->{hostname}, $user, $oid, $fid
    );

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
    my $iu = LJ::User::load_identity_user( 'O', $identity->{openid}, undef )
        or return undef;
    return $iu->id;
}

=head2 C<< $class->get_xpost_map( $user, $hashref ) >>

Returns a hashref mapping jitemids to crossposted entries.

=cut

sub get_xpost_map {
    my ( $class, $u, $data ) = @_;

    # see if the account we're importing from is configured to crosspost
    my $acct = $class->find_matching_acct( $u, $data );
    return {} unless $acct;

    # connect to the database and ready the sql
    my $p = LJ::get_prop( log => 'xpost' )
        or croak 'unable to get xpost logprop';
    my $dbcr = LJ::get_cluster_reader($u)
        or croak 'unable to get user cluster reader';
    my $sth =
        $dbcr->prepare("SELECT jitemid, value FROM logprop2 WHERE journalid = ? AND propid = ?")
        or croak 'unable to prepare statement';

    # now look up the values we need
    $sth->execute( $u->id, $p->{id} );
    croak 'database error: ' . $sth->errstr
        if $sth->err;

    # ( remote jitemid => local ditemid )
    my %map;

    # put together the mapping above
    while ( my ( $jitemid, $value ) = $sth->fetchrow_array ) {

        # decompose the xposter data
        my $data  = DW::External::Account->xpost_string_to_hash($value);
        my $xpost = $data->{ $acct->acctid }
            or next;

        # this item was crossposted, record it
        $map{$xpost} = $jitemid;
    }

    return \%map;
}

=head2 C<< $class->find_matching_acct( $u, $data ) >>

Finds the External Account ID, if this user is set up to xpost.

=cut

sub find_matching_acct {
    my ( $class, $u, $data ) = @_;

    my @accts = DW::External::Account->get_external_accounts($u);

    my $dh = lc( $data->{hostname} );
    $dh =~ s/^www\.//;

    my $duser = lc( $data->{username} );
    $duser =~ s/-/_/g;

    foreach my $acct (@accts) {
        my $sh = lc( $acct->serverhost );
        $sh =~ s/^www\.//;

        my $suser = lc( $acct->username );
        $suser =~ s/-/_/g;

        next unless $sh eq $dh;
        next unless $suser eq $duser;
        return $acct;
    }

    return undef;
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
