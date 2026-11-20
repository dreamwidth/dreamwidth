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
        deliverydate  => $date,
        anonymous     => $opts{anonymous} // 0,
    );
    my $item =
        $opts{points}
        ? DW::Shop::Item::Points->new( %item_args, points => 30 )
        : DW::Shop::Item::Account->new( %item_args, type => 'paid1' );
    my $cart = DW::Shop::Cart->new_cart($buyer) or die 'Cannot create cart';
    my ( $added, $error ) = $cart->add_item($item);
    die $error || 'Cannot add item' unless $added;
    $cart->{nextscan} = $opts{nextscan} // ( $now + 3600 );
    $item->{applied}  = 1 if $opts{applied};
    $cart->state( $opts{state} // $DW::Shop::STATE_PAID );
    $cart->save or die 'Cannot save cart';
    return $cart;
}

my $warning_14 = expiring_account( undef, 10, undef );
my $renewal_14 = add_order( $warning_14, $warning_14, $future );
my $warning_3  = expiring_account( undef, 2, 14 );
my $renewal_3  = add_order( $warning_3, $warning_3, $future );

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
my $due_today  = expiring_account( undef, -1, undef );
add_order( $due_today, $due_today, $today );
my $scannable = expiring_account( undef, -1, undef );
add_order( $scannable, $scannable, $past, nextscan => $now - 60 );

my $gifter = temp_user();
my @gifts;
for my $anonymous ( 0, 1 ) {
    my $account = expiring_account( undef, 10, undef );
    my $cart    = add_order( $gifter, $account, $future, anonymous => $anonymous );
    push @gifts, [ $account, $cart ];
}
my @other_carts = map { add_order( $gifter, $gifter, $later )->id } 1 .. 20;

my $community   = expiring_account( temp_comm(), -1, undef );
my @maintainers = ( temp_user(), temp_user() );
for my $maintainer (@maintainers) {
    $maintainer->set_email( $maintainer->user . '@example.test' );
    LJ::set_rel( $community, $maintainer, 'A' ) or die 'Cannot add maintainer';
}
add_order( $maintainers[0], $community, $today );

my ( %messages, @cart_reads, $warning_queries );
{
    no warnings 'redefine';
    local $dbh->{Callbacks} = {
        selectall_arrayref => sub {
            ++$warning_queries if $_[1] =~ /SELECT userid, lastemail/;
            return;
        },
    };
    my $read_cart = \&DW::Shop::Cart::get_from_cartid;
    local *DW::Shop::Cart::get_from_cartid = sub {
        push @cart_reads, $_[1];
        return $read_cart->(@_);
    };
    my $mysql_date = \&LJ::mysql_date;
    local *LJ::mysql_date = sub { return @_ ? $mysql_date->(@_) : $today; };
    my $monotonic = 42;
    local *Time::HiRes::clock_gettime = sub { return $monotonic; };
    local *LJ::send_mail              = sub {
        my ($mail) = @_;
        push @{ $messages{ $mail->{to} } }, $mail->{body} if defined $mail->{to};
        return 1;
    };
    my $stop  = bless {}, 'PaidstatusTest::Finished';
    my $loops = 0;
    local *LJ::DB::disconnect_dbs = sub {
        if ( ++$loops == 2 ) {
            is_deeply( messages_for($warning_14),
                [], 'Scheduled renewal suppresses the 14-day reminder' );
            is_deeply( messages_for($warning_3),
                [], 'Scheduled renewal suppresses the 3-day reminder' );
            is( last_email($warning_14), undef, 'Suppressed 14-day reminder is not marked sent' );
            is( last_email($warning_3),  14,    'Suppressed 3-day reminder is not marked sent' );
            my %fetched = map { $_ => 1 } @cart_reads;
            is_deeply( [ grep { $fetched{$_} } @other_carts ],
                [], 'Notice lookup does not read unrelated paid carts' );
            for my $gift (@gifts) {
                my ( $account, $cart ) = @$gift;
                my $kind = $cart->items->[0]->anonymous ? 'Anonymous gift' : 'Named gift';
                ok( !$fetched{ $cart->id }, "$kind: notice lookup does not read the cart" );
                is( scalar @{ messages_for($account) }, 1, "$kind: reminder is not suppressed" );
                like(
                    messages_for($account)->[0] // '',
                    qr{\Q/account?for=self\E},
                    "$kind: reminder is unchanged"
                );
                is( last_email($account), 14, "$kind: the regular reminder is recorded" );
                DW::Pay::update_paid_status( $account, expiretime => $now - 60 )
                    or die DW::Pay::error_text();
            }
            @cart_reads = ();
            $monotonic += 10;
        }
        elsif ( $loops == 3 ) {
            is( $warning_queries, 1, 'The next worker poll does not reselect reminder accounts' );
            is_deeply( \@cart_reads, [], 'The next worker poll does not reread any paid cart' );
            $renewal_14->state($DW::Shop::STATE_CLOSED);
            $renewal_14->save or die 'Cannot cancel cart';
            $renewal_3->state($DW::Shop::STATE_REFUNDED);
            $renewal_3->save or die 'Cannot refund cart';
            $monotonic += 300;
        }
        elsif ( $loops == 4 ) {
            die $stop;
        }
    };
    local $LJ::DISCONNECT_DBS = 0;
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

is( scalar @{ messages_for($warning_14) }, 1, 'Cancellation restores the regular 14-day reminder' );
is( last_email($warning_14),              14, 'The recovered 14-day reminder is recorded' );
is( scalar @{ messages_for($warning_3) }, 1,  'Refund restores the regular 3-day reminder' );
is( last_email($warning_3),               3,  'The recovered 3-day reminder is recorded' );
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
like( messages_for($due_today)->[0],
    qr/\Q$today\E/, 'An unapplied self-renewal scheduled for today still qualifies' );
cmp_ok( DW::Pay::get_paid_status($scannable)->{expiretime},
    '>', $now, 'A scannable self-renewal applies before the worker checks expiration' );

for my $maintainer (@maintainers) {
    is( scalar @{ messages_for($maintainer) }, 1, 'Each maintainer gets the community notice' );
    like( messages_for($maintainer)->[0],
        qr{\Q/account?for=gift\E}, 'Community notices are unchanged' );
    unlike(
        messages_for($maintainer)->[0],
        qr/\Q$today\E|scheduled renewal/i,
        'Community notices do not reveal a maintainer purchase'
    );
}
for my $gift (@gifts) {
    my ( $account, $cart ) = @$gift;
    my $kind = $cart->items->[0]->anonymous ? 'Anonymous gift' : 'Named gift';
    is( scalar @{ messages_for($account) },
        2, "$kind: the recipient gets the reminder and expiration notice" );
    like(
        messages_for($account)->[-1] // '',
        qr{\Q/account?for=self\E},
        "$kind: expiration notice is unchanged"
    );
    unlike(
        messages_for($account)->[-1] // '',
        qr/\Q$future\E|scheduled (?:renewal|to be applied)/i,
        "$kind: expiration notice does not reveal the gift"
    );
}
is( DW::Pay::get_paid_status($expired)->{expiretime}, undef, 'The personal account still expires' );
is( DW::Pay::get_paid_status($community)->{expiretime}, undef, 'The community still expires' );

done_testing;
