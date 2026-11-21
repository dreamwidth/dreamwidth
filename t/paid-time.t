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

use Test::More tests => 12;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Pay;
use FindBin qw($Bin);
use LJ::Test qw( temp_user temp_comm );
use LJ::Userpic;

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

sub _create_icons {
    my ( $user, @files ) = @_;
    return map {
        open( my $image, '<:raw', "$Bin/data/userpics/$_" )
            or die "Cannot open $_: $!";
        my $data = do { local $/; <$image> };
        LJ::Userpic->create( $user, data => \$data );
    } @files;
}

sub _active_picids {
    my ($user) = @_;
    return [ map { $_->id } grep { !$_->inactive } LJ::Userpic->load_user_userpics($user) ];
}

subtest 'paid expiration counts icons on older journal entries' => sub {
    my $free_type = DW::Pay::default_typeid();
    local $LJ::CAP{$free_type}->{userpics} = 2;
    local $LJ::ALLOW_PICS_OVER_QUOTA = 0;
    my $user = temp_user();
    DW::Pay::add_paid_time( $user, 'paid', 1 ) or die DW::Pay::error_text();

    my ( $default, $used, $unused ) = _create_icons( $user, qw(good.jpg good.png good.gif) );
    $default->make_default;
    $used->set_keywords('used');

    my $entry = $user->t_post_fake_entry;
    my $mapid = $user->get_mapid_from_keyword('used') or die 'Missing icon mapping';
    $entry->set_prop( 'picture_mapid', $mapid );
    my $posted = time() - 90 * 86400;
    $user->do(
        'UPDATE log2 SET logtime=FROM_UNIXTIME(?), rlogtime=? WHERE journalid=? AND jitemid=?',
        undef, $posted, $LJ::EndOfTime - $posted,
        $user->id, $entry->jitemid
    ) or die $user->errstr;

    is( $entry->userpic_kw, 'used', 'the old entry uses the non-default icon' );
    ok( DW::Pay::expire_user( $user, force => 1 ), 'expire paid time' );
    is( $user->userpic_quota, 2, 'free quota applies' );
    is_deeply(
        _active_picids($user),
        [ $default->id, $used->id ],
        'the default and the historically used icon stay active instead of the newest upload'
    );

    ok( DW::Pay::add_paid_time( $user, 'paid', 1 ), 'renew paid time' );
    is_deeply(
        _active_picids($user),
        [ $default->id, $used->id, $unused->id ],
        'renewal reactivates the unused icon'
    );
};

subtest 'paid expiration keeps earliest uploads when icon use counts tie' => sub {
    my $free_type = DW::Pay::default_typeid();
    local $LJ::CAP{$free_type}->{userpics} = 2;
    local $LJ::ALLOW_PICS_OVER_QUOTA = 0;
    my $user = temp_user();
    DW::Pay::add_paid_time( $user, 'paid', 1 ) or die DW::Pay::error_text();

    my ( $first, $second, $default ) = _create_icons( $user, qw(good.jpg good.png good.gif) );
    $default->make_default;

    ok( DW::Pay::expire_user( $user, force => 1 ), 'expire paid time with no icon usage' );
    is( $user->userpic_quota, 2, 'free quota applies' );
    is_deeply(
        _active_picids($user),
        [ $first->id, $default->id ],
        'zero-use tie keeps the default and the earliest upload'
    );

    ok( DW::Pay::add_paid_time( $user, 'paid', 1 ), 'renew paid time' );
    is_deeply(
        _active_picids($user),
        [ $first->id, $second->id, $default->id ],
        'renewal reactivates the deactivated upload'
    );

    $first->set_keywords('first');
    $second->set_keywords('second');
    my $first_mapid  = $user->get_mapid_from_keyword('first')  or die 'Missing first icon mapping';
    my $second_mapid = $user->get_mapid_from_keyword('second') or die 'Missing second icon mapping';

    my $first_entry = $user->t_post_fake_entry;
    $first_entry->set_prop( 'picture_mapid', $first_mapid );
    my $second_entry = $user->t_post_fake_entry;
    $second_entry->set_prop( 'picture_mapid', $second_mapid );

    ok( DW::Pay::expire_user( $user, force => 1 ), 'expire paid time with tied icon usage' );
    is_deeply(
        _active_picids($user),
        [ $first->id, $default->id ],
        'equal non-zero use keeps the default and the earliest upload'
    );
};

