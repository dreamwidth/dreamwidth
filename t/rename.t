# t/rename.t
#
# Test user renaming.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 154;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );
use DW::User::Rename;
use DW::RenameToken;

my $create_users = sub {
    my %opts = @_;

    my $fromu = temp_user();
    my $tou = temp_user();

    unless( $opts{match} ) {
        my %from_defaults = (
            status => 'N',
            email => 'from@testemail',
            password => 'from',
        );

        LJ::update_user( $fromu, { %from_defaults, %{$opts{from_details} || {}} } );

        my %to_defaults = (
            status => 'N',
            email => 'to@testemail',
            password => 'to',
        );

        LJ::update_user( $tou, { %to_defaults, %{$opts{to_details} || {}} } );
    }

    $fromu = LJ::load_userid( $fromu->userid ) if $opts{from_details};
    $tou = LJ::load_userid( $tou->userid ) if $opts{to_details};

    if ( $opts{validated} ) {
        LJ::update_user( $fromu, { status => 'A' } );
        LJ::update_user( $tou, { status => 'A' } );
    }

    return ( $fromu, $tou );
};

sub new_token { return DW::RenameToken->create_token( ownerid => $_[0]->id ) }

note( "-- personal-to-unregistered, no redirect" );
{

    my $u = temp_user();

    my $fromuid = $u->userid;
    my $fromusername = $u->username;
    my $tousername = $fromusername . "_renameto";

    ok( ! LJ::load_user( $tousername ), "Username '$tousername' is unregistered" );
    ok( $u->can_rename_to( $tousername ), "'" . $u->user . "' can rename to '$tousername'" );

    ok( $u->rename( $tousername, token => new_token( $u ), redirect => 0 ), "Rename fromu to a valid unregistered username, no redirect" );

    $u = LJ::load_userid( $u->userid );
    is( $u->userid, $fromuid, "Id '#$fromuid' remains the same after rename." );
    is( $u->user, $tousername, "fromu is now named '$tousername'" );
}

note( "-- personal-to-unregistered, with redirect" );
{

    my $u = temp_user();

    my $fromuid = $u->userid;
    my $fromusername = $u->user;
    my $tousername =  $fromusername . "_renameto";

    ok( ! LJ::load_user( $tousername ), "Username '$tousername' is unregistered" );
    ok( $u->can_rename_to( $tousername ), "'" . $u->user . "' can rename to '$tousername'" );

    ok( $u->rename( $tousername, token => new_token( $u ), redirect => 1 ), "Rename fromu to a valid unregistered username, with redirect" );

    $u = LJ::load_userid( $u->userid );
    is( $u->userid, $fromuid, "Id '#$fromuid' remains the same after rename." );
    is( $u->user, $tousername, "fromu is now named '$tousername'" );

    my $orig_u = LJ::load_user( $fromusername );
    ok( $orig_u->is_renamed, "Yup, renamed" );
    ok( $orig_u->is_redirect, "Chose to redirect this rename" );
    is( $orig_u->get_renamed_user->user, $tousername, "Confirm redirect from $fromusername to $tousername" );
}

note( "-- user-to-user, no redirect" );
{
    my ( $fromu, $tou ) = $create_users->( match => 1, validated => 1 );

    my $fromuid = $fromu->userid;
    my $touid = $tou->userid;
    my $tousername = $tou->user;

    ok( $fromu->rename( $tousername, token => new_token( $fromu ), redirect => 0 ), "Rename fromu to existing user $tousername" );

    $fromu = LJ::load_userid( $fromu->userid );
    $tou = LJ::load_userid( $tou->userid );
    is( $fromu->user, $tousername, "Rename fromu to tou, which is under the control of fromu" );
    my $ex_user = substr( $tousername, 0, 10 );
    like( $tou->user, qr/^ex_$ex_user/ , "Moved out of the way." );
    is( $fromu->userid, $fromuid, "Id of fromu remains the same after rename." );
    is( $tou->userid, $touid, "Id of tou remains the same after rename." );
}

