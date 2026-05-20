# t/pm-age-barrier.t
#
# Tests the PM age barrier at 18yo.
#
# Authors:
#
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2024 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;
use Test::More;
use DateTime;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user);
use LJ::User;

# Will hold temp user objects
my (
    $nineteen_today,          $eighteen_yesterday, $eighteen_today,
    $eighteen_in_1_to_4_days, $seventeen_today,    $age_unknown
);

# Test users and their ages
my @users = (    # \$user_obj, $years_old, $months_old, $days_old
    [ \$nineteen_today,          19, 0,  0 ],
    [ \$eighteen_yesterday,      18, 0,  1 ],
    [ \$eighteen_today,          18, 0,  0 ],
    [ \$eighteen_in_1_to_4_days, 17, 11, 28 ],    # 29..31 may get them to or past 18yo.
    [ \$seventeen_today,         17, 0,  0 ],
    [ \$age_unknown ]                             # Will use 0000-00-00 as init_bdate.
);

# Called as create_users(time(), @users)
sub create_users {
    my $time = shift;

    foreach my $user (@_) {
        my ( $user_obj_ref, $years_old, $months_old, $days_old ) = @$user;

        $$user_obj_ref = temp_user();

        if ( defined($years_old) && defined($months_old) && defined($days_old) ) {
            $$user_obj_ref->set_prop(
                "init_bdate",
                DateTime->from_epoch( epoch => $time )->subtract(
                    years  => $years_old,
                    months => $months_old,
                    days   => $days_old
                )->ymd
            );
        }
        else {
            $$user_obj_ref->set_prop( "init_bdate", "0000-00-00" );
        }

        $$user_obj_ref->set_prop( "opt_usermsg", "Y" );
    }
}

my $time = time();
my ( $h, $m ) = ( gmtime($time) )[ 2, 1 ];
if ( ( $h == 23 ) && ( $m == 59 ) ) {    # Assumes tests will take under 1 minute.
    plan skip_all => "Avoiding possible race condition at 23:59 UTC. Please rerun the test.";
}
else {
    create_users( $time, @users );

# ($nineteen_today, $eighteen_yesterday, $eighteen_today, $age_unknown) can all send to others in the group.
# ($eighteen_in_1_to_4_days, $seventeen_today) can both send to other in the group.
    my @can_send = (    # [$sending_user, $receiving_user, $description] for "can send" cases
        [ $nineteen_today,          $eighteen_yesterday,      "19+0 sending to 18+1" ],
        [ $nineteen_today,          $eighteen_today,          "19+0 sending to 18+0" ],
        [ $nineteen_today,          $age_unknown,             "19+0 sending to unknown age" ],
        [ $eighteen_yesterday,      $nineteen_today,          "18+1 sending to 19+0" ],
        [ $eighteen_yesterday,      $eighteen_today,          "18+1 sending to 18+0" ],
        [ $eighteen_yesterday,      $age_unknown,             "18+1 sending to unknown" ],
        [ $eighteen_today,          $nineteen_today,          "18+0 sending to 19+0" ],
        [ $eighteen_today,          $eighteen_yesterday,      "18+0 sending to 18+1" ],
        [ $eighteen_today,          $age_unknown,             "18+0 sending to unkwown" ],
        [ $age_unknown,             $nineteen_today,          "unknown sending to 19+0" ],
        [ $age_unknown,             $eighteen_yesterday,      "unknown sending to 18+1" ],
        [ $age_unknown,             $eighteen_today,          "unknown sending to 18+0" ],
        [ $eighteen_in_1_to_4_days, $seventeen_today,         "18-1..4 sending to 17+0" ],
        [ $seventeen_today,         $eighteen_in_1_to_4_days, "17+0 sending to 18-1..4" ]
    );

    # ($nineteen_today, $eighteen_yesterday, $eighteen_today, $age_unknown) and
    # ($eighteen_in_1_to_4_days, $seventeen_today) cannot send to any in the other group
    my @cannot_send = (    # [$sending_user, $receiving_user, $description] for "can't send" cases
        [ $nineteen_today,          $eighteen_in_1_to_4_days, "19+0 trying to send to 18-1..4" ],
        [ $eighteen_yesterday,      $eighteen_in_1_to_4_days, "18+1 trying to send to 18-1..4" ],
        [ $eighteen_today,          $eighteen_in_1_to_4_days, "18+0 trying to send to 18-1..4" ],
        [ $age_unknown,             $eighteen_in_1_to_4_days, "unknown trying to send to 18-1..4" ],
        [ $nineteen_today,          $seventeen_today,         "19+0 trying to send to 17+0" ],
        [ $eighteen_yesterday,      $seventeen_today,         "18+1 trying to send to 17+0" ],
        [ $eighteen_today,          $seventeen_today,         "18+0 trying to send to 17+0" ],
        [ $age_unknown,             $seventeen_today,         "unkwown trying to send to 17+0" ],
        [ $eighteen_in_1_to_4_days, $nineteen_today,          "18-1..4 trying to send to 19+0" ],
        [ $seventeen_today,         $nineteen_today,          "17+0 trying to send to 19+0" ],
        [ $eighteen_in_1_to_4_days, $eighteen_yesterday,      "18-1..4 trying to send to 18+1" ],
        [ $seventeen_today,         $eighteen_yesterday,      "17+0 trying to send to 18+0" ],
        [ $eighteen_in_1_to_4_days, $eighteen_today,          "18-1..4 trying to send to 18+0" ],
        [ $seventeen_today,         $eighteen_today,          "17+0 trying to send to 18+0" ],
        [ $eighteen_in_1_to_4_days, $age_unknown,             "18-1..4 trying to send to unknown" ],
        [ $seventeen_today,         $age_unknown,             "17+0 trying to send to unknown" ]
    );
    my $num_tests = scalar(@can_send) + scalar(@cannot_send);

    # Actual tests
    plan tests => $num_tests;
    foreach my $test (@can_send) {
        my ( $sending_user, $receiving_user, $description ) = @$test;
        ok( $receiving_user->can_receive_message($sending_user), $description );
    }
    foreach my $test (@cannot_send) {
        my ( $sending_user, $receiving_user, $description ) = @$test;
        ok( !$receiving_user->can_receive_message($sending_user), $description );
    }
}
