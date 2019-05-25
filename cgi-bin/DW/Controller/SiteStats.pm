#!/usr/bin/perl
#
# DW::Controller::SiteStats
#
# Controller module for new DW stats (public and restricted)
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

=head1 NAME

DW::Controller::SiteStats -- Controller for new DW stats (public and restricted)

=head1 SYNOPSIS

  use DW::Controller::SiteStats; # That's all there is to it.

=cut

use strict;
use warnings;

package DW::Controller::Sitestats;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::StatStore;
use DW::StatData;
use DW::Controller::Admin;

LJ::ModuleLoader::require_subclasses('DW::StatData');

DW::Routing->register_string(
    '/stats/site', \&stats_page,
    app  => 1,
    args => [ 'stats/site.tt', \&public_data, 1 ]
);

DW::Routing->register_string(
    '/admin/stats', \&stats_page,
    app  => 1,
    args => [ 'admin/stats.tt', \&admin_data, 0, 'payments' ]
);
DW::Controller::Admin->register_admin_page(
    '/',
    path     => '/admin/stats',
    ml_scope => '/admin/stats.tt',
    privs    => ['payments']
);

=head1 Internals

=head2 C<< DW::Controller::SiteStats::stats_page( $opts ) >>

C<< $opts->args >> is C<< [ $template, $source, $anon_ok, $privs ] >>, where

=over

=item $template -- filename of template, relative to views/

=item $source -- subref to retrieve stat data passed to template

=item $anon_ok -- true if anonymous not-logged-in access to the page is allowed

=item $privs -- (optional) privs needed, in the privcheck => controller format

=back

=cut

sub stats_page {
    my ( $template, $source, $anon_ok, $privs ) = @{ $_[0]->args };

    my ( $ok, $rv ) = controller( anonymous => $anon_ok, privcheck => $privs );

    return $rv unless $ok;

    my %vars = ( %$rv, %{ $source->() } );

    return DW::Template->render_template( $template, \%vars );
}

=head2 C<< _make_a_number( $value ) >>

Internal - return $value forced to a number

=cut

sub _make_a_number {
    return defined( $_[0] ) ? $_[0] + 0 : 0;
}

=head2 C<< _dashes_to_underlines( $string ) >>

Internal - returns $string with - characters changed to _

=cut

sub _dashes_to_underlines {
    my $undashed = $_[0];
    $undashed =~ tr/\-/_/;
    return $undashed;
}

=head2 C<< DW::Controller::SiteStats::public_data( ) >>

Public stats data

Returns hashref of variables to pass to the template. For example,
$vars->{accounts_by_type}->{personal} has a value equal to the number of
personal accounts. Note: doesn't check or care whether user should have
access. That's for the caller to do.

=cut

