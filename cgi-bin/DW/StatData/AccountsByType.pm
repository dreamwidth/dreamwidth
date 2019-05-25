#!/usr/bin/perl
#
# DW::StatData::AccountsByType - Total number of accounts broken down by type
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::StatData::AccountsByType;

=head1 NAME

DW::StatData::AccountsByType - Total number of accounts broken down by type

=head1 SYNOPSIS

  This module returns values for the following keys:
    redirect => number of redirected accounts
    identity => number of identity accounts
    personal => number of personal accounts
    syndicated => number of syndicated accounts
    community => number of community accounts
    total => total number of accounts

=cut

use strict;
use warnings;

use base 'DW::StatData';

=head1 API

=head2 C<< $class->collect >>
 
=cut

sub category { "accounts" }
sub name     { "Accounts by Type" }
sub keylist  { [qw( redirect identity personal syndicated community total )] }

sub collect {
    my $class = shift;
    my %opts  = map { $_ => 1 } @_;

    my %data;
    my $dbslow = LJ::get_dbh('slow') or die "Can't get slow role";

    # FIXME: look into using a count(*) ... group by. Efficiency?
    $data{redirect} = $dbslow->selectrow_array("SELECT COUNT(*) FROM user WHERE journaltype='R'")
        if $opts{redirect};
    $data{identity} = $dbslow->selectrow_array("SELECT COUNT(*) FROM user WHERE journaltype='I'")
        if $opts{identity};
    $data{personal} = $dbslow->selectrow_array("SELECT COUNT(*) FROM user WHERE journaltype='P'")
        if $opts{personal};
    $data{syndicated} = $dbslow->selectrow_array("SELECT COUNT(*) FROM user WHERE journaltype='Y'")
        if $opts{syndicated};
    $data{community} = $dbslow->selectrow_array("SELECT COUNT(*) FROM user WHERE journaltype='C'")
        if $opts{community};

    return \%data;
}

=head2 C<< $self->data >>
 
=cut

sub data {
    my $data = $_[0]->{data};

    # don't double-calculate the total
    return $data if $data->{total};

    my $total = 0;
    $total += $data->{$_} foreach keys %$data;
    $data->{total} = $total;
    return $data;
}

=head1 BUGS

Total is sometimes double-counted, maybe when you have multiple runs per collection period

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
