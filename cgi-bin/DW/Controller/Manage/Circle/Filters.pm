#!/usr/bin/perl
#
# DW::Controller::Manage::Circle::Filters
#
# /manage/circle/editfilters
#
# Authors:
#      Cocoa <momijizukamori@gmail.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Circle::Filters;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

DW::Routing->register_string( "/manage/circle/editfilters", \&filter_handler, app => 1 );
DW::Routing->register_rpc( "accessfilters", \&accessfilters_handler, format => 'json' );

sub filter_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;
    my $r = DW::Request->get;

    my $u    = $rv->{remote};
    my $POST = $r->post_args;
    my $GET  = $r->get_args;
    my $vars;
    my @bad_groups;

    my $trust_groups = $u->trust_groups;

    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {

        # no-JS group selector, just redirect.
        if ( $POST->{select_group} ) {
            my $current_group = $POST->{current_group};

            unless ( exists $trust_groups->{$current_group} ) {
                $r->add_msg( LJ::Lang::ml('/mange/circle/editfilters.tt.error.badgroup'),
                    $r->WARNING );
                $current_group = undef;
            }
            my $url =
                LJ::create_url( undef, keep_args => 1, args => { group_id => $current_group } );
            return $r->redirect($url);
        }

        # handle group delete
        if ( $POST->{delete_group} ) {
            my $i = $POST->{"delete_group"};
            $u->delete_trust_group( id => $i );
        }

        # handle rename/new/sortorder
        if ( $POST->{edit_group} ) {
            my @group_ids = keys %$trust_groups;
            for my $id (@group_ids) {
                my $groupname = $POST->{"name_$id"};
                my $sortorder = $POST->{"sortorder_$id"};

                # if we haven't actually updated anything, move on.
                next
                    if $sortorder == $trust_groups->{$id}->{sortorder}
                    && $groupname eq $trust_groups->{$id}->{groupname};

                # Check for bad input
                $errors->add( "name_$id",      ".error.comma" ) if $groupname =~ /,/;
                $errors->add( "sortorder_$id", ".error.sortorder" )
                    if $sortorder < 0 || $sortorder > 255;

                unless ( $errors->exist ) {
                    my $err = $u->edit_trust_group(
                        id        => $id,
                        groupname => $groupname,
                        sortorder => $sortorder
                    );
                    r->add_msg( LJ::Lang::ml('/mange/circle/editfilters.tt.saved.text'),
                        $r->SUCCESS );
                }
            }

            my $groupcount = scalar(@group_ids);

            # Handle new groups
            my @new_keys = grep { $_ =~ /new_name_\d+/ } keys %$POST;
            foreach my $new (@new_keys) {
                $new =~ /new_name_(\d+)/;
                my $groupname = $POST->{"new_name_$1"};
                my $sortorder = $POST->{"new_sortorder_$1"} || 0;
                $errors->add( "new_name_$1",      ".error.comma" ) if $groupname =~ /,/;
                $errors->add( "new_sortorder_$1", ".error.sortorder" )
                    if $sortorder < 0 || $sortorder > 255;
                $errors->add( "new_name_$1", ".error.max60" ) if $groupcount > 60;

                unless ( $errors->exist ) {
                    $u->create_trust_group(
                        groupname => $groupname,
                        sortorder => $sortorder
                    );
                    $groupcount += 1;
                    r->add_msg(
                        LJ::Lang::ml(
                            '/mange/circle/editfilters.tt.saved.new',
                            { name => LJ::ehtml($groupname) }
                        ),
                        $r->SUCCESS
                    );
                }
            }
        }

        # handle filter update
        if ( $POST->{save_members} ) {
            my $current_group = $POST->{current_group};
            my @group_members = $POST->get_all('members');
            update_filter_members( $u, $current_group, \@group_members );
            $r->add_msg( LJ::Lang::ml('/mange/circle/editfilters.tt.saved.text'), $r->SUCCESS );
        }

    }

    # Reload our trustgroups, because we may have edited them above.
    $trust_groups = $u->trust_groups;

    my @groups = ();
    foreach my $group ( values %$trust_groups ) {
        push( @groups, { value => $group->{groupnum}, text => $group->{groupname} } );
    }

    # this forms the dropdown select, sort it alphabetically
    my @groupselect = sort { $a->{text} cmp $b->{text} } @groups;

    # ...and add a placeholder entry at the top
    unshift @groupselect, { text => "Select a group", value => "" };

    # this is for the list of groups to edit and re-sort, sort it by sortorder then by name.
    my @trust_groups =
        sort { $a->{sortorder} cmp $b->{sortorder} || $a->{groupname} cmp $b->{groupname} }
        values %$trust_groups;

    # no-JS fallback for switching between groups.
    if ( $GET->{group_id} ) {
        my $id = $GET->{group_id};
        if ( exists $trust_groups->{$id} ) {
            $vars->{current_group} = $GET->{group_id};
        }
        else {
            $r->add_msg( LJ::Lang::ml('/mange/circle/editfilters.tt.error.badgroup'), $r->WARNING );
        }

    }

    $vars->{u}            = $u;
    $vars->{trust_groups} = \@trust_groups;
    $vars->{trusted_us}   = get_filter_members( $u, $vars->{current_group} );
    $vars->{groupselect}  = \@groupselect;
    $vars->{errors}       = $errors;
    $vars->{postdata}     = $POST;

    return DW::Template->render_template( 'manage/circle/editfilters.tt', $vars );
}

