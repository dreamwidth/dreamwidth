#!/usr/bin/perl

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use DW::Pay;
use LJ::Test qw (temp_user);

plan tests => 29;

my $u1 = temp_user();

my $dbh = LJ::get_db_writer();

# reset, delete, etc
sub rst {
    $dbh->do( 'DELETE FROM dw_paidstatus WHERE userid = ?', undef, $_ )
        foreach ( $u1->id );
}

sub assert {
    my ( $u, $type, $secs ) = @_;
    my ($typeid) = grep { $LJ::CAP{$_}->{_account_type} eq $type } keys %LJ::CAP;
    ok( $typeid, 'valid class' );

    my $ps = DW::Pay::get_paid_status( $u );
    ok( $ps, 'got paid status' );
    ok( $ps->{typeid} == $typeid, 'typeids match' );
    ok( $ps->{expiresin} == $secs, 'secs match' );
}

################################################################################
rst();

# free->paid 1 month
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();

assert( $u1, 'paid', 30*86400 );

# paid +1 month
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();

assert( $u1, 'paid', 60*86400 );

# premium +1 month
DW::Pay::add_paid_time( $u1, 'premium', 1 )
    or die DW::Pay::error_text();

# should be 72 days... they bought 1 month of premium time (30 days)
# and they had 60 days of paid.  60 days of paid converts to 42 days
# of premium, 42+30 = 72 days premium.
assert( $u1, 'premium', 72*86400 );

# premium +1 month
DW::Pay::add_paid_time( $u1, 'premium', 1 )
    or die DW::Pay::error_text();

assert( $u1, 'premium', 102*86400 );

# paid +1 month == premium +21 days
DW::Pay::add_paid_time( $u1, 'paid', 1 )
    or die DW::Pay::error_text();

assert( $u1, 'premium', 123*86400 );

################################################################################

# seed account
DW::Pay::add_paid_time( $u1, 'seed', 99 )
    or die DW::Pay::error_text();

assert( $u1, 'seed', 0 );

ok( ! DW::Pay::add_paid_time( $u1, 'paid', 1 ), 'adding paid time fails' );

assert( $u1, 'seed', 0 );

################################################################################
