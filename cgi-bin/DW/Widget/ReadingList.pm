#!/usr/bin/perl
#
# DW::Widget::ReadingList
#
# Breakdown of the user's reading list
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::ReadingList;

use strict;
use base qw/ LJ::Widget /;
use DW::Template;

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my %count   = ( personal => 0, community => 0, syndicated => 0 );
    my @watched = $remote->watched_users;
    $count{ $_->journaltype_readable }++ foreach @watched;

    my @filters = $remote->content_filters;
    my $vars    = {
        filters => \@filters,
        remote  => $remote,
        count   => \%count
    };
    return DW::Template->template_string( 'widget/readinglist.tt', $vars );
}

1;