subtest 'paid expiration counts only the account owner posting in their own journal' => sub {
    my $free_type = DW::Pay::default_typeid();
    local $LJ::CAP{$free_type}->{userpics} = 2;
    local $LJ::ALLOW_PICS_OVER_QUOTA = 0;
    my $user  = temp_user();
    my $other = temp_user();
    my $comm  = temp_comm();
    DW::Pay::add_paid_time( $user, 'paid', 1 ) or die DW::Pay::error_text();

    my ( $default, $external_only, $own_used ) =
        _create_icons( $user, qw(good.jpg good.png good.gif) );
    $default->make_default;
    $external_only->set_keywords('external');
    $own_used->set_keywords('own');
    my $external_mapid = $user->get_mapid_from_keyword('external')
        or die 'Missing external icon mapping';
    my $own_mapid = $user->get_mapid_from_keyword('own')
        or die 'Missing own icon mapping';

    my $own_entry = $user->t_post_fake_entry;
    $own_entry->set_prop( 'picture_mapid', $own_mapid );
    my $comm_entry = $user->t_post_fake_entry( usejournal => $comm->user, usejournal_okay => 1 );
    $comm_entry->set_prop( 'picture_mapid', $external_mapid );
    my $other_entry = $other->t_post_fake_entry( usejournal => $user->user, usejournal_okay => 1 );
    $other_entry->set_prop( 'picture_mapid', $external_mapid );

    is( $comm_entry->journalid,  $comm->id,  'community entry belongs to the community journal' );
    is( $other_entry->journalid, $user->id,  'other-poster entry belongs to the user journal' );
    is( $other_entry->posterid,  $other->id, 'other-poster entry has a different poster' );
    ok( DW::Pay::expire_user( $user, force => 1 ), 'expire paid time' );
    is_deeply(
        _active_picids($user),
        [ $default->id, $own_used->id ],
        'community and other-poster entries do not count toward own-journal icon usage'
    );
};

subtest 'partial reactivation selects highest numeric picids' => sub {
    my $free_type = DW::Pay::default_typeid();
    my ($paid_type) = grep { ( $LJ::CAP{$_}->{_account_type} || '' ) eq 'paid' } keys %LJ::CAP;
    local $LJ::CAP{$free_type}->{userpics} = 1;
    local $LJ::ALLOW_PICS_OVER_QUOTA = 0;
    my $user = temp_user();
    DW::Pay::add_paid_time( $user, 'paid', 1 ) or die DW::Pay::error_text();

    my ( $default, $low, $high ) = _create_icons( $user, qw(good.jpg good.png good.gif) );
    $default->make_default;

    ok( DW::Pay::expire_user( $user, force => 1 ), 'expire paid time to free quota of 1' );
    is_deeply( _active_picids($user), [ $default->id ],
        'only the default stays active at quota 1' );

    my ( $low_id, $high_id ) = ( 900000, 1000000 );
    $user->do( 'UPDATE userpic2 SET picid=? WHERE userid=? AND picid=?',
        undef, $low_id, $user->id, $low->id )
        or die $user->errstr;
    $user->do( 'UPDATE userpic2 SET picid=? WHERE userid=? AND picid=?',
        undef, $high_id, $user->id, $high->id )
        or die $user->errstr;
    LJ::Userpic->delete_cache($user);
    $user->clear_userpic_kw_map;

    local $LJ::CAP{$paid_type}->{userpics} = 2;
    ok( DW::Pay::add_paid_time( $user, 'paid', 1 ), 'renew paid time with quota 2' );
    is_deeply(
        _active_picids($user),
        [ $default->id, $high_id ],
        'partial reactivation picks the highest numeric picid across digit boundaries'
    );
};
