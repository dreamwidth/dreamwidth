#!/usr/bin/perl
#
# DW::Controller::Manage::Ban
#
# /manage/banusers
#
# Authors:
#      Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2022 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Ban;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/banusers", \&ban_handler, app => 1 );
DW::Routing->register_string(
    '/manage/banusers/confirm', \&ban_confirm_handler,
    app      => 1,
    no_cache => 1
);

sub ban_confirm_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $args   = $r->did_post ? $rv->{post_args} : $r->get_args;
    my $userid = $args->{userid} // '';
    my $target = $userid =~ /\A[1-9][0-9]{0,9}\z/ ? LJ::load_userid($userid) : undef;
    return DW::Template->render_template( 'error.tt',
        { message => 'This account cannot be banned or unbanned here.' } )
        unless $remote->can_ban_user($target);

    my $banned = $remote->has_banned($target);
    if ( $r->did_post ) {
        my $action = $args->{action} // '';
        return error_ml('error.invalidform') unless $action eq 'ban' || $action eq 'unban';

        my $saved = 1;
        if ( $action eq 'ban' && !$banned ) {
            my $banned_users = $remote->banned_userids || [];
            return DW::Template->render_template( 'error.tt',
                { message => 'You have reached the maximum number of banned users.' } )
                if @$banned_users >= ( $LJ::MAX_BANS || 5000 );
            $saved = $remote->ban_user_multi( $target->id );
        }
        elsif ( $action eq 'unban' && $banned ) {
            $saved = $remote->unban_user_multi( $target->id );
        }

        return DW::Template->render_template( 'error.tt',
            { message => 'Could not save the ban change. Please try again.' } )
            unless $saved;
        return $r->redirect( $target->profile_url );
    }

    return DW::Template->render_template(
        'manage/banusers-confirm.tt',
        {
            target      => $target,
            action      => $banned ? 'unban' : 'ban',
            label       => $banned ? 'Unban user' : 'Ban user',
            action_url  => "$LJ::SITEROOT/manage/banusers/confirm",
            profile_url => $target->profile_url,
        }
    );
}

sub ban_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1, authas => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;

    my $u      = $rv->{u};
    my $remote = $rv->{remote};
    my $POST   = $r->post_args;
    my $GET    = $r->get_args;

    my $submit_msg = 0;
    my %editvals;

    die "User cannot modify this community"
        unless $remote->can_manage($u);

    if ( $r->did_post ) {

        # check to see if we're doing a note edit instead
        foreach ( keys %{$POST} ) {
            my ($euid) = /^edit_ban_(\d+)$/;
            if ( defined $euid && $POST->{"edit_ban_$euid"} ) {
                my $eu = LJ::load_userid($euid);
                last unless $eu;
                %editvals = (
                    user => $eu->user,
                    note => $u->ban_note($eu)->{$euid},
                );
                last;    # stop searching keys
            }
        }

        my $dbh = LJ::get_db_writer();

        # unban users before banning users so that in the case of a collision (i.e. a particular
        # user is being banned and unbanned at the same time), that user is left banned

        # unban users
        if ( $POST->{unban_user} && !%editvals ) {

            # first remove any users from the list that are not valid users
            my @unbanlist = split( /\0/, $POST->{unban_user} );
            my $unbanus   = LJ::load_userids(@unbanlist);
            for ( my $i = 0 ; $i < scalar @unbanlist ; $i++ ) {
                unless ( $unbanus->{ $unbanlist[$i] } ) {
                    splice( @unbanlist, $i, 1 );
                    $i--;
                }
            }

            # now unban the users
            $u->unban_user_multi(@unbanlist) if @unbanlist;
        }

        # ban users
        if (%editvals) {
            $r->add_msg( LJ::Lang::ml('/manage/banusers.tt.editmsg'), $r->WARNING );
            $submit_msg = 1;
        }
        elsif ( $POST->{ban_list} ) {

            # first remove any users from the list that are not valid users
            # FIXME: we need load_user_multiple
            my @banlist_orig = split( /,/, $POST->{ban_list} );
            my @banlist;
            foreach my $banusername (@banlist_orig) {
                my $banu = LJ::load_user_or_identity($banusername);
                push @banlist, $banu->id if $banu;
            }

            # make sure the user isn't over the max number of bans allowed
            my $banned = LJ::load_rel_user( $u, 'B' ) || [];
            if ( scalar @$banned >= ( $LJ::MAX_BANS || 5000 ) ) {
                $r->add_msg( LJ::Lang::ml('/manage/banusers.tt.error.toomanybans'), $r->ERROR );
                $submit_msg = 1;
            }
            else {
                # now ban the users
                $u->ban_user_multi(@banlist) if @banlist;
            }

            if ( $POST->{ban_note} || $POST->{ban_note_previous} ) {
                $u->ban_note( \@banlist, "$POST->{ban_note}\n$POST->{ban_note_previous}" );
            }
        }

        $r->add_msg( LJ::Lang::ml('/manage/banusers.tt.success'), $r->SUCCESS ) unless $submit_msg;
    }

    # because we may have input from multiple community admins
    # separate the old note from the new note;
    # community admins can still edit the existing notes
    my $separate_add_from_edit = $u->is_community && defined $editvals{note};

    my $banned = $u->banned_userids;
    my @banned_array;
    if ( $banned && @$banned ) {
        my $us    = LJ::load_userids(@$banned);
        my $notes = $u->ban_note($banned);

        foreach my $banuid (@$banned) {
            my $bu = $us->{$banuid};
            next unless $bu;
            my $note = $notes->{$banuid} || '';
            LJ::CleanHTML::clean_subject( \$note );
            $note = LJ::html_newlines($note);
            push @banned_array, { user => $bu, banuid => $banuid, note => $note };

        }
    }

    my $vars = {
        banned       => $banned,
        banned_array => \@banned_array,

        separate_add_from_edit => $separate_add_from_edit,
        u                      => $u,
        authas_html            => $rv->{authas_html},
        editvals               => \%editvals,
    };

    return DW::Template->render_template( 'manage/banusers.tt', $vars );
}

1;
