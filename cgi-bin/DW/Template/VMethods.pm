#!/usr/bin/perl
#
# DW::Template::VMethods
#
# VMethods for the Dreamwidth Template Toolkit plugin
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Template::VMethods;
use strict;
use Template::Stash;

$Template::Stash::LIST_OPS->{ sort_by_key } = sub {
    my ( $lst, $k, $type ) = @_;

    my @r = ();
    $type ||= 'alpha';
    if ( $type eq 'alpha' ) {
        @r = sort { $a->{$k} cmp $b->{$k} } @$lst; 
    } elsif ( $type eq 'numeric' ) {
        @r = sort { $a->{$k} <=> $b->{$k} } @$lst; 
    }

    return \@r;
};

1;