note( "-- user-to-user, with redirect" );
{
    my ( $fromu, $tou ) = $create_users->( match => 1, validated => 1 );

    my $fromuid = $fromu->userid;
    my $fromusername = $fromu->username;
    my $touid = $tou->userid;
    my $tousername = $tou->user;

    ok( $fromu->rename( $tousername, token => new_token( $fromu ), redirect => 1 ), "Rename fromu to existing user $tousername" );

    $fromu = LJ::load_userid( $fromu->userid );
    $tou = LJ::load_userid( $tou->userid );
    is( $fromu->user, $tousername, "Rename fromu to tou, which is under the control of fromu" );
    my $ex_user = substr( $tousername, 0, 10 );
    like( $tou->user, qr/^ex_$ex_user/ , "Moved out of the way." );
    is( $fromu->userid, $fromuid, "Id of fromu remains the same after rename." );
    is( $tou->userid, $touid, "Id of tou remains the same after rename." );

    my $orig_u = LJ::load_user( $fromusername );
    ok( $orig_u->is_renamed, "Yup, renamed" );
    ok( $orig_u->is_redirect, "Chose to redirect this rename" );
    is( $orig_u->get_renamed_user->user, $tousername, "Confirm redirect from $fromusername to $tousername" );

}

note ( "-- rename opts: deleting relationships" );
{
    my ( $u ) = temp_user();
    my $tousername = $u->user . "_renameto";

    my $watcher = temp_user();
    my $truster = temp_user();
    my $watched = temp_user();
    my $trusted = temp_user();
    my $comm = temp_comm();

    $watcher->add_edge( $u, watch => { nonotify => 1 } );
    $truster->add_edge( $u, trust => { nonotify => 1 } );
    $u->add_edge( $watched, watch => { nonotify => 1 } );
    $u->add_edge( $trusted, trust => { nonotify => 1 } );
    $u->add_edge( $comm, watch => { nonotify => 1 } );

    ok( $watcher->watches( $u ), "User has a watcher." );
    ok( $truster->trusts( $u ), "User has a truster." );
    ok( $u->watches( $watched ), "User watches someone." );
    ok( $u->trusts( $trusted ), "User trusts someone." );
    ok( $u->watches( $comm ), "User watches a comm." );

    # no arguments means nothing was deleted
    $u->apply_rename_opts();
    ok( $watcher->watches( $u ), "User has a watcher." );
    ok( $truster->trusts( $u ), "User has a truster." );
    ok( $u->watches( $watched ), "User watches someone." );
    ok( $u->trusts( $trusted ), "User trusts someone." );
    ok( $u->watches( $comm ), "User watches a comm." );

    $u->apply_rename_opts( del => { del_watched_by => 1 } );
    ok( ! $watcher->watches( $u ), "User has no watcher." );
    ok( $truster->trusts( $u ), "User has a truster." );
    ok( $u->watches( $watched ), "User watches someone." );
    ok( $u->trusts( $trusted ), "User trusts someone." );
    ok( $u->watches( $comm ), "User watches a comm." );
    $watcher->add_edge( $u, watch => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_trusted_by => 1 } );
    ok( $watcher->watches( $u ), "User has a watcher." );
    ok( ! $truster->trusts( $u ), "User has no truster." );
    ok( $u->watches( $watched ), "User watches someone." );
    ok( $u->trusts( $trusted ), "User trusts someone." );
    ok( $u->watches( $comm ), "User watches a comm." );
    $truster->add_edge( $u, trust => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_watched => 1 } );
    ok( $watcher->watches( $u ), "User has a watcher." );
    ok( $truster->trusts( $u ), "User has a truster." );
    ok( ! $u->watches( $watched ), "User does not watch anyone." );
    ok( $u->trusts( $trusted ), "User trusts someone." );
    ok( $u->watches( $comm ), "User watches a comm." );
    $u->add_edge( $watched, watch => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_trusted => 1 } );
    ok( $watcher->watches( $u ), "User has a watcher." );
    ok( $truster->trusts( $u ), "User has a truster." );
    ok( $u->watches( $watched ), "User watches someone." );
    ok( ! $u->trusts( $watched ), "User does not trust anyone." );
    ok( $u->watches( $comm ), "User watches a comm." );
    $u->add_edge( $trusted, trust => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_communities => 1 } );
    ok( $watcher->watches( $u ), "User has a watcher." );
    ok( $truster->trusts( $u ), "User has a truster." );
    ok( $u->watches( $watched ), "User watches someone." );
    ok( $u->trusts( $trusted ), "User trusts someone." );
    ok( ! $u->watches( $comm ), "User does not watch a comm." );

    ok( $u->rename( $tousername, token => new_token( $u ), redirect => 0, del_trusted_by => 1, del_watched_by => 1 ), "Rename, break watchers and trusters" );
    ok( ! $watcher->watches( $u ), "User has no watcher." );
    ok( ! $truster->trusts( $u ), "User has no truster." );
    ok( $u->watches( $watched ), "User watches someone." );
    ok( $u->trusts( $trusted ), "User trusts someone." );
    ok( ! $u->watches( $comm ), "User does not watch a comm." );
}

