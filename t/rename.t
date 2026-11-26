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

use Test::More tests => 168;
use MIME::QuotedPrint qw( decode_qp );

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );
use DW::FormErrors;
use DW::User::Rename;
use DW::RenameToken;
use DW::TaskQueue;

my $create_users = sub {
    my %opts = @_;

    my $fromu = temp_user();
    my $tou   = temp_user();

    unless ( $opts{match} ) {
        my %from_defaults = (
            status   => 'N',
            email    => 'from@testemail',
            password => 'from',
        );

        LJ::update_user( $fromu, { %from_defaults, %{ $opts{from_details} || {} } } );

        my %to_defaults = (
            status   => 'N',
            email    => 'to@testemail',
            password => 'to',
        );

        LJ::update_user( $tou, { %to_defaults, %{ $opts{to_details} || {} } } );
    }

    $fromu = LJ::load_userid( $fromu->userid ) if $opts{from_details};
    $tou   = LJ::load_userid( $tou->userid )   if $opts{to_details};

    if ( $opts{validated} ) {
        LJ::update_user( $fromu, { status => 'A' } );
        LJ::update_user( $tou,   { status => 'A' } );
    }

    return ( $fromu, $tou );
};

sub new_token { return DW::RenameToken->create_token( ownerid => $_[0]->id ) }

sub token_status {
    return
        scalar LJ::get_db_writer()
        ->selectrow_array( 'SELECT status FROM renames WHERE renid=?', undef, $_[0]->id );
}

note("-- personal-to-unregistered, no redirect");
{

    my $u = temp_user();

    my $fromuid      = $u->userid;
    my $fromusername = $u->username;
    my $tousername   = $fromusername . "_renameto";

    ok( !LJ::load_user($tousername),    "Username '$tousername' is unregistered" );
    ok( $u->can_rename_to($tousername), "'" . $u->user . "' can rename to '$tousername'" );

    ok(
        $u->rename( $tousername, token => new_token($u), redirect => 0 ),
        "Rename fromu to a valid unregistered username, no redirect"
    );

    $u = LJ::load_userid( $u->userid );
    is( $u->userid, $fromuid,    "Id '#$fromuid' remains the same after rename." );
    is( $u->user,   $tousername, "fromu is now named '$tousername'" );
}

note("-- personal-to-unregistered, with redirect");
{

    my $u = temp_user();

    my $fromuid      = $u->userid;
    my $fromusername = $u->user;
    my $tousername   = $fromusername . "_renameto";

    ok( !LJ::load_user($tousername),    "Username '$tousername' is unregistered" );
    ok( $u->can_rename_to($tousername), "'" . $u->user . "' can rename to '$tousername'" );

    ok(
        $u->rename( $tousername, token => new_token($u), redirect => 1 ),
        "Rename fromu to a valid unregistered username, with redirect"
    );

    $u = LJ::load_userid( $u->userid );
    is( $u->userid, $fromuid,    "Id '#$fromuid' remains the same after rename." );
    is( $u->user,   $tousername, "fromu is now named '$tousername'" );

    my $orig_u = LJ::load_user($fromusername);
    ok( $orig_u->is_renamed,  "Yup, renamed" );
    ok( $orig_u->is_redirect, "Chose to redirect this rename" );
    is( $orig_u->get_renamed_user->user,
        $tousername, "Confirm redirect from $fromusername to $tousername" );
}

subtest 'redirects to a purged journal are still unavailable' => sub {
    my $requester = temp_user();
    my $first     = temp_user( journaltype => 'R' );
    my $second    = temp_user( journaltype => 'R' );
    my $target    = temp_user();

    ok( DW::User::Rename->create_redirect_journal( $first->user, $second->user ),
        'Created the first redirect' );
    ok( DW::User::Rename->create_redirect_journal( $second->user, $target->user ),
        'Created the second redirect' );
    $target->set_statusvis('X');

    ok( $requester->can_rename_to( $target->user ), 'The purged username itself is available' );
    for my $alias ( $second, $first ) {
        my $alias_name  = $alias->user;
        my $target_name = $target->user;
        my $errors      = DW::FormErrors->new;
        ok( !$requester->can_rename_to( $alias_name, errors => $errors ),
            'The redirecting username is unavailable' );
        my $error = $errors->get('touser');
        like(
            $error->{message},
            qr/\Q$alias_name\E.*redirects to.*\Q$target_name\E/i,
            'The error identifies the requested name and the final destination'
        );
    }
};

note("-- user-to-user, no redirect");
{
    my ( $fromu, $tou ) = $create_users->( match => 1, validated => 1 );

    my $fromuid    = $fromu->userid;
    my $touid      = $tou->userid;
    my $tousername = $tou->user;

    ok( $fromu->rename( $tousername, token => new_token($fromu), redirect => 0 ),
        "Rename fromu to existing user $tousername" );

    $fromu = LJ::load_userid( $fromu->userid );
    $tou   = LJ::load_userid( $tou->userid );
    is( $fromu->user, $tousername, "Rename fromu to tou, which is under the control of fromu" );
    my $ex_user = substr( $tousername, 0, 10 );
    like( $tou->user, qr/^ex_$ex_user/, "Moved out of the way." );
    is( $fromu->userid, $fromuid, "Id of fromu remains the same after rename." );
    is( $tou->userid,   $touid,   "Id of tou remains the same after rename." );
}

note("-- user-to-user, with redirect");
{
    my ( $fromu, $tou ) = $create_users->( match => 1, validated => 1 );

    my $fromuid      = $fromu->userid;
    my $fromusername = $fromu->username;
    my $touid        = $tou->userid;
    my $tousername   = $tou->user;

    ok( $fromu->rename( $tousername, token => new_token($fromu), redirect => 1 ),
        "Rename fromu to existing user $tousername" );

    $fromu = LJ::load_userid( $fromu->userid );
    $tou   = LJ::load_userid( $tou->userid );
    is( $fromu->user, $tousername, "Rename fromu to tou, which is under the control of fromu" );
    my $ex_user = substr( $tousername, 0, 10 );
    like( $tou->user, qr/^ex_$ex_user/, "Moved out of the way." );
    is( $fromu->userid, $fromuid, "Id of fromu remains the same after rename." );
    is( $tou->userid,   $touid,   "Id of tou remains the same after rename." );

    my $orig_u = LJ::load_user($fromusername);
    ok( $orig_u->is_renamed,  "Yup, renamed" );
    ok( $orig_u->is_redirect, "Chose to redirect this rename" );
    is( $orig_u->get_renamed_user->user,
        $tousername, "Confirm redirect from $fromusername to $tousername" );

}

