#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
plan tests => 191;

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';

use LJ::Test qw( temp_user temp_comm );

my $u = temp_user();
my $watched = temp_user();
my $trusted = temp_user();
my $watchedtrusted = temp_user();
my $comm = temp_comm();

my $watcher = temp_user();
my $truster = temp_user();
my $watchertruster = temp_user();

my @watched = ( $watched, $watchedtrusted, $comm );
my @trusted = ( $trusted, $watchedtrusted );
my @watchedby = ( $watcher, $watchertruster );
my @trustedby = ( $truster, $watchertruster );

$u->add_edge( $_, watch => { nonotify => 1 } ) foreach @watched;
$u->add_edge( $_, trust => { nonotify => 1 } ) foreach @trusted;
$_->add_edge( $u, watch => { nonotify => 1 } ) foreach @watchedby;
$_->add_edge( $u, trust => { nonotify => 1 } ) foreach @trustedby;

my $err = 0;
my $res = {};

my $do_request = sub {
    my ( $mode, %request_args ) = @_;

    my $err = 0;
    my $req = \%request_args;

    my $res = LJ::Protocol::do_request( $mode, $req, \$err, { noauth => 1 } );

    return ( $res, $err );
};


my $check_err = sub {
    my ( $responsecode, $expectedcode, $testmsg ) = @_;

    is( $responsecode, $expectedcode,
        "$testmsg Protocol error ($err) = " . LJ::Protocol::error_message( $err ) );
};

my $success = sub {
    my ( $responsecode, $testmsg ) = @_;

    is( $responsecode, 0, "$testmsg (success)" );
};

note( "getfriendgroups" );
{
    ( $res, $err ) = $do_request->( "getfriendgroups" );
    $check_err->( $err, 504, "'getfriendgroups' is deprecated." );
    is( $res, undef, "No response expected." );


    ( $res, $err ) = $do_request->( "getfriendgroups", username => $u->user );
    $check_err->( $err, 504, "'getfriendgroups' is deprecated." );
    is( $res, undef, "No response expected." );
}

note( "gettrustgroups" );
{
    # test arguments:
    #   username

    ( $res, $err ) = $do_request->( "gettrustgroups" );
    $check_err->( $err, 200, "'gettrustgroups' needs a user." );
    is( $res, undef, "No response expected." );


    ( $res, $err ) = $do_request->( "gettrustgroups", username => $u->user );
    $success->( $err, "'gettrustgroups' for user." );
    ok( ref $res->{trustgroups} eq "ARRAY" && scalar @{$res->{trustgroups}} == 0, 
        "Empty trust groups list." );
};

note( "getcircle" );
{
    # test arguments:
    #   username
    #   limit
    #   includetrustgroups
    #   includecontentfilters
    #   includewatchedusers
    #   includewatchedby
    #   includetrustedusers

    ( $res, $err ) = $do_request->( "getcircle" );
     $check_err->( $err, 200, "'getcircle' needs a user." );
    is( $res, undef, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user );
    $success->( $err, "'getcircle' for user." );
    is( scalar keys %$res, 0, "Empty circle; no arguments provided to select the subset of the circle." );

    my %circle_args = (
        # request hash key  => response hash key, users
        includewatchedby    => [ "watchedbys", \@watchedby ],
        includetrustedby    => [ "trustedbys", \@trustedby ],
        includewatchedusers => [ "watchedusers", \@watched ],
        includetrustedusers => [ "trustedusers", \@trusted ],
    );
    while( my ( $include, $val ) = each %circle_args ) {
        ( $res, $err ) = $do_request->( "getcircle", username => $u->user, $include => 1 );
        $success->( $err, "'getcircle' => $include" );
        is( scalar keys %$res, 1, "One key: " . (keys %$res)[0] );
        is( ref $res->{$val->[0]}, "ARRAY", "Returned an arrayref of this user's $include." );

        my @cached_users = @{$val->[1]};
        my @response_users = @{$res->{$val->[0]}};
        is ( scalar @response_users, scalar @cached_users, "Matched the number of users who are watching/trusting." );

        # check both ways that the users we added are the users we got back
        my %cached_users = map { $_->user => 0 } @cached_users;
        foreach my $user ( @response_users ) {
            ok( ++$cached_users{$user->{username}}, "User from response is expected to be there." );
        }
        ok( $cached_users{$_}, "User appeared in the response." ) foreach keys %cached_users;
    }

    # set a limit, and check against that
    my $old_limit = $LJ::MAX_WT_EDGES_LOAD;
    $LJ::MAX_WT_EDGES_LOAD = 2;
    while( my ( $include, $val ) = each %circle_args ) {
        my @cached_users = @{$val->[1]};
        my $limit = scalar @cached_users > $LJ::MAX_WT_EDGES_LOAD
            ? $LJ::MAX_WT_EDGES_LOAD
            : scalar @cached_users;

        ( $res, $err ) = $do_request->( "getcircle", username => $u->user, $include => 1,
            limit => $LJ::MAX_WT_EDGES_LOAD + 1 );
        $success->( $err, "'getcircle' => $include" );

        # check that the users we got back are from the users we added
        # don't check the other way, since we are over limit
        my @response_users = @{$res->{$val->[0]}};
        is ( scalar @response_users, $limit, "Check that the number of users who can be fetched is limited." );
        my %cached_users = map { $_->user => 0 } @cached_users;
        foreach my $user ( @response_users ) {
            ok( ++$cached_users{$user->{username}}, "User from response is expected to be there." );
        }
    }

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includetrustgroups => 1 );
    $success->( $err, "'getcircle' => includetrustgroups" );
    is( scalar keys %$res, 1, "One key: " . (keys %$res)[0] );
    ok( ref $res->{trustgroups} eq "ARRAY" && scalar @{$res->{trustgroups}} == 0, 
        "Empty trust groups list." );


    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    $success->( $err, "'getcircle' => includecontentfilters" );
    is( scalar keys %$res, 1, "One key: " . (keys %$res)[0] );
    ok( ref $res->{contentfilters} eq "ARRAY" && scalar @{$res->{contentfilters}} == 0, "Empty list of content filters for this user." );

    $LJ::MAX_WT_EDGES_LOAD = $old_limit;
}

