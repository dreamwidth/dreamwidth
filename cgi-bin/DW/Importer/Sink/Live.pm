#!/usr/bin/perl
#
# DW::Importer::Sink::Live
#
# Writes imported content to the local site.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Importer::Sink::Live;

=head1 NAME

DW::Importer::Sink::Live - The sink that really writes

=head1 DESCRIPTION

Wraps the C<DW::Worker::ContentImporter::Local::*> code that does the writing. See
L<DW::Importer::Sink> for what the methods do.

=cut

use strict;
use warnings;

use Carp qw( croak );
use Storable qw( nfreeze thaw );

use base 'DW::Importer::Sink';

use DW::External::Account;
use DW::Search;
use DW::Task::SearchCopier;
use DW::TaskQueue;
use DW::Worker::ContentImporter;
use DW::Worker::ContentImporter::Local::Bio;
use DW::Worker::ContentImporter::Local::Comments;
use DW::Worker::ContentImporter::Local::Entries;
use DW::Worker::ContentImporter::Local::Tags;
use DW::Worker::ContentImporter::Local::TrustGroups;
use DW::Worker::ContentImporter::Local::Userpics;

=head2 C<< DW::Importer::Sink::Live->new( u => $u, data => $import_data ) >>

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless { u => $args{u}, data => $args{data}, comment_cache => {} }, $class;
}

sub u    { $_[0]->{u} }
sub data { $_[0]->{data} }

# writes ---------------------------------------------------------------------------------

sub post_entry {
    my ( $self, $entry, %opts ) = @_;

    my $posteru = $opts{posterid} ? LJ::load_userid( $opts{posterid} ) : undef;
    return DW::Worker::ContentImporter::Local::Entries->post_event( $self->{data}, $self->entry_map,
        $self->{u}, $posteru, $entry, $opts{errors},
        ( exists $opts{group_revision} ? ( group_revision => $opts{group_revision} ) : () ),
    );
}

sub update_entry_icon {
    my ( $self, $jitemid, $keyword ) = @_;
    my $u = $self->{u};

    my $entry = LJ::Entry->new( $u, jitemid => $jitemid );
    if ( $u->userpic_have_mapid ) {
        $entry->set_prop( picture_mapid => $u->get_mapid_from_keyword( $keyword, create => 1 ) );
    }
    else {
        $entry->set_prop( picture_keyword => $keyword );
    }
}

sub insert_comment {
    my ( $self, $comment, $errref ) = @_;
    return DW::Worker::ContentImporter::Local::Comments->insert_comment( $self->{u}, $comment,
        $errref, $self->{comment_cache} );
}

sub update_comment {
    my ( $self, $comment, $errref ) = @_;
    return DW::Worker::ContentImporter::Local::Comments->update_comment( $self->{u}, $comment,
        $errref );
}

sub merge_tags {
    my ( $self, $tags ) = @_;
    return DW::Worker::ContentImporter::Local::Tags->merge_tags( $self->{u}, $tags );
}

sub merge_trust_groups {
    my ( $self, $groups, %opts ) = @_;
    return DW::Worker::ContentImporter::Local::TrustGroups->merge_trust_groups( $self->{u},
        $groups, %opts );
}

sub save_groupmap {
    my ( $self, $map, $revision ) = @_;
    my $data = $self->{data};

    my $stored =
        defined $revision
        ? { map { $_ => "$map->{$_}:$revision" } keys %$map }
        : $map;

    my $dbh = LJ::get_db_writer()
        or croak 'unable to get global database handle';
    my $rows = $dbh->do(
        q{UPDATE import_data SET groupmap = ?
          WHERE userid = ? AND import_data_id = ?},
        undef, nfreeze($stored), $self->{u}->id, $data->{import_data_id}
    );
    return defined $rows;
}

sub merge_trust {
    my ( $self, $friends, %opts ) = @_;
    return DW::Worker::ContentImporter->merge_trust( $self->{u}, \%opts, $friends );
}

sub merge_interests {
    my ( $self, $interests ) = @_;
    return DW::Worker::ContentImporter::Local::Bio->merge_interests( $self->{u}, $interests );
}

sub merge_bio {
    my ( $self, $bio ) = @_;
    return DW::Worker::ContentImporter::Local::Bio->merge_bio_items( $self->{u}, $bio );
}

