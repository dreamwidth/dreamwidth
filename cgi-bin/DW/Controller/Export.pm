#!/usr/bin/perl
#
# DW::Controller::Export
#
# Pages for exporting journal content.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Export;

use v5.10;
use strict;

use DW::Routing;
use DW::Template;
use DW::Controller;

DW::Routing->register_string( '/export', \&index_handler, app => 1 );

sub get_encodings {
    my ( %encodings, %encnames );
    LJ::load_codes( { "encoding" => \%encodings } );
    LJ::load_codes( { "encname"  => \%encnames } );

    my $rv = {};
    foreach my $id ( keys %encodings ) {
        next if lc $encodings{$id} eq 'none';
        $rv->{ $encodings{$id} } = $encnames{$id};
    }
    return $rv;
}

sub index_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    $rv->{encodings} = [ %{ get_encodings() } ];

    return DW::Template->render_template( 'export/index.tt', $rv );
}

1;
