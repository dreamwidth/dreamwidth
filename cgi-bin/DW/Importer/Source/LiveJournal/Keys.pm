#!/usr/bin/perl
#
# DW::Importer::Source::LiveJournal::Keys
#
# Builds and reads the keys that identify imported LiveJournal content.
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

package DW::Importer::Source::LiveJournal::Keys;

=head1 NAME

DW::Importer::Source::LiveJournal::Keys - The key formats of LiveJournal imports

=head1 DESCRIPTION

Imported entries and comments are found again, on a re-import, by the key stored in
their C<import_source> property. Keys are stored data: these formats must never
change, or content already imported would be imported a second time.

An entry's key is C<hostname/journal/N> where N is the remote item id times 256 plus
its anum, as in a LiveJournal URL. A comment's key is its entry's key (or the
crossposter's pseudo-key) followed by C</N>, where N is the remote comment id times
256.

=cut

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( entry_key comment_key crosspost_source index_entries index_comments );

=head2 C<< entry_key( $hostname, $journal, $itemid, $anum ) >>

C<$journal> is the community when importing into one, otherwise the username.

=cut

sub entry_key {
    my ( $hostname, $journal, $itemid, $anum ) = @_;
    return $hostname . '/' . $journal . '/' . ( $itemid * 256 + $anum );
}

=head2 C<< comment_key( $entry_source, $remote_comment_id ) >>

=cut

sub comment_key {
    my ( $entry_source, $comment_id ) = @_;
    return $entry_source . '/' . ( $comment_id << 8 );
}

=head2 C<< crosspost_source( $hostname, $username, $remote_itemid ) >>

The pseudo entry key comments use on an entry we crossposted to the source.

=cut

sub crosspost_source {
    my ( $hostname, $username, $itemid ) = @_;
    return "CROSSPOSTER $hostname $username $itemid ";
}

# does this stored key belong to the import from this site and journal? this assumes keys
# never have other hostnames, so if someone were to register testlivejournal.com and do an
# import, they will have trouble importing.
sub _from_this_import {
    my ( $key, $hostname, @users ) = @_;

    ( my $turl = $key ) =~ s/-/_/g;    # makes \b work below
    return 0 unless $turl =~ /\Q$hostname\E/;
    foreach my $user ( grep { defined && length } @users ) {
        return 1 if $turl =~ /\b$user\b/;
    }
    return 0;
}

=head2 C<< index_entries( $entry_map, $hostname, $username, [ $usejournal ] ) >>

Takes the local map of C<import_source> key to local jitemid and returns what an
import from this site and journal already has:

    {
        by_remote_id => { remote itemid => local jitemid },
        source_of    => { local jitemid => its key },
        unparsed     => [ keys from this import that don't end in an id ],
    }

The username is matched with dashes read as underscores. Pass C<$usejournal> to also
accept keys that carry the community's name.

=cut

sub index_entries {
    my ( $map, $hostname, $username, $usejournal ) = @_;

    my %index = ( by_remote_id => {}, source_of => {}, unparsed => [] );
    foreach my $key ( keys %$map ) {
        next unless _from_this_import( $key, $hostname, $username, $usejournal );

        if ( $key =~ m!/(\d+)(?:\.html)?$! ) {
            my $itemid = $1 >> 8;
            $index{by_remote_id}->{$itemid} = $map->{$key};
            $index{source_of}->{ $map->{$key} } = $key;
        }
        else {
            push @{ $index{unparsed} }, $key;
        }
    }
    return \%index;
}

=head2 C<< index_comments( $comment_map, $hostname, $username, [ $usejournal ] ) >>

The same for comments: returns C<< { remote comment id => local jtalkid } >>.

=cut

sub index_comments {
    my ( $map, $hostname, $username, $usejournal ) = @_;

    my %by_remote_id;
    foreach my $key ( keys %$map ) {
        next unless _from_this_import( $key, $hostname, $username, $usejournal );

        $by_remote_id{ $1 >> 8 } = $map->{$key} if $key =~ m!(?:thread=|/)(\d+)$!;
    }
    return \%by_remote_id;
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