note("-- rename opts: deleting relationships");
{
    my ($u) = temp_user();
    my $tousername = $u->user . "_renameto";

    my $watcher = temp_user();
    my $truster = temp_user();
    my $watched = temp_user();
    my $trusted = temp_user();
    my $comm    = temp_comm();

    $watcher->add_edge( $u, watch => { nonotify => 1 } );
    $truster->add_edge( $u, trust => { nonotify => 1 } );
    $u->add_edge( $watched, watch => { nonotify => 1 } );
    $u->add_edge( $trusted, trust => { nonotify => 1 } );
    $u->add_edge( $comm,    watch => { nonotify => 1 } );

    ok( $watcher->watches($u), "User has a watcher." );
    ok( $truster->trusts($u),  "User has a truster." );
    ok( $u->watches($watched), "User watches someone." );
    ok( $u->trusts($trusted),  "User trusts someone." );
    ok( $u->watches($comm),    "User watches a comm." );

    # no arguments means nothing was deleted
    $u->apply_rename_opts();
    ok( $watcher->watches($u), "User has a watcher." );
    ok( $truster->trusts($u),  "User has a truster." );
    ok( $u->watches($watched), "User watches someone." );
    ok( $u->trusts($trusted),  "User trusts someone." );
    ok( $u->watches($comm),    "User watches a comm." );

    $u->apply_rename_opts( del => { del_watched_by => 1 } );
    ok( !$watcher->watches($u), "User has no watcher." );
    ok( $truster->trusts($u),   "User has a truster." );
    ok( $u->watches($watched),  "User watches someone." );
    ok( $u->trusts($trusted),   "User trusts someone." );
    ok( $u->watches($comm),     "User watches a comm." );
    $watcher->add_edge( $u, watch => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_trusted_by => 1 } );
    ok( $watcher->watches($u), "User has a watcher." );
    ok( !$truster->trusts($u), "User has no truster." );
    ok( $u->watches($watched), "User watches someone." );
    ok( $u->trusts($trusted),  "User trusts someone." );
    ok( $u->watches($comm),    "User watches a comm." );
    $truster->add_edge( $u, trust => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_watched => 1 } );
    ok( $watcher->watches($u),  "User has a watcher." );
    ok( $truster->trusts($u),   "User has a truster." );
    ok( !$u->watches($watched), "User does not watch anyone." );
    ok( $u->trusts($trusted),   "User trusts someone." );
    ok( $u->watches($comm),     "User watches a comm." );
    $u->add_edge( $watched, watch => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_trusted => 1 } );
    ok( $watcher->watches($u), "User has a watcher." );
    ok( $truster->trusts($u),  "User has a truster." );
    ok( $u->watches($watched), "User watches someone." );
    ok( !$u->trusts($watched), "User does not trust anyone." );
    ok( $u->watches($comm),    "User watches a comm." );
    $u->add_edge( $trusted, trust => { nonotify => 1 } );

    $u->apply_rename_opts( del => { del_communities => 1 } );
    ok( $watcher->watches($u), "User has a watcher." );
    ok( $truster->trusts($u),  "User has a truster." );
    ok( $u->watches($watched), "User watches someone." );
    ok( $u->trusts($trusted),  "User trusts someone." );
    ok( !$u->watches($comm),   "User does not watch a comm." );

    ok(
        $u->rename(
            $tousername,
            token          => new_token($u),
            redirect       => 0,
            del_trusted_by => 1,
            del_watched_by => 1
        ),
        "Rename, break watchers and trusters"
    );
    ok( !$watcher->watches($u), "User has no watcher." );
    ok( !$truster->trusts($u),  "User has no truster." );
    ok( $u->watches($watched),  "User watches someone." );
    ok( $u->trusts($trusted),   "User trusts someone." );
    ok( !$u->watches($comm),    "User does not watch a comm." );
}

note("-- rename opts: breaking email redirection");
TODO: {
    local $TODO = "-- rename opts: breaking email redirection";
}

note("-- personal-to-personal, authorization");
{
    my ( $fromu, $tou, $tousername );
    my %rename_cond = (
        status   => 'A',
        password => 'rename',
        email    => 'rename@testemail',
    );
    ( $fromu, $tou ) = $create_users->(
        from_details => { %rename_cond, email => 'from@testemail' },
        to_details   => { %rename_cond, email => 'to@testemail' }
    );
    $tousername = $tou->user;
    ok( !$fromu->can_rename_to($tousername),
        "Cannot rename fromu to existing user $tousername (because: email)" );

    ( $fromu, $tou ) = $create_users->(
        from_details => { %rename_cond, status => 'N' },
        to_details   => { %rename_cond, status => 'N' }
    );
    $tousername = $tou->user;
    ok( !$fromu->can_rename_to($tousername),
        "Cannot rename fromu to existing user $tousername (because: validation)" );

    ( $fromu, $tou ) = $create_users->(
        from_details => {%rename_cond},
        to_details   => { %rename_cond, status => 'N' }
    );
    $tousername = $tou->user;
    ok( $fromu->can_rename_to($tousername),
        "Can rename fromu to existing user $tousername (at least one user is validated)" );
    ok( $fromu->rename( $tousername, token => new_token($fromu) ),
        "Renamed fromu to existing user $tousername" );
}

{
    my ( $fromu, $tou ) = $create_users->();
    my $tousername = $tou->user;

    ok( $fromu->can_rename_to( $tousername, force => 1 ),
        "Can force rename fromu to existing user $tousername not under their control" );
    ok( $fromu->rename( $tousername, token => new_token($fromu), force => 1 ),
        "Renamed fromu to existing user $tousername" );
}

TODO: {
    local $TODO =
        "rename to linked usernames, once we allow one account to control multiple usernames";
}

note("-- user status special casing");
{
    my ( $fromu, $tou ) = $create_users->();

    my $fromusername = $fromu->username;
    my $tousername   = $tou->user;

    $tou->update_self(
        {
            clusterid => 0,
            statusvis => 'X',
            raw       => "statusvisdate=NOW()"
        }
    );

    LJ::start_request();
    $tou   = LJ::load_user( $tousername,   1 );
    $fromu = LJ::load_user( $fromusername, 1 );

    ok( $fromu->can_rename_to($tousername), "Can always rename to expunged users." );
    ok( $fromu->rename( $tousername, token => new_token($fromu) ),
        "Rename to expunged user $tousername" );

    $fromu = LJ::load_userid( $fromu->userid, 1 );
    $tou   = LJ::load_userid( $tou->userid,   1 );
    is( $fromu->user, $tousername, "Rename fromu to tou, which is under the control of fromu" );
    my $ex_user = substr( $tousername, 0, 10 );
    like( $tou->user, qr/^ex_$ex_user/, "Moved out of the way." );
}

{
    my ( $fromu, $tou ) = $create_users->();

    my $fromusername = $fromu->username;
    my $tousername   = $tou->user;

    $tou->set_statusvis("D");

    ok( !$fromu->can_rename_to($tousername), "Cannot rename to (nonmatching) deleted users." );
}

{
    my ( $fromu, $tou, $tousername );

    ( $fromu, $tou ) = $create_users->( validated => 1 );
    $tousername = $tou->user;

    $tou->set_statusvis("S");
    ok( !$fromu->can_rename_to($tousername), "Cannot rename to nonmatching suspended users." );

    ( $fromu, $tou ) = $create_users->( match => 1, validated => 1 );
    $tousername = $tou->user;

    $tou->set_statusvis("S");
    ok( !$fromu->can_rename_to($tousername), "Cannot rename to matching suspended users." );

    $tou->set_statusvis("L");
    ok( !$fromu->can_rename_to($tousername), "Cannot rename to matching locked users." );

    $tou->set_statusvis("M");
    ok( !$fromu->can_rename_to($tousername), "Cannot rename to matching memorial users." );

    $tou->set_statusvis("O");
    ok( !$fromu->can_rename_to($tousername), "Cannot rename to matching read-only users." );

    $tou->set_statusvis("R");
    ok( !$fromu->can_rename_to($tousername),
        "Cannot rename to matching renamed and redirecting users." );

    $tou->set_statusvis("V");
    ok( $fromu->can_rename_to($tousername), "(reset status)" );

    $fromu->set_statusvis("S");
    ok( !$fromu->can_rename_to($tousername), "Cannot rename from suspended users." );
}

