# t/paid-time.t
#
# Test DW::Pay::add_paid_time.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 8;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Pay;
use LJ::Test qw (temp_user);

my $u1      = temp_user();
my $paidmos = 0;

my @lt    = localtime();
my $mdays = LJ::days_in_month( $lt[4] + 1, $lt[5] + 1900 );
die "Could not calculate days in month" unless $mdays;

my $dbh = LJ::get_db_writer();

# reset, delete, etc
sub rst {
    $dbh->do( 'DELETE FROM dw_paidstatus WHERE userid = ?', undef, $_ ) foreach ( $u1->id );
    $paidmos = 0;
}

sub assert {
    my ( $u, $type, $testname ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    subtest $testname => sub {
        plan tests => 4;

        my ($typeid) = grep { ( $LJ::CAP{$_}->{_account_type} || "" ) eq $type } keys %LJ::CAP;
        ok( $typeid, 'valid class' );

        my $ps   = DW::Pay::get_paid_status($u);
        my $secs = 86400 * $paidmos;
        $ps->{expiresin} = $secs if $type eq 'seed';    # not relevant to test
        ok( $ps,                                  'got paid status' );
        ok( $ps->{typeid} == $typeid,             'typeids match' );
        ok( abs( $ps->{expiresin} - $secs ) < 60, 'secs match within a minute' );

    }
}

################################################################################
rst();

# free->paid 1 month
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();
$paidmos += $mdays;    # 30

assert( $u1, 'paid', "free->paid 1 month" );

# paid +1 month
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();
$paidmos += $mdays;    # 60

assert( $u1, 'paid', "paid +1 month" );

# premium +1 month
DW::Pay::add_paid_time( $u1, 'premium', 1 )
    or die DW::Pay::error_text();
$paidmos = $paidmos * 0.7 + $mdays;

# should be 72 days... they bought 1 month of premium time (30 days)
# and they had 60 days of paid.  60 days of paid converts to 42 days
# of premium, 42+30 = 72 days premium.
assert( $u1, 'premium', "premium +1 month" );

# premium +1 month
DW::Pay::add_paid_time( $u1, 'premium', 1 )
    or die DW::Pay::error_text();
$paidmos += $mdays;    # 102

assert( $u1, 'premium', "premium +1 month" );

# paid +1 month == premium +21 days
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();
$paidmos += 21;        # 123

assert( $u1, 'premium', "paid +1 month == premium +21 days" );

################################################################################

# seed account
DW::Pay::add_paid_time( $u1, 'seed', 99 )
    or die DW::Pay::error_text();

# no additional paid time, but store old value for reference

assert( $u1, 'seed', "seed account" );

ok( !DW::Pay::add_paid_time( $u1, 'paid', 1 ), 'adding paid time fails' );

assert( $u1, 'seed', "seed account after trying to add paid time" );

################################################################################
