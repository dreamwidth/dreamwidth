#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::RPC;

use strict;
use LJ::JSON;

=head1 NAME

DW::RPC - Convenience methods to print output for RPC endpoints

=head1 SYNOPSIS

=cut

sub out {
    my ( $class, %obj ) = @_;
    my $r = DW::Request->get;
    $r->print( to_json( \%obj ) );
    return $r->OK;
}

# return error as { error => error or "" }
sub err {
    my ( $class, $err ) = @_;
    my $r = DW::Request->get;
    $r->print( to_json( { error => $err ? $err : "" } ) );
    return $r->OK;
}

# return error as { alert => ..., error => 1 }
sub alert {
    my ( $class, $err ) = @_;
    my $r = DW::Request->get;
    $r->print( to_json( { alert => $err, error => 1 } ) );
    return $r->OK;
}

1;
