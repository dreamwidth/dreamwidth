#!/usr/bin/perl
#
# DW::Widget::LatestNews
#
# The latest site news.
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

package DW::Widget::LatestNews;

use strict;
use base qw/ LJ::Widget /;

# define the news journal in your site config
sub should_render { $LJ::NEWS_JOURNAL ? 1 : 0; }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $news_journal = LJ::load_user( $LJ::NEWS_JOURNAL )
        or return;

    my $ret = "<h2>" . $class->ml( 'widget.latestnews.title', { sitename => $LJ::SITENAMESHORT } ) . "</h2>";

    # do getevents request
    my %res = ();
    LJ::do_request( { mode => 'getevents',
                      selecttype => 'one',
                      ver => $LJ::PROTOCOL_VER,
                      user => $news_journal->user,
                      itemid => -1 },
                      \%res,
                      { noauth => 1 }
                   );

    return unless $res{success} eq 'OK';

    my $entry = LJ::Entry->new( $news_journal, ditemid => ( $res{events_1_itemid} << 8) + $res{events_1_anum} );

    $ret .= "<div class='sidebar'>";
    $ret .= "<p><a href='" . $entry->url . "#comments'>" . $class->ml( 'widget.latestnews.comments', { num_comments => $entry->reply_count } ) . "</a></p>";

    if ( $remote->watches( $news_journal ) ) {
        $ret .= "<p>" . $class->ml( 'widget.latestnews.subscribe.modify', { 
            aopts => "href='$LJ::SITEROOT/circle/" . $news_journal->user . "/edit'",
            news => LJ::ljuser( $news_journal ) } ) . "</p>";
    } else {
        $ret .= "<p>" . $class->ml( 'widget.latestnews.subscribe.add2', { 
            aopts => "href='$LJ::SITEROOT/circle/" . $news_journal->user. "/edit?action=subscribe'",
            news => LJ::ljuser( $news_journal ) } ) . "</p>";
    }

    $ret .= "</div>";

    $ret .= "<div class='contents'>";
    $ret .= "<p><a href='" . $entry->url . "'>" . $entry->subject_html . "</a></p>";

    if ( $entry->event_raw =~ /<(?:lj-)?cut/ ) {
        # if we have a cut, then use it
        $ret .= $entry->event_html( { cuturl => $entry->url } );
    } else {
        # if we don't have a cut, we want to output in summary mode
        $ret .= $entry->event_summary;
    }

    $ret .= "</div>";

    return $ret;
}

1;

