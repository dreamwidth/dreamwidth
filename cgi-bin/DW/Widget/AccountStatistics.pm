#!/usr/bin/perl
#
# DW::Widget::AccountStatistics
#
# User's account statistics, similar to those on the profile page.
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

package DW::Widget::AccountStatistics;

use strict;
use base qw/ LJ::Widget /;

sub should_render { 1; }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $tags_count     = scalar keys %{ $remote->tags || {} };
    my $memories_count = LJ::Memories::count( $remote->id ) || 0;

    my $accttype = DW::Pay::get_account_type_name($remote);
    my $accttype_string;
    if ($accttype) {
        my $expire_time = DW::Pay::get_account_expiration_time($remote);
        $accttype_string =
            $expire_time > 0
            ? BML::ml( 'widget.accountstatistics.expires_on',
            { type => $accttype, date => DateTime->from_epoch( epoch => $expire_time )->date } )
            : $accttype;
    }

    my $ret = "<h2>" . $class->ml('widget.accountstatistics.title') . "</h2>";
    $ret .= "<ul>";
    $ret .= "<li>"
        . $class->ml(
        'widget.accountstatistics.member_since',
        { date => LJ::mysql_time( $remote->timecreate ) }
        ) . "</li>";
    $ret .= "<li>"
        . $class->ml(
        'widget.accountstatistics.entries2',
        {
            num_raw   => $remote->number_of_posts,
            num_comma => LJ::commafy( $remote->number_of_posts )
        }
        ) . "</li>";
    $ret .= "<li>"
        . $class->ml(
        'widget.accountstatistics.last_updated',
        { date => LJ::mysql_time( $remote->timeupdate ) }
        ) . "</li>";
    $ret .= "<li>"
        . $class->ml(
        'widget.accountstatistics.comments2',
        {
            num_received_raw   => $remote->num_comments_received,
            num_received_comma => LJ::commafy( $remote->num_comments_received ),
            num_posted_raw     => $remote->num_comments_posted,
            num_posted_comma   => LJ::commafy( $remote->num_comments_posted )
        }
        ) . "</li>";
    $ret .= "<li>"
        . $class->ml(
        'widget.accountstatistics.memories2',
        {
            num_raw   => $memories_count,
            num_comma => LJ::commafy($memories_count),
            aopts     => "href='$LJ::SITEROOT/tools/memories?user=" . $remote->user . "'",
        }
        );
    $ret .= ", "
        . $class->ml(
        'widget.accountstatistics.tags2',
        {
            num_raw   => $tags_count,
            num_comma => LJ::commafy($tags_count),
            aopts     => 'href="' . $remote->journal_base . '/tag/"'
        }
        ) . "</li>";
    $ret .= "<li>" . $accttype_string . "</li>";
    $ret .= "</ul>";

    return $ret;
}

1;

