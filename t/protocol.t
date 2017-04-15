# t/protocol.t
#
# Test LJ::Protocol.
#
# Authors:
#      Catness <TODO>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More skip_all => "Test is not deterministic -- inconsistent results from content filters"; #tests => 243;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Protocol;
use DW::Pay;

use LJ::Test qw( temp_user temp_comm );
no warnings "once";

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
    my %flags = %{ delete  $request_args{flags} || {} };
    my $req = \%request_args;

    my $res = LJ::Protocol::do_request( $mode, $req, \$err, { noauth => 1, %flags } );

    return ( $res, $err );
};


my $check_err = sub {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ( $expectedcode, $testmsg ) = @_;

    # code is either in the form of ###, or ###:description
    like( $err, qr/^$expectedcode(?:$|[:])/,
        "$testmsg Protocol error ($err) = " . LJ::Protocol::error_message( $err ) );
};

my $success = sub {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my ( $testmsg ) = @_;

    is( $err, 0, "$testmsg (success)" );
};

note( "getfriendgroups" );
{
    ( $res, $err ) = $do_request->( "getfriendgroups" );
    $check_err->( 504, "'getfriendgroups' is deprecated." );
    is( $res, undef, "No response expected." );


    ( $res, $err ) = $do_request->( "getfriendgroups", username => $u->user );
    $check_err->( 504, "'getfriendgroups' is deprecated." );
    is( $res, undef, "No response expected." );
}

note( "gettrustgroups" );
{
    # test arguments:
    #   username

    ( $res, $err ) = $do_request->( "gettrustgroups" );
    $check_err->( 200, "'gettrustgroups' needs a user." );
    is( $res, undef, "No response expected." );


    ( $res, $err ) = $do_request->( "gettrustgroups", username => $u->user );
    $success->( "'gettrustgroups' for user." );
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
     $check_err->( 200, "'getcircle' needs a user." );
    is( $res, undef, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user );
    $success->( "'getcircle' for user." );
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
        $success->( "'getcircle' => $include" );
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
        $success->( "'getcircle' => $include" );

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
    $success->( "'getcircle' => includetrustgroups" );
    is( scalar keys %$res, 1, "One key: " . (keys %$res)[0] );
    ok( ref $res->{trustgroups} eq "ARRAY" && scalar @{$res->{trustgroups}} == 0,
        "Empty trust groups list." );


    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    $success->( "'getcircle' => includecontentfilters" );
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
    $check_err->( 200, "'editcircle' needs a user." );
    is( $res, undef, "No response expected." );


    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, settrustgroups => 1 );
    $success->( "No valid action provided for editcircle; ignore." );
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
    $success->( "Set trust groups." );
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
    $success->( "Edited trust groups; those not mentioned should not be affected." );
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
    $success->( "Deleted a trust group." );
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
    $check_err->( 203, "Tried to edit invalid user." );
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
    $success->( "Set content filters." );
    is( scalar keys %$res, 1, "Response contains only the newly added content filters." );
    # FIXME (1/3): this sometimes returns 1 instead of 2
    is( scalar @{$res->{addedcontentfilters}}, scalar keys %contentfilters, "Got back the newly-added content filters." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    # FIXME (2/3): this sometimes returns 1 instead of 2
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
    $success->( "Edited content filters; those not mentioned should not be affected." );
    is( scalar keys %$res, 1, "Response contains only the newly added content filters." );
    is( scalar @{$res->{addedcontentfilters}}, 1, "Got back the newly-added content filter." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    # FIXME (3/3): this sometimes returns 2 instead of 3
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
    $success->( "Deleted content filters." );
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
    $check_err->( 203, "Tried to add an invalid user to a content filter." );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} eq "", "No data for the content filter." );


    # added a valid user
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, addtocontentfilters => [ {
        username => $watched->user,
        id => 2
    } ] );
    $success->( "Added a user to a content filter." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} ne "", "Some data in the content filter." );


    # tried to remove a non-existent user
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletefromcontentfilters => [ {
        username => "invalid_user",
        id => 2
    } ] );
    $check_err->( 203, "Tried to remove an invalid user from a content filter." );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} ne "", "Some data in the content filter." );


    # tried to remove a valid user, but one not in the content filter
    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletefromcontentfilters => [ {
        username => $watchedtrusted->user,
        id => 2
    } ] );
    $success->( "Tried to remove a user who was not in the content filter." );
    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} ne "", "Some data in the content filter." );


    ( $res, $err ) = $do_request->( "editcircle", username => $u->user, deletefromcontentfilters => [ {
        username => $watched->user,
        id => 2
    } ] );
    $success->( "Removed a user from a content filter." );
    is( scalar keys %$res, 0, "No response expected." );

    ( $res, $err ) = $do_request->( "getcircle", username => $u->user, includecontentfilters => 1 );
    ok( $res->{contentfilters}->[0]->{data} eq "", "No more data in the content filter." );
}


