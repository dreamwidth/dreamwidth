#!/usr/bin/perl
#
# DW::Importer::Sink
#
# The interface through which imports write to the local site.
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

package DW::Importer::Sink;

=head1 NAME

DW::Importer::Sink - Where imported content is written

=head1 DESCRIPTION

Import jobs never write to the local site themselves: every write goes through a sink.
L<DW::Importer::Sink::Live> makes the writes; L<DW::Importer::Sink::DryRun> records
what it would have written, so a dry run can show an import's effect without having it.
A sink belongs to one job, and holds the caches and the map of what the job has
written so far.

This class documents the interface; both sinks inherit from it.

=head2 Writes

=over

=item C<< post_entry( $entry, posterid => $id, errors => \@errors ) >>

Posts an entry record whose security is already local, as the poster (for communities)
or the journal owner. Returns C<( $ok, $result )>; failures are added to C<errors>. The
entry is remembered in the C<entry_map>, so posting it again does nothing.

=item C<< update_entry_icon( $local_entry_id, $keyword ) >>

=item C<< insert_comment( $comment, \$error ) >>

Returns the new local id, or false (with the reason in C<$error>). The comment has its
local C<jitemid>, C<parentid>, C<posterid> and C<entry_source>.

=item C<< update_comment( $comment, \$error ) >>

=item C<< merge_tags( \@tags ) >>

=item C<< merge_trust_groups( \@groups ) >>

Returns a map from the source's group ids to local ones.

=item C<< save_groupmap( \%map ) >>

Remembers the group map for the import, for entries and friends to use.

=item C<< merge_trust( \@friends ) >>

=item C<< merge_interests( \@interests ) >>

=item C<< merge_bio( $bio ) >>

=item C<< import_userpics( \@errors, $default, \@pics, $log ) >>

Returns the source ids of the icons that were imported.

=item C<< identity_user( $openid_url ) >>

Finds or creates the local OpenID account for an identity, and returns its userid.

=item C<< save_usermap( $hostname, $username, $userid, $feed_userid ) >>

=item C<< dispatch_search_copy( $source ) >>

=back

=head2 Reads

Reads go to the real database in every sink, so a dry run of a re-import knows what is
already there.

=over

=item C<< entry_map >>

C<import_source> key to local entry id, for entries here, including the ones this job
has written.

=item C<< comment_map >>

=item C<< xpost_map( $hostname, $username ) >>

Remote entry id to local id of the entries we crossposted to that account.

=item C<< groupmap >>

=item C<< usermap_lookup( $hostname, $username ) >>

Returns C<( $userid, $feed_userid )>.

=item C<< precache( \@entry_ids, \@user_ids ) >>

Loads what the comments about to be written will need.

=back

=head2 Notes

=over

=item C<< note( $kind, %details ) >>

Tells the sink about something that was left unwritten: C<skip> (already imported),
C<orphan>, C<unmapped> (comments), or C<warning>. A live sink ignores them; a dry run
reports them.

=back

=cut

use strict;
use warnings;

use Carp qw( croak );

our $AUTOLOAD;

foreach my $method (
    qw( post_entry update_entry_icon insert_comment update_comment merge_tags merge_trust_groups
    save_groupmap merge_trust merge_interests merge_bio import_userpics identity_user
    save_usermap dispatch_search_copy entry_map comment_map xpost_map groupmap
    usermap_lookup precache )
    )
{
    no strict 'refs';
    *{$method} = sub { croak ref( $_[0] ) . " does not implement $method" };
}

sub note { return }

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
