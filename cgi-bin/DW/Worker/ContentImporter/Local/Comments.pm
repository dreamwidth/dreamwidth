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

=head2 C<< $class->get_comment_map( $user, $hashref )

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

=head2 C<< $class->insert_comment( $u, $comment, $errref ) >>

$comment is a hashref representation of a single comment, with the following format:

  {
    subject => "Comment",
    body => 'I DID STUFF!!!!!',
    posterid => $local_userid,

    jitemid => $local_jitemid,

    parentid => $local_parent,

    state => 'A',
  }

$errref is a scalar reference to put any error text in.

=cut

sub insert_comment {
    my ( $class, $u, $cmt, $errref ) = @_;
    $errref ||= '';

    # load the data we need to make this comment
    use Data::Dumper;
    warn Dumper( $cmt ) unless $cmt->{jitemid};

    my $jitem = LJ::Entry->new( $u, jitemid => $cmt->{jitemid} );
    my $source = $jitem->prop( "import_source" ) . "?thread=" . ( $cmt->{id} << 8 );
    my $user = LJ::load_userid( $cmt->{posterid} )
        if $cmt->{posterid};

    # fix the XML timestamp to a useful timestamp
    my $date = $cmt->{date};
    $date =~ s/T/ /;
    $date =~ s/Z//;

    # sometimes the date is empty
    # FIXME: why?  Dre had this, when can the date be empty?
    $date ||= LJ::mysql_time();

    # build the data structures we use.  we are sort of faking it here.
    my $comment = {
        subject => $cmt->{subject},
        body => $cmt->{body},

        state => $cmt->{state},
        u => $user,

        props => {
            import_source => $source,
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


1;
