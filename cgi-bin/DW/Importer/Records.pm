#!/usr/bin/perl
#
# DW::Importer::Records
#
# Documents the normalized records that import sources produce and sinks consume.
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

package DW::Importer::Records;

use strict;

=head1 NAME

DW::Importer::Records - The shapes of the data that flows through an import

=head1 DESCRIPTION

An import is a pipeline: a I<source> adapter reads the remote site (or a file) and
produces normalized records, pure I<transforms> adjust them, and a I<sink> writes them
locally (or, in a dry run, only records that it would). These are plain hashrefs; this
module has no code, it is the one place that says what they hold. A source fills in
what it has and leaves out the rest.

Text fields are Perl character strings or UTF-8 bytes exactly as the source gave them;
the sink takes care of encoding.

=head2 Entry

    {
        key       => 'livejournal.com/someone/263',   # unique across all sources; see below
        remote_id => 1,                # the id on the source, used to ask for it again
        url       => 'http://someone.livejournal.com/1.html',   # where it lives (may be undef)
        subject   => 'A subject',
        event     => 'The body, as HTML',
        security  => 'public',         # 'public', 'private' or 'usemask'
        allowmask => 0,                # with usemask: bit 0 is "trusted", bit N is group N
        eventtime => '2009-03-04 05:06:07',   # when the entry says it was written
        logtime   => '2009-03-04 05:06:08',   # when it was posted
        poster    => 'someone',        # who wrote it, for community journals; else undef
        props     => { picture_keyword => 'happy', current_mood => 'tired' },
    }

The C<key> becomes the local C<import_source> property and is how a re-import knows it
already has the entry, so a source must always build the same key for the same entry,
and no two sources may ever build the same one. Straight from a source C<security> and
C<allowmask> use the I<source's> groups; L<DW::Importer::Transform::Security> turns
them into local ones before an entry reaches a sink.

=head2 Comment

    {
        remote_id => 5,                # the comment's id on the source
        entry_id  => 1,                # remote_id of the entry it belongs to
        parent_id => 0,                # remote_id of the comment it replies to, or 0
        poster    => 'commenter',      # the source's name for the poster; undef if anonymous
        external  => 0,                # true if the poster is not an account on the source
        state     => 'A',              # 'A'ctive, 'S'creened, 'D'eleted, 'F'rozen
        subject   => 'Re: ...',
        body      => 'Text',
        date      => '2009-03-06T01:00:00Z',
        props     => { picture_keyword => 'smile' },
    }

Comments are keyed by the key of their entry plus their own id, which
L<DW::Importer::Source::LiveJournal::Keys> builds the way the LiveJournal importer
always has; sinks that are given a comment to write get the C<entry_source> (the entry's
key) and the local ids of the entry, poster and parent too.
L<DW::Importer::Threading> orders comments so a parent is always written first.

=head2 Tag

    { name => 'travel', display => 1 }

=head2 Trust group

    { id => 3, name => 'Family', sortorder => 10, public => 0 }

C<id> is the group's id on the source; the sink returns a map from it to the local id.

=head2 Friend

    { username => 'someone', groupmask => 3, type => undef, status => undef }

C<groupmask> uses the source's groups. A C<type> other than C<identity>, or a C<status>
(the account is not visible), means the friend is not imported.

=head2 Userpic

    { id => 7, src => 'http://.../pic.png', keywords => ['happy'], comment => 'Smiling',
      default => 1 }

=head2 Bio

    {
        bio => 'About me', jabber => '...', journaltitle => '...', journalsubtitle => '...',
        homepage => { url => 'http://...', title => 'My site' },
        interests => [ 'knitting', 'cats' ],
    }

=head2 Action

What a sink reports for every write it makes, or, in a dry run, would make:

    {
        type    => 'entry',            # entry, comment, comment_update, tag, trust_group, ...
        target  => 'livejournal.com/someone/263',   # a key or name that says what it is about
        summary => 'public entry "A subject"',
        record  => { ... },            # the record that would be written
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
