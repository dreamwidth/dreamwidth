#!/usr/bin/perl
#
# DW::Hooks::SpamCheck
#
# This module implements a hook for checking input for blocked domains, and
# auto-suspending a user if one is found.
#
# Authors:
#      Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::SpamCheck;

use strict;
use warnings;
use Scalar::Util qw/reftype/;

use LJ::Hooks;
use LJ::MemCache;

LJ::Hooks::register_hook(
    'spam_check',
    sub {
        my ( $user, $data, $location ) = @_;
        return unless defined $user && defined $data && defined $location;
        my $system = LJ::load_user('system');
        my @blocked_links = grep { $_ } split( /\r?\n/, LJ::load_include('spamblocklist') );
        my $suspended     = 0;
        my $location_str  = $location; # same for everything but hashrefs

        my $check_item = sub {
            my $item = shift;
            return unless defined $item;    # don't waste time iterating over undefined items

            foreach my $re (@blocked_links) {
                if ( $item =~ $re ) {
                    LJ::User::set_suspended( $user, $system,
                        "auto-suspend for matching domain blocklist: $re in $location_str" );
                    $suspended = 1;
                    last;
                }
            }
        };

        if ( reftype $data eq reftype [] ) {
            foreach my $item (@$data) {
                $check_item->($item);
                last if $suspended;
            }
        }
        elsif ( reftype $data eq reftype {} ) {
            foreach my $key ( keys %$data ) {
                $location_str = "$key of $location";
                $check_item->( $data->{$key} );
                last if $suspended;
            }
        }
        else {
            $check_item->($data);
        }

    }
);

1;