sub import_userpics {
    my ( $self, $errors, $default, $pics, $log ) = @_;
    return DW::Worker::ContentImporter::Local::Userpics->import_userpics( $self->{u}, $errors,
        $default, $pics, $log );
}

sub identity_user {
    my ( $self, $url ) = @_;

    # build the identity account (or return it if it exists)
    my $iu = LJ::User::load_identity_user( 'O', $url, undef )
        or return undef;
    return $iu->id;
}

sub save_usermap {
    my ( $self, $hostname, $username, $oid, $fid ) = @_;

    my $dbh = LJ::get_db_writer()
        or croak 'unable to get global database handle';
    $dbh->do(
'REPLACE INTO import_usermap (hostname, username, identity_userid, feed_userid) VALUES (?, ?, ?, ?)',
        undef, $hostname, $username, $oid, $fid
    );
}

sub dispatch_search_copy {
    my ( $self, $source ) = @_;

    if ( DW::Search::enabled() ) {
        DW::TaskQueue->dispatch(
            DW::Task::SearchCopier->new( { userid => $self->{u}->id, source => $source } ) );
    }
}

# reads --------------------------------------------------------------------------------------

sub entry_map {
    my ($self) = @_;
    return $self->{entry_map} ||=
        DW::Worker::ContentImporter::Local::Entries->get_entry_map( $self->{u} ) || {};
}

sub comment_map {
    my ($self) = @_;
    return DW::Worker::ContentImporter::Local::Comments->get_comment_map( $self->{u} ) || {};
}

# the entries we crossposted to the account being imported from, if we do
sub xpost_map {
    my ( $self, $hostname, $username ) = @_;
    my $u = $self->{u};

    # see if the account we're importing from is configured to crosspost
    my $acct = $self->_matching_account( $hostname, $username );
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
        my $xposted = DW::External::Account->xpost_string_to_hash($value);
        my $xpost   = $xposted->{ $acct->acctid }
            or next;

        # this item was crossposted, record it
        $map{$xpost} = $jitemid;
    }

    return \%map;
}

# the external account this user crossposts to, if it is the one being imported from
sub _matching_account {
    my ( $self, $hostname, $username ) = @_;

    my @accts = DW::External::Account->get_external_accounts( $self->{u} );

    my $dh = lc($hostname);
    $dh =~ s/^www\.//;

    my $duser = lc($username);
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

sub _load_groupmap {
    my ($self) = @_;
    my $data = $self->{data};

    my $dbh = LJ::get_db_writer()
        or croak 'unable to get global database handle';
    my $row = $dbh->selectrow_array(
        'SELECT groupmap FROM import_data WHERE userid = ? AND import_data_id = ?',
        undef, $data->{userid}, $data->{import_data_id} );
    my $raw = $row ? thaw($row) : {};
    return ( {}, undef ) unless ref $raw eq 'HASH' && %$raw;

    my ( %map, $revision );
    my $versioned = 1;
    while ( my ( $remote, $val ) = each %$raw ) {
        if ( defined $val && !ref $val && $val =~ /\A([1-9][0-9]?):([0-9]+)\z/ ) {
            $map{$remote} = $1 + 0;
            $versioned = 0 if defined $revision && $revision ne $2;
            $revision //= $2;
        }
        elsif ( defined $val && !ref $val && $val =~ /\A([1-9][0-9]?)\z/ ) {
            $map{$remote} = $1 + 0;
            $versioned = 0;
        }
        else {
            $versioned = 0;
        }
    }
    return ( \%map, $versioned ? $revision : undef );
}

sub groupmap {
    my ($self) = @_;
    my ($map)  = $self->_load_groupmap;
    return $map;
}

sub groupmap_with_revision {
    my ($self) = @_;
    return $self->_load_groupmap;
}

sub usermap_lookup {
    my ( $self, $hostname, $username ) = @_;

    my $dbh = LJ::get_db_writer()
        or return;
    return $dbh->selectrow_array(
'SELECT identity_userid, feed_userid FROM import_usermap WHERE hostname = ? AND username = ?',
        undef, $hostname, $username
    );
}

sub precache {
    my ( $self, $jitemids, $userids ) = @_;
    DW::Worker::ContentImporter::Local::Comments->precache( $self->{u}, $jitemids, $userids,
        $self->{comment_cache} );
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
