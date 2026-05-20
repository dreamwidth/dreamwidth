#!/usr/bin/perl
#
# Plack::Middleware::DW::Dev
#
# Middleware that is used by development servers to do things like reload PM files
# that have changed, etc. Must not be included in production.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2021 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::Dev;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use parent qw/ Plack::Middleware /;

our %LIB_MOD_TIME;

sub call {
    my ( $self, $env ) = @_;

    $log->logcroak('Unable to run: not dev server!') unless $LJ::IS_DEV_SERVER;

    # Refresh modtimes in case we don't have one (if a file got loaded later
    # in another request, we should still be able to reload it)
    while ( my ( $k, $file ) = each %INC ) {
        next unless defined $file;    # Happens if require caused a runtime error
        next if $LIB_MOD_TIME{$file};
        next unless $file =~ m!^\Q$LJ::HOME\E!;
        my $mod = ( stat($file) )[9];
        $LIB_MOD_TIME{$file} = $mod;
    }

    # Now determine what to reload
    my %to_reload;
    while ( my ( $file, $mod ) = each %LIB_MOD_TIME ) {
        my $cur_mod = ( stat($file) )[9];
        next if $cur_mod == $mod;
        $to_reload{$file} = 1;
    }
    foreach my $key ( keys %INC ) {
        my $file = $INC{$key};
        delete $INC{$key} if $to_reload{$file};
    }

    # And now reload it
    foreach my $file ( keys %to_reload ) {
        $log->info( 'Reloading file: ', $file );
        my %reloaded;
        local $SIG{__WARN__} = sub {
            if ( $_[0] =~ m/^Subroutine (\S+) redefined at / ) {
                warn @_ if ( $reloaded{$1}++ );
            }
            else {
                warn(@_);
            }
        };
        my $good = do $file;
        if ($good) {
            $LIB_MOD_TIME{$file} = ( stat($file) )[9];
        }
        else {
            $log->logcroak( 'Failed to reload module [', $file, '] due to error: ', $@ );
        }
    }

    return $self->app->($env);
}

1;
