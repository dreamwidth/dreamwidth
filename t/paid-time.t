#!/usr/bin/perl

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use DW::Pay;
use LJ::Test qw (temp_user);

plan tests => 29;

my $u1 = temp_user();
my $paidmos = 0;

my @lt = localtime();
my $mdays = LJ::days_in_month( $lt[4] + 1, $lt[5] + 1900 );
die "Could not calculate days in month" unless $mdays;

my $dbh = LJ::get_db_writer();

# reset, delete, etc
sub rst {
    $dbh->do( 'DELETE FROM dw_paidstatus WHERE userid = ?', undef, $_ )
        foreach ( $u1->id );
    $paidmos = 0;
}

sub assert {
    my ( $u, $type ) = @_;
    my ($typeid) = grep { $LJ::CAP{$_}->{_account_type} eq $type } keys %LJ::CAP;
    ok( $typeid, 'valid class' );

    my $ps = DW::Pay::get_paid_status( $u );
    my $secs = 86400 * $paidmos;
    ok( $ps, 'got paid status' );
    ok( $ps->{typeid} == $typeid, 'typeids match' );
    ok( abs( $ps->{expiresin} - $secs) < 60, 'secs match within a minute' );
}

################################################################################
rst();

# free->paid 1 month
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();
$paidmos += $mdays;  # 30

assert( $u1, 'paid' );

# paid +1 month
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();
$paidmos += $mdays;  # 60

assert( $u1, 'paid' );

# premium +1 month
DW::Pay::add_paid_time( $u1, 'premium', 1 )
    or die DW::Pay::error_text();
$paidmos = $paidmos * 0.7 + $mdays;

# should be 72 days... they bought 1 month of premium time (30 days)
# and they had 60 days of paid.  60 days of paid converts to 42 days
# of premium, 42+30 = 72 days premium.
assert( $u1, 'premium' );

# premium +1 month
DW::Pay::add_paid_time( $u1, 'premium', 1 )
    or die DW::Pay::error_text();
$paidmos += $mdays;  # 102

assert( $u1, 'premium' );

# paid +1 month == premium +21 days
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();
$paidmos += int( $mdays * 0.7 );  # 123

assert( $u1, 'premium' );

################################################################################

# seed account
DW::Pay::add_paid_time( $u1, 'seed', 99 )
    or die DW::Pay::error_text();
$paidmos = 0;  # never expires

assert( $u1, 'seed' );

ok( ! DW::Pay::add_paid_time( $u1, 'paid', 1 ), 'adding paid time fails' );

assert( $u1, 'seed' );

################################################################################
