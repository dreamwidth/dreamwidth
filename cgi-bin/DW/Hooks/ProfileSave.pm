#!/usr/bin/perl
#
# DW::Hooks::ProfileSave
#
# This module implements a hook for lightweight logging of uids
# who save profile edits, for later examination to detect
# accounts being used for spam purposes.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2022 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::ProfileSave;

use strict;
use warnings;

use LJ::Hooks;
use LJ::MemCache;

LJ::Hooks::register_hook(
    'profile_save',
    sub {
        my ( $u, $saved, $post ) = @_;
        return unless defined $u && defined $saved && defined $post;

        my $log_edit = 1;

        # only log this if the URL changed and is non-null

        my $oldurl = $saved->{url} // '';
        my $newurl = $post->{url}  // '';

        $log_edit = 0 if $oldurl eq $newurl;
        $log_edit = 0 unless $newurl;

        return unless $log_edit;

        # set the new key - expires after a week if no activity
        my $memval = LJ::MemCache::get('profile_editors') // [];
        push @$memval, $u->id;
        LJ::MemCache::set( 'profile_editors', $memval, 86400 * 7 );
    }
);

1;
