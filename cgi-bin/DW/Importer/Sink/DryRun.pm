#!/usr/bin/perl
#
# DW::Importer::Sink::DryRun
#
# A sink that records what an import would write instead of writing it.
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

package DW::Importer::Sink::DryRun;

=head1 NAME

DW::Importer::Sink::DryRun - Shows what an import would do

=head1 DESCRIPTION

Every write is recorded as an action in a L<DW::Importer::Report> and nothing else
happens: no database writes, nothing in BlobStore, memcache, the task queue or
TheSchwartz, and no accounts are created. Reads go to a live sink, so a dry run of a
re-import knows what is already there and reports it as skipped.

Writes still have to look as if they happened to what comes next: a comment's parent has
to have an id, a trust group an id that can be used in an access mask. So the sink makes
up ids (that can't be real ones: large numbers for entries, comments and users, and
unused group numbers for groups) and remembers what it has "written" in a I<world>, a hash
that can be shared with the sinks of the other jobs of one dry run, so the whole chain
(groups before entries before comments) hangs together.

=cut

use strict;
use warnings;

use Carp qw( croak );

use base 'DW::Importer::Sink';

use DW::Importer::Source::LiveJournal::Keys qw( comment_key );

# ids a real database would not hand out for a long while
use constant FAKE_ENTRY   => 2_000_000_000;
use constant FAKE_COMMENT => 2_100_000_000;
use constant FAKE_USER    => 2_200_000_000;

=head2 C<< DW::Importer::Sink::DryRun->new( live => $live_sink, report => $report, [ world => \%world ] ) >>

C<live> is used for reads only. Pass the same C<world> to the sinks of every job in a chain.

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless {
        live   => $args{live},
        report => $args{report},
        world  => $args{world} || $class->new_world,
    }, $class;
}

=head2 C<< DW::Importer::Sink::DryRun->new_world >>

An empty world.

=cut

sub new_world {
    return {
        entries    => {},
        comments   => {},
        identities => {},
        usermap    => {},
        tags       => {},
        groups     => {},
        groupmap   => undef,
        counter    => 0,
    };
}

sub report { $_[0]->{report} }
sub live   { $_[0]->{live} }
sub u      { $_[0]->{live}->u }

sub _fake_id {
    my ( $self, $base ) = @_;
    return $base + ++$self->{world}->{counter};
}

sub _record {
    my ( $self, %action ) = @_;
    $self->{report}->add_action(%action);
}

sub _quote {
    my ($text) = @_;
    $text = '' unless defined $text;
    $text =~ s/\s+/ /g;
    $text = substr( $text, 0, 37 ) . '...' if length $text > 40;
    return $text;
}

# writes ---------------------------------------------------------------------------------

sub post_entry {
    my ( $self, $entry, %opts ) = @_;

    # an entry we have is not posted again
    return if $self->entry_map->{ $entry->{key} };

    my $id = $self->_fake_id(FAKE_ENTRY);
    $self->entry_map->{ $entry->{key} } = $self->{world}->{entries}->{ $entry->{key} } = $id;

    my $security =
        $entry->{security} eq 'usemask' ? "usemask($entry->{allowmask})" : $entry->{security};
    $self->_record(
        type    => 'entry',
        target  => $entry->{key},
        summary => "$security entry \""
            . _quote( $entry->{subject} )
            . "\" of $entry->{eventtime}"
            . ( $opts{posterid} ? " as user $opts{posterid}" : '' ),
        record => { %$entry, posterid => $opts{posterid}, local_id => $id },
    );
    return ( 1, { itemid => $id } );
}

sub update_entry_icon {
    my ( $self, $jitemid, $keyword ) = @_;
    $self->_record(
        type    => 'entry_icon',
        target  => $jitemid,
        summary => "entry $jitemid icon keyword " . ( defined $keyword ? "'$keyword'" : '(none)' ),
        record  => { jitemid => $jitemid, keyword => $keyword },
    );
}

sub insert_comment {
    my ( $self, $comment, $errref ) = @_;

    my $key = comment_key( $comment->{entry_source}, $comment->{orig_id} );
    my $id  = $self->_fake_id(FAKE_COMMENT);
    $self->{world}->{comments}->{$key} = $id;

    $self->_record(
        type    => 'comment',
        target  => $key,
        summary => "comment $comment->{orig_id} ($comment->{state}) on entry $comment->{jitemid}"
            . ( $comment->{parentid} ? ", reply to $comment->{parentid}" : '' )
            . ( $comment->{posterid} ? ", by user $comment->{posterid}"  : ', anonymous' ),
        record => { %$comment, key => $key, local_id => $id },
    );
    return $id;
}

sub update_comment {
    my ( $self, $comment, $errref ) = @_;
    $self->_record(
        type    => 'comment_update',
        target  => $comment->{id},
        summary => "comment $comment->{id} icon keyword",
        record  => {%$comment},
    );
    return 1;
}

sub merge_tags {
    my ( $self, $tags ) = @_;

    my %have = map { $_->{name} => 1 } values %{ LJ::Tags::get_usertags( $self->u ) || {} };
    foreach my $tag (@$tags) {
        if ( $have{ $tag->{name} } || $self->{world}->{tags}->{ $tag->{name} } ) {
            $self->{report}->add_skip(
                type   => 'tag',
                target => $tag->{name},
                reason => 'already exists'
            );
            next;
        }
        $self->{world}->{tags}->{ $tag->{name} } = 1;
        $self->_record(
            type    => 'tag',
            target  => $tag->{name},
            summary => "tag $tag->{name}",
            record  => {%$tag}
        );
    }
}

