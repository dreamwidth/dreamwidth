#!/usr/bin/perl
#
# DW::Controller::Manage::Circle::Edit
#
# Page that shows an overview of accounts a user subscribes to
# or grants access to, and vice-versa, with an interface for editing
# or adding accounts.
#
# Authors:
#   Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2009-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Circle::Edit;

use strict;

use DW::Routing;
use DW::Template;
use DW::Controller;
use LJ::JSON;

DW::Routing->register_string( '/manage/circle/edit', \&edit_handler, app => 1 );

sub edit_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;

    my $remote = $rv->{remote};

    my $GET  = $r->get_args;
    my $POST = $r->post_args;
    my $u    = $rv->{u};
    my $vars = {};

    my $view_banned = $GET->{view} eq 'banned';

    return error_ml('error.invalidauth')
        unless $u;
    return $r->redirect( $u->community_manage_members_url )
        if $u->is_community;
    return error_ml('.error.badjournaltype')
        unless $u->is_individual;

    unless ( $r->did_post ) {
        my @banned_userids = @{ $u->banned_userids || [] };
        my %is_banned      = map { $_ => 1 } @banned_userids;

        my $trust_list           = $u->trust_list;
        my $watch_list           = $u->watch_list;
        my @trusted_by_userids   = $u->trusted_by_userids;
        my %is_trusted_by_userid = map { $_ => 1 } @trusted_by_userids;
        my @watched_by_userids   = $u->watched_by_userids;
        my %is_watched_by_userid = map { $_ => 1 } @watched_by_userids;
        my @member_of_userids    = $u->member_of_userids;
        my %is_member_of_userid  = map { $_ => 1 } @member_of_userids;

        my @all_circle_userids = (
            keys %$trust_list,   keys %$watch_list, @trusted_by_userids,
            @watched_by_userids, @member_of_userids
        );
        my $us = LJ::load_userids(@all_circle_userids);

        $vars->{is_trusted_by_userid} = \%is_trusted_by_userid;
        $vars->{is_watched_by_userid} = \%is_watched_by_userid;
        $vars->{is_member_of_userid}  = \%is_member_of_userid;
        $vars->{all_circle_userids}   = \@all_circle_userids;
        $vars->{us}                   = $us;
        $vars->{watch_list}           = $watch_list;
        $vars->{trust_list}           = $trust_list;
        $vars->{u}                    = $u;
        $vars->{acttype}              = DW::Pay::get_account_type($u);

        if (@all_circle_userids) {
            my ( @person_userids, @comm_userids, @feed_userids );

            # get sorted arrays
            foreach
                my $uid ( sort { $us->{$a}->display_name cmp $us->{$b}->display_name } keys %$us )
            {
                next if $is_banned{$uid} && !$view_banned;

                my $other_u = $us->{$uid};
                next unless $other_u;

                if ( $other_u->is_community ) {
                    push @comm_userids, $uid;
                }
                elsif ( $other_u->is_syndicated ) {
                    push @feed_userids, $uid;
                }
                else {
                    push @person_userids, $uid;
                }
            }

            $vars->{comm_userids}   = \@comm_userids;
            $vars->{feed_userids}   = \@feed_userids;
            $vars->{person_userids} = \@person_userids;

        }

        my $show_watch_col = $u->can_watch ? 1 : 0;
        my $show_colors = ( $show_watch_col || keys %$watch_list ) ? 1 : 0;
        $vars->{show_watch_col} = $show_watch_col;
        $vars->{show_trust_col} = $u->can_trust ? 1 : 0;
        $vars->{show_colors}    = $show_colors;

        # still let them edit colors for existing circle, even if they can't make new subscriptions

        my @color = ();
        if ($show_colors) {

            # load the colors
            LJ::load_codes( { "color" => \@color } );
            my @color_codes = map { $_->{'code'} } @color;

            $vars->{colors} = to_json( \@color_codes );
        }
    }

    # if they did a post, then process their changes
    if ( $r->did_post ) {

        # this hash is used to keep track of who we've processed via the add
        # interface, since anyone who's in both the add and edit interfaces should
        # only be proccessed via the add interface and not by the edit interface
        my %userid_processed;

        #  Maintain a list of invalid userids for display to the user
        my @not_user;

        # process the additions
        foreach my $key ( keys %$POST ) {
            if ( $key =~ /^editfriend_add_(\d+)_user$/ ) {
                my $num = $1;
                next unless $POST->{"editfriend_add_${num}_user"};

                my $other_u = LJ::load_user_or_identity( $POST->{"editfriend_add_${num}_user"} );
                unless ($other_u) {
                    push @not_user, $POST->{"editfriend_add_${num}_user"};
                    next;
                }
                if ( $other_u->is_redirect && $other_u->prop('renamedto') ) {
                    $other_u = $other_u->get_renamed_user;
                }

                my $trusted_nonotify = $u->trusts($other_u)  ? 1 : 0;
                my $watched_nonotify = $u->watches($other_u) ? 1 : 0;
                $userid_processed{ $other_u->id } = 1;

                # only modify relationship if at least one of the checkboxes is checked
                # otherwise, assume that the user was editing colors
                # and do not remove the existing edges
                my $edit_color_only = !( $POST->{"editfriend_add_${num}_trust"}
                    || $POST->{"editfriend_add_${num}_watch"} );

                if ( $POST->{"editfriend_add_${num}_trust"} ) {
                    $u->add_edge(
                        $other_u,
                        trust => {
                            nonotify => $trusted_nonotify ? 1 : 0,
                        }
                    );
                }
                elsif ( !$edit_color_only ) {
                    $u->remove_edge(
                        $other_u,
                        trust => {
                            nonotify => $trusted_nonotify ? 0 : 1,
                        }
                    );
                }
                if ( $POST->{"editfriend_add_${num}_watch"} || $edit_color_only ) {
                    my $fg = LJ::color_todb( $POST->{"editfriend_add_${num}_fg"} );
                    my $bg = LJ::color_todb( $POST->{"editfriend_add_${num}_bg"} );
                    $u->add_edge(
                        $other_u,
                        watch => {
                            fgcolor  => $fg,
                            bgcolor  => $bg,
                            nonotify => $watched_nonotify ? 1 : 0,
                        }
                    );
                }
                elsif ( !$edit_color_only ) {
                    $u->remove_edge(
                        $other_u,
                        watch => {
                            nonotify => $watched_nonotify ? 0 : 1,
                        }
                    );
                }
            }
            elsif ( $key =~ /^editfriend_edit_(\d+)_user/ ) {
                my $uid = $1;

                my $other_u = LJ::load_userid($uid);
                next unless $other_u && !$userid_processed{$uid};

                my $trusted_nonotify = $u->trusts($other_u)  ? 1 : 0;
                my $watched_nonotify = $u->watches($other_u) ? 1 : 0;

                if ( $POST->{"editfriend_edit_${uid}_trust"} ) {
                    $u->add_edge(
                        $other_u,
                        trust => {
                            nonotify => $trusted_nonotify ? 1 : 0,
                        }
                    );
                }
                else {
                    $u->remove_edge(
                        $other_u,
                        trust => {
                            nonotify => $trusted_nonotify ? 0 : 1,
                        }
                    );
                }

                if ( $POST->{"editfriend_edit_${uid}_watch"} ) {
                    $u->add_edge(
                        $other_u,
                        watch => {
                            nonotify => $watched_nonotify ? 1 : 0,
                        }
                    );
                }
                else {
                    $u->remove_edge(
                        $other_u,
                        watch => {
                            nonotify => $watched_nonotify ? 0 : 1,
                        }
                    );
                }

                if ( $other_u->is_community ) {
                    my $wants_member = $POST->{"editfriend_edit_${uid}_join"};
                    my $is_member    = $u->member_of($other_u);

                    if ( $wants_member && !$is_member ) {
                        $u->join_community($other_u)
                            if $u->can_join($other_u);
                    }
                    elsif ( $is_member && !$wants_member ) {
                        $u->leave_community($other_u)
                            if $u->can_leave($other_u);
                    }
                }
            }
        }

        #if there are entries in the not_user array, tell the user there were problems.
        if ( @not_user > 0 ) {
            foreach my $not_u (@not_user) {
                $r->add_msg(
                    LJ::Lang::ml(
                        '/manage/circle/edit/index.tt.error.adding.text',
                        { username => LJ::ehtml($not_u) }
                    ),
                    $r->WARNING
                );
            }
        }
        my @success_items = [
            { text_ml => '.success.friendspage',        url => $u->journal_base . "/read" },
            { text_ml => '.success.editfriends',        url => '/manage/circle/edit' },
            { text_ml => '.success.editaccess_filters', url => '/manage/circle/editfilters' },
            { text_ml => '.success.editsubscr_filters', url => '/manage/subscriptions/filters' }
        ];

        return DW::Controller->render_success( 'manage/circle/edit/index.tt', undef,
            @success_items );
    }

    return DW::Template->render_template( 'manage/circle/edit/index.tt', $vars );
}

1;