note( "-- rename opts: breaking email redirection" );
TODO: {
    local $TODO = "-- rename opts: breaking email redirection";
}

note( "-- personal-to-personal, authorization" );
{
    my ( $fromu, $tou, $tousername );
    my %rename_cond = (
        status => 'A',
        password => 'rename',
        email => 'rename@testemail',
    );
    ( $fromu, $tou ) = $create_users->(
        from_details => { %rename_cond, email => 'from@testemail' },
        to_details   => { %rename_cond, email => 'to@testemail'   }  );
    $tousername = $tou->user;
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename fromu to existing user $tousername (because: email)" );


    ( $fromu, $tou ) = $create_users->(
        from_details => { %rename_cond, password => 'from' },
        to_details   => { %rename_cond, password => 'to'   }  );
    $tousername = $tou->user;
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename fromu to existing user $tousername (because: password)" );

    ( $fromu, $tou ) = $create_users->(
        from_details => { %rename_cond, status => 'N' },
        to_details   => { %rename_cond, status => 'N' }  );
    $tousername = $tou->user;
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename fromu to existing user $tousername (because: validation)" );


    ( $fromu, $tou ) = $create_users->(
        from_details => { %rename_cond },
        to_details   => { %rename_cond, status => 'N' }  );
    $tousername = $tou->user;
    ok( $fromu->can_rename_to( $tousername ), "Can rename fromu to existing user $tousername (at least one user is validated)" );
    ok( $fromu->rename( $tousername, token => new_token( $fromu ) ), "Renamed fromu to existing user $tousername" );
}

{
    my ( $fromu, $tou ) = $create_users->();
    my $tousername = $tou->user;

    ok( $fromu->can_rename_to( $tousername, force => 1 ), "Can force rename fromu to existing user $tousername not under their control" );
    ok( $fromu->rename( $tousername, token => new_token( $fromu ), force => 1 ), "Renamed fromu to existing user $tousername" );
}

TODO: {
    local $TODO = "rename to linked usernames, once we allow one account to control multiple usernames";
}

note( "-- user status special casing" );
{
    my ( $fromu, $tou ) = $create_users->();

    my $fromusername = $fromu->username;
    my $tousername = $tou->user;

    $tou->update_self( { clusterid => 0,
                       statusvis => 'X',
                       raw => "statusvisdate=NOW()" } );

    LJ::start_request();
    $tou = LJ::load_user( $tousername, 1 );
    $fromu = LJ::load_user( $fromusername, 1 );

    ok( $fromu->can_rename_to( $tousername ), "Can always rename to expunged users." );
    ok( $fromu->rename( $tousername, token => new_token( $fromu ) ), "Rename to expunged user $tousername" );

    $fromu = LJ::load_userid( $fromu->userid, 1 );
    $tou = LJ::load_userid( $tou->userid, 1 );
    is( $fromu->user, $tousername, "Rename fromu to tou, which is under the control of fromu" );
    my $ex_user = substr( $tousername, 0, 10 );
    like( $tou->user, qr/^ex_$ex_user/ , "Moved out of the way." );
}


{
    my ( $fromu, $tou ) = $create_users->();

    my $fromusername = $fromu->username;
    my $tousername = $tou->user;

    $tou->set_statusvis( "D" );

    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename to (nonmatching) deleted users." );
}

