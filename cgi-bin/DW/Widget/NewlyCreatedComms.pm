#!/usr/bin/perl
#
# DW::Widget::NewlyCreatedComms
#
# Returns the 10 most recently created communities
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

package DW::Widget::NewlyCreatedComms;

use strict;
use base qw/ LJ::Widget /;

# hang this widget on the same hook as the (old) stats page uses for
# determining whether or not to show the newly created journals
# section, since the queries are mostly taken from those queries
# anyway. disable this feature in config.pl if you start having
# load issues, or if you just don't want this widget to render.
sub should_render { LJ::is_enabled('stats-newjournals') }

sub need_res { qw( stc/widgets/commlanding.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    # prep the db reader

    my $dbr = LJ::get_db_reader();
    my $sth;
    my $ret;

    # prep the stats we're interested in using here

    $sth = $dbr->prepare(
"SELECT u.user, u.name, uu.timeupdate FROM user u, userusage uu WHERE u.userid=uu.userid AND uu.timeupdate IS NOT NULL AND u.journaltype = 'C' ORDER BY uu.timecreate DESC LIMIT 10"
    );
    $sth->execute;

    $ret .= "<h2>" . $class->ml('widget.comms.recentcreate') . "</h2>";
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

    return $ret;
}

1;

