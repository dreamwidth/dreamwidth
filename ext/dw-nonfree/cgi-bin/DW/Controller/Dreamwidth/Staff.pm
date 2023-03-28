#!/usr/bin/perl
#
# DW::Controller::Dreamwidth::Staff
#
# Controller for Dreamwidth staff page.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is NOT free software or open-source; you can use it as an
# example of how to implement your own site-specific extensions to the
# Dreamwidth Studios open-source code, but you cannot use it on your site
# or redistribute it, with or without modifications.
#

package DW::Controller::Dreamwidth::Staff;

use strict;
use DW::Routing;
use DW::Template;
use YAML::Any;

DW::Routing->register_string( '/site/staff', \&staff_page, app => 1 );

my $staff_groups = undef;

sub staff_page {
    $staff_groups ||= generate_staff_groups();

    return DW::Template->render_template( "site/staff.tt", { groups => $staff_groups } );
}

sub generate_staff_groups {
    my $groups = YAML::Any::LoadFile( LJ::resolve_file("etc/staff.yaml") );

    # This takes the list of usernames, determines if they are a journal or a community
    # and makes a list of the ljuser_display under the proper type if the username exists
    # otherwise treats it as a journal, and just lists the plain text username.
    foreach my $group (@$groups) {
        foreach my $person ( @{ $group->{people} } ) {
            my $official = $person->{official} || [];
            my $result   = {};
            foreach my $name (@$official) {
                my $u    = LJ::load_user($name);
                my $text = $u ? $u->ljuser_display : $name;
                if ( $u && $u->is_community ) {
                    push @{ $result->{community} }, $text;
                }
                else {
                    push @{ $result->{journal} }, $text;
                }
            }
            if ( $result != {} ) {
                $person->{official} = $result;
            }
            else {
                delete $person->{official};
            }

        }
    }
    return $groups;
}

1;
