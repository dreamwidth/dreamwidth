#!/usr/bin/perl
#
# DW::Controller::API::REST::Entries
#
# API controls for entries
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::REST::Entries;
use base 'DW::Controller::API::REST';

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;

__PACKAGE__->register_rest_controller( '^/journals/([^/]*)/entries', 1 );

sub rest_get_list {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );

    my $journal = LJ::load_user( $journalname );
    return $self->rest_error( "No such user: $journalname" ) unless $journal;
    
    my $skip = 0;
   
    my $itemshow = 25;
    my $viewall = 1;
    my @itemids;
    my $err;
    my @items = $journal->recent_items(
        clusterid     => $journal->{clusterid},
        clustersource => 'slave',
        viewall       => $viewall,
        remote        => $rv->{remote},
        itemshow      => $itemshow + 1,
        skip          => $skip,
        tagids        => [],
        tagmode       => $opts->{tagmode},
        security      => $opts->{securityfilter},
        itemids       => \@itemids,
        dateformat    => 'S2',
        order         => $journal->is_community ? 'logtime' : '',
        err           => \$err,
        posterid      => undef,
        );
    foreach my $it ( @items ) {
        my $itemid  = $it->{'itemid'};
        my $ditemid = $itemid*256 + $it->{'anum'};
        $it->{ditemid} = $ditemid;
    }
    return $self->rest_ok( \@items );
}


sub rest_get_item {
    my ( $self, $opts, $journalname, $ditemid ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );

    my $journal = LJ::load_user( $journalname );
    return $self->rest_error( "No such user: $journalname" ) unless $journal;

    my $item = LJ::Entry->new($journal, ditemid => $ditemid);
    return $self->rest_error( "No such item $ditemid in journal $journalname" ) unless $item;
    
    return $self->rest_ok( $item );

}


1;
