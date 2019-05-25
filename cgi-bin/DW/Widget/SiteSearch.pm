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

sub render_body {

    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $ret = "<h2>"
        . $class->ml( 'widget.sitesearch.title', { sitename => $LJ::SITENAMESHORT } ) . "</h2>";
    $ret .= "<p>" . $class->ml('widget.sitesearch.desc') . "</p>";

    $ret .= "<form method='post' action='$LJ::SITEROOT/search'>" . LJ::form_auth();
    $ret .= "<input type='text' name='query' maxlength='255' size='30'>";
    $ret .= "<input type='submit' value='Search'></form>";

    return $ret;

}

1;