note( "post to community by various journaltypes" );
{
    # test cases:
    # personal journal posting to a community
    # community posting to a community
    # openid account posting to a community

    # open up community posting to everybody
    my $admin = temp_user();
    $admin->join_community( $comm, 1, 1 );
    LJ::set_rel( $comm->userid, $admin->userid, "A" );
    delete $LJ::REQ_CACHE_REL{$comm->userid."-".$admin->userid."-A"};  # to be safe

    $comm->set_comm_settings( $admin, { membership => "open", postlevel => "members" } );
    $comm->set_prop( nonmember_posting => 1 );


    # validate the user, so they can post
    LJ::update_user( $u, { status => 'A' } );

    ( $res, $err ) = $do_request->( "postevent",
        username   => $u->user,
        usejournal => $comm->user,

        event      => "new test post to community",
        tz         => "guess",
    );
    $success->( "Entry posted successfully to community by personal journal." );


    my $comm2 = temp_comm();
    ( $res, $err ) = $do_request->( "postevent",
        username    => $comm2->user,
        usejournal  => $comm->user,
        event       => "new test post to community by community2"
    );
    $check_err->( 300, "Communities cannot post entries." );

    ( $res, $err ) = $do_request->( "postevent",
        username    => $comm->user,
        usejournal  => $comm->user,

        event       => "new test post to self by a community",
        tz          => "guess",
    );
    $check_err->( 300, "Communities cannot post entries, not even to themselves." );



    # openid cases
    my $identity_u = temp_user( journaltype => "I" );
    $identity_u->update_self( { status => "A" } );

    # allow all users to add and control tags (for convenience)
    $comm->set_prop( opt_tagpermissions => "public,public" );


    # allow identity users to post entries and add / control tags
    ok( LJ::Tags::can_control_tags( $comm, $identity_u ), "Identity user can control tags on communities." );
    ok( LJ::Tags::can_add_tags( $comm, $identity_u ), "Identity user can control tags on communities." );

    ( $res, $err ) = $do_request->( "postevent",
        username    => $identity_u->user,
        usejournal  => $comm->user,

        event       => "new test post to a community by an identity user (no tags)",
        tz          => "guess",
    );
    $success->( "OpenID users can post entries to communities." );

    ( $res, $err ) = $do_request->( "postevent",
        username    => $identity_u->user,
        usejournal  => $comm->user,

        event       => "new test post to a community by an identity user (with tags)",
        props       => { taglist => "testing" },
        tz          => "guess",
    );
    $success->( "OpenID users can post entries including tags to communities." );
}


