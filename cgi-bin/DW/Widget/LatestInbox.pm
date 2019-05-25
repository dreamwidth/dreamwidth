#!/usr/bin/perl
#
# DW::Widget::LatestInbox
#
# Latest inbox messages
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

package DW::Widget::LatestInbox;

use strict;
use base qw/ LJ::Widget /;

sub need_res {
    qw( stc/widgets/latestinbox.css );
}

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return "";

    my $limit = $opts{limit} || 5;

    my $ret = "<h2>" . $class->ml('widget.latestinbox.title') . "</h2>";

    $ret .= "<div class='sidebar'><ul>";
    $ret .= "<li><a href='/inbox/'>" . $class->ml('widget.latestinbox.links.inbox') . "</a></li>";
    $ret .=
          "<li><a href='/inbox/compose'>"
        . $class->ml('widget.latestinbox.links.compose')
        . "</a></li>";
    $ret .=
          "<li><a href='/manage/settings/?cat=notifications'>"
        . $class->ml('widget.latestinbox.links.manage')
        . "</a></li>";
    $ret .= "</ul></div>";

    $ret .= "<div class='contents'>";

    # get the user's inbox
    my $error;
    my $inbox = $remote->notification_inbox
        or $error = LJ::error_list(
        $class->ml( 'inbox.error.couldnt_retrieve_inbox', { 'user' => $remote->{user} } ) );

    if ($error) {
        $ret .= $error;
    }
    else {
        my @inbox_items = reverse $inbox->all_items;

        if (@inbox_items) {
            foreach my $item ( splice( @inbox_items, 0, $limit ) ) {
                $ret .= "<div class='item'>";
                $ret .= "<div class='title'>" . $item->title . "</div>";

                my $summary = $item->as_html_summary;
                $ret .= "<div class='summary'>$summary</div>" if $summary;

                $ret .= "</div>";
            }
        }
        else {
            $ret .= "<div class='item'>" . $class->ml('widget.latestinbox.empty') . "</div>";
        }
    }

    $ret .= "</div>";
    return $ret;
}

1;

