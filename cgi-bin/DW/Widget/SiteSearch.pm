#!/usr/bin/perl
#
# DW::Widget::SiteSearch
#
# Simple site-search module (global search only).
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::SiteSearch;

use strict;
use base qw/ LJ::Widget /;
use DW::Template;

sub render_body {

    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    return DW::Template->template_string('widget/sitesearch.tt');

}

1;