note("-- username issues");
{
    my $fromu = temp_user();

    my $fromusername = $fromu->user;

    # taken from htdocs/inc/reserved-usernames. Production site may have more
    # but these are good enough for testing
    my @reserved_names = qw( dw_test ex_test ext_test s_test _test test__test );

    foreach my $name (@reserved_names) {
        ok( !$fromu->can_rename_to( $name . $fromusername, token => new_token($fromu) ),
            "Cannot rename to reserved username '$name'" );
    }

    # reserved usernames can be force-renamed to
    foreach my $name (@reserved_names) {
        ok(
            $fromu->can_rename_to( $name . $fromusername, token => new_token($fromu), force => 1 ),
            "Forced rename to reserved username '$name$fromusername'"
        );
    }

    ok( !$fromu->can_rename_to( $fromu->username, token => new_token($fromu) ),
        "Cannot rename to own name" );
}

{
    my $fromu = temp_user();

    my $fromusername      = $fromu->user;
    my @invalid_usernames = qw( a.b a!b a\x{123}b );
    push @invalid_usernames, "x" x 30;

    foreach my $name (@invalid_usernames) {
        ok(
            !$fromu->rename( $name, token => new_token($fromu) ),
            "Cannot rename to invalid username '$name'"
        );
    }

    # invalid usernames cannot be force-renamed to
    foreach my $name (@invalid_usernames) {
        ok( !$fromu->rename( $name, token => new_token($fromu), force => 1 ),
            "Cannot force rename to invalid username '$name'" );
    }
}

{
    my $fromu = temp_user();

    my $tousername = $fromu->user . "-abc";
    ok( $fromu->rename( $tousername, token => new_token($fromu) ), "Rename does canonicalization" );
    $fromu = LJ::load_userid( $fromu->userid );
    is( $fromu->user, LJ::canonical_username($tousername), "Canonicalize away hyphens" );
}

note("-- community-to-unregistered");
{
    my $admin      = temp_user();
    my $fromu      = temp_comm();
    my $tousername = $fromu->username . "_renameto";

    ok( !$admin->can_manage($fromu), "User cannot manage community fromu." );
    ok(
        !$fromu->can_rename_to( $tousername, user => $admin ),
        "Cannot rename community to  $tousername (not admin)"
    );

    LJ::set_rel( $fromu, $admin, "A" );

    # FIXME: we shouldn't need to do this!
    DW::Cache->request->remove( 'rel', $fromu->userid . "-" . $admin->userid . "-A" );
    ok( $admin->can_manage($fromu), "User can manage fromu." );

    ok( !LJ::load_user($tousername), "Username '$tousername' is unregistered" );
    ok( $fromu->can_rename_to( $tousername, user => $admin ), "Can rename to $tousername" );
    ok( $fromu->rename( $tousername, token => new_token($admin), user => $admin ),
        "Renamed community to $tousername" );

    LJ::update_user( $admin, { status => 'A' } );
    ok( $admin->is_validated, "Admin was validated so could rename." );
    LJ::update_user( $admin, { status => 'N' } );
    ok(
        !$admin->is_validated && !$fromu->can_rename_to( $tousername . "_rename", user => $admin ),
        "Admin no longer validated; can no longer rename"
    );

    ok( !$fromu->can_rename_to($tousername),
        "Cannot rename community without providing a user doing the renaming" );
}

