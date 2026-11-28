# DW::Console::Command::SysbanHistory
#
# Look up sysban history, including expired bans, for a value.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Console::Command::SysbanHistory;

use strict;
use base qw(LJ::Console::Command);
use POSIX qw(strftime);
use LJ::Sysban;

sub cmd { 'sysban_history' }

sub desc { 'Look up sysban history, including expired bans. Requires priv: sysban:*.' }

sub args_desc { [ value => 'The exact value whose sysban history to retrieve.' ] }

sub usage { '<value>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( 'sysban', '*' );
}

sub execute {
    my ( $self, $value, @args ) = @_;
    return $self->error('This command takes exactly one argument. Consult the reference.')
        unless defined $value && length $value && !@args;

    my $dbh = LJ::get_db_writer();
    return $self->error('Database temporarily unavailable.') unless $dbh;

    my $bans =
        LJ::Sysban::populate_full_by_value_with_expired( $value, LJ::list_valid_args('sysban') );
    return $self->error('Database temporarily unavailable.') if $dbh->err;
    return $self->info( 'No sysban history found for ' . $value . '.' )
        unless $bans && keys %$bans;

    $self->info( 'Sysban history for ' . $value . ':' );
    for my $type ( sort keys %$bans ) {
        for my $ban ( sort { $a->{banid} <=> $b->{banid} } @{ $bans->{$type} } ) {
            my $expires =
                $ban->{expire}
                ? strftime( '%Y-%m-%d %H:%M:%S UTC', gmtime( $ban->{expire} ) )
                : 'never';
            $self->info("Type: $type; Expires: $expires; Note: $ban->{note}");
        }
    }
    return 1;
}

1;
