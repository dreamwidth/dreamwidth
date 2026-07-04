#!/usr/bin/perl
#
# LJ::Console::Command::SuspendUserpic
#
# Console command to suspend an individual userpic (e.g. for a DMCA complaint),
# serving the default icon in its place until unsuspended.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Console::Command::SuspendUserpic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "suspend_userpic" }

sub desc {
"Suspend a userpic (e.g. for a DMCA complaint) so the default icon is served in its place. Reversible with unsuspend_userpic. Requires priv: siteadmin:userpics.";
}

sub args_desc {
    [
        'url'    => "URL of the userpic to suspend",
        'reason' => "Reason for the suspension (logged to status history)",
    ]
}

sub usage { '<url> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "siteadmin", "userpics" );
}

sub execute {
    my ( $self, $url, @args ) = @_;

    my $reason = join " ", @args;
    return $self->error("This command takes two arguments. Consult the reference.")
        unless $url && $reason;

    my ( $userid, $picid );
    if ( $url =~ m!(\d+)/(\d+)/?$! ) {
        $picid  = $1;
        $userid = $2;
    }

    my $u = LJ::load_userid($userid);
    return $self->error("Invalid userpic URL.")
        unless $u;

    my ( $rval, @hookval ) = $u->suspend_userpic($picid);
    return $self->error("Error suspending userpic.") unless $rval;

    foreach my $hv (@hookval) {
        my ( $type, $msg ) = @$hv;
        $self->$type($msg);
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add( $u, $remote, 'suspend_userpic',
        "suspended userpic; id=$picid; reason: $reason" );

    return $self->print( "Userpic '$picid' for '" . $u->user . "' suspended." );
}

1;
