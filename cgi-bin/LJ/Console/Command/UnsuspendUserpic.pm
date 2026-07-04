#!/usr/bin/perl
#
# LJ::Console::Command::UnsuspendUserpic
#
# Console command to reverse a userpic suspension, restoring the icon to normal
# service.
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

package LJ::Console::Command::UnsuspendUserpic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "unsuspend_userpic" }

sub desc {
"Reverse a userpic suspension, restoring the icon to normal service. Requires priv: siteadmin:userpics.";
}

sub args_desc {
    [
        'url'    => "URL of the userpic to unsuspend",
        'reason' => "Reason for the unsuspension (optional; logged to status history)",
    ]
}

sub usage { '<url> [reason]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "siteadmin", "userpics" );
}

sub execute {
    my ( $self, $url, @args ) = @_;

    my $reason = join " ", @args;
    return $self->error("This command requires a URL. Consult the reference.")
        unless $url;

    my ( $userid, $picid );
    if ( $url =~ m!(\d+)/(\d+)/?$! ) {
        $picid  = $1;
        $userid = $2;
    }

    my $u = LJ::load_userid($userid);
    return $self->error("Invalid userpic URL.")
        unless $u;

    my ( $rval, @hookval ) = $u->unsuspend_userpic($picid);
    return $self->error("Error unsuspending userpic.") unless $rval;

    foreach my $hv (@hookval) {
        my ( $type, $msg ) = @$hv;
        $self->$type($msg);
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add( $u, $remote, 'unsuspend_userpic',
        "unsuspended userpic; id=$picid" . ( $reason ? "; reason: $reason" : "" ) );

    return $self->print( "Userpic '$picid' for '" . $u->user . "' unsuspended." );
}

1;
