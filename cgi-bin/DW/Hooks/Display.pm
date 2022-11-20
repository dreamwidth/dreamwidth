#!/usr/bin/perl
#
# DW::Hooks::Display
#
# A file for miscellaneous display-related hooks.
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::Display;

use strict;
use LJ::Hooks;

# Displays extra info on finduser results. Called as:
#   LJ::Hooks::run_hooks("finduser_extrainfo", $u })
# Currently used to return paid status, expiration date, and number of
# unused invite codes.

LJ::Hooks::register_hook(
    'finduser_extrainfo',
    sub {
        my $u = shift;

        my $ret;

        my $paidstatus = DW::Pay::get_paid_status($u);
        my $numinvites = DW::InviteCodes->unused_count( userid => $u->id );

        unless ( DW::Pay::is_default_type($paidstatus) ) {
            $ret .= "  " . DW::Pay::type_name( $paidstatus->{typeid} );
            $ret .=
                $paidstatus->{permanent}
                ? ", never expires"
                : ", expiring " . LJ::mysql_time( $paidstatus->{expiretime} );
            $ret .= "\n";
        }

        if ($numinvites) {
            $ret .= "  Unused invites: " . $numinvites . "\n";
        }

        return $ret;
    }
);

LJ::Hooks::register_hook(
    'finduser_delve',
    sub {
        my ($us) = @_;

        my @users = sort { $a->user cmp $b->user } grep { !$_->is_community } values %$us;

        my $ret = '';

        my @paid;

        foreach my $u (@users) {
            my %ok    = ( $DW::Shop::STATE_PAID => 1, $DW::Shop::STATE_PROCESSED => 1 );
            my @carts = grep { $ok{ $_->state } } DW::Shop::Cart->get_all($u);
            push @paid, $u if @carts;
        }

        $ret .= sprintf( "%d accounts with payment history:\n", scalar @paid );
        $ret .= sprintf( "%s\n", $_->user ) foreach @paid;

        # infohistory

        my $dbh = LJ::get_db_reader();
        my $sth = $dbh->prepare("SELECT * FROM infohistory WHERE userid=?");

        my %emails;
        my %seen;

        foreach my $u (@users) {
            $sth->execute( $u->id );
            next unless $sth->rows;

            while ( my $info = $sth->fetchrow_hashref ) {
                if ( $info->{what} && $info->{what} eq 'email' ) {
                    my $e = $info->{oldvalue};
                    $emails{$e} ||= [];
                    push @{ $emails{$e} }, $u->user;
                    $seen{ $u->user } = 1;
                }
            }
        }

        if ( my $num_changed = scalar keys %seen ) {

            $ret .= sprintf( "%d additional historical email addresses on %d accounts:\n",
                scalar keys %emails, $num_changed );
        }

        foreach my $e ( sort keys %emails ) {
            $ret .= sprintf( "%s: used by %s\n", $e, join( ', ', @{ $emails{$e} } ) );
        }

        return $ret;
    }
);

1;
