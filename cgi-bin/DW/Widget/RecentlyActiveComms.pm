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

    # prep the stats we're interested in using here

    $sth =
        $dbr->prepare( "SELECT u.user, u.name, uu.timeupdate_public FROM user u, userusage uu"
            . " WHERE u.userid=uu.userid AND uu.timeupdate_public > DATE_SUB(NOW(), INTERVAL 30 DAY)"
            . " AND u.journaltype = 'C' ORDER BY uu.timeupdate_public DESC LIMIT 10" );
    $sth->execute;

    my $targetu;
    my @rowdata;

    while ( my ( $iuser, $iname, $itime ) = $sth->fetchrow_array ) {
        $targetu = LJ::load_user($iuser);
        push @rowdata, { user => $targetu, name => $iname, time => $itime };
    }

    return DW::Template->template_string( 'widget/comms.tt',
        { title => 'widget.comms.recentactive', rowdata => \@rowdata } );
}

1;

