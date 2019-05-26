#!/usr/bin/perl
#
# DW::StatData::ActiveAccounts - Active accounts, by #days since last active
# and account level
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#      Some code based off bin/maint/stats.pl
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
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
use DW::Pay;

sub category { "active" }
sub name     { "Active Accounts" }

my %key_to_days = ( active_1d => 1, active_7d => 7, active_30d => 30 );

sub keylist {
    my @levels = ( 'unknown', values %{ DW::Pay::all_shortnames() } );
    my @keys   = ();
    foreach my $k ( keys %key_to_days ) {
        push @keys, $k, map { +"$k-$_", "$k-$_-P", "$k-$_-C", "$k-$_-I" } @levels;
    }
    return \@keys;
}

=head1 API

=head2 C<< $class->collect >>

Collects data for the following keys:

=over

=item active_1d, active_1d-I<< level name >>, active_1d-I<< level name >>-I<< type letter >>

Number of accounts active in the last 24 hours (total, for each account
level, and for each account level and type - for personal, community, and
identity accounts only)

=item active_7d, active_7d-I<< level name >>, active_7d-I<< level name >>-I<< type letter >>

Number of accounts active in the last 168 (7*24) hours (total, for each
account level, and for each account level and type - for personal, community,
and identity accounts only)

=item active_30d, active_30d-I<< level name >>, active_30d-I<< level name >>-I<< type letter >>

Number of accounts active in the last 720 (30*24) hours (total, for each
account level, and for each account level and type - for personal, community,
and identity accounts only)

=back

In the above, I<< level name >> is any of the account level names returned by
C<< DW::Pay::all_shortnames >> or "unknown", and I<< type letter >> is P for
personal, C for community, or I for identity (OpenID, etc).

=cut

sub collect {
    my ( $class, @keys ) = @_;
    my $max_days = 0;
    my %data;
    my $shortnames = DW::Pay::all_shortnames();
    my @levels     = ( '', 'unknown', values %$shortnames );

    foreach my $k (@keys) {
        my ( $keyprefix, $keylevel, $keytype ) = split( '-', $k );
        $keylevel ||= '';
        $keytype  ||= '';

        die "Unknown statkey $k for $class"
            unless exists $key_to_days{$keyprefix}
            and grep { $_ eq $keylevel } @levels
            and $keytype =~ /^[PCI]?$/;

        $max_days = $key_to_days{$keyprefix}
            if $max_days < $key_to_days{$keyprefix};
        $data{$k} = 0;
    }

    LJ::DB::foreach_cluster(
        sub {
            my ( $cid, $dbr ) = @_;    # $cid isn't used

            my $sth = $dbr->prepare(
                qq{
            SELECT FLOOR((UNIX_TIMESTAMP()-timeactive)/86400) as days,
                   accountlevel, journaltype, COUNT(*)
            FROM clustertrack2
            WHERE timeactive > UNIX_TIMESTAMP()-?
            GROUP BY days, accountlevel, journaltype }
            );
            $sth->execute( $max_days * 86400 );

            while ( my ( $days, $level, $type, $active ) = $sth->fetchrow_array ) {
                $level = ( defined $level ) ? $shortnames->{$level} : 'unknown';
                $type ||= '';

                # which day interval(s) does this fall in?
                # -- in last day, in last 7, in last 30?
                foreach my $k (@keys) {
                    my ( $keyprefix, $keylevel, $keytype ) = split( '-', $k );
                    $keylevel ||= '';
                    $keytype  ||= '';
                    if (   $days < $key_to_days{$keyprefix}
                        && ( $keylevel eq $level || $keylevel eq '' )
                        && ( $keytype eq $type   || $keytype eq '' ) )
                    {
                        $data{$k} += $active;
                    }
                }
            }
        }
    );

    return \%data;
}

=head1 BUGS

Because not all account types are collected separately, only P/C/I, but the
per-level stats count all types, the numbers don't add up. This is arguably
a bug in the design.

=head1 AUTHORS

Pau Amma <pauamma@dreamwidth.org>, with some code based off bin/maint/stats.pl

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
