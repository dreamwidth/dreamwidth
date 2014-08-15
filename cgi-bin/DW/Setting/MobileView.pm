#!/usr/bin/perl
#
# DW::Setting::MobileView
#
# LJ::Setting module which controls whether we constrain the width of the viewport on mobile devices
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::MobileView;
use base 'LJ::Setting::BoolSetting';
use strict;

sub should_render {
    my ( $class, $u ) = @_;
    return $u && $u->is_community ? 0 : 1;
}

sub label {
    return $_[0]->ml( 'setting.mobileview.label' );
}

sub is_selected {
    my $r = DW::Request->get;

    # make sure the checkbox is accurate immediately after post
    return $r->note( 'no_mobile_post_value' )
        if defined $r->note( 'no_mobile_post_value' );

    # normal page load, check the cookie
    return $r->cookie( 'no_mobile' ) ? 1 : 0;
}

sub option {
    my ($class, $u, $errs, $args, %opts) = @_;
    return $class->as_html( $u, $errs );
}

sub des {
    return $_[0]->ml( 'setting.mobileview.des' );
}

sub save {
    my ( $class, $u, $args ) = @_;

    my $r = DW::Request->get;
    if ( $args->{val} ) {
        $r->add_cookie(
            name    => 'no_mobile',
            domain  => ".$LJ::DOMAIN",
            value   => 1,
            expires => time() + 86400 * 365 * 10, # 10 years
        );
        $r->note( 'no_mobile_post_value', 1 );
    } else {
        $r->delete_cookie(
            name => 'no_mobile',
            domain  => ".$LJ::DOMAIN"
        );
        $r->note( 'no_mobile_post_value', 0 );
    }
    return 1;
}

1;
