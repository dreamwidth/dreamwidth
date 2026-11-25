#!/usr/bin/perl
#
# t/paidstatus-checkmoneyorder.t
#
# Paid account notices for pending check and money order payments.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
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
use DW::Shop;
use DW::Shop::Cart;
use DW::Shop::Item::Account;
use DW::Shop::Item::Points;

{
    no warnings qw(once redefine);
    my $stop = bless {}, 'PaidstatusCheckMoneyOrderTest::Ready';
    local *LJ::DB::disconnect_dbs = sub { die $stop };
    do "$ENV{LJHOME}/bin/worker/paidstatus";
    die $@ || $! || 'Could not load the worker' unless ref $@ eq ref $stop;
}

local $LJ::IS_DEV_SERVER    = 1;
local $LJ::ACCOUNTS_EMAIL   = 'accounts@example.test';
local $LJ::T_SUPPRESS_EMAIL = 1;
local $LJ::SHOP{paid1} = [ 3, 1, 'paid',    30 ];
local $LJ::SHOP{prem1} = [ 5, 1, 'premium', 50 ];
local $LJ::SHOP{points} = [];

my $dbh = LJ::get_db_writer() or die 'No test database';
my ( @cartids, @paidids, @mail );
my $accounts_email         = qr/\Q$LJ::ACCOUNTS_EMAIL\E/;
my $renewal_link           = qr{/account\?for=self};
my $community_renewal_link = qr{/account\?for=gift&user=};
my $pending_payment        = qr/check or money order/i;

END {
    if ($dbh) {
        $dbh->do( 'DELETE FROM shop_carts WHERE cartid = ?',    undef, $_ ) foreach @cartids;
        $dbh->do( 'DELETE FROM dw_paidstatus WHERE userid = ?', undef, $_ ) foreach @paidids;
    }
}

sub set_expiration {
    my ( $account, $seconds ) = @_;
    DW::Pay::update_paid_status( $account, expiretime => time() + $seconds )
        or die DW::Pay::error_text();
}

sub paid_account {
    my ( $account, $type ) = @_;
    $account ||= temp_user();
    push @paidids, $account->id;
    DW::Pay::add_paid_time( $account, $type || 'paid', 1 ) or die DW::Pay::error_text();
    set_expiration( $account, 2 * 86400 );
    return $account;
}

sub pending_cart {
    my ( $buyer, $recipient, %opts ) = @_;
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;
    my $cart = DW::Shop::Cart->new_cart($buyer) or die 'Could not create cart';
    push @cartids, $cart->id;
    my %item_args = ( from_userid => $buyer->id, target_userid => $recipient->id );
    my $item =
        $opts{points}
        ? DW::Shop::Item::Points->new( %item_args, points => 50 )
        : DW::Shop::Item::Account->new(
        %item_args,
        type      => $opts{type} || 'paid1',
        anonymous => $opts{anonymous},
        );
    die 'Could not build cart item' unless $item;
    my ( $ok, $error ) = $cart->add_item($item);
    die "Could not add cart item: $error" unless $ok;
    $cart->paymentmethod( $opts{method} || 'checkmoneyorder' );
    $cart->state($DW::Shop::STATE_CHECKOUT);
    $cart->state($DW::Shop::STATE_PEND_PAID);
    return $cart;
}

sub reminder {
    my ($account) = @_;
    @mail = ();
    my $row = $dbh->selectrow_arrayref(
'SELECT userid, lastemail, expiretime - UNIX_TIMESTAMP() FROM dw_paidstatus WHERE userid = ?',
        undef, $account->id,
    ) or die 'Missing paid-account fixture';
    warn_user( $dbh, $row ) or die 'Reminder failed';
    return @mail;
}

sub expiration {
    my ($account) = @_;
    @mail = ();
    set_expiration( $account, -60 );
    expire_user( $dbh, $account->id ) or die DW::Pay::error_text();
    return @mail;
}

