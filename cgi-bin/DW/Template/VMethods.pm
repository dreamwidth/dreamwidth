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

my $sort_subs = {
    alpha   => sub { $_[0] cmp $_[1] },
    numeric => sub { $_[0] <=> $_[1] },
};

$Template::Stash::LIST_OPS->{sort_by_key} = sub {
    my ( $lst, $k, $type, @rest ) = @_;

    my @r  = ();
    my $sb = $sort_subs->{ $type || 'alpha' };

    if ( $type && $type eq 'order' ) {
        my ( $v_type, $o_ky ) = @rest;
        $o_ky ||= 'order';

        $sb = $sort_subs->{ $v_type || 'alpha' };
        return $lst unless defined $sb;

        @r = sort { ( $a->{$o_ky} || 0 ) <=> ( $a->{$o_ky} || 0 ) || $sb->( $a->{$k}, $b->{$k} ) }
            @$lst;
    }
    elsif ( defined $sb ) {
        @r = sort { $sb->( $a->{$k}, $b->{$k} ) } @$lst;
    }
    else {
        return $lst;
    }

    return \@r;
};

1;
