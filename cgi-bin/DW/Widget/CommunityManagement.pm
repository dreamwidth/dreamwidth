#!/usr/bin/perl
#
# DW::Widget::CommunityManagement
#
# List the user's communities which require attention.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::CommunityManagement;

use strict;
use base qw/ LJ::Widget /;

sub should_render { 1; }

# requires attention are: 
# * has pending join requests
# * has pending entries in the queue
sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    # TODO: everything!
    my $ret = "";
    return $ret;
}

1;

