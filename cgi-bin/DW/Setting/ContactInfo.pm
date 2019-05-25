#!/usr/bin/perl
#
# DW::Setting::ContactInfo
#
# LJ::Setting module for selecting the default security level for
# a journal user's contact information.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::ContactInfo;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return 1;
}

sub label {
    return $_[0]->ml('setting.contactinfo.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $contactinfo = $class->get_arg( $args, "contactinfo" ) || $u->opt_showcontact;

    my $iscomm = $u->is_community ? '.comm' : '';

    my @options =
        $iscomm
        ? (
        "Y" => $class->ml('setting.usermessaging.opt.a'),
        "R" => $class->ml('setting.usermessaging.opt.y'),
        "F" => $class->ml('setting.usermessaging.opt.members'),
        "N" => $class->ml('setting.usermessaging.opt.admins'),
        )
        : (
        "Y" => $class->ml('setting.usermessaging.opt.a'),
        "R" => $class->ml('setting.usermessaging.opt.y'),
        "F" => $class->ml('setting.usermessaging.opt.f'),
        "N" => $class->ml('setting.usermessaging.opt.n'),
        );

    my $ret;

    $ret .= " <label for='${key}contactinfo'>";
    $ret .= $class->ml("setting.contactinfo.option$iscomm");
    $ret .= "</label> ";

    $ret .= LJ::html_select(
        {
            name     => "${key}contactinfo",
            id       => "${key}contactinfo",
            selected => $contactinfo,
        },
        @options
    );

    $ret .= "<p class='details'>";
    $ret .= $class->ml("setting.contactinfo.option.note$iscomm");
    $ret .= "</p>";

    my $errdiv = $class->errdiv( $errs, "contactinfo" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "contactinfo" );

    $class->errors( contactinfo => $class->ml('setting.contactinfo.error.invalid') )
        unless !$val || $val =~ /^[YRFN]$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $val = $class->get_arg( $args, "contactinfo" );
    $u->update_self( { allow_contactshow => $val } );

    return 1;
}

1;
