#!/usr/bin/perl
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
# Copyright (c) 2026 by Dreamwidth Studios, LLC.

package DW::Controller::Manage::Circle::Filters;
use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string(
    '/manage/circle/editfilters', \&filters_handler,
    app      => 1,
    no_cache => 1
);

sub filters_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;
    my $r     = $rv->{r};
    my $u     = $rv->{u};
    my $scope = '/manage/circle/editfilters.tt';
    $rv->{self_uri} = LJ::create_url( '/manage/circle/editfilters', keep_args => ['authas'] );

    # Communities cannot use access filters, including through a forged POST.
    return DW::Template->render_template( 'manage/circle/editfilters.tt', $rv )
        if $u->is_community;

    my %post = %{ $r->post_args };

    # These multi-select fields are UI state; membership uses the mask fields.
    delete @post{qw(list_in list_out)};
    return error_ml('error.invalidform') unless LJ::text_in( \%post );

    if ( $r->did_post && ( $post{mode} || '' ) eq 'save' ) {
        my $reload_error = 'Could not save access filters. Reload the page and try again.';
        my $mutation_error =
            'Some access filter changes may have been saved. Reload the page and try again.';
        my $save_error = $u->with_trust_groups_lock(
            sub {
                my $revision = $u->trust_group_revision;
                return $reload_error
                    unless defined $revision
                    && defined $post{group_revision}
                    && $post{group_revision} eq $revision;
                my $groups = $u->trust_groups( force_database => 1 ) or return $reload_error;

                # Validate every name before making changes to any group.
                for my $id ( 1 .. 60 ) {
                    my $name = $post{"efg_set_${id}_name"};
                    next unless $name;
                    return LJ::Lang::ml("$scope.error.comma")
                        if $name =~ /,/
                        && ( !$groups->{$id} || $name ne $groups->{$id}->{groupname} );
                    return LJ::Lang::ml('error.invalidform')
                        unless DW::User::Edges::WatchTrust::valid_group_name($name)
                        && ( $post{"efg_set_${id}_sort"} // '' ) =~ /^\d+$/;
                }
                my $allowed_mask = 1;
                for my $id ( 1 .. 60 ) {
                    my $existing = $groups->{$id};
                    if ( $post{"efg_delete_$id"} ) {
                        return $mutation_error if $existing && !$u->delete_trust_group( id => $id );
                        next;
                    }
                    if ( my $name = $post{"efg_set_${id}_name"} ) {
                        my %args = (
                            id        => $id,
                            groupname => $name,
                            sortorder => $post{"efg_set_${id}_sort"},
                            is_public => $post{"efg_set_${id}_public"} ? 1 : 0,
                        );
                        my $saved =
                            $existing ? $u->edit_trust_group(%args) : $u->create_trust_group(%args);
                        return $mutation_error unless $saved;
                        $allowed_mask |= 1 << $id;
                    }
                    elsif ($existing) {
                        $allowed_mask |= 1 << $id;
                    }
                }

                my $members = $u->trust_list( force_database => 1 );
                return $mutation_error unless defined $members;
                for my $key ( keys %post ) {
                    next unless $key =~ /^editfriend_(groupmask|maskhi)_(\w+)$/;
                    my ( $format, $name ) = ( $1, $2 );
                    my $trusted = LJ::load_user($name);

                    # Never re-add someone removed from the circle since the form loaded.
                    my $member = $trusted && $members->{ $trusted->id } or next;
                    my $mask =
                          $format eq 'groupmask'
                        ? $post{$key}
                        : ( $post{$key} << 31 ) | $post{"editfriend_masklo_$name"};

                    # Deleting a group must not restore its bits from stale form fields.
                    $mask = ( $mask & $allowed_mask ) | 1;
                    next if $mask == ( $member->{groupmask} & ~( 7 << 61 ) );
                    return $mutation_error
                        unless $u->add_edge( $trusted, trust => { mask => $mask, nonotify => 1 } );
                }
                return '';
            }
        );
        return DW::Template->render_template( 'error.tt',
            { message => $save_error // $reload_error } )
            if !defined $save_error || length $save_error;
        $rv->{saved} = 1;
        return DW::Template->render_template( 'manage/circle/editfilters.tt', $rv );
    }

    my $load_error = 'Could not load access filters. Reload the page and try again.';
    my $lock       = $u->lock_trust_groups
        or return DW::Template->render_template( 'error.tt', { message => $load_error } );
    my $revision   = $u->trust_group_revision;
    my $groups     = $u->trust_groups( force_database => 1 );
    my $trust_list = $u->trust_list( force_database => 1 );
    $lock->release;
    return DW::Template->render_template( 'error.tt', { message => $load_error } )
        unless defined $revision && $groups && defined $trust_list;

    $rv->{group_revision} = $revision;
    $rv->{group_fields}   = [
        map {
            my $group = $groups->{$_};
            {
                id     => $_,
                name   => $group ? $group->{groupname} : '',
                sort   => $group ? $group->{sortorder} + 0 : 255,
                public => $group && $group->{is_public} ? 1 : 0
            }
        } 1 .. 60
    ];
    $rv->{groups} =
        [ sort { $a->{sortorder} <=> $b->{sortorder} || $a->{groupname} cmp $b->{groupname} }
            values %$groups ];
    my $users = LJ::load_userids( keys %$trust_list );
    $rv->{members} = [
        map {
            my $member = $users->{$_};
            my $mask   = $trust_list->{$_}->{groupmask} || 1;
            {
                user     => $member->user,
                display  => $member->display_name,
                identity => $member->is_identity,
                maskhi   => ( $mask & ~( 7 << 61 ) ) >> 31,
                masklo   => $mask & ~( ~0 << 31 )
            }
        } sort { $users->{$a}->display_username cmp $users->{$b}->display_username }
            grep { $users->{$_} } keys %$trust_list
    ];
    return DW::Template->render_template( 'manage/circle/editfilters.tt', $rv );
}
1;