subtest 'Community rename preserves memberships and notifies eligible members' => sub {
    my $community = temp_comm();
    my $oldname   = $community->user;
    my $newname   = $oldname . '_renamed';
    my $admin     = temp_user();
    my $coadmin   = temp_user();
    my $watcher   = temp_user();

    LJ::update_user( $admin,   { status => 'A', email => 'rename-admin@example.com' } );
    LJ::update_user( $coadmin, { status => 'A', email => 'rename-coadmin@example.com' } );
    LJ::update_user( $watcher, { status => 'A', email => 'rename-watcher@example.com' } );
    LJ::set_rel( $community, $admin,   'A' );
    LJ::set_rel( $community, $coadmin, 'A' );
    $watcher->add_edge( $community, watch => {} );

    my $make_member = sub {
        my (%fields) = @_;
        my $member = temp_user();
        LJ::set_rel( $community, $member, 'E' );
        LJ::update_user( $member, { status => 'A', %fields } );
        return $member;
    };

    my $member = $make_member->( email => 'rename-member@example.com' );
    my $second = $make_member->( email => 'rename-second@example.com' );
    $make_member->( email => 'Rename-Member@example.com' );
    $make_member->( email => 'rename-unverified@example.com', status => 'N' );
    $make_member->( email => 'rename-deleted@example.com', statusvis => 'D' );
    $make_member->( email => 'rename-suspended@example.com', statusvis => 'S' );
    $make_member->( email => 'rename-purged@example.com', statusvis => 'X' );
    $make_member->( email => 'rename-invalid@@example.com' );
    $make_member->( email => '' );
    LJ::set_rel( $community, $coadmin, 'E' );

    my @members_before    = sort { $a <=> $b } $community->member_userids;
    my $original_dispatch = DW::TaskQueue->can('dispatch');
    my @mail;
    no warnings 'redefine';
    local *DW::TaskQueue::dispatch = sub {
        my ( $class, $task ) = @_;
        return $original_dispatch->(@_) unless $task->isa('DW::Task::SendEmail');
        push @mail, $task->args->[0];
        return 1;
    };

    my $token = new_token($admin);
    ok( !$community->rename( $newname, token => new_token($member), user => $member ),
        'A member without admin rights cannot rename the community' );
    my $occupied = temp_comm();
    LJ::set_rel( $occupied, $admin,  'A' );
    LJ::set_rel( $occupied, $second, 'E' );
    ok(
        !$community->rename( $occupied->user, token => $token, user => $admin ),
        'A rename cannot displace another community that has members'
    );
    is( $community->user, $oldname, 'Denied rename does not change the name' );
    is_deeply( \@mail, [], 'Denied rename does not queue mail' );

    ok(
        $community->can_rename_to( $newname, user => $admin ),
        'Admin can rename a community with members'
    );
    ok( $community->rename( $newname, token => $token, user => $admin, redirect => 1 ),
        'Rename succeeds with members' );
    is_deeply( \@mail, [], 'The rename does not expand recipients' );
    ok(
        DW::Task::CommunityRenameNotice->process_pending( $community->id ),
        'The worker finds and processes the committed notice'
    );

    my $renamed = LJ::load_user($newname);
    my $old     = LJ::load_user($oldname);
    is( $renamed && $renamed->userid, $community->userid, 'The new name keeps the same ID' );
    my ($mapped_name) = LJ::get_db_writer()
        ->selectrow_array( 'SELECT user FROM useridmap WHERE userid=?', undef, $community->userid );
    is( $mapped_name, $newname, 'The name map and community account agree' );
    ok( $old && $old->is_redirect, 'The old name is a redirect' );
    is( $old && $old->prop('renamedto'), $newname, 'The old name redirects to the new name' );
    is_deeply( [ sort { $a <=> $b } $community->member_userids ],
        \@members_before, 'The full membership list stays intact' );
    ok( $renamed && $member->member_of($renamed) && $second->member_of($renamed),
        'Members still belong to the renamed community' );
    ok( $renamed && $admin->can_manage_other($renamed) && $coadmin->can_manage_other($renamed),
        'Both admins still manage the renamed community' );
    is_deeply(
        [
            sort map {
                map { lc $_ }
                    @{ $_->{rcpts} }
            } @mail
        ],
        [qw( rename-coadmin@example.com rename-member@example.com rename-second@example.com )],
        'Only distinct verified mailboxes of eligible members receive email'
    );
    is( scalar @mail, 3, 'Each mailbox gets a separate notice' );

    my $profile = $renamed ? $renamed->profile_url : '';
    foreach my $message (@mail) {
        my ( undef, $body ) = split /\r?\n\r?\n/, $message->{data}, 2;
        $body = decode_qp( $body // '' );
        is( scalar @{ $message->{rcpts} }, 1, 'The envelope names a single recipient' );
        like( $body, qr/\b\Q$oldname\E\b/, 'The email body names the old community' );
        like( $body, qr/\b\Q$newname\E\b/, 'The email body names the renamed community' );
        like( $body, qr/\Q$profile\E/,     'The email body links to the renamed profile' );
        like( $body, qr/leave from the community's profile/i, 'The email explains how to leave' );
    }
};

subtest 'Community preflight can use a reader, but displacement needs a writer' => sub {
    my $actor       = temp_user();
    my $target      = temp_comm();
    my $source_name = $actor->user;
    my $target_name = $target->user;
    my $token       = new_token($actor);
    LJ::set_rel( $target, $actor, 'A' );

    my $original_writer = LJ->can('get_db_writer');
    {
        no warnings 'redefine';
        local *LJ::get_db_writer = sub {
            return undef if caller eq 'DW::User::Rename';
            return $original_writer->(@_);
        };
        ok( $actor->can_rename_to($target_name),
            'Preflight can verify the target without the writer' );
        my $result = eval { $actor->rename( $target_name, token => $token ) };
        is( $@, '', 'The writer outage does not throw' );
        ok( !$result, 'The rename fails closed' );
    }
    is( LJ::load_userid( $actor->userid,  1 )->user, $source_name, 'The source is unchanged' );
    is( LJ::load_userid( $target->userid, 1 )->user, $target_name, 'The target is unchanged' );
    is( token_status($token), 'U', 'The token is still unused' );
    {
        my $original_read = DBI::db->can('selectcol_arrayref');
        no warnings 'redefine';
        local *DBI::db::selectcol_arrayref = sub {
            my ( $db, $sql ) = @_;
            die 'simulated membership read error' if $sql =~ /FROM reluser.*type='E'/;
            return $original_read->(@_);
        };
        ok( !$actor->can_rename_to($target_name), 'A membership query exception blocks preflight' );
        ok(
            !$actor->rename( $target_name, token => $token ),
            'A membership query exception blocks displacement'
        );
    }
    ok( $actor->rename( $target_name, token => $token ), 'The same token works after recovery' );
};

subtest 'A stale vacancy cannot authorize moving aside a different account' => sub {
    my $actor         = temp_user();
    my $target        = temp_comm();
    my $source_name   = $actor->user;
    my $target_name   = $target->user;
    my $token         = new_token($actor);
    my $original_load = LJ->can('load_user');
    my $lookups       = 0;

    {
        no warnings 'redefine';
        local *LJ::load_user = sub {
            return undef if $_[0] eq $target_name && !$lookups++;
            return $original_load->(@_);
        };
        ok(
            !$actor->rename( $target_name, token => $token ),
            'The exact occupying account must be authorized'
        );
    }
    is( LJ::load_userid( $actor->userid,  1 )->user, $source_name, 'The source is unchanged' );
    is( LJ::load_userid( $target->userid, 1 )->user, $target_name, 'The target is unchanged' );
    is( token_status($token), 'U', 'The token is still unused' );
};

subtest 'A stale target lookup cannot authorize a community swap' => sub {
    my $actor       = temp_user();
    my $community   = temp_comm();
    my $source_name = $actor->user;
    my $target_name = $community->user;
    my @tokens      = ( new_token($actor), new_token($actor) );
    LJ::update_user( $actor, { status => 'A' } );
    LJ::set_rel( $community, $actor,      'A' );
    LJ::set_rel( $community, temp_user(), 'E' );
    my $original_load = LJ->can('load_user');
    my $lookups       = 0;

    {
        no warnings 'redefine';
        local *LJ::load_user = sub {
            return undef if $_[0] eq $target_name && !$lookups++;
            return $original_load->(@_);
        };
        ok(
            !$actor->swap_usernames( $community, tokens => \@tokens ),
            'An occupied community cannot be swapped using a stale vacancy'
        );
    }
    is( LJ::load_userid( $actor->userid,     1 )->user, $source_name, 'The source is unchanged' );
    is( LJ::load_userid( $community->userid, 1 )->user, $target_name, 'The target is unchanged' );
    is_deeply( [ map { token_status($_) } @tokens ], [ 'U', 'U' ], 'Both tokens are still unused' );
};

subtest 'A failed source write rolls back the target move' => sub {
    my $actor       = temp_user();
    my $target      = temp_comm();
    my $source_name = $actor->user;
    my $target_name = $target->user;
    my $token       = new_token($actor);
    LJ::set_rel( $target, $actor, 'A' );

    my $dbh = LJ::get_db_writer();
    {
        my $original_do = $dbh->can('do');
        no warnings 'redefine';
        local *DBI::db::do = sub {
            my ( $db, $sql, $attrs, @values ) = @_;
            return '0E0'
                if $sql =~ /UPDATE user JOIN useridmap/ && $values[2] == $actor->userid;
            return $original_do->(@_);
        };
        ok(
            !$actor->rename( $target_name, token => $token ),
            'The failed write refuses the rename'
        );
    }
    is( LJ::load_userid( $actor->userid,  1 )->user, $source_name, 'The source is unchanged' );
    is( LJ::load_userid( $target->userid, 1 )->user, $target_name, 'The target move rolled back' );
    is(
        $dbh->selectrow_array(
            'SELECT user FROM useridmap WHERE userid=?', undef, $target->userid
        ),
        $target_name,
        'The target name map also rolled back'
    );
    is( token_status($token), 'U', 'The token is still unused' );
    ok( $actor->rename( $target_name, token => $token ), 'The same token works on retry' );
};

subtest 'System token allocation failure leaves both usernames unchanged' => sub {
    my $dbh = LJ::get_db_writer();
    foreach my $operation (qw(rename swap)) {
        my $source      = temp_user();
        my $target      = temp_comm();
        my $source_name = $source->user;
        my $target_name = $target->user;
        my @tokens      = ( new_token($source) );
        push @tokens, new_token($source) if $operation eq 'swap';
        LJ::update_user( $source, { status => 'A' } );
        LJ::set_rel( $target, $source, 'A' );
        my $change = sub {
            return $operation eq 'rename'
                ? $source->rename( $target_name, token => $tokens[0] )
                : $source->swap_usernames( $target, tokens => \@tokens );
        };

        LJ::load_user($source_name);
        LJ::load_user($target_name);
        my $allocations = 0;
        {
            no warnings 'redefine';
            local *DW::RenameToken::create_token = sub {
                $allocations++;
                die 'simulated system token allocation failure';
            };
            my $changed = eval { $change->() };
            is( $@, '', "$operation reports allocation failure without throwing" );
            ok( !$changed, "$operation fails when the system token cannot be allocated" );
        }
        is( $allocations, 1, "$operation attempted system token allocation" );

        foreach my $account ( [ $source->id, $source_name ], [ $target->id, $target_name ] ) {
            my ( $userid, $name ) = @$account;
            my $stored_names = $dbh->selectrow_arrayref(
                'SELECT user.user, useridmap.user FROM user JOIN useridmap USING (userid) '
                    . 'WHERE userid=?',
                undef, $userid
            );
            is_deeply(
                $stored_names,
                [ $name, $name ],
                "$operation leaves both name records intact"
            );
            my $cached = LJ::load_user($name);
            is( $cached && $cached->id, $userid, "$operation leaves the name lookup consistent" );
        }
        is_deeply(
            [ map { token_status($_) } @tokens ],
            [ ('U') x @tokens ],
            "$operation does not consume customer tokens on failure"
        );
        ok( $change->(), "$operation succeeds on retry with the same tokens" );
        is_deeply(
            [ map { token_status($_) } @tokens ],
            [ ('A') x @tokens ],
            "$operation consumes customer tokens only on success"
        );
    }
};

subtest 'A failed commit discards the allocated system token' => sub {
    my $source      = temp_user();
    my $target      = temp_comm();
    my $source_name = $source->user;
    my $target_name = $target->user;
    my $token       = new_token($source);
    LJ::set_rel( $target, $source, 'A' );

    my $dbh             = LJ::get_db_writer();
    my $original_create = DW::RenameToken->can('create_token');
    my $system_token;
    {
        no warnings 'redefine';
        local *DW::RenameToken::create_token = sub { $system_token = $original_create->(@_) };
        local *DBI::db::commit               = sub { die 'simulated commit failure' };
        ok(
            !$source->rename( $target_name, token => $token ),
            'The failed commit refuses the rename'
        );
    }
    ok( $system_token, 'A system token was reserved before commit' ) or return;
    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM renames WHERE renid=?',
            undef, $system_token->id
        ),
        0,
        'The reserved token does not remain after rollback'
    );
    is( LJ::load_userid( $source->id, 1 )->user, $source_name, 'The source name rolled back' );
    is( LJ::load_userid( $target->id, 1 )->user, $target_name, 'The target name rolled back' );
    is( token_status($token), 'U', 'The customer token remains unused' );
};

