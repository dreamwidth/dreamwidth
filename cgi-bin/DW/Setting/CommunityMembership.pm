#!/usr/bin/perl
#
# DW::Setting::CommunityMembership
#
# DW::Setting module for community membership
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

package DW::Setting::CommunityMembership;
use base 'LJ::Setting';
use strict;

sub should_render {
    my ( $class, $u ) = @_;

    return $u->is_community;
}

sub label {
    return $_[0]->ml('setting.communitymembership.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my ( $current_comm_membership, $current_comm_postlevel ) = $u->get_comm_settings;
    my $communitymembership =
        $class->get_arg( $args, "communitymembership" ) || $current_comm_membership || "open";

    my @options = (
        "open"      => $class->ml('setting.communitymembership.option.select.open'),
        "moderated" => $class->ml('setting.communitymembership.option.select.moderated'),
        "closed"    => $class->ml('setting.communitymembership.option.select.closed'),
    );

    my $select = LJ::html_select(
        {
            name     => "${key}communitymembership",
            id       => "${key}communitymembership",
            selected => $communitymembership,
        },
        @options
    );

    my $ret;
    $ret .= " <label for='${key}communitymembership'>";
    $ret .= $class->ml( "setting.communitymembership.option", { option => $select } );
    $ret .= "</label> ";

    my $errdiv = $class->errdiv( $errs, "communitymembership" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "communitymembership" );

    $class->errors( communitymembership => $class->ml('setting.communitymembership.error.invalid') )
        unless $val =~ /^(?:open|moderated|closed)$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $remote = LJ::get_remote();

    my $val = $class->get_arg( $args, "communitymembership" );
    $u->set_comm_settings( $remote, { membership => $val } );

    return 1;
}

1;
