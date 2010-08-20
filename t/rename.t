#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
plan tests => 96;

use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
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

    $tou->set_statusvis( "X" );

    ok( $fromu->can_rename_to( $tousername ), "Can always rename to expunged users." );
    ok( $fromu->rename( $tousername, token => new_token( $fromu ) ), "Rename to expunged user $tousername" );

    $fromu = LJ::load_userid( $fromu->userid );
    $tou = LJ::load_userid( $tou->userid );
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
}

note( "-- community-to-community" );
TODO: {
    local $TODO = "community to community";
    my $admin = temp_user();
    my $fromu = temp_comm();
    my $tou = temp_comm();
    my $tousername = $tou->user;

    ok( ! $admin->can_manage( $fromu ), "User cannot manage community fromu" );
    ok( ! $admin->can_manage( $tou ), "User cannot manage community tou" );
    ok( ! $fromu->can_rename_to( $tousername, user => $admin ), $admin->user . " cannot rename community fromu to existing community $tousername (because: not admin)" );

    # make admin of fromu
    LJ::set_rel( $fromu, $admin, "A" );
    delete $LJ::REQ_CACHE_REL{$fromu->userid."-".$admin->userid."-A"};
    ok( $admin->can_manage( $fromu ), "User can manage community fromu" );
    ok( ! $admin->can_manage( $tou ), "User cannot manage community tou" );

    ok( ! $fromu->can_rename_to( $tousername, user => $admin ), $admin->user . " cannot rename community fromu to existing community $tousername (because: not admin of tou)" );

    # make admin of tou
    LJ::set_rel( $tou, $admin, "A" );
    delete $LJ::REQ_CACHE_REL{$tou->userid."-".$admin->userid."-A"};
    ok( $admin->can_manage( $fromu ), "User can manage community fromu" );
    ok( $admin->can_manage( $tou ), "User can manage community tou" );

    ok( $fromu->can_rename_to( $tousername, user => $admin ), $admin->user . " can rename community fromu to existing community $tousername (is admin of both)" );
    ok( $fromu->rename( $tousername, token => new_token( $admin ), user => $admin ), $admin->user . " renamed community fromu to existing community $tousername" );
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
TODO: {
    local $TODO = "personal to community";
    my $fromu = temp_user();
    my $tou = temp_comm();
    my $tousername = $tou->user;

    # make admin of tou
    LJ::set_rel( $tou, $fromu, "A" );
    delete $LJ::REQ_CACHE_REL{$tou->userid."-".$fromu->userid."-A"};

    ok( $fromu->can_rename_to( $tousername ), "Can rename to a community under your own control." );
    ok( $fromu->rename( $tousername, token => new_token( $fromu ) ), "Renamed personal journal fromu to existing community $tousername" );
}

TODO: {
    local $TODO = "community with multiple admins";
    my $admin1 = temp_user();
    my $admin2 = temp_user();
    my $tou = temp_comm();
    my $tousername = $tou->user;

    # make admins of tou
    LJ::set_rel_multi( [ $tou, $admin1, "A" ], [ $tou, $admin2, "A"] );
    delete $LJ::REQ_CACHE_REL{$tou->userid."-".$admin1->userid."-A"};
    delete $LJ::REQ_CACHE_REL{$tou->userid."-".$admin2->userid."-A"};

    ok( ! $admin1->can_rename_to( $tousername ), "Cannot rename to a community under your own control if there are multiple admins." );
}

note( "-- openid and feeds" );
{
    my $u = temp_user();
    LJ::update_user( $u, { journaltype => 'I' } );

    ok( ! $u->can_rename_to( $u->user . "_rename" ), "Cannot rename OpenID accounts" );

    LJ::update_user( $u, { journaltype => 'F' } );
    ok( ! $u->can_rename_to( $u->user . "_rename" ), "Cannot rename feed accounts" );
}

TODO: {
    local $TODO = "two username swap";
}