# Bug 3271
note( "editing an entry with existing tags, when only admins can edit tags" );
{
    my $u = temp_user();
    my $admin = temp_user();
    my $comm = temp_comm();

    ## SETUP
    $admin->join_community( $comm, 1, 1 );
    LJ::set_rel( $comm->userid, $admin->userid, "A" );
    delete $LJ::REQ_CACHE_REL{$comm->userid."-".$admin->userid."-A"};  # to be safe

    $comm->set_comm_settings( $admin, { membership => "open", postlevel => "members" } );
    $comm->set_prop( nonmember_posting => 1 );

    # restrict so that only admins can edit tags
    $comm->set_prop( opt_tagpermissions => "private,private" );

    # validate the user, so they can post
    LJ::update_user( $u, { status => 'A' } );


    ## TEST
    # post entry with tags...
    ( $res, $err ) = $do_request->( "postevent",
        username    => $u->user,
        usejournal  => $comm->user,

        event       => "new test post to a community containing tags when you're not allowed to have them",
        props       => { taglist => "user-tag" },
        tz          => "guess",
    );
    $check_err->( 312, "Can't add tags to entries in this community" );


    # post entry with no tags
    ( $res, $err ) = $do_request->( "postevent",
        username    => $u->user,
        usejournal  => $comm->user,

        event       => "new test post to a community this time with no tags",
        tz          => "guess",
    );
    $success->( "entry posted successfully" );
    my $itemid = $res->{itemid};

    # admin adds tags
    LJ::Tags::update_logtags($comm, $itemid, {
            set_string => "admin-tag",
            remote => $admin,
    });

    my $entry = LJ::Entry->new( $comm, jitemid => $itemid );
    is_deeply( [ $entry->tags ], [ qw( admin-tag ) ], "yes, admin added tags successfully" );

    # try to edit entry (editing tags)
    ( $res, $err ) = $do_request->( "editevent",
        username    => $u->user,
        usejournal  => $comm->user,
        itemid      => $entry->jitemid,
        ver         => 1,

        event       => "new entry text lalala",
        props       => { taglist => "admin-tag, user-tag" },
    );
    is( $res->{message}, "You are not allowed to tag entries in this journal.",
        "warning given because we can't edit the tags" );

    LJ::start_request();
    $entry = LJ::Entry->new( $comm, jitemid => $itemid );
    is( $entry->event_raw, "new entry text lalala", "BUT entry text was edited" );
    is_deeply( [ $entry->tags ], [ qw( admin-tag ) ], "did not touch the tags" );


    # try to edit entry (original tags)
    ( $res, $err ) = $do_request->( "editevent",
        username    => $u->user,
        usejournal  => $comm->user,
        itemid      => $itemid,
        ver         => 1,

        event       => "new entry text (again) lalala",
        props       => { taglist =>  "admin-tag", },
    );
    $success->( "edited entry successfully" );

    LJ::start_request();
    $entry = LJ::Entry->new( $comm, jitemid => $itemid );
    is( $entry->event_raw, "new entry text (again) lalala", "entry text edited" );
    is_deeply( [ $entry->tags ], [ qw( admin-tag ) ], "did not touch the tags" );
}