{
    my ( $fromu, $tou, $tousername );

    ( $fromu, $tou ) = $create_users->( validated => 1 );
    $tousername = $tou->user;

    $tou->set_statusvis( "S" );
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename to nonmatching suspended users." );


    ( $fromu, $tou ) = $create_users->( match => 1, validated => 1 );
    $tousername = $tou->user;

    $tou->set_statusvis( "S" );
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename to matching suspended users." );

    $tou->set_statusvis( "L" );
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename to matching locked users." );

    $tou->set_statusvis( "M" );
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename to matching memorial users." );

    $tou->set_statusvis( "O" );
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename to matching read-only users." );

    $tou->set_statusvis( "R" );
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename to matching renamed and redirecting users." );


    $tou->set_statusvis( "V" );
    ok( $fromu->can_rename_to( $tousername ), "(reset status)" );

    $fromu->set_statusvis( "S" );
    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename from suspended users." );
}

note( "-- username issues" );
{
    my $fromu = temp_user();

    my $fromusername = $fromu->user;
    # taken from htdocs/inc/reserved-usernames. Production site may have more
    # but these are good enough for testing
    my @reserved_names = qw( dw_test ex_test ext_test s_test _test test__test );

    foreach my $name ( @reserved_names ) {
        ok( ! $fromu->can_rename_to( $name . $fromusername, token => new_token( $fromu ) ), "Cannot rename to reserved username '$name'" );
    }

    # reserved usernames can be force-renamed to
    foreach my $name ( @reserved_names ) {
        ok( $fromu->can_rename_to( $name . $fromusername, token => new_token( $fromu ), force => 1 ), "Forced rename to reserved username '$name$fromusername'" );
    }

    ok( ! $fromu->can_rename_to( $fromu->username, token => new_token( $fromu ) ), "Cannot rename to own name" );
}

{
    my $fromu = temp_user();

    my $fromusername = $fromu->user;
    my @invalid_usernames = qw( a.b a!b a\x{123}b );
    push @invalid_usernames, "x" x 30;

    foreach my $name ( @invalid_usernames ) {
        ok( ! $fromu->rename( $name, token => new_token( $fromu ) ), "Cannot rename to invalid username '$name'" );
    }

    # invalid usernames cannot be force-renamed to
    foreach my $name ( @invalid_usernames ) {
        ok( ! $fromu->rename( $name, token => new_token( $fromu ), force => 1 ), "Cannot force rename to invalid username '$name'" );
    }
}

{
    my $fromu = temp_user();

    my $tousername = $fromu->user . "-abc";
    ok( $fromu->rename( $tousername, token => new_token( $fromu ) ), "Rename does canonicalization" );
    $fromu = LJ::load_userid( $fromu->userid );
    is( $fromu->user, LJ::canonical_username( $tousername ), "Canonicalize away hyphens" );
}

note( "-- community-to-unregistered" );
{
    my $admin = temp_user();
    my $fromu = temp_comm();
    my $oldusername = $fromu->username;
    my $tousername = $fromu->username . "_renameto";

    ok( ! $admin->can_manage( $fromu ), "User cannot manage community fromu." );
    ok( ! $fromu->can_rename_to( $tousername, user => $admin ), "Cannot rename community to  $tousername (not admin)" );

    LJ::set_rel( $fromu, $admin, "A" );
    # FIXME: we shouldn't need to do this!
    delete $LJ::REQ_CACHE_REL{$fromu->userid."-".$admin->userid."-A"};
    ok( $admin->can_manage( $fromu ), "User can manage fromu." );

    ok( ! LJ::load_user( $tousername ), "Username '$tousername' is unregistered" );
    ok( $fromu->can_rename_to( $tousername, user => $admin ), "Can rename to $tousername" );
    ok( $fromu->rename( $tousername, token => new_token( $admin ), user => $admin ), "Renamed community to $tousername" );

    LJ::update_user( $admin, { status => 'A' } );
    ok( $admin->is_validated, "Admin was validated so could rename.");
    LJ::update_user( $admin, { status => 'N' } );
    ok( ! $admin->is_validated && ! $fromu->can_rename_to( $tousername . "_rename", user => $admin ), "Admin no longer validated; can no longer rename" );

    ok( ! $fromu->can_rename_to( $tousername ), "Cannot rename community without providing a user doing the renaming" );

    my $member = temp_user();
    $member->join_community( $fromu );
    ok( ! $fromu->can_rename_to( $oldusername, user => $admin ), "Cannot rename a community with members" );

    $member->leave_community( $fromu );
    ok( $fromu->can_rename_to( $oldusername, user => $admin ), "Can rename community again, no members." );
}

