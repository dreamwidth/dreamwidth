#!/usr/bin/perl
#
# DW::Console::Command::RenameOpts
#
# Console command for tweaking options on renamed users.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Console::Command::RenameOpts;
use strict;

use base qw/ LJ::Console::Command /;
use Carp qw/ croak /;

sub cmd  { 'rename_opts' }
sub desc { 'Manage options attached to a rename. Requires priv: siteadmin:rename.' }

sub args_desc {
    [
        'command' =>
'Subcommand: redirect, break_redirect, break_email_redirect, del_trusted_by, del_watched_by, del_trusted, del_watched, del_communities.',
        'username' => 'Username to act on.',
    ]
}

sub usage {
'redirect from_nonexistent_user to_existing_user | break_email_redirect from_user to_user | <subcommand> <username>';
}

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "siteadmin", "rename" );
}

sub execute {
    my ( $self, $cmd, $user, $tousername ) = @_;

    return $self->error( 'Invalid command. Usage: ' . usage() )
        unless $cmd
        && $cmd =~
/^(?:redirect|break_redirect|break_email_redirect|del_trusted_by|del_watched_by|del_trusted|del_watched|del_communities)$/;

    if ( $cmd eq 'redirect' ) {

        # "from" is the user we are creating; "to" is an existing user
        my $from_user = LJ::canonical_username($user);

        my $to_u = LJ::load_user($tousername);
        return $self->error('No destination user provided.')
            unless $to_u;

        return $self->error('Unable to setup redirection')
            unless DW::User::Rename->create_redirect_journal( $from_user, $to_u->user );

    }
    elsif ( $cmd eq 'break_email_redirect' ) {
        return $self->error(
            'Need to provide the user being redirected from and the user being redirected to')
            unless $user && $tousername;

        return $self->error(
            'Unable to break the email redirect. Note that from_user must redirect to to_user')
            unless DW::User::Rename->break_email_redirection( $user, $tousername );

    }
    else {
        my $u = LJ::load_user($user);
        return $self->error('Invalid user.')
            unless $u;

        if ( $cmd eq 'break_redirect' ) {
            if ( $u->break_redirects ) {
                $u->set_expunged;
            }
            else {
                $self->error("Unable to break redirection");
            }
        }
        elsif ( $cmd eq 'del_trusted_by' )  { $u->delete_relationships( del_trusted_by  => 1 ) }
        elsif ( $cmd eq 'del_watched_by' )  { $u->delete_relationships( del_watched_by  => 1 ) }
        elsif ( $cmd eq 'del_trusted' )     { $u->delete_relationships( del_trusted     => 1 ) }
        elsif ( $cmd eq 'del_watched' )     { $u->delete_relationships( del_watched     => 1 ) }
        elsif ( $cmd eq 'del_communities' ) { $u->delete_relationships( del_communities => 1 ) }
    }

    $self->print('Done.');

    return 1;
}

1;
