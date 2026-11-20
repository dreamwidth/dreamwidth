#!/usr/bin/perl
#
# t/paidstatus.t
#
# Test the paid-status worker's expiration notices.
#
# Authors:
#     SAPHID
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);
use DW::Pay;
use DW::Shop::Cart;
use DW::Shop::Item::Account;
use DW::Shop::Item::Points;
use LJ::Sendmail;

local $LJ::_PRAGMA_FORCE_MASTER       = 1;
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::DEFAULT_LANG               = 'en';
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;
local $LJ::T_SUPPRESS_EMAIL           = 1;
local $LJ::SHOP{paid1}  = [ 3, 1, 'paid', 30 ];
local $LJ::SHOP{points} = [];

my $dbh = LJ::get_db_writer() or die 'Cannot connect to the test database';
for my $table (qw(dw_paidstatus shop_carts)) {
    my ( undef, $ddl ) = $dbh->selectrow_array("SHOW CREATE TABLE $table");
    $ddl =~ s/^CREATE TABLE/CREATE TEMPORARY TABLE/;
    $dbh->do($ddl) or die $dbh->errstr;
}

my $now    = time;
my $future = LJ::mysql_date( $now + 7 * 86400 );
my $later  = LJ::mysql_date( $now + 9 * 86400 );
my $today  = LJ::mysql_date($now);
my $past   = LJ::mysql_date( $now - 86400 );

my %typeids = reverse %{ DW::Pay::all_shortnames() };

sub expiring_account {
    my ( $account, $days, $lastemail ) = @_;
    $account ||= temp_user();
    $account->set_email( $account->user . '@example.test' );
    DW::Pay::update_paid_status(
        $account,
        typeid     => $typeids{paid},
        expiretime => $now + $days * 86400,
        permanent  => 0,
        lastemail  => $lastemail
    ) or die DW::Pay::error_text();
    return $account;
}

sub add_order {
    my ( $buyer, $recipient, $date, %opts ) = @_;
    my %item_args = (
        from_userid   => $buyer->id,
        target_userid => $recipient->id,
        deliverydate  => $date
    );
    my $item =
        $opts{points}
        ? DW::Shop::Item::Points->new( %item_args, points => 30 )
        : DW::Shop::Item::Account->new( %item_args, type => 'paid1' );
    my $cart = DW::Shop::Cart->new_cart($buyer) or die 'Cannot create cart';
    my ( $added, $error ) = $cart->add_item($item);
    die $error || 'Cannot add item' unless $added;
    $cart->{nextscan} = $now + 3600;
    $item->{applied}  = 1 if $opts{applied};
    $cart->state( $opts{state} // $DW::Shop::STATE_PAID );
    $cart->save or die 'Cannot save cart';
}

my $warning_14 = expiring_account( undef, 10, undef );
add_order( $warning_14, $warning_14, $future );
my $warning_3 = expiring_account( undef, 2, 14 );
add_order( $warning_3, $warning_3, $future );

my $unpaid = expiring_account( undef, 10, undef );
add_order( $unpaid, $unpaid, $future, state => $DW::Shop::STATE_PEND_PAID );
my $not_renewal = expiring_account( undef, 2, 14 );
add_order( $not_renewal, $not_renewal, $future, points  => 1 );
add_order( $not_renewal, $not_renewal, $future, applied => 1 );
add_order( $not_renewal, $not_renewal, $past );

my $expired = expiring_account( undef, -1, undef );
add_order( $expired, $expired, $future );
add_order( $expired, $expired, $later );
my $no_renewal = expiring_account( undef, -1, undef );

my $community   = expiring_account( temp_comm(), -1, undef );
my @maintainers = ( temp_user(), temp_user() );
for my $maintainer (@maintainers) {
    $maintainer->set_email( $maintainer->user . '@example.test' );
    LJ::set_rel( $community, $maintainer, 'A' ) or die 'Cannot add maintainer';
}
add_order( $maintainers[0], $community, $today );

my %messages;
{
    no warnings 'redefine';
    local *LJ::send_mail = sub {
        my ($mail) = @_;
        push @{ $messages{ $mail->{to} } }, $mail->{body} if defined $mail->{to};
        return 1;
    };
    my $stop  = bless {}, 'PaidstatusTest::Finished';
    my $loops = 0;
    local *LJ::DB::disconnect_dbs = sub { die $stop if $loops++; };
    local $LJ::DISCONNECT_DBS     = 0;
    do "$ENV{LJHOME}/bin/worker/paidstatus";
    die $@ || $! unless ref $@ eq ref $stop;
}

sub messages_for {
    my ($account) = @_;
    return $messages{ $account->email_raw } || [];
}

sub last_email {
    my ($account) = @_;
    return $dbh->selectrow_array( 'SELECT lastemail FROM dw_paidstatus WHERE userid = ?',
        undef, $account->id );
}

is_deeply( messages_for($warning_14), [], 'Scheduled renewal suppresses the 14-day reminder' );
is_deeply( messages_for($warning_3),  [], 'Scheduled renewal suppresses the 3-day reminder' );
is( last_email($warning_14), undef, 'Suppressed 14-day reminder is not marked sent' );
is( last_email($warning_3),  14,    'Suppressed 3-day reminder is not marked sent' );
is( scalar @{ messages_for($unpaid) }, 1,  'Unconfirmed payment does not suppress the reminder' );
is( last_email($unpaid),               14, 'The regular 14-day reminder is recorded' );
is( scalar @{ messages_for($not_renewal) },
    1, 'Points, applied, and past-due items do not suppress the reminder' );
is( last_email($not_renewal), 3, 'The regular 3-day reminder is recorded' );

is( scalar @{ messages_for($expired) }, 1, 'One expiration email is sent with a pending renewal' );
like( messages_for($expired)->[0],
    qr/\Q$future\E/, 'Expiration email gives the earliest delivery date' );
unlike(
    messages_for($expired)->[0],
    qr{\Q$later\E|\Q/account?for=self\E},
    'Email does not suggest another purchase'
);
like( messages_for($no_renewal)->[0],
    qr{\Q/account?for=self\E}, 'An account with no renewal gets the usual expiration email' );

for my $maintainer (@maintainers) {
    is( scalar @{ messages_for($maintainer) }, 1, 'Each maintainer gets the community notice' );
    like( messages_for($maintainer)->[0],
        qr/\Q$today\E/, 'Community notice includes a renewal still pending on its scheduled day' );
}
is( DW::Pay::get_paid_status($expired)->{expiretime}, undef, 'The personal account still expires' );
is( DW::Pay::get_paid_status($community)->{expiretime}, undef, 'The community still expires' );

done_testing;