subtest 'A move-aside logging failure does not interrupt committed renames' => sub {
    foreach my $operation (qw(rename swap)) {
        my $source      = temp_user();
        my $target      = temp_comm();
        my $source_name = $source->user;
        my $target_name = $target->user;
        my @tokens      = ( new_token($source) );
        push @tokens, new_token($source) if $operation eq 'swap';
        LJ::update_user( $source, { status => 'A' } );
        LJ::set_rel( $target, $source, 'A' );

        foreach my $account ( $source, $target ) {
            is( LJ::get_userid( $account->user ), $account->id, 'Prime the username to ID cache' );
            is( LJ::get_username( $account->id ), $account->user,
                'Prime the ID to username cache' );
            is( LJ::load_userid( $account->id )->user, $account->user, 'Prime the user cache' );
        }

        my $original_log_event = LJ::User->can('log_event');
        my $displaced_name;
        {
            no warnings 'redefine';
            local *LJ::User::log_event = sub {
                my ( $account, $event, $details ) = @_;
                if (   $account->id == $target->id
                    && $event eq 'rename'
                    && $details->{from} eq $target_name )
                {
                    $displaced_name = $details->{to};
                    die 'simulated cluster outage while logging the move-aside';
                }
                return $original_log_event->(@_);
            };
            my $changed = eval {
                return $operation eq 'rename'
                    ? $source->rename( $target_name, token => $tokens[0] )
                    : $source->swap_usernames( $target, tokens => \@tokens );
            };
            is( $@, '', "$operation does not throw after commit" );
            ok( $changed, "$operation reports the committed change" );
        }
        like( $displaced_name, qr/^ex_/, "$operation attempted to log the move-aside" );

        my $target_final_name = $operation eq 'swap' ? $source_name : $displaced_name;
        is( LJ::get_username( $source->id ), $target_name, 'The source username cache is fresh' );
        is( LJ::get_username( $target->id ),
            $target_final_name, 'The displaced username cache is fresh' );
        is( LJ::load_userid( $source->id )->user, $target_name, 'The source user cache is fresh' );
        is( LJ::load_userid( $target->id )->user,
            $target_final_name, 'The displaced user cache is fresh' );
        is( LJ::get_userid($target_name), $source->id, 'The destination name maps to the source' );
        is( LJ::get_userid($target_final_name),
            $target->id, 'The final displaced name maps to the displaced account' );
        is(
            LJ::get_userid($source_name),
            $operation eq 'swap' ? $target->id : 0,
            'The former source name no longer maps to the source account'
        );
        is( token_status($_), 'A', "$operation consumed a customer token" ) foreach @tokens;
    }
};

subtest 'A relationship removal exception is not reported as a successful rename' => sub {
    my $source  = temp_user();
    my $trusted = temp_user();
    my $newname = $source->user . 'new';
    my $token   = new_token($source);
    ok( $source->add_edge( $trusted, trust => { nonotify => 1 } ), 'Create a trust relationship' );

    my $remove_edge = LJ::User->can('remove_edge');
    {
        no warnings 'redefine';
        local *LJ::User::remove_edge = sub {
            my ( $from, $to, %edges ) = @_;
            die 'simulated trust removal exception'
                if $from->id == $source->id && $to->id == $trusted->id && $edges{trust};
            return $remove_edge->(@_);
        };
        my $renamed = eval { $source->rename( $newname, token => $token, del_trusted => 1 ) };
        my $error   = $@;
        ok( !$renamed, 'Rename does not report success when requested trust removal fails' );
        like(
            $error,
            qr/simulated trust removal exception/,
            'The removal exception reaches the caller'
        );
    }

    ok( $source->trusts($trusted), 'The interrupted trust removal did not take effect' );
    is( LJ::load_userid( $source->id )->user, $newname, 'The committed username is visible' );
    is( token_status($token), 'A', 'The committed rename still consumes the customer token' );
};