note( "editcircle" );
{
    # test arguments:
    #     settrustgroups
    #     deletetrustgroups
    #     setcontentfilters
    #     deletecontentfilters
    #     add
    #     addtocontentfilters
    #     deletefromcontentfilters

    ( $res, $err ) = $do_request->( "editcircle", settrustgroups => 1 );
    $check_err->( $err, 200, "'editcircle' needs a user." );
    is( $res, undef, "No response expected." );


    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, settrustgroups => 1 );
    $success->( $err, "No valid action provided for editcircle; ignore." );
    is( scalar keys %$res, 0, "No action taken." );


    my %trustgroups = (
        1 => {
            name => "first",
            sort => 1,
            public => 0
        },
        5 => {
            name => "incomplete"
        },
        10 => {
            # no name?
        }
    );
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, settrustgroups => \%trustgroups );
    $success->( $err, "Set trust groups." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includetrustgroups => 1 );
    is( scalar @{$res->{trustgroups}}, scalar keys %trustgroups, "Number of trust groups match." );
    foreach my $trustgroup ( @{$res->{trustgroups}} ) {
        my $id = $trustgroup->{id};
        my $orig_trustgroup = $trustgroups{$id};

        is( $trustgroup->{name}, $orig_trustgroup->{name} || "", "Trustgroup name matches." );
        is( $trustgroup->{public}, $orig_trustgroup->{public} || 0, "Trustgroup public setting matches." );
        is( $trustgroup->{sortorder}, $orig_trustgroup->{sort} || 50, "Trustgroup sortorder matches." );
    }


    # then edit one trust group, and add another
    my $edited = {
        name => "hasname",
        sortorder => 20,
        public => 1,
    };
    $trustgroups{10} = $edited;

    my $new = {
        name => "new",
    };
    $trustgroups{20} = $new;

    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, settrustgroups => { 10 => $edited, 20 => $new } );
    $success->( $err, "Edited trust groups; those not mentioned should not be affected." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includetrustgroups => 1 );
    is( scalar @{$res->{trustgroups}}, scalar keys %trustgroups, "Number of trust groups match." );
    foreach my $trustgroup ( @{$res->{trustgroups}} ) {
        my $id = $trustgroup->{id};
        my $orig_trustgroup = $trustgroups{$id};

        is( $trustgroup->{name}, $orig_trustgroup->{name} || "", "Trustgroup name matches." );
        is( $trustgroup->{public}, $orig_trustgroup->{public} || 0, "Trustgroup public setting matches." );
        is( $trustgroup->{sortorder}, $orig_trustgroup->{sort} || 50, "Trustgroup sortorder matches." );
    }


    # then delete some trust groups
    delete $trustgroups{5};
    delete $trustgroups{10};
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletetrustgroups => [ 10, 5 ] );
    $success->( $err, "Deleted a trust group." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includetrustgroups => 1 );
    is( scalar @{$res->{trustgroups}}, scalar keys %trustgroups, "Number of trust groups match." );
    foreach my $trustgroup ( @{$res->{trustgroups}} ) {
        my $id = $trustgroup->{id};
        my $orig_trustgroup = $trustgroups{$id};

        is( $trustgroup->{name}, $orig_trustgroup->{name} || "", "Trustgroup name matches." );
        is( $trustgroup->{public}, $orig_trustgroup->{public} || 0, "Trustgroup public setting matches." );
        is( $trustgroup->{sortorder}, $orig_trustgroup->{sort} || 50, "Trustgroup sortorder matches." );
    }


    # now add / edit some users' status in your circle
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => "invalidusername" } ] );
    $check_err->( $err, 203, "Tried to edit invalid user." );
    is( scalar keys %$res, 0, "No response expected." );

    # let's make our watch/trust mutual
    # ... but not yet
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => $watchertruster->user } ] );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includewatchedusers => 1, includetrustedusers => 1 );

    is( scalar @{$res->{watchedusers}}, scalar @watched, "Number of watched users did not change." );
    is( scalar @{$res->{trustedusers}}, scalar @trusted, "Number of trusted users did not change." );

    # add with trust group
    is( $u->trustmask( $watchertruster ), 0, "Currently not trusted." );
    ok( ! $u->trusts( $watchertruster ), "Currently not trusted." );
    ok( ! $u->watches( $watchertruster ), "Currently not watched." );
    ok( $watchertruster->trusts( $u ), "Trusted by." );
    ok( $watchertruster->watches( $u ), "Watched by." );

    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => $watchertruster->user, groupmask => 201 } ] );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includewatchedusers => 1, includetrustedusers => 1 );
    is( scalar @{$res->{watchedusers}}, scalar @watched, "Number of watched users did not change." );
    is( scalar @{$res->{trustedusers}}, scalar @trusted + 1, "Trusted this user." );
    is( $u->trustmask( $watchertruster ), 201, "Trusted, with trust group that matches." );
    ok( $u->trusts( $watchertruster ), "Currently trusted." );
    ok( ! $u->watches( $watchertruster ), "Currently not watched." );
    ok( $watchertruster->trusts( $u ), "Trusted by." );
    ok( $watchertruster->watches( $u ), "Watched by." );


    # add and remove
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => $watchertruster->user, edge => 0b00 } ] );
    is( $u->trustmask( $watchertruster ), 0, "Not trusted." );
    ok( ! $u->trusts( $watchertruster ), "Currently not trusted." );
    ok( ! $u->watches( $watchertruster ), "Currently not watched." );
    ok( $watchertruster->trusts( $u ), "Trusted by." );
    ok( $watchertruster->watches( $u ), "Watched by." );


    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => $watchertruster->user, edge => 0b01 } ] );
    is( $u->trustmask( $watchertruster ), 1, "Just trust." );
    ok( $u->trusts( $watchertruster ), "Currently trusted." );
    ok( ! $u->watches( $watchertruster ), "Currently not watched." );
    ok( $watchertruster->trusts( $u ), "Trusted by." );
    ok( $watchertruster->watches( $u ), "Watched by." );


    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => $watchertruster->user, edge => 0b10 } ] );
    is( $u->trustmask( $watchertruster ), 0, "Not trusted." );
    ok( ! $u->trusts( $watchertruster ), "Currently not trusted." );
    ok( $u->watches( $watchertruster ), "Currently watched." );
    ok( $watchertruster->trusts( $u ), "Trusted by." );
    ok( $watchertruster->watches( $u ), "Watched by." );


    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => $watchertruster->user, edge => 0b11 } ] );
    is( $u->trustmask( $watchertruster ), 1, "Just trust." );
    ok( $u->trusts( $watchertruster ), "Currently trusted." );
    ok( $u->watches( $watchertruster ), "Currently watched." );
    ok( $watchertruster->trusts( $u ), "Trusted by." );
    ok( $watchertruster->watches( $u ), "Watched by." );


    # edit again with groupmask, after already having created a trust mask
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, add => [ { username => $watchertruster->user, groupmask => 201 } ] );
    is( $u->trustmask( $watchertruster ), 201, "Trusted, with trust group that matches." );
    ok( $u->trusts( $watchertruster ), "Currently trusted." );
    ok( $u->watches( $watchertruster ), "Currently watched." );
    ok( $watchertruster->trusts( $u ), "Trusted by." );
    ok( $watchertruster->watches( $u ), "Watched by." );


    # now to 
    my %contentfilters = (
        1 => {
            name => "first",
            sort => 1,
            public => 0
        },
        2 => {
            name => "incomplete"
        },
    );

    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, setcontentfilters => \%contentfilters );
    $success->( $err, "Set content filters." );
    is( scalar keys %$res, 1, "Response contains only the newly added content filters." );
    is( scalar @{$res->{addedcontentfilters}}, scalar keys %contentfilters, "Got back the newly-added content filters." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    is( scalar @{$res->{contentfilters}}, scalar keys %contentfilters, "Number of content filters match." );
    foreach my $filter ( @{$res->{contentfilters}} ) {
        my $id = $filter->{id};
        my $orig_filter = $contentfilters{$id};

        is( $filter->{name}, $orig_filter->{name} || "", "Filter name matches." );
        is( $filter->{public}, $orig_filter->{public} || 0, "Filter public setting matches." );
        is( $filter->{sortorder}, $orig_filter->{sort} || 0, "Filter sortorder matches." );
    }

    # then edit one filter, and add another
    $edited = {
        name => "not so incomplete",
        sortorder => 20,
        public => 1,
    };
    $contentfilters{2} = $edited;

    $new = {
        name => "new",
    };
    $contentfilters{3} = $new;

    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, setcontentfilters => { 2 => $edited, 3 => $new } );
    $success->( $err, "Edited content filters; those not mentioned should not be affected." );
    is( scalar keys %$res, 1, "Response contains only the newly added content filters." );
    is( scalar @{$res->{addedcontentfilters}}, 1, "Got back the newly-added content filter." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    is( scalar @{$res->{contentfilters}}, scalar keys %contentfilters, "Number of content filters match." );
    foreach my $filter ( @{$res->{contentfilters}} ) {
        my $id = $filter->{id};
        my $orig_filter = $contentfilters{$id};

        is( $filter->{name}, $orig_filter->{name} || "", "Filter name matches." );
        is( $filter->{public}, $orig_filter->{public} || 0, "Filter public setting matches." );
        is( $filter->{sortorder}, $orig_filter->{sort} || 0, "Filter sortorder matches." );
    }


    # then delete some content filters
    delete $contentfilters{1};
    delete $contentfilters{3};
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletecontentfilters => [ 1, 3 ] );
    $success->( $err, "Deleted content filters." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    is( scalar @{$res->{contentfilters}}, scalar keys %contentfilters, "Number of content filters match." );
    foreach my $filter ( @{$res->{contentfilters}} ) {
        my $id = $filter->{id};
        my $orig_filter = $contentfilters{$id};

        is( $filter->{name}, $orig_filter->{name} || "", "Filter name matches." );
        is( $filter->{public}, $orig_filter->{public} || 0, "Filter public setting matches." );
        is( $filter->{sortorder}, $orig_filter->{sort} || 0, "Filter sortorder matches." );
    }


    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} eq "", "No data for the content filter." );


    # added non-existent user
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, addtocontentfilters => [ {
        username => "invalid_user",
        id => 2
    } ] );
    $check_err->( $err, 203, "Tried to add an invalid user to a content filter." );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} eq "", "No data for the content filter." );


    # added a valid user
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, addtocontentfilters => [ {
        username => $watched->user,
        id => 2
    } ] );
    $success->( $err, "Added a user to a content filter." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} ne "", "Some data in the content filter." );


    # tried to remove a non-existent user
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletefromcontentfilters => [ {
        username => "invalid_user",
        id => 2
    } ] );
    $check_err->( $err, 203, "Tried to remove an invalid user from a content filter." );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} ne "", "Some data in the content filter." );


    # tried to remove a valid user, but one not in the content filter
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletefromcontentfilters => [ {
        username => $watchedtrusted->user,
        id => 2
    } ] );
    $success->( $err, "Tried to remove a user who was not in the content filter." );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} ne "", "Some data in the content filter." );


    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletefromcontentfilters => [ {
        username => $watched->user,
        id => 2
    } ] );
    $success->( $err, "Removed a user from a content filter." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} eq "", "No more data in the content filter." );
}
