#!/usr/bin/perl
#
# DW::Widget::ReadingList
#
# Breakdown of the user's reading list
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

package DW::Widget::ReadingList;

use strict;
use base qw/ LJ::Widget /;

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my %count   = ( personal => 0, community => 0, syndicated => 0 );
    my @watched = $remote->watched_users;
    $count{ $_->journaltype_readable }++ foreach @watched;

    my $ret = "<h2>" . $class->ml('widget.readinglist.title2') . "</h2>";
    $ret .= "<p>"
        . $class->ml( 'widget.readinglist.readpage2',
        { aopts => "href='" . $remote->journal_base . "/read'" } )
        . "</p>";
    $ret .= "<p>" . $class->ml('widget.readinglist.breakdown.header') . "</p>";
    $ret .=
          "<ul><li>"
        . $class->ml( 'widget.readinglist.breakdown.personal', { num => $count{personal} } )
        . "</li>";
    $ret .= "<li>"
        . $class->ml( 'widget.readinglist.breakdown.communities', { num => $count{community} } )
        . "</li>";
    $ret .= "<li>"
        . $class->ml( 'widget.readinglist.breakdown.feeds', { num => $count{syndicated} } )
        . "</li></ul><br />";

    my @filters = $remote->content_filters;

    if (@filters) {
        $ret .= $class->ml('widget.readinglist.filters.title');
        $ret .= "<ul>";
        foreach my $filter (@filters) {
            $ret .=
                  "<li><a href='"
                . $remote->journal_base
                . "/read/"
                . LJ::eurl( $filter->name ) . "'>"
                . LJ::ehtml( $filter->name )
                . "</a></li>\n";
        }
        $ret .= "</ul>";
    }
    else {
        $ret .= $class->ml( 'widget.readinglist.filters.nofilters',
            { aopts => "href='$LJ::SITEROOT/manage/subscriptions/filters'" } );
    }

    return $ret;
}

1;

