#!/usr/bin/perl
#
# DW::Controller::Manage::Subscriptions
#
# /manage/subscriptions
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

package DW::Controller::Manage::Subscriptions;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/manage/subscriptions/filters", \&filter_handler, app => 1 );

sub filter_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;
    my $r = DW::Request->get;

    my $u    = $rv->{remote};
    my $POST = $r->post_args;

    # these are only used by the client-side for JS to play with.
    # we delete them because they may contain embedded NULLs, which
    # text_in won't like.
    delete $POST->{'list_in'};
    delete $POST->{'list_out'};

    unless ( LJ::text_in($POST) ) {

        # $body = "<?badinput?>";
        return;
    }

    my $trust_groups = $u->trust_groups;

    if ( $POST->{mode} eq 'save' ) {

        # check all creations/renames first
        for ( my $i = 1 ; $i <= 60 ; $i++ ) {
            my $name = $POST->{"efg_set_${i}_name"};
            if ( $name
                && ( ref $trust_groups->{$i} ne 'HASH'
                    || $name ne $trust_groups->{$i}->{groupname} ) )
            {
                if ( $name =~ /,/ ) {
                    return error_ml('.error.comma');
                }
            }
        }

        # add/edit/delete groups
        for ( my $i = 1 ; $i <= 60 ; $i++ ) {
            if ( $POST->{"efg_delete_$i"} ) {
                $u->delete_trust_group( id => $i );
            }
            elsif ( $POST->{"efg_set_${i}_name"} ) {
                my $create = ref $trust_groups->{$i} eq 'HASH' ? 0 : 1;
                my $name   = $POST->{"efg_set_${i}_name"};
                my $sort   = $POST->{"efg_set_${i}_sort"};
                my $public = $POST->{"efg_set_${i}_public"} ? 1 : 0;
                if ($create) {
                    $u->create_trust_group(
                        id        => $i,
                        groupname => $name,
                        sortorder => $sort,
                        is_public => $public
                    );
                }
                else {
                    $u->edit_trust_group(
                        id        => $i,
                        groupname => $name,
                        sortorder => $sort,
                        is_public => $public
                    );
                }
            }
        }

        # update users' trustmasks
        foreach my $post_key ( keys %$POST ) {

            # If someone tries to edit their trust list at the wrong time,
            # they may get a page sent out with the old format (groupmask) and
            # processed with the new (maskhi and masklo). So make sure not to
            # give users the wrong trust masks, by accepting both. (Since no
            # page will mix both, there's no need to check for contradicting
            # data.)
            next unless $post_key =~ /^editfriend_(groupmask|maskhi)_(\w+)$/;

            my $trusted_u = LJ::load_user($2);

            # User might have been removed from circle between load and
            # submit; don't re-add.
            next unless $trusted_u && $u->trusts($trusted_u);
            my $groupmask;
            if ( $1 eq 'groupmask' ) {
                $groupmask = $POST->{$post_key};
            }
            else {
                $groupmask = ( $POST->{$post_key} << 31 ) | $POST->{"editfriend_masklo_$2"};
            }

            $u->add_edge(
                $trusted_u,
                trust => {
                    mask     => $groupmask,
                    nonotify => 1,
                }
            );
        }

#        $body .= "<?h1 $ML{'.saved.header'} h1?><?p $ML{'.saved.text'} p?>";
#        $body .= "<ul><li><a href='$LJ::SITEROOT/update'>$ML{'.saved.action.post'}</li><li><a href='$LJ::SITEROOT/manage/subscriptions/filters'>$ML{'.saved.action.subscription'}</li></ul>";

        return;
    }

    my $trust_list = $u->trust_list;
    my $trusted_us = LJ::load_userids( keys %$trust_list );
    my @trusted_us;

    foreach my $uid (
        sort { $trusted_us->{$a}->display_username cmp $trusted_us->{$b}->display_username }
        keys %$trust_list )
    {
        my $trusted_u = $trusted_us->{$uid};

        my $user      = $trusted_u->user;
        my $groupmask = $trust_list->{$uid}->{groupmask} || 1;

        # Work around JS 64-bit lossitude
        my $maskhi = ( $groupmask & ~( 7 << 61 ) ) >> 31;
        my $masklo = $groupmask & ~( ~0 << 31 );

        push @trusted_us,
            (
            {
                user   => $user,
                masklo => $masklo,
                maskhi => $maskhi,
                is_id  => $trusted_u->is_identity,
                dn     => $trusted_u->display_name
            }
            );
    }

    return DW::Template->render_template( 'manage/circle/editfilters.tt',
        { u => $u, trust_groups => $trust_groups, trusted_us => \@trusted_us } );
}

1;
