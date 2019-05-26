#!/usr/bin/perl
#
# bin/get-users-for-paid-accounts.pl
#
# Builds data set for paid account gifts.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}
use LJ::Sysban;
use DW::Pay;
use List::Util qw( min );

my $dbslow = LJ::get_dbh('slow');
my $dbh    = LJ::get_db_writer();

my $userids = $dbslow->selectcol_arrayref(
    "SELECT userid FROM user WHERE statusvis = 'V' AND journaltype IN ( 'P', 'C' )");
my $starttime = $dbslow->selectrow_array("SELECT UNIX_TIMESTAMP()");

my $week_ago  = $starttime - 60 * 60 * 24 * 7;
my $month_ago = $starttime - 60 * 60 * 24 * 30;

while ( @$userids && ( my @userids_chunk = splice( @$userids, 0, 100 ) ) ) {
    my $us = LJ::load_userids(@userids_chunk);
    foreach my $userid ( keys %$us ) {
        my $u = $us->{$userid};

        next if $u->is_paid;                    # must not be a paid user
        next if $u->timecreate > $month_ago;    # must be created more than a month ago
        next if $u->number_of_posts < 10;       # must have at least 10 posts
        next if $u->timeupdate < $week_ago;     # must have posted in the past week
        next unless $u->opt_randompaidgifts;    # must allow random paid gifts
        next if LJ::sysban_check( 'pay_user', $u->user );    # must not be sysbanned from payments

        my $members_count = 0;
        if ( $u->is_community ) {
            $members_count = scalar $u->member_userids;
            next if $members_count < 10;    # community must have at least 10 members
        }

        # get the number of entries posted and comments left in the past month
        my $dbcr = LJ::get_cluster_reader($u);
        my $num_posts =
            $dbcr->selectrow_array( "SELECT COUNT(*) FROM log2 WHERE journalid = ? AND logtime > ?",
            undef, $userid, LJ::mysql_time($month_ago) );
        my $num_comments;
        if ( $u->is_personal ) {
            $num_comments = $dbcr->selectrow_array(
                "SELECT COUNT(*) FROM talkleft WHERE userid = ? AND posttime > ?",
                undef, $userid, $month_ago );
        }
        else {
            $num_comments = $dbcr->selectrow_array(
                "SELECT COUNT(*) FROM talk2 WHERE journalid = ? AND datepost > ?",
                undef, $userid, LJ::mysql_time($month_ago) );
        }

        # assign point values based on these numbers
        my $post_points    = min( 10, $num_posts )     || 0;
        my $comment_points = min( 10, $num_comments )  || 0;
        my $member_points  = min( 10, $members_count ) || 0;

        # insert the total points for the user
        $dbh->do(
"INSERT INTO users_for_paid_accounts ( userid, time_inserted, points, journaltype ) VALUES ( ?, ?, ?, ? )",
            undef,
            $userid,
            $starttime,
            $post_points + $comment_points + $member_points,
            $u->journaltype
        );
    }
}

# delete all old data
$dbh->do( "DELETE FROM users_for_paid_accounts WHERE time_inserted < ?", undef, $starttime );

1;