note( "-- community-to-personal" );
{
    my ( $admin, $tou ) = $create_users->( validated => 1 );
    my $fromu = temp_comm();
    my $tousername = $tou->user;

    # make admin of fromu
    LJ::set_rel( $fromu, $admin, "A" );
    delete $LJ::REQ_CACHE_REL{$fromu->userid."-".$admin->userid."-A"};

    ok( ! $fromu->can_rename_to( $tousername, user => $admin ), "Cannot rename fromu to existing user $tousername (tou is a personal journal not under admin's control)" );

    ( $admin, $tou ) = $create_users->( match => 1, validated => 1 );
    $tousername = $tou->user;

    # make admin of fromu
    LJ::set_rel( $fromu, $admin, "A" );
    delete $LJ::REQ_CACHE_REL{$fromu->userid."-".$admin->userid."-A"};
    ok( $fromu->can_rename_to( $tousername, user => $admin ), $admin->user . " can rename community fromu to existing user $tousername (tou is a personal journal under admin's control)" );
    ok( $fromu->rename( $tousername, token => new_token( $admin ), user => $admin ), $admin->user . " renamed community fromu to existing community $tousername" );
}

note( "-- personal-to-community" );
{
    my $fromu = temp_user();
    LJ::update_user( $fromu, { status => 'A' } );

    my $tou = temp_comm();
    my $tousername = $tou->user;

    # make admin of tou
    LJ::set_rel( $tou, $fromu, "A" );
    delete $LJ::REQ_CACHE_REL{$tou->userid."-".$fromu->userid."-A"};

    my $member = temp_user();
    $member->join_community( $tou );
    ok( ! $fromu->can_rename_to( $tousername, user => $fromu, verbose => 1 ), "Cannot rename a community with members" );

    $member->leave_community( $tou );
    ok( $fromu->can_rename_to( $tousername ),
        "Can rename to a community under your own control if it has no members.");
    ok( $fromu->rename( $tousername, token => new_token( $fromu ) ),
        "Renamed personal journal fromu to existing community." );
}

note( "-- openid and feeds" );
{
    my $u = temp_user();
    LJ::update_user( $u, { journaltype => 'I' } );

    ok( ! $u->can_rename_to( $u->user . "_rename" ), "Cannot rename OpenID accounts" );

    LJ::update_user( $u, { journaltype => 'F' } );
    ok( ! $u->can_rename_to( $u->user . "_rename" ), "Cannot rename feed accounts" );
}

note( "-- rename token ownership ignored" );
{
    my $u = temp_user();

    my $fromusername = $u->user;
    my $tousername =  $fromusername . "_renameto";

    ok( $u->rename( $tousername, token => new_token( temp_user() ) ),
        "Check that rename token ownership is ignored" );
}

note( "-- two username swap (personal to personal)" );
{
    my ( $u1, $u2 ) = $create_users->( match => 1, validated => 1 );

    my $u1id = $u1->userid;
    my $u2id = $u2->userid;
    my $u1sername = $u1->user;
    my $u2sername = $u2->user;

    ok( $u1sername ne $u2sername, "Not the same username" );

    my $token = new_token( $u1 );
    ok( ! $u1->swap_usernames(
        $u2,
        tokens => [ $token, $token ]
     ), "Can't swap, token is the same" );


    ok( $u1->swap_usernames(
        $u2,
        tokens => [ new_token( $u1 ), new_token( $u1 ) ]
     ), "Swap usernames" );

    $u1 = LJ::load_userid( $u1->userid );
    $u2 = LJ::load_userid( $u2->userid );

    is( $u1->user, $u2sername, "Swap usernames of u1 and u2" );
    is( $u2->user, $u1sername, "Swap usernames of u2 and u1" );

    is( $u1->userid, $u1id, "Id of u1 remains the same after rename." );
    is( $u2->userid, $u2id, "Id of u2 remains the same after rename." );
}

note( "-- two username swap (personal to personal), one token owned by each user" );
{
    my ( $u1, $u2 ) = $create_users->( match => 1, validated => 1 );

    ok( $u1->swap_usernames(
        $u2,
        tokens => [ new_token( $u1 ), new_token( $u2 ) ]
     ), "Swap usernames with one token owned by each account" );
}

