#!/usr/bin/perl
#
# DW::Setting::ResetReplyEmail
#
# LJ::Setting module for reply by email reset - pulled from /manage/emailpost
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
package DW::Setting::ResetReplyEmail;
use base 'LJ::Setting';

use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub label {
    return '<nobr>' . $_[0]->ml('setting.resetreplyemail.label') . '</nobr>';
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    my $ret = '<p>' . $class->ml('setting.resetreplyemail.des') . '</p>';

    my $check = LJ::html_check(
        {
            name     => $class->pkgkey . "resetreplyemail",
            value    => 1,
            selected => 0,
            label    => $class->ml('setting.resetreplyemail.act'),
        }
    );

    my $saved = $class->get_arg( $args, "resetreplyemail" );
    my $error = $errs->{resetreplyemail};

    if ( !$saved ) {
        $ret .= '<p>' . $check . '</p>';
    }
    elsif ($error) {
        $ret .= '<p><b>' . $error . '</b></p>';
        $ret .= '<p>' . $check . '</p>';
    }
    else {
        $ret .= '<p><b>' . $class->ml('setting.resetreplyemail.reset') . '</b></p>';
    }

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;

    eval { $u->generate_emailpost_auth };

    $class->errors( resetreplyemail => $class->ml('setting.resetreplyemail.error') ) if $@;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;

    if ( $class->get_arg( $args, "resetreplyemail" ) ) {
        return $class->error_check( $u, $args );
    }
}

1;