sub public_data {
    my $vars = {};

    # Accounts by type
    my $accounts_by_type =
        DW::StatData::AccountsByType->load_latest( DW::StatStore->get("accounts") );
    if ( defined $accounts_by_type ) {
        $vars->{accounts_by_type} =
            { map { _dashes_to_underlines($_) => _make_a_number( $accounts_by_type->value($_) ) }
                @{ $accounts_by_type->keylist } };

        # Computed: total personal and community accounts
        $vars->{accounts_by_type}->{total_PC} =
            $vars->{accounts_by_type}->{personal} + $vars->{accounts_by_type}->{community};
    }

    # Active accounts by time since last active, level, and type
    my $active_accounts = DW::StatData::ActiveAccounts->load_latest( DW::StatStore->get("active") );
    if ( defined $active_accounts ) {
        $vars->{active_accounts} =
            { map { _dashes_to_underlines($_) => _make_a_number( $active_accounts->value($_) ) }
                @{ $active_accounts->keylist } };

        # Computed: total active personal and community accounts
        $vars->{active_accounts}->{active_PC} =
            $vars->{active_accounts}->{active_30d_free_P} +
            $vars->{active_accounts}->{active_30d_paid_P} +
            $vars->{active_accounts}->{active_30d_premium_P} +
            $vars->{active_accounts}->{active_30d_seed_P} +
            $vars->{active_accounts}->{active_30d_free_C} +
            $vars->{active_accounts}->{active_30d_paid_C} +
            $vars->{active_accounts}->{active_30d_premium_C} +
            $vars->{active_accounts}->{active_30d_seed_C};

        # Computed: total active allpaid (paid, premium, and seed) accounts
        $vars->{active_accounts}->{active_allpaid} =
            $vars->{active_accounts}->{active_30d_paid} +
            $vars->{active_accounts}->{active_30d_premium} +
            $vars->{active_accounts}->{active_30d_seed};

        # Computed: total allpaid (paid, premium, and seed) personal accounts
        # active in the last 1/7/30 days
        $vars->{active_accounts}->{"active_${_}d_allpaid_P"} =
            $vars->{active_accounts}->{"active_${_}d_paid_P"} +
            $vars->{active_accounts}->{"active_${_}d_premium_P"} +
            $vars->{active_accounts}->{"active_${_}d_seed_P"}
            foreach qw( 1 7 30 );

        # Computed: total allpaid community accounts
        # active in the last 1/7/30 days
        $vars->{active_accounts}->{"active_${_}d_allpaid_C"} =
            $vars->{active_accounts}->{"active_${_}d_paid_C"} +
            $vars->{active_accounts}->{"active_${_}d_premium_C"} +
            $vars->{active_accounts}->{"active_${_}d_seed_C"}
            foreach qw( 1 7 30 );

        # Computed: total allpaid identity accounts
        # active in the last 1/7/30 days
        $vars->{active_accounts}->{"active_${_}d_allpaid_I"} =
            $vars->{active_accounts}->{"active_${_}d_paid_I"} +
            $vars->{active_accounts}->{"active_${_}d_premium_I"} +
            $vars->{active_accounts}->{"active_${_}d_seed_I"}
            foreach qw( 1 7 30 );
    }

    # Paid accounts by level
    my $paid = DW::StatData::PaidAccounts->load_latest( DW::StatStore->get("paid") );
    if ( defined $paid ) {
        $vars->{paid} = { map { _dashes_to_underlines($_) => _make_a_number( $paid->value($_) ) }
                @{ $paid->keylist } };
        $vars->{paid}->{allpaid} = 0;
        $vars->{paid}->{allpaid} += $vars->{paid}->{$_} foreach @{ $paid->keylist };
    }

    return $vars;
}

=head2 C<< DW::Controller::SiteStats::admin_data( ) >>

Admin stats data

Returns hashref of variables to pass to the template. Note: doesn't check or
or care whether user should have access. That's for the caller to do.

=cut

sub admin_data {
    my $vars = public_data(@_);    # Just in case it gets arguments someday.

    <<COMMENT;

FIXME: remove this when you have implemented them all

* Number of accounts, total (done)
* Number of accounts active (done)
* Number of paid accounts (by payment level) (done)
  -- as a percentage of total accounts (done)
  -- as a percentage of active accounts (done)
  -- number of active paid accounts (done)
  -- number of inactive paid accounts (done)
* Number of payments in last 1d/2d/5d/7d/1m/3m/1y
  -- broken down by which payment level/payment item chosen
  -- and divided into new payments vs. renewals
  -- and expressed as a dollar amount taken in during that time
* Number of lapsed paid accounts in last 1d/2d/5d/7d/1m/3m/1y
  -- and renewed within 7d/14d/1m
  -- and not renewed within 7d/14d/1m
  -- and as a percentage of total paid accounts
* Percent churn over last 7d/1m/3m/1y
 -- (churn formula: total lapsed paid accounts that don't renew within 7d/total
paid accounts * 100)
* Number of paid accounts that were created via payment (no code)
* Number of paid accounts that were created via code, then paid
  -- within 1d/2d/5d/7d/1m/3m/1y of creation
* Total refunds issued within last 7d/1m/3m/1y
  -- with dollar amount refunded
  -- with fees added to dollar amount refunded
* Total chargebacks/PayPal refunds within last 7d/1m/3m/1y
  -- with dollar amount charged back
  -- with fees added to dollar amount charged back
COMMENT

    return $vars;
}

1;
