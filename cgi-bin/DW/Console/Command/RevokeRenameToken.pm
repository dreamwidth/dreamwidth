#!/usr/bin/perl
#
# DW::Console::Command::RevokeRenameToken
#
# Console command for revoking rename tokens
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Console::Command::RevokeRenameToken;
use strict;

use base qw/ LJ::Console::Command /;

sub cmd  { 'revoke_rename_token' }
sub desc { 'Revoke rename token. Requires priv: siteadmin:rename.' }

sub args_desc {
    [
        'token'  => 'Token to revoke.',
        'reason' => 'Reason for revoking it.',
    ]
}
sub usage { '<token> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "siteadmin", "rename" );
}

sub execute {
    my ( $self, $tokenstring, $reason ) = @_;

    my $token = DW::RenameToken->new( token => $tokenstring );
    return $self->error('Invalid token') unless $token;
    return $self->error('Token already applied or revoked')
        if $token->applied || $token->revoked;

    return $self->error('You didn\'t supply a reason') unless $reason;

    if ( $token->revoke ) {
        LJ::statushistory_add( $token->ownerid, LJ::get_remote(),
            'rename_token', "$tokenstring revoked: $reason" );
        $self->print('Token successfully revoked');
    }
    else {
        return $self->error('Unable to revoke token');
    }

    return 1;
}

1;