note( "checkforupdates" );
{

    my $u = temp_user();

    my $start = 0;
    my $end = 15;

    # make sure no one can use the protocol...
    $LJ::CAP{$_}->{checkfriends} = 0
        foreach( 0.. 15 );

    ( $res, $err ) = $do_request->( "checkfriends" );
    $check_err->( 504, "Use 'checkforupdates' instead" );


    ( $res, $err ) = $do_request->( "checkforupdates" );
    $check_err->( 200, "Needs arguments" );

    ( $res, $err ) = $do_request->( "checkforupdates",
        username => $u->user,
        flags    => { noauth => 0 },
    );
    $check_err->( 101, "Have all arguments, but needs authorization" );

    ( $res, $err ) = $do_request->( "checkforupdates",
        username => $u->user,
    );
    $success->( "Not authorized to use checkforupdates" );
    is_deeply( $res, {
            interval => 36000,
            new => 0
    }, "Not authorized to use checkforupdates; no new entries, check back in an hour" );


    # make sure everyone can use the protocol, and set interval to a known variable we can check against
    # (not using $LJ::T_HAS_ALL_CAPS = 1, because that makes everyone readonly)
    $LJ::CAP{$_}->{checkfriends} = 1
        foreach( 0.. 15 );
    $LJ::CAP{$_}->{checkfriends_interval} = 7
        foreach( 0.. 15 );

    ( $res, $err ) = $do_request->( "checkforupdates",
        username => $u->user,
    );
    $success->( "Checkforupdates. We don't watch anyone, but that's okay" );
    is( scalar %{ $u->watch_list }, 0, "Not watching anyone" );
    is_deeply( $res, {
            interval => 7,
            new => 0,
            lastupdate => "0000-00-00 00:00:00",
    }, "Watching no one." );


    # now we watch some people (who have no updates yet)
    my $userinfilter = temp_user();
    $u->add_edge( $userinfilter, watch => { nonotify => 1 } );
    $u->create_content_filter( name => "filter" );
    my $filter = $u->content_filters( name => "filter" );
    $filter->add_row( userid => $userinfilter->userid );

    my $usernotinfilter = temp_user();
    $u->add_edge( $usernotinfilter, watch => { nonotify => 1 } );


    # and go through the protocol again
    ( $res, $err ) = $do_request->( "checkforupdates",
        username => $u->user,
    );
    $success->( "Checkforupdates. No one has updated." );
    is( scalar $u->watched_userids,2 );
    is_deeply( $res, {
            interval => 7,
            new => 0,
            lastupdate => "0000-00-00 00:00:00",
    }, "No new entries." );


    # and then let's see what happens when they get updates
    $do_request->( "postevent", username => $userinfilter->user, event => "update", tz => "guess" );
    sleep( 1 ); # pause so we have different time stamps (for checking against)
    $do_request->( "postevent", username => $usernotinfilter->user, event => "update", tz => "guess" );

    # use variables to make it easier to determine what I'm trying to check for
    # In some tests, I will deliberately *not* use the variables
    my $earlierupdate = $userinfilter->timeupdate;
    my $laterupdate = $usernotinfilter->timeupdate;
    ok( $earlierupdate < $laterupdate, "Timestamps need to be unequal for when we're testing stuff." );

    # and go through the protocol again
    ( $res, $err ) = $do_request->( "checkforupdates",
        username => $u->user,
    );
    $success->( "Checkforupdates. Users have updated." );
    is_deeply( $res, {
            interval => 7,
            new => 0,
            lastupdate => LJ::mysql_time( $usernotinfilter->timeupdate ),
    }, "No new entries." );


    # and we also check a subset (filter)
    ( $res, $err ) = $do_request->( "checkforupdates",
        username => $u->user,
        filter   => $filter->name,
    );
    $success->( "Checkforupdates of a subset of watched users." );
    is_deeply( $res, {
            interval => 7,
            new => 0,
            lastupdate => LJ::mysql_time( $userinfilter->timeupdate ),
    }, "No new entries." );


    # optional argument lastupdate
    ( $res, $err ) = $do_request->( "checkforupdates",
        username   => $u->user,
        lastupdate => $earlierupdate
    );
    $check_err->( 203, "lastupdate argument needs to be in mysql_time format." );

    ( $res, $err ) = $do_request->( "checkforupdates",
        username   => $u->user,
        lastupdate => LJ::mysql_time( $earlierupdate ),
    );
    $success->( "Checkforupdates since lastupdate. Have new updates" );
    is_deeply( $res, {
            interval => 7,
            new => 1,
            lastupdate => LJ::mysql_time( $laterupdate ),
    }, "Have new entries." );

    ( $res, $err ) = $do_request->( "checkforupdates",
        username   => $u->user,
        lastupdate => LJ::mysql_time( $laterupdate ),
    );
    $success->( "Checkforupdates since lastupdate. No new updates" );
    is_deeply( $res, {
            interval => 7,
            new => 0,
            lastupdate => LJ::mysql_time( $laterupdate ),
    }, "No new entries." );

}

