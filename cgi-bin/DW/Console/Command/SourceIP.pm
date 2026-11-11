# DW::Console::Command::SourceIP
#
# Look up the IP address recorded when an account was created.
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
package DW::Console::Command::SourceIP;
use strict;
use base qw(LJ::Console::Command);

sub cmd { 'sourceip' }

sub desc {
    'Look up the account creation IP address. Requires priv: canview:userlog or canview:*.';
}

sub args_desc {
    [ username => 'The username whose account creation IP address to retrieve.' ]
}

sub usage { '<username>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( 'canview', 'userlog' );
}

sub execute {
    my ( $self, $username, @args ) = @_;
    return $self->error('This command takes exactly one argument. Consult the reference.')
        unless $username && !@args;

    my $u = LJ::load_user($username);
    return $self->error('Invalid user.') unless $u;
    return $self->error('No user log is available for a purged account.')
        if $u->is_expunged;

    my $dbcr = LJ::get_cluster_reader($u);
    return $self->error('Database temporarily unavailable.') unless $dbcr;

    my ($ip) = $dbcr->selectrow_array(
"SELECT ip FROM userlog WHERE userid=? AND action='account_create' ORDER BY logtime ASC LIMIT 1",
        undef, $u->id
    );
    return $self->error('Database temporarily unavailable.') if $dbcr->err;
    return $self->error( 'No account creation IP address recorded for ' . $u->user . '.' )
        unless defined $ip && length $ip;

    return $self->info( 'Account Created IP address for ' . $u->user . ': ' . $ip );
}

1;
