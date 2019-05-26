#!/usr/bin/perl
#
# DW::StatData::PaidAccounts - Paid accounts
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::StatData::PaidAccounts;

=head1 NAME

DW::StatData::PaidAccounts - Paid accounts

=head1 SYNOPSIS

  my $data = DW::StatData::PaidAccounts->collect( @keys ); # See list below
  my $stats_obj = DW::StatData::PaidAccounts->new( %$data );
 
=cut

use strict;
use warnings;

use base 'DW::StatData';
use DW::Pay;

sub category { "paid" }
sub name     { "Paid Accounts" }

sub keylist {
    my @account_type_keys;
    my $default_typeid = DW::Pay::default_typeid();
    my $shortnames     = DW::Pay::all_shortnames();

    while ( my ( $typeid, $name ) = each %$shortnames ) {
        next if $typeid == $default_typeid;

        push @account_type_keys, $name;
    }
    push @account_type_keys, 'total';
    return \@account_type_keys;
}

=head1 API

=head2 C<< $class->collect >>

Collects data for each account type, defined as any capability class under $LJ::CAP with an _account_type, but excluding the default (assumed to be free)

Example: paid, premium, seed

=over

=item paid

=item premium

=item seed

=back

=cut

sub collect {
    my $class = shift;
    my %data  = map { $_ => 0 } @_;

    my $dbslow = LJ::get_dbh('slow') or die "Can't get slow role";

    my $default_typeid = DW::Pay::default_typeid();
    my $sth            = $dbslow->prepare(
        qq{
        SELECT typeid, count(*) FROM dw_paidstatus WHERE typeid != ? GROUP BY typeid
    }
    );
    $sth->execute($default_typeid);

    while ( my ( $typeid, $active ) = $sth->fetchrow_array ) {
        next unless DW::Pay::type_is_valid($typeid);

        my $account_type = DW::Pay::type_shortname($typeid);
        $data{$account_type} = $active if exists $data{$account_type};
    }

    return \%data;
}

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

Trying to get the number of free accounts from dw_paidstatus will return an inaccurate number, because that only counts accounts which were paid at some point. So we do not collect stats for the default_typeid, which are free accounts for Dreamwidth. This makes assumptions, but I think not too out of line. 

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
