#!/usr/bin/perl
#
# LJ::Widget::ImportStatus
#
# Renders the status of the user's current import jobs.
#
# Authors:
#      Janine Costanzo <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::ImportStatus;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

use DW::Logic::Importer;

sub need_res { qw( stc/importer.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $u = LJ::get_effective_remote();
    return "" unless LJ::isu( $u );

    my $items = DW::Logic::Importer->get_import_items_for_user( $u );
    my $ret;

    if ( scalar keys %$items ) {
        $ret .= "<h2 class='gradient'>" . $class->ml( 'widget.importstatus.header' ) . "</h2>";
        $ret .= "<table width='100%' class='importer-status'>";

        foreach my $importid ( sort { $b <=> $a } keys %$items ) {
            my $import_item = $items->{$importid};

            $ret .= "<tr><td colspan='4' class='table-header'>" . $class->ml( 'widget.importstatus.whichaccount', { user => $import_item->{user}, host => $import_item->{host} } ) . " | ";
            $ret .= "<a href='$LJ::SITEROOT/misc/import'>" . $class->ml( 'widget.importstatus.refresh' ) . "</a></td></tr>";
            foreach my $item ( sort keys %{$import_item->{items}} ) {
                my $i = $import_item->{items}->{$item};
                my $color = { init => '#333333', ready => '#3333aa', queued => '#33aa33', failed => '#aa3333', succeeded => '#00ff00' }->{$i->{status}};
                my $ago_text = $i->{last_touch} ? LJ::ago_text( time() - $i->{last_touch} ) : "";
                my $status = "<span style='color: $color;'>";
                if ( $i->{status} eq 'init' ) {
                    $status .= $class->ml( "widget.importstatus.status.$i->{status}.$item" );
                } else {
                    $status .= $class->ml( "widget.importstatus.status.$i->{status}" );
                }
                $status .= "</span>";

                $ret .= "<tr>";
                $ret .= "<td><em>" . $class->ml( "widget.importstatus.item.$item" ) . "</em></td>";
                $ret .= "<td>";
                $ret .= $ago_text ? $class->ml( 'widget.importstatus.statusasof', { status => $status, timeago => $ago_text } ) : $status;
                $ret .= "</td>";
                $ret .= "<td>" . $class->ml( 'widget.importstatus.createtime', { timeago => LJ::ago_text( time() - $i->{created} ) } ) . "</td>";
                $ret .= "</tr>";
            }
        }

        $ret .= "</table>";
        $ret .= "<p class='queueanother'>" . $class->ml( 'widget.importstatus.importanother' ) . "</p>";

        $ret .= $class->start_form;
        $ret .= $class->html_submit( import => $class->ml( 'widget.importstatus.btn.importanother' ) );
        $ret .= $class->end_form;
    }

    return $ret;
}

sub should_render {
    my $class = shift;

    my $u = LJ::get_effective_remote();

    return 0 unless LJ::isu( $u );
    return 0 unless scalar keys %{ DW::Logic::Importer->get_import_items_for_user( $u ) };
    return 1;
}

sub handle_post {
    my ( $class, $post, %opts ) = @_;

    return ( ret => LJ::Widget::ImportChooseSource->render( warning => 1 ) );
}

1;
