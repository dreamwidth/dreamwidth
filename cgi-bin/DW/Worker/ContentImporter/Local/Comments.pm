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
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
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

=head2 C<< $class->get_comment_map( $user, $hashref ) >>

Returns a hashref mapping import_source keys to jtalkids

=cut

sub get_comment_map {
    my ( $class, $u ) = @_;

    my $p = LJ::get_prop( "talk", "import_source" );
    return {} unless $p;

    my $dbr = LJ::get_cluster_reader( $u );
    my %map;
    my $sth = $dbr->prepare( "SELECT jtalkid, value FROM talkprop2 WHERE journalid = ? AND tpropid = ?" );

    $sth->execute( $u->id, $p->{id} );

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
    $errref ||= '';

    # FIXME: we should try to do more than just update the picture keyword, this should handle
    # edits and such.  for now, I'm just trying to get the icons to update...
    my $c = LJ::Comment->instance( $u, jtalkid => $cmt->{id} )
        or return $$errref = 'Unable to instantiate LJ::Comment object.';
    my $pu = $c->poster;
    if ( $pu && $pu->userpic_have_mapid ) {
        $c->set_prop( picture_mapid => $u->get_mapid_from_keyword( $cmt->{props}->{picture_keyword}, create => 1 ) );
    } else {
        $c->set_prop( picture_keyword => $cmt->{props}->{picture_keyword} );
    }
}


=head2 C<< $class->insert_comment( $u, $comment, $errref ) >>

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

$errref is a scalar reference to put any error text in.

=cut

sub insert_comment {
    my ( $class, $u, $cmt, $errref ) = @_;
    $errref ||= '';

    # load the data we need to make this comment
    my $jitem = LJ::Entry->new( $u, jitemid => $cmt->{jitemid} );
    my $source = ( $cmt->{entry_source} || $jitem->prop( "import_source" ) ) . "?thread=" . ( $cmt->{id} << 8 );
    my $user = $cmt->{posterid} ? LJ::load_userid( $cmt->{posterid} ) : undef;

    # fix the XML timestamp to a useful timestamp
    my $date = $cmt->{date};
    $date =~ s/T/ /;
    $date =~ s/Z//;

    # sometimes the date is empty
    $date ||= LJ::mysql_time();

    # remove properties that we don't know or care about
    foreach my $name ( keys %{$cmt->{props} || {}} ) {
        delete $cmt->{props}->{$name}
            unless LJ::get_prop( talk => $name ) &&
                ( $name ne 'import_source' && $name ne 'imported_from' );
    }

    # build the data structures we use.  we are sort of faking it here.
    my $comment = {
        subject => $cmt->{subject},
        body => $cmt->{body},

        state => $cmt->{state},
        u => $user,

        # we have to promote these from properties to the main comment hash so that
        # the enter_imported_comment function can demote them back to properties
        picture_keyword => delete $cmt->{props}->{picture_keyword},
        preformat       => delete $cmt->{props}->{opt_preformatted},
        subjecticon     => delete $cmt->{props}->{subjecticon},
        unknown8bit     => delete $cmt->{props}->{unknown8bit},

        props => {
            import_source => $source,
            imported_from => $cmt->{source},
            %{$cmt->{props} || {}},
        },

        no_urls => 1,
        no_esn => 1,
    };

    my $item = {
        itemid => $cmt->{jitemid},
    };

    my $parent = {
        talkid => $cmt->{parentid},
    };

    # now try to import it and return this as the error code
    return LJ::Talk::Post::enter_imported_comment( $u, $parent, $item, $comment, $date, \$errref );
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
