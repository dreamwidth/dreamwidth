#!/usr/bin/perl
#
# DW::Setting::CommunityPostLevel
#
# DW::Setting module for community post level
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

package DW::Setting::CommunityPostLevel;
use base 'LJ::Setting';
use strict;

sub should_render {
    my ( $class, $u ) = @_;

    return $u->is_community;
}

sub label {
    return $_[0]->ml( 'setting.communitypostlevel.label' );
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $key = $class->pkgkey;

    my ( $current_comm_membership, $current_comm_postlevel ) = $u->get_comm_settings;
    my $communitypostlevel = $class->get_arg( $args, "communitypostlevel" ) || $current_comm_postlevel || "members";
    $communitypostlevel = "anybody" if $u->prop( "nonmember_posting" );


    my @options = (
        "anybody"   => $class->ml( 'setting.communitypostlevel.option.select.anybody' ),
        "members"   => $class->ml( 'setting.communitypostlevel.option.select.members' ),
        "select"    => $class->ml( 'setting.communitypostlevel.option.select.select' ),
    );

    my $select = LJ::html_select( {
        name => "${key}communitypostlevel",
        id => "${key}communitypostlevel",
        selected => $communitypostlevel,
        class => "js-related-setting",
        "data-related-setting-id" => DW::Setting::CommunityPostLevelNew->pkgkey,
        "data-related-setting-on" => "select",
    }, @options );

    my $ret;
    $ret .= " <label for='${key}communitypostlevel'>";
    $ret .= $class->ml( "setting.communitypostlevel.option", { option => $select } );
    $ret .= "</label> ";

    my $errdiv = $class->errdiv( $errs, "communitypostlevel" );
    $ret .= "<br />$errdiv" if $errdiv;

    return $ret;
}

sub error_check {
    my ( $class, $u, $args ) = @_;
    my $val = $class->get_arg( $args, "communitypostlevel" );

    $class->errors( communitypostlevel => $class->ml( 'setting.communitypostlevel.error.invalid' ) )
        unless $val =~ /^(?:anybody|members|select)$/;

    return 1;
}

sub save {
    my ( $class, $u, $args ) = @_;
    $class->error_check( $u, $args );

    my $remote = LJ::get_remote();

    my $val = $class->get_arg( $args, "communitypostlevel" );

    # postlevel and nonmember_posting are a single setting in the UI, but separate options in the backend
    # split them out so we can save them properly
    my $nonmember_posting = 0;
    if ( $val eq "anybody" ) {
        $val = "members";
        $nonmember_posting = 1;
    }

    $u->set_comm_settings( $remote, { postlevel => $val });
    $u->set_prop({ nonmember_posting => $nonmember_posting });

    # unconditionally give posting access to all members
    my $cid = $u->userid;
    LJ::set_rel_multi( (map { [$cid, $_, 'P'] } $u->member_userids ) );
    return 1;
}

1;
