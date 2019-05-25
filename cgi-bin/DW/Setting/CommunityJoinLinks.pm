#!/usr/bin/perl
#
# DW::Setting::CommunityJoinLinks
#
# DW::Setting module to choose which links should be displayed to users when they join the community
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

package DW::Setting::CommunityJoinLinks;
use base 'LJ::Setting::BoolSetting';
use strict;

sub should_render { return $_[1]->is_community }

sub label { $_[0]->ml('setting.communityjoinlinks.label') }
sub des   { $_[0]->ml('setting.communityjoinlinks.option') }

sub prop_name       { "hide_join_post_link" }
sub checked_value   { undef }
sub unchecked_value { 1 }

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    my $ret = $class->as_html( $u, $errs, $args );
    $ret .= "<p class='note'>" . LJ::Lang::ml("setting.communityjoinlinks.desc") . "</p>";
}

1;
