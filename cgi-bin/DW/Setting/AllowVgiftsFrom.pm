#!/usr/bin/perl
#
# DW::Setting::AllowVgiftsFrom
#
# LJ::Setting module for allowing a user to restrict
# who can send virtual gifts to that user or to
# opt out of receiving anonymous virtual gifts.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Setting::AllowVgiftsFrom;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;
    return exists $LJ::SHOP{vgifts};
}

sub label {
    my $class = $_[0];
    return $class->ml('setting.allowvgiftsfrom.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my $allowed =
           $class->get_arg( $args, "allowvgiftsfrom" )
        || $u->prop('opt_allowvgiftsfrom')
        || 'all';
    my $anonopt = $class->get_arg( $args, "anonvgift_optout" )
        || !$u->prop('opt_anonvgift_optout');

    my %menu_items = (
        all        => [qw( all a )],
        registered => [qw( registered r )],
        circle     => [qw( circle c )],
        access     => [qw( access t )],
        members    => [qw( access m )],
        none       => [qw( none n )],
    );

    my @opts;
    if ( $u->is_community ) {
        @opts = map {
            $menu_items{$_}->[0],
                $class->ml("setting.allowvgiftsfrom.sel.$menu_items{$_}->[1]")
        } qw( all registered members none );
    }
    else {
        @opts = map {
            $menu_items{$_}->[0],
                $class->ml("setting.allowvgiftsfrom.sel.$menu_items{$_}->[1]")
        } qw( all registered circle access none );

        # trust group selection
        my @groups = sort { $a->{sortorder} <=> $b->{sortorder} } $u->trust_groups;
        if (@groups) {
            my @items;
            push @items, { value => $_->{groupnum}, text => $_->{groupname} } foreach @groups;

            push @opts,
                { optgroup => $class->ml('setting.allowvgiftsfrom.sel.g'), items => \@items };
        }
    }

    my $ret = LJ::html_select(
        {
            name     => "${key}allowvgiftsfrom",
            id       => "${key}allowvgiftsfrom",
            selected => $allowed
        },
        @opts
    );

    my $errdiv = $class->errdiv( $errs, "allowvgiftsfrom" );
    $ret .= $errdiv if $errdiv;

    $ret .= "<br />\n";

    # anonymous optout
    $ret .= LJ::html_check(
        {
            name     => "${key}anonvgift_optout",
            id       => "${key}anonvgift_optout",
            label    => $class->ml('setting.allowvgiftsfrom.anon'),
            selected => $anonopt
        }
    );
    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;

    my $allowed = $class->get_arg( $args, "allowvgiftsfrom" );
    $class->errors( allowvgiftsfrom => $class->ml('setting.allowvgiftsfrom.error') )
        if $allowed && $allowed !~ /^(?:all|registered|circle|access|none|\d+)$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $allowed = $class->get_arg( $args, "allowvgiftsfrom" );
    my $anonopt = $class->get_arg( $args, "anonvgift_optout" );

    $u->set_prop( 'opt_allowvgiftsfrom'  => $allowed ) if $allowed;
    $u->set_prop( 'opt_anonvgift_optout' => $anonopt ? 0 : 1 );

    return 1;
}

1;
