#!/usr/bin/perl
#
# DW::Worker::ContentImporter::Local::Comments
#
# Local data utilities to handle importing of comments.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::Local::Comments;
use strict;

=head1 NAME

DW::Worker::ContentImporter::Local::Comments - Local data utilities for comments

=head1 Comments

These functions are part of the Saving API for comments.

=head2 C<< $class->precache( $u, $jitemid_hash, $userid_hash, $cache ) >>

Given a user and two hashrefs (keys are jitemids and then userids respectively), this
will do a bulk load of those items and precache them in C<$cache>, a hashref the caller
keeps and passes to C<insert_comment> (so nothing is shared between imports). This is
designed to be used right before we import a bunch of comments to give us some performance
and save all the roundtrips.

=cut

sub precache {
    my ( $class, $u, $jitemids, $userids, $cache ) = @_;

    $cache->{users} = LJ::load_userids(@$userids);

    foreach my $jitemid (@$jitemids) {
        $cache->{entries}->{$jitemid} = LJ::Entry->new( $u, jitemid => $jitemid );
    }
    LJ::Entry->preload_props_all();
}

=head2 C<< $class->get_comment_map( $user, $hashref ) >>

Returns a hashref mapping import_source keys to jtalkids. This really shouldn't
fail or we get into awkward duplication states.

=cut

sub get_comment_map {
    my ( $class, $u ) = @_;

    my $p = LJ::get_prop( "talk", "import_source" )
        or die "Failed to load import_source property.";
    my $dbr = LJ::get_cluster_reader($u)
        or die "Failed to get database reader for user.";
    my $sth =
        $dbr->prepare("SELECT jtalkid, value FROM talkprop2 WHERE journalid = ? AND tpropid = ?")
        or die "Failed to allocate statement handle.";
    $sth->execute( $u->id, $p->{id} )
        or die "Failed to execute query.";

    my %map;
    while ( my ( $jitemid, $value ) = $sth->fetchrow_array ) {
        $map{$value} = $jitemid;
    }
    return \%map;
}

=head2 C<< $class->update_comment( $u, $comment, $errref ) >>

Called by the importer when it has gotten a copy of a comment and wants to make sure that our local
copy of a comment is syncronized.

$comment is a hashref representation of a single comment, same as for <<insert_comment>>.

$errref is a scalar reference to put any error text in.

=cut

sub update_comment {
    my ( $class, $u, $cmt, $errref ) = @_;
    $errref ||= \my $discarded_error;

    # FIXME: we should try to do more than just update the picture keyword, this should handle
    # edits and such.  for now, I'm just trying to get the icons to update...
    my $c = LJ::Comment->instance( $u, jtalkid => $cmt->{id} )
        or return $$errref = 'Unable to instantiate LJ::Comment object.';

    # so we don't load the bodies of every comment ever
    # (most of the time, we don't need to)
    # empty body of a nondeleted comment indicates something went wrong with the import process
    if ( $LJ::FIX_COMMENT_IMPORT{ $u->user } && !$c->is_deleted && $c->body_raw eq "" ) {
        $c->set_subject_and_body( $cmt->{subject}, $cmt->{body} );
    }

    # (only what would change: setting a property to what it already is, or to nothing on a
    # comment that has none, would still write a row)
    my $pu = $c->poster;
    if ( $pu && $pu->userpic_have_mapid ) {
        my $mapid = $pu->get_mapid_from_keyword( $cmt->{props}->{picture_keyword}, create => 1 );
        $c->set_prop( picture_mapid => $mapid )
            if ( $c->prop('picture_mapid') // 0 ) != ( $mapid // 0 );
    }
    else {
        my $keyword = $cmt->{props}->{picture_keyword};
        $c->set_prop( picture_keyword => $keyword )
            if ( $c->prop('picture_keyword') // '' ) ne ( $keyword // '' );
    }
}

=head2 C<< $class->insert_comment( $u, $comment, $errref, [ $cache ] ) >>

$comment is a hashref representation of a single comment, with the following format:

  {
    subject => "Comment",
    body => 'I DID STUFF!!!!!',
    posterid => $local_userid,

    jitemid => $local_jitemid,

    parentid => $local_parent,

    props => { ... }, # hashref of talkprops

    state => 'A',
  }

$errref is a scalar reference to put any error text in. $cache is what C<precache> filled.

=cut

sub insert_comment {
    my ( $class, $u, $cmt, $errref, $cache ) = @_;
    $errref ||= \my $discarded_error;
    $cache  ||= {};

    # load the data we need to make this comment
    my $jitem = $cache->{entries}->{ $cmt->{jitemid} }
        || LJ::Entry->new( $u, jitemid => $cmt->{jitemid} );
    my $source =
        ( $cmt->{entry_source} || $jitem->prop("import_source") ) . "/" . ( $cmt->{orig_id} << 8 );
    my $user =
        $cmt->{posterid}
        ? ( $cache->{users}->{ $cmt->{posterid} } || LJ::load_userid( $cmt->{posterid} ) )
        : undef;

    # fix the XML timestamp to a useful timestamp
    my $date = $cmt->{date};
    $date =~ s/T/ /;
    $date =~ s/Z//;

    # sometimes the date is empty
    $date ||= LJ::mysql_time();

    # remove properties that we don't know or care about
    foreach my $name ( keys %{ $cmt->{props} || {} } ) {
        delete $cmt->{props}->{$name}
            unless LJ::get_prop( talk => $name )
            && ( $name ne 'import_source' && $name ne 'imported_from' );
    }

    # build the data structures we use.  we are sort of faking it here.
    my $comment = {
        subject => $cmt->{subject},
        body    => $cmt->{body},

        state => $cmt->{state},
        u     => $user,

        # we have to promote these from properties to the main comment hash so that
        # the enter_imported_comment function can demote them back to properties
        picture_keyword => delete $cmt->{props}->{picture_keyword},
        preformat       => delete $cmt->{props}->{opt_preformatted},
        subjecticon     => delete $cmt->{props}->{subjecticon},
        unknown8bit     => delete $cmt->{props}->{unknown8bit},

        props => {
            import_source => $source,
            imported_from => $cmt->{source},
            %{ $cmt->{props} || {} },
        },

        no_urls => 1,
        no_esn  => 1,
    };

    my $item = { itemid => $cmt->{jitemid}, };

    my $parent = { talkid => $cmt->{parentid}, };

    # now try to import it and return this as the error code
    return LJ::Talk::Post::enter_imported_comment( $u, $parent, $item, $comment, $date, $errref );
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