subtest 'A system token apply failure does not interrupt committed renames' => sub {
    foreach my $operation (qw(rename swap)) {
        my $source      = temp_user();
        my $target      = temp_comm();
        my $source_name = $source->user;
        my $target_name = $target->user;
        my @tokens      = ( new_token($source) );
        push @tokens, new_token($source) if $operation eq 'swap';
        LJ::update_user( $source, { status => 'A' } );
        LJ::set_rel( $target, $source, 'A' );

        foreach my $account ( $source, $target ) {
            is( LJ::get_userid( $account->user ), $account->id, 'Prime the username to ID cache' );
            is( LJ::get_username( $account->id ), $account->user,
                'Prime the ID to username cache' );
            is( LJ::load_userid( $account->id )->user, $account->user, 'Prime the user cache' );
        }

        my $apply = DW::RenameToken->can('apply');
        my $displaced_name;
        {
            no warnings 'redefine';
            local *DW::RenameToken::apply = sub {
                my ( $token, %change ) = @_;
                if ( !$token->ownerid && $change{userid} == $target->id ) {
                    $displaced_name = $change{to};
                    my $target_final = $operation eq 'swap' ? $source_name : $displaced_name;
                    is( LJ::get_username( $source->id ),
                        $target_name, 'Source name cache is already fresh' );
                    is( LJ::get_username( $target->id ),
                        $target_final, 'Displaced name cache is already fresh' );
                    is( LJ::load_userid( $source->id )->user,
                        $target_name, 'Source user cache is already fresh' );
                    is( LJ::load_userid( $target->id )->user,
                        $target_final, 'Displaced user cache is already fresh' );
                    is( LJ::get_userid($target_name),
                        $source->id, 'Destination name now maps to the source' );
                    is( LJ::get_userid($target_final),
                        $target->id, 'Final displaced name maps to the target' );
                    die 'simulated system token apply exception';
                }
                return $apply->(@_);
            };
            my $changed = eval {
                return $operation eq 'rename'
                    ? $source->rename( $target_name, token => $tokens[0] )
                    : $source->swap_usernames( $target, tokens => \@tokens );
            };
            is( $@, '', "$operation does not throw if the system token fails to apply" );
            ok( $changed, "$operation reports the committed change" );
        }

        like( $displaced_name, qr/^ex_/, "$operation attempted to apply the move-aside token" );
        is( token_status($_), 'A', "$operation consumed a customer token" ) foreach @tokens;
    }
};

subtest 'Moving aside a community records its durable rename notice' => sub {
    my $admin     = temp_user();
    my $community = temp_comm();
    my $oldname   = $community->user;
    my $mailbox   = 'rename-displaced@example.com';
    LJ::update_user( $admin, { status => 'A', email => $mailbox } );
    LJ::set_rel( $community, $admin, 'A' );
    LJ::set_rel( $community, $admin, 'E' );

    ok( $admin->rename( $oldname, token => new_token($admin) ), 'Rename into the community name' );
    my $newname = LJ::load_userid( $community->id )->user;
    like( $newname, qr/^ex_/, 'The original community has a displaced name' );

    my $dispatch = DW::TaskQueue->can('dispatch');
    my @messages;
    no warnings 'redefine';
    local *DW::TaskQueue::dispatch = sub {
        my ( $class, $task ) = @_;
        return $dispatch->(@_) unless $task->isa('DW::Task::SendEmail');
        push @messages, $task->args->[0];
        return 1;
    };
    ok( DW::Task::CommunityRenameNotice->process_pending( $community->id ),
        'The worker finds the durable displacement notice' );
    is_deeply( [ map { @{ $_->{rcpts} } } @messages ],
        [$mailbox], 'The community member receives exactly one notice' );
    my ( undef, $body ) = split /\r?\n\r?\n/, ( $messages[0] || {} )->{data} // '', 2;
    $body = decode_qp( $body // '' );
    like( $body, qr/\b\Q$oldname\E\b/, 'The notice names the original community' );
    like( $body, qr/\b\Q$newname\E\b/, 'The notice names the displaced community' );
};

subtest 'An outbox write failure rolls back a community rename' => sub {
    my $community = temp_comm();
    my $target    = temp_comm();
    my $admin     = temp_user();
    my $oldname   = $community->user;
    my $newname   = $target->user;
    my $token     = new_token($admin);
    LJ::set_rel( $community, $admin, 'A' );
    LJ::set_rel( $target,    $admin, 'A' );

    my $dbh         = LJ::get_db_writer();
    my $original_do = $dbh->can('do');
    no warnings 'redefine';
    local *DBI::db::do = sub {
        my ( $db, $sql ) = @_;
        die 'simulated outbox write exception' if $sql =~ /^INSERT INTO community_rename_notice /;
        return $original_do->(@_);
    };
    ok( !$community->rename( $newname, token => $token, user => $admin, redirect => 1 ),
        'Rename fails closed if the durable notice cannot be written' );
    is( LJ::load_userid( $community->id, 1 )->user, $oldname, 'Source name rolled back' );
    is( LJ::load_userid( $target->id,    1 )->user, $newname, 'Destination name rolled back' );
    is( token_status($token), 'U', 'The token remains unused' );
};

subtest 'Queue failures do not undo a rename or stop other notices' => sub {
    my $community = temp_comm();
    my $admin     = temp_user();
    my $oldname   = $community->user;
    my $target    = temp_comm();
    my $newname   = $target->user;
    my $token     = new_token($admin);
    LJ::set_rel( $community, $admin, 'A' );
    LJ::set_rel( $target,    $admin, 'A' );
    my @mailboxes = (
        qw(rename-fail@example.com rename-leave@example.com),
        map { sprintf 'rename-next-%02d@example.com', $_ } 1 .. 24
    );
    my $leaving;

    foreach my $mailbox (@mailboxes) {
        my $member = temp_user();
        LJ::set_rel( $community, $member, 'E' );
        LJ::update_user( $member, { status => 'A', email => $mailbox } );
        $leaving = $member if $mailbox eq 'rename-leave@example.com';
    }

    my $original_dispatch = DW::TaskQueue->can('dispatch');
    my ( @security_events, @attempts );
    my $fail_recipient = 1;
    no warnings 'redefine';
    local *DW::TaskQueue::dispatch = sub {
        my ( $class, $task ) = @_;
        if ( $task->isa('LJ::Event::SecurityAttributeChanged') ) {
            push @security_events, $task;
            die 'simulated security notification exception';
        }
        return $original_dispatch->(@_) unless $task->isa('DW::Task::SendEmail');
        my ($recipient) = @{ $task->args->[0]->{rcpts} };
        push @attempts, $recipient;
        die 'simulated per-recipient exception'
            if $fail_recipient && $recipient eq $mailboxes[0];
        return undef if $fail_recipient && $recipient eq $mailboxes[1];
        return 1;
    };
    my $renamed =
        eval { $community->rename( $newname, token => $token, user => $admin, redirect => 1 ) };
    is( $@, '', 'The failed enqueue does not throw from rename' );
    ok( $renamed, 'Rename reports success even if notification enqueue fails' );
    is( $community->user, $newname, 'The rename is committed' );
    like( LJ::load_userid( $target->id, 1 )->user, qr/^ex_/, 'The destination moved aside' );
    is( token_status($token), 'A', 'The source token was applied' );
    my $redirect = LJ::load_user($oldname);
    is( $redirect && $redirect->prop('renamedto'), $newname, 'The redirect is in place' );
    is( scalar @security_events, 2, 'Both security events were attempted' );
    is_deeply( \@attempts, [], 'The web request does not dispatch mail' );

    my $poll = DW::Task::CommunityRenameNotice->can('process_pending');
    ok( $poll, 'The worker can recover committed notices without a queue message' ) or return;
    ok( $poll->( 'DW::Task::CommunityRenameNotice', $community->id ),
        'The worker finds the notice' );
    is_deeply(
        \@attempts,
        [ @mailboxes[ 0 .. 24 ] ],
        'One bounded batch is attempted despite the first dispatch exception'
    );
    {
        my $original_do = LJ::get_db_writer()->can('do');
        local *DBI::db::do = sub {
            my ( $db, $sql ) = @_;
            die 'simulated continuation checkpoint exception'
                if $sql =~ /^UPDATE community_rename_notice SET after_mailbox=/;
            return $original_do->(@_);
        };
        is( $poll->( 'DW::Task::CommunityRenameNotice', $community->id ),
            0, 'A failed continuation checkpoint leaves the next page pending' );
    }
    is( scalar @attempts, 25, 'No accepted mail is replayed when the next page fails' );
    ok(
        $poll->( 'DW::Task::CommunityRenameNotice', $community->id ),
        'A later batch can finish without waiting for the failed dispatch'
    );
    is_deeply( \@attempts, \@mailboxes, 'All recipients are attempted' );

    $leaving->leave_community($community);
    LJ::get_db_writer()->do(
        'UPDATE community_rename_recipient SET next_attempt=0 WHERE noticeid IN '
            . '(SELECT noticeid FROM community_rename_notice WHERE commid=?)',
        undef, $community->id
    );
    @attempts       = ();
    $fail_recipient = 0;
    ok( $poll->( 'DW::Task::CommunityRenameNotice', $community->id ), 'The retry finishes' );
    is_deeply(
        \@attempts,
        [ $mailboxes[0] ],
        'Only the still-eligible failed recipient is retried'
    );
    is( $poll->( 'DW::Task::CommunityRenameNotice', $community->id ),
        0, 'Polling again does not replay an accepted recipient or continuation' );
};

subtest 'A permanently failing notice recipient stops retrying' => sub {
    my $community = temp_comm();
    my $admin     = temp_user();
    my $member    = temp_user();
    my $mailbox   = 'rename-permanent-failure@example.com';
    LJ::set_rel( $community, $admin,  'A' );
    LJ::set_rel( $community, $member, 'E' );
    LJ::update_user( $member, { status => 'A', email => $mailbox } );
    ok(
        $community->rename( $community->user . 'new', token => new_token($admin), user => $admin ),
        'Rename stages a notice'
    );

    my $dbh               = LJ::get_db_writer();
    my $original_dispatch = DW::TaskQueue->can('dispatch');
    my @attempts;
    no warnings 'redefine';
    local *DW::TaskQueue::dispatch = sub {
        my ( $class, $task ) = @_;
        return $original_dispatch->(@_) unless $task->isa('DW::Task::SendEmail');
        push @attempts, @{ $task->args->[0]->{rcpts} };
        return undef;
    };

    my $make_due = sub {
        $dbh->do(
            'UPDATE community_rename_recipient SET next_attempt=0 WHERE noticeid IN '
                . '(SELECT noticeid FROM community_rename_notice WHERE commid=?)',
            undef, $community->id
        );
    };
    foreach my $attempt ( 1 .. 10 ) {
        $make_due->();
        ok( DW::Task::CommunityRenameNotice->process_pending( $community->id ),
            "Worker processes due attempt $attempt" );
    }
    $make_due->();
    is( DW::Task::CommunityRenameNotice->process_pending( $community->id ),
        0, 'No work remains after the last allowed failure' );
    is_deeply( \@attempts, [ ($mailbox) x 10 ], 'Mail submission stops after ten failures' );
    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM community_rename_notice WHERE commid=?', undef,
            $community->id
        ),
        0,
        'The completed notice is deleted'
    );
};