note( "-- two username swap (one user is suspended)" );
{
    my ( $u1, $u2 ) = $create_users->( match => 1, validated => 1 );
    $u2->set_statusvis( "S" );

    my $u1id = $u1->userid;
    my $u2id = $u2->userid;
    my $u1sername = $u1->user;
    my $u2sername = $u2->user;

    ok( $u1sername ne $u2sername, "Not the same username" );

    ok( ! $u1->swap_usernames(
        $u2,
        tokens => [ new_token( $u1 ), new_token( $u1 ) ]
     ), "Cannot swap usernames." );

    $u1 = LJ::load_userid( $u1->userid );
    $u2 = LJ::load_userid( $u2->userid );

    is( $u1->user, $u1sername, "No swap" );
    is( $u2->user, $u2sername, "No swap" );
}

note( "-- two username swap personal <=> community " );
{
    my $u = temp_user();
    LJ::update_user( $u, { status => 'A' } );

    my $comm = temp_comm();
    my $uname = $u->user;
    my $commname = $comm->user;

    ok( ! $u->swap_usernames(
        $comm,
        tokens => [ new_token( $u ), new_token( $u ) ]
     ), "Cannot swap personal and community usernames (not an admin)" );

    # make admin of u
    LJ::set_rel( $comm, $u, "A" );
    delete $LJ::REQ_CACHE_REL{$comm->userid."-".$u->userid."-A"};

    ok( $u->swap_usernames(
        $comm,
        tokens => [ new_token( $u ), new_token( $u ) ],
     ), "Swap personal and community usernames" );

    is( $u->user, $commname, "Swap usernames u => comm" );
    is( $comm->user, $uname, "Swap usernames comm => u" );
}

note( "-- two username swap personal <=> community (with malice)" );
{
    my ( $u, $u2 ) = $create_users->( validate => 1 );

    my $comm = temp_comm();
    my $uname = $u->user;
    my $commname = $comm->user;

    # make admin of u
    LJ::set_rel( $comm, $u, "A" );
    delete $LJ::REQ_CACHE_REL{$comm->userid."-".$u->userid."-A"};

    LJ::set_rel( $comm, $u2, "A" );
    delete $LJ::REQ_CACHE_REL{$comm->userid."-".$u2->userid."-A"};

    ok( ! $u->swap_usernames(
        $u2,
        tokens => [ new_token( $u ), new_token( $u ) ],
     ), "Swap usernames with someone not under your control" );

    ok ( ! $comm->swap_usernames(
        $u2,
        user => $u,
        tokens => [ new_token( $u ), new_token( $u )],
    ), "Swapping the username of a co-admin");
}

note( "-- two username swap community <=> personal" );
{
    my $u = temp_user();
    LJ::update_user( $u, { status => 'A' } );

    my $comm = temp_comm();
    my $uname = $u->user;
    my $commname = $comm->user;

    ok( ! $comm->swap_usernames(
        $u,
        tokens => [ new_token( $u ), new_token( $u ) ]
     ), "Cannot swap personal and community usernames (not an admin)" );

    # make admin of u
    LJ::set_rel( $comm, $u, "A" );
    delete $LJ::REQ_CACHE_REL{$comm->userid."-".$u->userid."-A"};

    ok( ! $comm->swap_usernames(
        $u,
        tokens => [ new_token( $u ), new_token( $u ) ]
     ), "Cannot swap community and personal when acting on the community" );
}

note( "-- two username swap (community and community)" );
{
    my $admin = temp_user();
    LJ::update_user( $admin, { status => 'A' } );

    my $c1 = temp_comm();
    my $c2 = temp_comm();

    LJ::set_rel( $c1, $admin, "A" );
    delete $LJ::REQ_CACHE_REL{$c1->userid."-".$admin->userid."-A"};
    LJ::set_rel( $c2, $admin, "A" );
    delete $LJ::REQ_CACHE_REL{$c2->userid."-".$admin->userid."-A"};

    my $c1sername = $c1->user;
    my $c2sername = $c2->user;

    ok( $c1sername ne $c2sername, "Not the same username" );

    ok( $c1->swap_usernames(
        $c2,
        user => $admin,
        tokens => [ new_token( $admin ), new_token( $admin ) ],
     ), "Swap community usernames" );

    is( $c1->user, $c2sername, "Swap usernames of c1 and c2" );
    is( $c2->user, $c1sername, "Swap usernames of c2 and c1" );
}
