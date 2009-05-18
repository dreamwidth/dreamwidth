#!/usr/bin/perl
#
# DW::StatData::ActiveAccounts - Active accounts, by #days since last active
#
# Authors:
#      Pau Amma <pauamma@cpan.org>
#      Some code based off bin/maint/stats.pl
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::StatData::ActiveAccounts;

=head1 NAME

DW::StatData::ActiveAccounts - Active accounts, by #days since last active

=head1 SYNOPSIS

  my $stats_obj = DW::StatData::ActiveAccounts->new( %$data );

  # Don't use in web context.
  my $data = DW::StatData::ActiveAccounts->collect( @keys ); # See list below

An account is counted as active when it logs in, when it posts an entry (when
posting to a community, both the poster and the community are marked active),
or when it posts or edits a comment.
 
=cut

use strict;
use warnings;

use base 'DW::StatData';

sub category { "active" }
sub name     { "Active Accounts" }
sub keylist  { [ qw( active_1d active_7d active_30d ) ] }

=head1 API

=head2 C<< $class->collect >>

Collects data for the following keys:

=over

=item active_1d

Number of accounts active in the last 24 hours

=item active_7d

Number of accounts active in the last 168 (7*24) hours

=item active_30d

Number of accounts active in the last 720 (30*24) hours

=back

=cut

my %key_to_days = ( active_1d => 1, active_7d => 7, active_30d => 30 );
sub collect {
    my ( $class, @keys ) = @_;
    my $max_days = 0;
    my %data;

    foreach my $k ( @keys ) {
        die "Unknown statkey $k for $class"
            unless exists $key_to_days{$k};
        $max_days = $key_to_days{$k}
            if $max_days < $key_to_days{$k};
        $data{$k} = 0;
    }

    LJ::foreach_cluster( sub {
        my ( $cid, $dbr ) = @_; # $cid isn't used

        my $sth = $dbr->prepare( qq{
            SELECT FLOOR((UNIX_TIMESTAMP()-timeactive)/86400) as days, COUNT(*)
            FROM clustertrack2
            WHERE timeactive > UNIX_TIMESTAMP()-? GROUP BY days } );
        $sth->execute( $max_days*86400 );

        while ( my ( $days, $active ) = $sth->fetchrow_array ) {

            # which day interval(s) does this fall in?
            # -- in last day, in last 7, in last 30?
            foreach my $k ( @keys ) {
                $data{$k} += $active if $days < $key_to_days{$k};
            }
        }
    } );

    return \%data;
}

=head1 BUGS

Bound to be some.

=head1 AUTHORS

Pau Amma <pauamma@cpan.org>, with some code based off bin/maint/stats.pl

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