note("-- community-to-personal");
{
    my ( $admin, $tou ) = $create_users->( validated => 1 );
    my $fromu      = temp_comm();
    my $tousername = $tou->user;

    # make admin of fromu
    LJ::set_rel( $fromu, $admin, "A" );
    DW::Cache->request->remove( 'rel', $fromu->userid . "-" . $admin->userid . "-A" );

    ok(
        !$fromu->can_rename_to( $tousername, user => $admin ),
"Cannot rename fromu to existing user $tousername (tou is a personal journal not under admin's control)"
    );

    ( $admin, $tou ) = $create_users->( match => 1, validated => 1 );
    $tousername = $tou->user;

    # make admin of fromu
    LJ::set_rel( $fromu, $admin, "A" );
    DW::Cache->request->remove( 'rel', $fromu->userid . "-" . $admin->userid . "-A" );
    ok(
        $fromu->can_rename_to( $tousername, user => $admin ),
        $admin->user
            . " can rename community fromu to existing user $tousername (tou is a personal journal under admin's control)"
    );
    ok(
        $fromu->rename( $tousername, token => new_token($admin), user => $admin ),
        $admin->user . " renamed community fromu to existing community $tousername"
    );
}

note("-- personal-to-community");
{
    my $fromu = temp_user();
    LJ::update_user( $fromu, { status => 'A' } );

    my $tou        = temp_comm();
    my $tousername = $tou->user;

    # make admin of tou
    LJ::set_rel( $tou, $fromu, "A" );
    DW::Cache->request->remove( 'rel', $tou->userid . "-" . $fromu->userid . "-A" );

    my $member = temp_user();
    $member->join_community($tou);
    ok( !$fromu->can_rename_to( $tousername, user => $fromu, verbose => 1 ),
        "Cannot rename a community with members" );

    $member->leave_community($tou);
    ok( $fromu->can_rename_to($tousername),
        "Can rename to a community under your own control if it has no members." );
    ok(
        $fromu->rename( $tousername, token => new_token($fromu) ),
        "Renamed personal journal fromu to existing community."
    );
}

note("-- openid and feeds");
{
    my $u = temp_user();
    LJ::update_user( $u, { journaltype => 'I' } );

    ok( !$u->can_rename_to( $u->user . "_rename" ), "Cannot rename OpenID accounts" );

    LJ::update_user( $u, { journaltype => 'F' } );
    ok( !$u->can_rename_to( $u->user . "_rename" ), "Cannot rename feed accounts" );
}

note("-- rename token ownership ignored");
{
    my $u = temp_user();

    my $fromusername = $u->user;
    my $tousername   = $fromusername . "_renameto";

    ok( $u->rename( $tousername, token => new_token( temp_user() ) ),
        "Check that rename token ownership is ignored" );
}

note("-- two username swap (personal to personal)");
{
    my ( $u1, $u2 ) = $create_users->( match => 1, validated => 1 );

    my $u1id      = $u1->userid;
    my $u2id      = $u2->userid;
    my $u1sername = $u1->user;
    my $u2sername = $u2->user;

    ok( $u1sername ne $u2sername, "Not the same username" );

    my $token = new_token($u1);
    ok(
        !$u1->swap_usernames(
            $u2, tokens => [ $token, $token ]
        ),
        "Can't swap, token is the same"
    );

    ok(
        $u1->swap_usernames(
            $u2, tokens => [ new_token($u1), new_token($u1) ]
        ),
        "Swap usernames"
    );

    $u1 = LJ::load_userid( $u1->userid );
    $u2 = LJ::load_userid( $u2->userid );

    is( $u1->user, $u2sername, "Swap usernames of u1 and u2" );
    is( $u2->user, $u1sername, "Swap usernames of u2 and u1" );

    is( $u1->userid, $u1id, "Id of u1 remains the same after rename." );
    is( $u2->userid, $u2id, "Id of u2 remains the same after rename." );
}

