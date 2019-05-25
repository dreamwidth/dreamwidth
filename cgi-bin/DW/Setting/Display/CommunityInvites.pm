#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Setting::Display::CommunityInvites;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ( $class, $u ) = @_;

    return $u && !$u->is_community ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.communityinvites.label');
}

sub option {
    my ( $class, $u, $errs, $args ) = @_;

    return
        "<a href='$LJ::SITEROOT/manage/invites'>"
        . $class->ml('setting.display.communityinvites.option') . "</a>";
}

1;