sub standard_notices {
    my ($account) = @_;
    my ($warning) = reminder($account);
    like( $warning->{body} // '', $renewal_link, 'Sends the usual 3-day reminder' );
    my ($expired) = expiration($account);
    like( $expired->{body} // '', $renewal_link, 'Sends the usual expiration notice' );
    unlike( ( $warning->{body} // '' ) . ( $expired->{body} // '' ),
        $pending_payment, 'Neither notice mentions a pending payment' );
}

{
    no warnings qw(once redefine);
    local *LJ::send_mail = sub { push @mail, $_[0]; return 1; };

    subtest 'Pending self-renewal' => sub {
        my $account = paid_account( undef, 'premium' );
        pending_cart( $account, $account, type => 'prem1' );
        set_expiration( $account, 10 * 86400 );
        my ($early) = reminder($account);
        like( $early->{body} // '', $renewal_link, 'The 14-day reminder is unchanged' );

        set_expiration( $account, 2 * 86400 );
        my @warnings = reminder($account);
        is( scalar @warnings, 1, 'One 3-day reminder is sent' );
        like( $warnings[0]{body} // '',
            $accounts_email, '3-day reminder directs the buyer to Accounts' );
        unlike( $warnings[0]{body} // '',
            $renewal_link, '3-day reminder does not ask for another order' );
        is( scalar reminder($account), 0, 'The 3-day reminder is not sent again at the next poll' );

        my @expired = expiration($account);
        is( scalar @expired, 1, 'One expiration notice is sent' );
        like( $expired[0]{body} // '',
            $accounts_email, 'Expiration notice directs the buyer to Accounts' );
        unlike( $expired[0]{body} // '',
            $renewal_link, 'Expiration notice does not ask for another order' );
        is( DW::Pay::get_account_type($account), 'free', 'Account still expires' );
    };

    subtest 'Gift carts do not change personal notices' => sub {
        my $buyer = paid_account();
        for my $anonymous ( undef, 1 ) {
            my $recipient = paid_account();
            pending_cart( $buyer, $recipient, anonymous => $anonymous );
            standard_notices($recipient);
        }
        standard_notices($buyer);
    };

    for my $scenario (
        [ 'Payment received', $DW::Shop::STATE_PAID ],
        [ 'Cart cancelled',   $DW::Shop::STATE_CLOSED ],
        [ 'Cart refunded',    $DW::Shop::STATE_REFUNDED ],
        )
    {
        my ( $name, $state ) = @$scenario;
        subtest $name => sub {
            my $account = paid_account();
            my $cart    = pending_cart( $account, $account );
            $cart->state($state);
            standard_notices($account);
        };
    }

    subtest 'Other pending purchases do not qualify' => sub {
        my $account = paid_account();
        pending_cart( $account, $account, method => 'stripe' );
        pending_cart( $account, $account, points => 1 );
        standard_notices($account);
    };

    subtest 'Maintainer renewal changes community notices' => sub {
        my $community        = paid_account( temp_comm() );
        my $maintainer       = temp_user();
        my $other_maintainer = temp_user();
        $other_maintainer->set_email( $other_maintainer->user . '@example.test' );
        LJ::set_rel( $community, $maintainer,       'A' );
        LJ::set_rel( $community, $other_maintainer, 'A' );
        pending_cart( $maintainer, $community );

        set_expiration( $community, 10 * 86400 );
        my @early = reminder($community);
        is( scalar @early, 2, 'Both maintainers still get the 14-day reminder' );
        for my $notice (@early) {
            like( $notice->{body} // '',
                $community_renewal_link, 'The 14-day reminder is unchanged' );
            unlike( $notice->{body} // '',
                $pending_payment, 'The early reminder omits payment details' );
        }

        set_expiration( $community, 2 * 86400 );
        my @warnings          = reminder($community);
        my @expired           = expiration($community);
        my @maintainer_emails = sort map { $_->email_raw } ( $maintainer, $other_maintainer );
        for my $notices ( \@warnings, \@expired ) {
            is_deeply( [ sort map { $_->{to} } @$notices ],
                \@maintainer_emails, 'Notice goes to both maintainers' );
            for my $notice (@$notices) {
                like( $notice->{body} // '',
                    $pending_payment, 'Notice mentions the pending payment' );
                like( $notice->{body} // '',
                    $accounts_email, 'Notice directs maintainers to Accounts' );
                unlike( $notice->{body} // '',
                    $community_renewal_link, 'Notice does not ask for another order' );
            }
        }
    };

    for my $scenario ( 'Non-maintainer gift', 'No pending community renewal' ) {
        subtest $scenario => sub {
            my $community  = paid_account( temp_comm() );
            my $maintainer = temp_user();
            LJ::set_rel( $community, $maintainer, 'A' );
            if ( $scenario eq 'Non-maintainer gift' ) {
                pending_cart( temp_user(), $community );
            }
            else {
                pending_cart( $maintainer, $maintainer );
            }
            my @warnings = reminder($community);
            my @expired  = expiration($community);
            for my $notices ( \@warnings, \@expired ) {
                is_deeply(
                    [ map { $_->{to} } @$notices ],
                    [ $maintainer->email_raw ],
                    'Notice goes only to the maintainer'
                );
                my ($notice) = @$notices;
                like( $notice->{body} // '',
                    $community_renewal_link, 'Notice uses the community renewal link' );
                unlike( $notice->{body} // '',
                    $pending_payment, 'Notice omits unrelated pending payments' );
            }
        };
    }
}

done_testing;
