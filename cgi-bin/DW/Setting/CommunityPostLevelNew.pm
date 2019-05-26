#!/usr/bin/perl
#
# DW::Setting::CommunityPostLevelNew
#
# DW::Setting module for whether new members should be able to post to the community or not when they join
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

package DW::Setting::CommunityPostLevelNew;
use base 'LJ::Setting::BoolSetting';
use strict;

sub should_render { return $_[1]->is_community }

sub label { $_[0]->ml('setting.communitypostlevelnew.label') }
sub des   { $_[0]->ml('setting.communitypostlevelnew.option') }

sub prop_name       { "comm_postlevel_new" }
sub checked_value   { 1 }
sub unchecked_value { 0 }

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    return $class->as_html( $u, $errs, $args );
}

sub is_conditional_setting { 1 }
1;
