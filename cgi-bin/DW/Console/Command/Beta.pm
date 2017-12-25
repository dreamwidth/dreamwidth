#!/usr/bin/perl
#
# DW::Console::Command::Beta
#
# Displays beta features a user opted into
#
# Author: Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Console::Command::Beta;

use strict;
use base qw(LJ::Console::Command);
use LJ::BetaFeatures;
use LJ::Support;

sub cmd { "beta" }

sub desc { "Displays beta features a user opted into. Requires any support priv." }

sub args_desc { [
                 'user' => "The username to display beta features for.",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && LJ::Support::has_any_support_priv( $remote );
}

sub execute {
    my ($self, $username, @args) = @_;

    return $self->error( 'This command takes one argument. Consult the reference.' )
        unless $username && scalar( @args ) == 0;

    return $self->error( 'No beta features defined.' )
        unless %LJ::BETA_FEATURES;

    my $u = LJ::load_user( $username );
    return $self->error( "Invalid user $username" )
        unless $u;

    my $betafeatures = join( ', ', $u->prop( LJ::BetaFeatures->prop_name ) )
                       || '(none)';
    return $self->print( "Beta testing: $betafeatures" );
}

1;
