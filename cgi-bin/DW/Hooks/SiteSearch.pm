#!/usr/bin/perl
#
# DW::Hooks::SiteSearch
#
# Hooks for Site Search functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::SiteSearch;

use strict;
use LJ::Hooks;
use Carp;
use DW::Search;
use DW::Task::SearchCopier;

LJ::Hooks::register_hook(
    'setprop',
    sub {
        my %opts = @_;
        my $bool;
        if ( $opts{prop} eq 'opt_blockglobalsearch' ) {
            $bool = $opts{value} eq 'Y' ? 0 : 1;
        }
        elsif ( $opts{prop} eq 'not_approved' ) {

            # only act on this if it is being cleared from a visible user
            return if $opts{value};
            return if $opts{u}->is_suspended;
            $bool = 1;
        }
        else {
            return;
        }

        return DW::Search::set_journal_flag( $opts{u}->id, allow_global_search => $bool );
    }
);

# Set when the user's status(vis) changes. The user may still undelete or be
# unsuspended, so flip the is_deleted flag rather than removing their content
# from the index.
sub _mark_deleted {
    my ( $u, $is_deleted ) = @_;
    return DW::Search::set_journal_flag( $u->id, is_deleted => $is_deleted );
}

LJ::Hooks::register_hook( 'account_delete', sub { _mark_deleted( $_[0], 1 ) } );
LJ::Hooks::register_hook( 'account_cancel', sub { _mark_deleted( $_[0], 1 ) } );
LJ::Hooks::register_hook(
    'account_makevisible',
    sub {
        my ( $u, %opts ) = @_;

        my $old = $opts{old_statusvis};
        _mark_deleted( $u, 0 ) if $old eq "D" || $old eq "S";
    }
);

LJ::Hooks::register_hook(
    'purged_user',
    sub {
        my ($u) = @_;

       # queue up a copier job, which will notice that the entries by this user have been deleted...
        DW::TaskQueue->dispatch(
            DW::Task::SearchCopier->new( { userid => $u->id, source => "purghook" } ) );

    }
);

1;
