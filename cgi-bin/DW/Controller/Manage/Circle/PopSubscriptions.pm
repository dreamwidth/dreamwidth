#!/usr/bin/perl
#
# DW::Controller::Manage::Circle::PopSubscriptions
#
# Page that shows a sorted list of popular accounts in the user's circle.
# User can pick which circle group to base these calculations on by selecting
# from a drop-down menu. Results are displayed in three sections: personal
# accounts, community accounts, feed accounts. Page for listing subscriptions
# that are popular with other members of the user's circle.
#
# Authors:
#   Rebecca Freiburg <beckyvi@gmail.com>   (BML version)
#   Jen Griffin <kareila@livejournal.com>  (TT conversion)
#
# Copyright (c) 2009-2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Circle::PopSubscriptions;

use strict;

use DW::Routing;
use DW::Template;
use DW::Controller;

my $popsub_path = '/manage/circle/popsubscriptions';

DW::Routing->register_string( $popsub_path, \&popsubscriptions_handler, app => 1 );

sub popsubscriptions_handler {
    return error_ml("$popsub_path.tt.disabled")
        unless LJ::is_enabled('popsubscriptions');

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};

    return error_ml("$popsub_path.tt.invalidaccounttype")
        unless $remote->can_use_popsubscriptions;

    my $r    = DW::Request->get;
    my $args = $r->get_args;

    # filter options:
    # 1: only accounts subscribed to (DEFAULT)
    # 2: only mutually subscribed accounts
    # 3: trusted accounts
    # 4: mutually trusted accounts
    # 5: whole circle => subscriptions + gives access to

    my $filter = $args->{filter} || 1;
    my @ftypes = (
        "$popsub_path.tt.filters.subscriptions", "$popsub_path.tt.filters.mutualsubscriptions",
        "$popsub_path.tt.filters.access",        "$popsub_path.tt.filters.mutualaccess",
        "$popsub_path.tt.filters.circle"
    );    # for dropdown

    $rv->{filter} = $filter;
    $rv->{ftypes} = [ map { $_ => LJ::Lang::ml( $ftypes[ $_ - 1 ] ) } ( 1 .. 5 ) ];

    # circle_ids stores the user ids of accounts to base the calculation on.
    # which accounts these are is based on which filter the user picks.
    # default: subscriptions (filter: 1)

    my @circle_ids;

    if ( $filter == 1 ) {
        @circle_ids = $remote->watched_userids;
    }
    elsif ( $filter == 2 ) {
        @circle_ids = $remote->mutually_watched_userids;
    }
    elsif ( $filter == 3 ) {
        @circle_ids = $remote->trusted_userids;
    }
    elsif ( $filter == 4 ) {
        @circle_ids = $remote->mutually_trusted_userids;
    }
    else {
        @circle_ids = $remote->circle_userids;
    }

    # circle can currently have a maximum of 4,000 userids
    # (2,000 watched, 2,000 trusted); calculate for a maximum of 750.
    # on those scales, we won't lose much resolution doing this, as
    # trusted and watched are almost always overlapping.

    my $circle_limit = 750;
    @circle_ids = splice( @circle_ids, 0, $circle_limit )
        if @circle_ids > $circle_limit;

    # hash for searching whether the user is already subscribed to someone later
    my %circle_members;
    $circle_members{$_} = 1 foreach $remote->watched_userids;

    # hash for counting how many accounts in @circle_ids are subscribed to a particular account
    my %count;

    # limit the number of userids loaded for each @circle_ids user to 500
    my $limit     = 500;
    my $remote_id = $remote->userid;

    # load users...
    my $circleusers = LJ::load_userids(@circle_ids);

    # now load the accounts the users are watching...
    foreach my $uid (@circle_ids) {

        # don't want to include the remote user
        next if $uid == $remote_id;

      # since we have just loaded all user objects, we can now load subscribed accounts of that user
        my $circleuser = $circleusers->{$uid};

        # but we only include undeleted, unsuspended, personal journals (personal + identity)
        next unless $circleuser->is_individual && !$circleuser->is_inactive;

        # get userids subscribers are watching
        my @subsubs = $circleuser->watched_userids( limit => $limit );

        # if there are none, skip to next subscription
        next unless @subsubs;

        # now we count the occurrence of the userids that the remote user
        # isn't already subscribed to
        foreach my $userid (@subsubs) {
            $count{$userid}++ unless $circle_members{$userid};
        }
    }

    # now that we have the count for all userids, we sort it and take the most popular 500
    my @pop = sort { $count{$b} <=> $count{$a} } keys %count;
    @pop = splice( @pop, 0, 500 );

    # now we sort according to personal, community or feed account and only take the top 50 accounts
    # for this we need to lead the user objects
    my $popusers = LJ::load_userids(@pop);
    my ( @poppersonal, @popcomms, @popfeeds );
    my ( $numberpersonal, $numbercomms, $numberfeeds ) = ( 0, 0, 0 );
    my $maximum = 50;

    foreach my $uid (@pop) {
        my $popuser = $popusers->{$uid};

        # don't show inactive accounts, or banned accounts
        next if $uid == $remote_id || $popuser->is_inactive || $remote->has_banned($popuser);

        # sort userids into arrays
        if ( $numberpersonal < $maximum && $popuser->is_personal ) {
            push @poppersonal, $uid;
            $numberpersonal++;
        }
        elsif ( $numbercomms < $maximum && $popuser->is_community ) {
            push @popcomms, $uid;
            $numbercomms++;
        }
        elsif ( $numberfeeds < $maximum && $popuser->is_syndicated ) {
            push @popfeeds, $uid;
            $numberfeeds++;
        }

        # don't continue loop if all three arrays have reached the maximum number
        last if $numberpersonal + $numbercomms + $numberfeeds >= $maximum * 3;
    }

    # need to load user objects to use ->ljuser_display.
    # this is for a maximum of 50 accounts per type (150) here.
    $rv->{popularusers} = LJ::load_userids( @poppersonal, @popcomms, @popfeeds );
    $rv->{usercounts}   = \%count;

    $rv->{poppersonal} = \@poppersonal;
    $rv->{popcomms}    = \@popcomms;
    $rv->{popfeeds}    = \@popfeeds;

    $rv->{hasresults} = $numberpersonal + $numbercomms + $numberfeeds;

    return DW::Template->render_template( 'manage/circle/popsubscriptions.tt', $rv );
}

1;