note("-- two username swap (personal to personal), one token owned by each user");
{
    my ( $u1, $u2 ) = $create_users->( match => 1, validated => 1 );

    ok(
        $u1->swap_usernames(
            $u2, tokens => [ new_token($u1), new_token($u2) ]
        ),
        "Swap usernames with one token owned by each account"
    );
}

note("-- two username swap (one user is suspended)");
{
    my ( $u1, $u2 ) = $create_users->( match => 1, validated => 1 );
    $u2->set_statusvis("S");

    my $u1id      = $u1->userid;
    my $u2id      = $u2->userid;
    my $u1sername = $u1->user;
    my $u2sername = $u2->user;

    ok( $u1sername ne $u2sername, "Not the same username" );

    ok(
        !$u1->swap_usernames(
            $u2, tokens => [ new_token($u1), new_token($u1) ]
        ),
        "Cannot swap usernames."
    );

    $u1 = LJ::load_userid( $u1->userid );
    $u2 = LJ::load_userid( $u2->userid );

    is( $u1->user, $u1sername, "No swap" );
    is( $u2->user, $u2sername, "No swap" );
}

note("-- two username swap personal <=> community ");
{
    my $u = temp_user();
    LJ::update_user( $u, { status => 'A' } );

    my $comm     = temp_comm();
    my $uname    = $u->user;
    my $commname = $comm->user;

    ok(
        !$u->swap_usernames(
            $comm, tokens => [ new_token($u), new_token($u) ]
        ),
        "Cannot swap personal and community usernames (not an admin)"
    );

    # make admin of u
    LJ::set_rel( $comm, $u, "A" );
    DW::Cache->request->remove( 'rel', $comm->userid . "-" . $u->userid . "-A" );

    ok(
        $u->swap_usernames(
            $comm, tokens => [ new_token($u), new_token($u) ],
        ),
        "Swap personal and community usernames"
    );

    is( $u->user,    $commname, "Swap usernames u => comm" );
    is( $comm->user, $uname,    "Swap usernames comm => u" );
}

subtest 'A community swap notifies its administrator who is also a member' => sub {
    my $admin     = temp_user();
    my $community = temp_comm();
    my $oldname   = $community->user;
    my $newname   = $admin->user;
    my $mailbox   = 'rename-swap@example.com';
    LJ::update_user( $admin, { status => 'A', email => $mailbox } );
    LJ::set_rel( $community, $admin, 'A' );
    LJ::set_rel( $community, $admin, 'E' );

    ok( $admin->swap_usernames( $community, tokens => [ new_token($admin), new_token($admin) ] ),
        'Swap with a community whose only member is the administrator' );

    my $original_dispatch = DW::TaskQueue->can('dispatch');
    my @messages;
    no warnings 'redefine';
    local *DW::TaskQueue::dispatch = sub {
        my ( $class, $task ) = @_;
        return $original_dispatch->(@_) unless $task->isa('DW::Task::SendEmail');
        push @messages, $task->args->[0];
        return 1;
    };
    ok( DW::Task::CommunityRenameNotice->process_pending( $community->id ),
        'The worker finds the durable swap notice' );
    is_deeply( [ map { @{ $_->{rcpts} } } @messages ],
        [$mailbox], 'The administrator receives exactly one notice' );
    my ( undef, $body ) = split /\r?\n\r?\n/, $messages[0]->{data} // '', 2;
    $body = decode_qp( $body // '' );
    like( $body, qr/\b\Q$oldname\E\b/, 'The notice names the original community' );
    like( $body, qr/\b\Q$newname\E\b/, 'The notice names the renamed community' );
};

note("-- two username swap personal <=> community (with malice)");
{
    my ( $u, $u2 ) = $create_users->( validate => 1 );

    my $comm     = temp_comm();
    my $uname    = $u->user;
    my $commname = $comm->user;

    # make admin of u
    LJ::set_rel( $comm, $u, "A" );
    DW::Cache->request->remove( 'rel', $comm->userid . "-" . $u->userid . "-A" );

    LJ::set_rel( $comm, $u2, "A" );
    DW::Cache->request->remove( 'rel', $comm->userid . "-" . $u2->userid . "-A" );

    ok(
        !$u->swap_usernames(
            $u2, tokens => [ new_token($u), new_token($u) ],
        ),
        "Swap usernames with someone not under your control"
    );

    ok(
        !$comm->swap_usernames(
            $u2,
            user   => $u,
            tokens => [ new_token($u), new_token($u) ],
        ),
        "Swapping the username of a co-admin"
    );
}

note("-- two username swap community <=> personal");
{
    my $u = temp_user();
    LJ::update_user( $u, { status => 'A' } );

    my $comm     = temp_comm();
    my $uname    = $u->user;
    my $commname = $comm->user;

    ok(
        !$comm->swap_usernames(
            $u, tokens => [ new_token($u), new_token($u) ]
        ),
        "Cannot swap personal and community usernames (not an admin)"
    );

    # make admin of u
    LJ::set_rel( $comm, $u, "A" );
    DW::Cache->request->remove( 'rel', $comm->userid . "-" . $u->userid . "-A" );

    ok(
        !$comm->swap_usernames(
            $u, tokens => [ new_token($u), new_token($u) ]
        ),
        "Cannot swap community and personal when acting on the community"
    );
}

note("-- two username swap (community and community)");
{
    my $admin = temp_user();
    LJ::update_user( $admin, { status => 'A' } );

    my $c1 = temp_comm();
    my $c2 = temp_comm();

    LJ::set_rel( $c1, $admin, "A" );
    DW::Cache->request->remove( 'rel', $c1->userid . "-" . $admin->userid . "-A" );
    LJ::set_rel( $c2, $admin, "A" );
    DW::Cache->request->remove( 'rel', $c2->userid . "-" . $admin->userid . "-A" );

    my $c1sername = $c1->user;
    my $c2sername = $c2->user;

    ok( $c1sername ne $c2sername, "Not the same username" );

    ok(
        $c1->swap_usernames(
            $c2,
            user   => $admin,
            tokens => [ new_token($admin), new_token($admin) ],
        ),
        "Swap community usernames"
    );

    is( $c1->user, $c2sername, "Swap usernames of c1 and c2" );
    is( $c2->user, $c1sername, "Swap usernames of c2 and c1" );
    is_deeply(
        LJ::get_db_writer()->selectall_arrayref(
            'SELECT commid, oldname, newname FROM community_rename_notice WHERE commid IN (?, ?) '
                . 'ORDER BY commid',
            undef,
            $c1->id,
            $c2->id
        ),
        [ [ $c1->id, $c1sername, $c2sername ], [ $c2->id, $c2sername, $c1sername ] ],
        'Both communities have one notice for the final swap, not the intermediate name'
    );
}
