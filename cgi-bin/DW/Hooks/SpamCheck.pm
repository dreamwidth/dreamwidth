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

sub _blocked_domains {
    return grep { length } split( /\r?\n/, LJ::load_include('spamblocklist') // '' );
}

sub _matching_domain {
    my ( $text, @blocked_domains ) = @_;
    return unless defined $text;

    foreach my $domain (@blocked_domains) {
        return $domain if $text =~ /\b\Q$domain\E\b/i;
    }
    return;
}

LJ::Hooks::register_hook( 'spam_blocklist_match',
    sub { return _matching_domain( $_[0], _blocked_domains() ); } );

LJ::Hooks::register_hook(
    'spam_check',
    sub {
        my ( $u, $data, $location ) = @_;
        return unless defined $u && defined $data && defined $location;
        return if $u->has_priv('siteadmin');    # some users can be trusted

        my $system          = LJ::load_user('system');
        my @blocked_domains = grep { $_ } _blocked_domains();

        my $check_item = sub {
            my ( $item, $loc ) = @_;
            return unless defined $item;

            foreach my $domain (@blocked_domains) {
                if ( $item =~ /\b${domain}\b/i ) {
                    $u->set_suspended( $system,
                        "auto-suspend for matching domain blocklist: $domain in $loc" );
                    return 1;
                }
            }
            return;
        };

        my $type = reftype($data) // '';
        if ( $type eq 'ARRAY' ) {
            foreach my $item (@$data) {
                my $suspended = $check_item->( $item, $location );
                last if $suspended;
            }
        }
        elsif ( $type eq 'HASH' ) {
            foreach my $key ( keys %$data ) {
                my $suspended = $check_item->( $data->{$key}, "$key of $location" );
                last if $suspended;
            }
        }
        else {
            $check_item->( $data, $location );
        }

    }
);

1;
