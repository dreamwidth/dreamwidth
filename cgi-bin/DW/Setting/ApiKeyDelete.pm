#!/usr/bin/perl
#
# DW::Setting::ApiKeyDelete
#
# LJ::Setting module for deleting API keys - pulled from /manage/emailpost
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Setting::ApiKeyDelete;
use base 'LJ::Setting';

use strict;
use warnings;

use DW::API::Key;

sub should_render {
    my ( $class, $u ) = @_;

    return 0 unless $u && $u->is_personal;

    my $apikeys = DW::API::Key->get_keys_for_user($u);
    my $numkeys = scalar @{$apikeys};

    return $numkeys ? 1 : 0;
}

sub label {
    return '<nobr>' . $_[0]->ml('setting.apikeydelete.label') . '</nobr>';
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $ret = '<p>' . $class->ml('setting.apikeydelete.des') . '</p>';

    my $apikeys = DW::API::Key->get_keys_for_user($u);
    my $numkeys = scalar @{$apikeys};

    my $check = sub {
        my ($idx) = @_;
        LJ::html_check(
            {
                name     => $class->pkgkey . "keydel" . $idx,
                value    => $apikeys->[$idx]->{keyhash},
                selected => 0,
                label    => $apikeys->[$idx]->{keyhash},
            }
        );
    };

    my @keysel;

    for ( my $idx = 0 ; $idx < $numkeys ; $idx++ ) {
        my $chk = $check->($idx);
        my $arg = "keydel" . $idx;
        if ( my $error = $errs->{$arg} ) {
            $chk .= '<br><b>' . $error . '</b>';
        }
        push @keysel, $chk;
    }

    unless (@keysel) {
        $ret .= '<b>' . $class->ml('setting.apikeydelete.none') . '</b>';
    }

    $ret .= join '<br>', @keysel;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my ( $arg, $val ) = %$args;

    my $key = DW::API::Key->get_key($val);
    return 1 unless defined $key;

    eval { $key->delete($u) };

    $class->errors( $arg => $class->ml('setting.apikeydelete.error') ) if $@;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $apikeys = DW::API::Key->get_keys_for_user($u);
    my $numkeys = scalar @{$apikeys};

    for ( my $idx = 0 ; $idx < $numkeys ; $idx++ ) {
        my $arg = "keydel" . $idx;
        if ( my $keyval = $class->get_arg( $args, $arg ) ) {
            $class->error_check( $u, { $arg => $keyval } );
        }
    }

    return 1;
}

1;
