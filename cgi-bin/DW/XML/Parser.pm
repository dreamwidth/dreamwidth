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

package DW::XML::Parser;
use base qw(XML::Parser);

use strict;


=head1 NAME

DW::XML::Parser - XML Parser with security options turned on. Use when parsing XML files that you don't control and that could contain potentially malicious input

=head1 SYNOPSIS

=cut

sub new {
    my ( $self, %opts ) = @_;

    # don't try to load external entities (remote/local file inclusion attacks)
    $opts{Handlers}->{ExternEnt} ||= \&_ignore_extern_ent,
    $opts{Handlers}->{ExternEntFin} ||= \&_ignore_extern_ent,

    return $self->SUPER::new( %opts );
}


sub _ignore_extern_ent {
    return "";
}

1;