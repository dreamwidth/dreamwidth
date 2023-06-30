#!/usr/bin/perl
#
# DW::Widget::CommunityManagement
#
# List the user's communities which require attention.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::CommunityManagement;

use strict;
use base qw/ LJ::Widget /;

sub should_render { 1; }

sub need_res { qw( stc/widgets/communitymanagement.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my %show;

    # keep track of what communities remote maintains
    my $cids = LJ::load_rel_target_cache( $remote, 'A' );
    my %admin;
    if ($cids) {
        $admin{$_} = $show{$_} = 1 foreach @$cids;
    }

    # keep track of what communities remote moderates
    my $mids = LJ::load_rel_target_cache( $remote, 'M' );
    my %mods;
    if ($mids) {
        $mods{$_} = $show{$_} = 1 foreach @$mids;
    }

    my @list;
    if (%show) {
        my $us = LJ::load_userids( keys %show );

        foreach my $cu ( sort { $a->user cmp $b->user } values %$us ) {
            next unless $cu->is_visible;

            my ( $membership, $postlevel ) = $cu->get_comm_settings;

            my $pending_entries_count;
            $pending_entries_count = $cu->get_mod_queue_count
                if $mods{ $cu->userid };

            my $pending_members_count;
            $pending_members_count = $cu->get_pending_members_count
                if $membership && $membership eq "moderated" && $admin{ $cu->userid };
            if ( $pending_members_count || $pending_entries_count ) {

                push @list,
                    (
                    {
                        cu              => $cu,
                        pending_members => $pending_members_count,
                        pending_entries => $pending_entries_count
                    }
                    );

            }
        }
    }

    return DW::Template->template_string( 'widget/communitymanagement.tt', { list => \@list } );
}

1;