sub update_filter_members {
    my ( $u, $group_id, $userlist ) = @_;

    my $group_members = $u->trust_group_members( id => $group_id );
    my @accesslist;
    my $members = LJ::load_userids( keys %$group_members );

    foreach my $userid ( keys %$members ) {
        my $name = $members->{$userid}->user;
        push @accesslist, ($name);
    }

    my %old = map { $_ => 1 } @accesslist;
    my @new;

    foreach my $user (@$userlist) {
        if ( $old{$user} ) {

            # user is on both lists, no updates necessary
            # delete from the old hash and move on.
            delete $old{$user};
        }
        else {
            # user is only on the new list, save for later processing
            push @new, ($user);
        }
    }

    # old hash only has items that were NOT on the new userlist - remove them
    foreach my $user ( keys %old ) {
        my $trusted_u = LJ::load_user($user);

        # User might have been removed from circle between load and submit;
        next unless $trusted_u && $u->trusts($trusted_u);
        $u->edit_trustmask( $trusted_u, remove => [$group_id] );
    }

    # new list only has items that were NOT in the old hash - add them
    foreach my $user (@new) {
        my $trusted_u = LJ::load_user($user);

        # User might have been removed from circle between load and submit;
        next unless $trusted_u && $u->trusts($trusted_u);
        $u->edit_trustmask( $trusted_u, add => [$group_id] );
    }
}

sub accessfilters_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $post = $r->json;
    my $u    = $rv->{remote};

    my $trust_groups = $u->trust_groups;

    my $mode = $post->{mode}
        or return DW::RPC->alert('No mode passed.');

    if ( $mode eq 'getmembers' ) {
        my $current_group = $post->{current_group};
        return DW::RPC->alert('Invalid access filter id')
            if defined $current_group && !( exists $trust_groups->{$current_group} );
        my $members = get_filter_members( $u, $current_group );
        my $vars    = {
            items => $members,
            label => "Group Members",
            id    => "members"
        };
        my $memberslist =
            DW::Template->template_string( 'components/checkbox-multiselect.tt', $vars );
        return DW::RPC->out( success => { members => $memberslist } );

    }

    if ( $mode eq 'savemembers' ) {
        my $current_group = $post->{current_group};
        my $group_members = $post->{'members'};
        return DW::RPC->alert('Invalid access filter id')
            if defined $current_group && !( exists $trust_groups->{$current_group} );
        update_filter_members( $u, $current_group, $group_members );
        return DW::RPC->out( success => { msg => 'Save successful!' } );
    }
}

# Helper method for retrieving and formatting the list of
# users a given user trusts, optionally marked with whether
# or not they're in a given access filter.
sub get_filter_members {
    my ( $u, $current_group ) = @_;
    my $trust_groups = $u->trust_groups;
    my $members;

    # if we were given a group, load it's members.
    if ( defined $current_group ) {
        my $group_members = $u->trust_group_members( id => $current_group );
        $members = LJ::load_userids( keys %$group_members );
    }

    my $trust_list = $u->trust_list;
    my $trusted_us = LJ::load_userids( keys %$trust_list );
    my @trusted_us;

    foreach my $uid (
        sort { $trusted_us->{$a}->display_username cmp $trusted_us->{$b}->display_username }
        keys %$trust_list
        )
    {
        my $trusted_u = $trusted_us->{$uid};

        my $user     = $trusted_u->user;
        my $in_group = exists $members->{$uid};

        push @trusted_us,
            (
            {
                selected => $in_group,
                value    => $user,
                name     => $trusted_u->display_name
            }
            );
    }
    return \@trusted_us;

}

1;