sub merge_trust_groups {
    my ( $self, $groups ) = @_;

    my $current = $self->u->trust_groups || {};
    my %by_name = map { $current->{$_}->{groupname} => $_ } keys %$current;
    my %used    = (
        ( map { $_ => 1 } keys %$current ),
        ( map { $_ => 1 } values %{ $self->{world}->{groups} } )
    );

    my %map;
    foreach my $group (@$groups) {
        my $name = $group->{name};
        my $id   = $by_name{$name} // $self->{world}->{groups}->{$name};
        my $verb = $id ? 'update' : 'create';

        unless ($id) {

            # the lowest group number that is free: it has to work as a bit in an access mask
            ($id) = grep { !$used{$_} } 1 .. 60;
            $used{$id} = 1;
            $self->{world}->{groups}->{$name} = $id;
        }
        $map{ $group->{id} } = $id;

        $self->_record(
            type    => 'trust_group',
            target  => $name,
            summary => "$verb group $name as $id",
            record  => { %$group, local_id => $id },
        );
    }
    return \%map;
}

sub save_groupmap {
    my ( $self, $map ) = @_;
    $self->{world}->{groupmap} = {%$map};
    $self->_record(
        type    => 'groupmap',
        target  => 'groupmap',
        summary => 'group map '
            . join( ', ', map { "$_=>$map->{$_}" } sort { $a <=> $b } keys %$map ),
        record => {%$map},
    );
}

sub merge_trust {
    my ( $self, $friends ) = @_;
    foreach my $friend (@$friends) {
        $self->_record(
            type    => 'trust',
            target  => $friend->{userid},
            summary => "trust user $friend->{userid} with mask $friend->{groupmask}",
            record  => {%$friend},
        );
    }
}

sub merge_interests {
    my ( $self, $interests ) = @_;

    my $have = $self->u->interests || {};
    my @new  = grep { !defined $have->{$_} } @{ $interests || [] };
    $self->_record(
        type    => 'interests',
        target  => 'interests',
        summary => scalar(@new) . ' new interests: ' . join( ', ', @new ),
        record  => { interests => \@new },
    );
}

sub merge_bio {
    my ( $self, $bio ) = @_;
    my @fields = grep { defined $bio->{$_} } qw( bio jabber journaltitle journalsubtitle homepage );
    $self->_record(
        type    => 'bio',
        target  => 'bio',
        summary => 'bio fields: ' . join( ', ', @fields ),
        record  => { map { $_ => $bio->{$_} } @fields },
    );
}

sub import_userpics {
    my ( $self, $errors, $default, $pics, $log ) = @_;

    my @imported;
    my %seen;
    foreach my $pic ( grep { defined }
        ( ( $default && $default->{src} ? $default : undef ), @{ $pics || [] } ) )
    {
        next if $seen{ $pic->{id} }++;
        $self->_record(
            type    => 'userpic',
            target  => $pic->{id},
            summary => "icon $pic->{id} ("
                . join( ', ', @{ $pic->{keywords} || [] } ) . ')'
                . ( $pic->{default} ? ' default' : '' ),
            record => {%$pic},
        );
        push @imported, $pic->{id};
    }
    return @imported;
}

sub identity_user {
    my ( $self, $url ) = @_;

    my $existing = LJ::User::load_existing_identity_user( 'O', $url );
    return $existing->id if $existing && !$existing->is_expunged;

    return $self->{world}->{identities}->{$url} if $self->{world}->{identities}->{$url};

    my $id = $self->{world}->{identities}->{$url} = $self->_fake_id(FAKE_USER);
    $self->_record(
        type    => 'identity',
        target  => $url,
        summary => "OpenID account for $url as user $id",
        record  => { url => $url, local_id => $id },
    );
    return $id;
}

sub save_usermap {
    my ( $self, $hostname, $username, $oid, $fid ) = @_;
    $self->{world}->{usermap}->{"$hostname/$username"} = [ $oid, $fid ];
    $self->_record(
        type    => 'usermap',
        target  => "$hostname/$username",
        summary => "$username\@$hostname is user " . ( $oid // 'unmapped' ),
        record  => { hostname => $hostname, username => $username, identity_userid => $oid },
    );
}

sub dispatch_search_copy {
    my ( $self, $source ) = @_;
    $self->_record(
        type    => 'search_copy',
        target  => $source,
        summary => "index the journal ($source)"
    );
}

# reads --------------------------------------------------------------------------------------

sub entry_map {
    my ($self) = @_;
    return $self->{entry_map} ||= { %{ $self->{live}->entry_map }, %{ $self->{world}->{entries} } };
}

sub comment_map {
    my ($self) = @_;
    return { %{ $self->{live}->comment_map }, %{ $self->{world}->{comments} } };
}

sub xpost_map { my $self = shift; return $self->{live}->xpost_map(@_) }

sub groupmap {
    my ($self) = @_;
    return $self->{world}->{groupmap} || $self->{live}->groupmap;
}

sub usermap_lookup {
    my ( $self, $hostname, $username ) = @_;
    my $mapped = $self->{world}->{usermap}->{"$hostname/$username"};
    return $mapped ? @$mapped : $self->{live}->usermap_lookup( $hostname, $username );
}

sub precache { return }

sub note {
    my ( $self, $kind, %details ) = @_;

    my $report = $self->{report};
    if    ( $kind eq 'skip' )     { $report->add_skip(%details) }
    elsif ( $kind eq 'orphan' )   { $report->add_orphan(%details) }
    elsif ( $kind eq 'unmapped' ) { $report->add_unmapped(%details) }
    elsif ( $kind eq 'warning' )  { $report->add_warning( delete $details{text}, %details ) }
    return;
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
