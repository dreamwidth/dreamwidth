#!/usr/bin/perl
#
# DW::Setting::ApiKeyGenerate
#
# LJ::Setting module for generating API keys - pulled from /manage/emailpost
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
package DW::Setting::ApiKeyGenerate;
use base 'LJ::Setting';

use strict;
use warnings;

use DW::API::Key;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub label {
    return '<nobr>' . $_[0]->ml('setting.apikeygenerate.label') . '</nobr>';
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $ret = '<p>' . $class->ml('setting.apikeygenerate.des') . '</p>';

    my $error = $errs->{keygen};
    my $check = LJ::html_check(
        {
            name     => $class->pkgkey . "keygen",
            value    => 1,
            selected => $error ? 1 : 0,
            label    => $class->ml('setting.apikeygenerate.act'),
        }
    );

    my $lastkey;
    my $apikeys = DW::API::Key->get_keys_for_user($u);
    if (@$apikeys) {
        $lastkey = $apikeys->[-1];
    }

    if ($error) {
        $ret .= '<p><b>' . $error . '</b></p>';
    }
    elsif ( $class->get_arg( $args, "keygen" ) ) {
        $ret .=
              '<p><b>'
            . $class->ml( 'setting.apikeygenerate.ok', { keyval => $lastkey->{keyhash} } )
            . '</b></p>';
    }

    $ret .= '<p>' . $check . '</p>';

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;

    eval { DW::API::Key->new_for_user($u) };

    $class->errors( keygen => $class->ml('setting.apikeygenerate.error') ) if $@;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;

    if ( $class->get_arg( $args, "keygen" ) ) {
        return $class->error_check( $u, $args );
    }
}

1;
