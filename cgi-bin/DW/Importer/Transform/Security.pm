#!/usr/bin/perl
#
# DW::Importer::Transform::Security
#
# Maps the visibility of imported content onto local security.
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

package DW::Importer::Transform::Security;

=head1 NAME

DW::Importer::Transform::Security - Remote security settings to local ones

=head1 DESCRIPTION

This decides who can read an imported entry, so it fails closed: whatever it does not
fully understand ends up private, with a warning, never more visible than the source
made it.

=head2 What it maps

=over

=item C<public> becomes public, and C<private> private. The access mask is ignored.

=item C<usemask> is access limited to those in the mask. Bit 0 is "trusted" (the
source's friends) and means the same here. Bit N, for N from 1 to 30, is the source's
group N; the group map says which local group that becomes. A group that has no local
group (it wasn't imported, or the friend groups job failed) is dropped from the mask,
never widened to something else.

=item If nothing is left of a mask that had something in it, the entry becomes private
and the warning C<Could not determine groups to post to.> is returned. An empty mask is
private.

=item A mask with both the trusted bit and groups left in it can't be posted (an entry is
for friends or for groups, not both), so it becomes private with a warning.

=item Anything else, including a missing or unrecognised security or a mask that isn't
a number, becomes private with a warning.

=back

=cut

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( map_security );

# a mask is bit 0 (trusted) and bits above it for groups: LiveJournal has up to 30 groups,
# local accounts up to 60
use constant MAX_REMOTE_GROUP => 30;
use constant MAX_LOCAL_GROUP  => 60;

=head2 C<< map_security( security => $s, allowmask => $m, groupmap => \%remote_to_local ) >>

Returns a hashref:

    {
        security   => 'public' | 'private' | 'usemask',
        allowmask  => the local mask (0 unless usemask),
        warnings   => [ ... ],   # things the user should be told about
        dropped    => [ ... ],   # source group ids that had no local group
    }

=cut

sub map_security {
    my (%args) = @_;
    my ( $security, $mask, $groupmap ) = @args{qw( security allowmask groupmap )};
    $groupmap = {} unless ref $groupmap eq 'HASH';

    my $private = sub {
        my (@warnings) = @_;
        return { security => 'private', allowmask => 0, warnings => \@warnings, dropped => [] };
    };

    return $private->("Unrecognised security setting, so the entry was made private.")
        unless defined $security && !ref $security;

    return { security => 'public', allowmask => 0, warnings => [], dropped => [] }
        if $security eq 'public';
    return $private->() if $security eq 'private';

    return $private->("Unrecognised security setting '$security', so the entry was made private.")
        unless $security eq 'usemask';

    $mask = 0 unless defined $mask && $mask ne '';
    return $private->("Unrecognised access list, so the entry was made private.")
        if ref $mask || $mask !~ /^\d+$/;
    $mask += 0;

    return $private->() if $mask == 0;

    my $newmask = $mask & 1 ? 1 : 0;
    my @dropped;
    foreach my $remote ( 1 .. MAX_REMOTE_GROUP ) {
        next unless $mask & ( 1 << $remote );

        my $local = $groupmap->{$remote};
        if ( defined $local && $local =~ /^\d+$/ && $local >= 1 && $local <= MAX_LOCAL_GROUP ) {
            $newmask |= 1 << $local;
        }
        else {
            push @dropped, $remote;
        }
    }

    # bits above the groups we know are not groups anywhere we could map them
    push @dropped, 'unknown' if $mask >> ( MAX_REMOTE_GROUP + 1 );

    # nothing usable was left, or only the trusted bit survived a mask that wanted groups:
    # we can't tell who this was meant for, so no one but the owner
    if ( $newmask == 0 || ( $newmask == 1 && $mask != 1 ) ) {
        return $private->("Could not determine groups to post to.");
    }

    # the site doesn't accept a mask that has both the trusted bit and groups in it (an entry
    # is for friends or for chosen groups), and we can't say which was meant
    if ( $newmask > 1 && $newmask & 1 ) {
        return $private->(
                  'This entry was visible to friends and to groups at once, which can not be'
                . ' represented here, so it was made private.' );
    }

    return { security => 'usemask', allowmask => $newmask, warnings => [], dropped => \@dropped };
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
