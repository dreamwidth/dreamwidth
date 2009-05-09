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
sub keylist  {
    my @account_type_keys;
    my $default_typeid = DW::Pay::default_typeid();

    foreach my $typeid ( keys %LJ::CAP ) {
        next if $typeid == $default_typeid;

        push @account_type_keys, $LJ::CAP{$typeid}->{_account_type} if $LJ::CAP{$typeid}->{_account_type};
    }

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
    my %data = map { $_ => 0 } @_;

    my $dbslow = LJ::get_dbh( 'slow' ) or die "Can't get slow role";

    my $sth = $dbslow->prepare( qq{
        SELECT typeid, count(*) FROM dw_paidstatus GROUP BY typeid
    } );
    $sth->execute;

    my $default_typeid = DW::Pay::default_typeid();
    while ( my ( $typeid, $active ) = $sth->fetchrow_array ) {
        next if $typeid == $default_typeid;

        my $account_type = $LJ::CAP{$typeid}->{_account_type};
        next unless defined $account_type and exists $data{$account_type};

        $data{$account_type} = $active;
    }

    return \%data;
}

=head1 BUGS

Trying to get the number of free accounts from dw_paidstatus will return an inaccurate number, because that only counts accounts which were paid at some point. So we do not collect stats for the default_typeid, which are free accounts for Dreamwidth. This makes assumptions, but I think not too out of line. 

Needs to refactor more of the logic into DW::Pay (or some kind of BusinessRule or hook, to take care of site-specific logic)

=head1 AUTHORS

Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