note( "adding a comment to a journal" );
{
    my $u = temp_user();
    $u->update_self({ status => "A" });
    DW::Pay::add_paid_time( $u, "paid", 2 );

    my $entry = $u->t_post_fake_entry;

    ( $res, $err ) = $do_request->( "addcomment",
        username => $u->user,

        ditemid => $entry->ditemid,
        subject => "subject",
        body    => "comment body " . rand(),
    );

    my $comment = LJ::Comment->new( $entry->journal, dtalkid => $res->{dtalkid} );
    ok( $comment->poster->equals( $u ), "Check comment poster when posting to your own journal" );
    ok( $comment->journal->equals( $u ), "Check comment journal when posting to your own journal" );
}

note( "adding a comment to a community" );
{
    my $u = temp_user();
    $u->update_self({ status => "A" });
    DW::Pay::add_paid_time( $u, "paid", 2 );

    my $cu = temp_comm();

    my $entry = $u->t_post_fake_comm_entry( $cu );

    ( $res, $err ) = $do_request->( "addcomment",
        username => $u->user,
        journal => $cu->user,

        ditemid => $entry->ditemid,
        subject => "subject",
        body    => "comment body " . rand(),
    );

    my $comment = LJ::Comment->new( $entry->journal, dtalkid => $res->{dtalkid} );
    ok( $comment->poster->equals( $u ), "Check comment poster when posting to a community" );
    ok( $comment->journal->equals( $cu ), "Check comment journal when posting to a community" );
}

note( "adding a comment to another journal" );
{
    my $u1 = temp_user();
    $u1->update_self({ status => "A" });
    DW::Pay::add_paid_time( $u1, "paid", 2 );

    my $u2 = temp_user();

    my $entry = $u2->t_post_fake_entry;

    ( $res, $err ) = $do_request->( "addcomment",
        username => $u1->user,
        journal => $u2->user,

        ditemid => $entry->ditemid,
        subject => "subject",
        body    => "comment body " . rand(),
    );

    my $comment = LJ::Comment->new( $entry->journal, dtalkid => $res->{dtalkid} );
    ok( $comment->poster->equals( $u1 ), "Check comment poster when posting to another journal" );
    ok( $comment->journal->equals( $u2 ), "Check comment journal when posting to another journal" );
}

note( "getfriendspage" );
{
    my $u = temp_user();
    ( $res, $err ) = $do_request->( "getfriendspage",
        username => $u->user
    );

    $check_err->( 504, "'getfriendspage' is deprecated." );
}

note( "getreadpage" );
{
    my $u1 = temp_user();
    my $u2 = temp_user();

    $u1->add_edge( $u2, watch => { nonotify => 1 } );
    my $e1 = $u2->t_post_fake_entry( body => "entry 1 " . rand(), subject => "#1", );
    my $e2 = $u2->t_post_fake_entry( body => "entry 2 " . rand(), subject => "#2", );
    my $e3 = $u2->t_post_fake_entry( body => "entry 3 " . rand(), subject => "#3", );

    my @entries;

    # show everything
    ( $res, $err ) = $do_request->( "getreadpage",
        username => $u1->user,
    );
    @entries = @{$res->{entries}};
    is( scalar @entries, 3, "3... 3 entries ah HA HA HA" );
    is( $entries[0]->{subject_raw}, "#3" );
    is( $entries[1]->{subject_raw}, "#2" );
    is( $entries[2]->{subject_raw}, "#1" );


    # limit to one item
    ( $res, $err ) = $do_request->( "getreadpage",
        username => $u1->user,
        itemshow => 1,
    );
    @entries = @{$res->{entries}};
    is( scalar @entries, 1, "we asked for one entry" );
    is( $entries[0]->{subject_raw}, "#3" );

    # limit to one, skip one
    ( $res, $err ) = $do_request->( "getreadpage",
        username => $u1->user,
        itemshow => 1,
        skip     => 1,
    );
    @entries = @{$res->{entries}};
    is( scalar @entries, 1, "we asked for one entry (skip back one)" );
    is( $entries[0]->{subject_raw}, "#2" );

}
