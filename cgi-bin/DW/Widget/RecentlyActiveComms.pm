#!/usr/bin/perl
#
# DW::Widget::RecentlyActiveComms
#
# Returns the 10 most recently updated communities
#
# Authors:
#      Denise Paolucci <denise@dreamwidth.org>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::RecentlyActiveComms;

use strict;
use base qw/ LJ::Widget /;

# hang this widget on the same hook as the (old) stats page uses for
# determining whether or not to show the newly updated journals
# section, since the queries are mostly taken from those queries
# anyway. disable this feature in config.pl if you start having
# load issues, or if you just don't want this widget to render.
sub should_render { LJ::is_enabled('stats-recentupdates') }

sub need_res { qw( stc/widgets/commlanding.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    # prep the db reader

    my $dbr = LJ::get_db_reader();
    my $sth;
    my $ret;

    # prep the stats we're interested in using here

    $sth =
        $dbr->prepare( "SELECT u.user, u.name, uu.timeupdate_public FROM user u, userusage uu"
            . " WHERE u.userid=uu.userid AND uu.timeupdate_public > DATE_SUB(NOW(), INTERVAL 30 DAY)"
            . " AND u.journaltype = 'C' ORDER BY uu.timeupdate_public DESC LIMIT 10" );
    $sth->execute;

    $ret .= "<h2>" . $class->ml('widget.comms.recentactive') . "</h2>";
    $ret .= "<ul>";

    # build the list

    my $ct;
    my $targetu;

    while ( my ( $iuser, $iname, $itime ) = $sth->fetchrow_array ) {
        $targetu = LJ::load_user($iuser);
        $ret .= "<li>" . $targetu->ljuser_display . ": " . $iname . ", " . $itime . "</li>\n";
        $ct++;
    }

    $ret .= "<li><em> " . BML::ml('widget.comms.notavailable') . "</em></li>" unless $ct;
    $ret .= "</ul>\n";

    LJ::warn_for_perl_utf8($ret);
    return $ret;
}

1;

