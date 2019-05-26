#!/usr/bin/perl
#
# DW::Setting::CommunityEntryModeration
#
# DW::Setting module for moderated entries in communities
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

package DW::Setting::CommunityEntryModeration;
use base 'LJ::Setting::BoolSetting';
use strict;

sub should_render { return $_[1]->is_community }

sub label { $_[0]->ml('setting.communityentrymoderation.label') }
sub des   { $_[0]->ml('setting.communityentrymoderation.option') }

sub prop_name       { "moderated" }
sub checked_value   { 1 }
sub unchecked_value { 0 }

sub option {
    my ( $class, $u, $errs, $args ) = @_;
    return $class->as_html( $u, $errs, $args );
}

sub save {
    my ( $class, $u, $args ) = @_;
    my $ret = $class->SUPER::save( $u, $args );

    my $remote = LJ::get_remote();

    # if we're not yet a moderator, make us one
    # (don't check $remote->can_moderate, because that's also true for admins
    LJ::set_rel( $u->userid, $remote->userid, 'M' )
        if $u->has_moderated_posting && !LJ::check_rel( $u, $remote, 'M' );

    return $ret;
}

1;
