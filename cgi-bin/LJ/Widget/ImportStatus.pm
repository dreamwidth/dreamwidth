#!/usr/bin/perl
#
# LJ::Widget::ImportStatus
#
# Renders the status of the user's current import jobs.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
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
        $ret .= "<table summary='' width='100%' class='importer-status'>";

        my $import_in_progress = 0;

        my $item_to_funcname = {
            lj_bio => 'DW::Worker::ContentImporter::LiveJournal::Bio',
            lj_tags => 'DW::Worker::ContentImporter::LiveJournal::Tags',
            lj_entries => 'DW::Worker::ContentImporter::LiveJournal::Entries',
            lj_comments => 'DW::Worker::ContentImporter::LiveJournal::Comments',
            lj_userpics => 'DW::Worker::ContentImporter::LiveJournal::Userpics',
            lj_friends => 'DW::Worker::ContentImporter::LiveJournal::Friends',
            lj_friendgroups => 'DW::Worker::ContentImporter::LiveJournal::FriendGroups',
            lj_verify => 'DW::Worker::ContentImporter::LiveJournal::Verify',
        };


        my $dbr;
        my $funcmap;
        my $dupect = 0;
        foreach my $importid ( sort { $b <=> $a } keys %$items ) {
            my $import_item = $items->{$importid};

            $ret .= "<tr><td colspan='4' class='table-header'>";
            if ( $import_item->{usejournal} ) {
                $ret .= $class->ml( 'widget.importstatus.whichaccount.comm', {
                    user => $import_item->{user},
                    comm => $import_item->{usejournal},
                    host => $import_item->{host}
                } ) . " | ";
            } else {
                $ret .= $class->ml( 'widget.importstatus.whichaccount', {
                    user => $import_item->{user},
                    host => $import_item->{host}
                } ) . " | ";
            }
            $ret .= "<a href='$LJ::SITEROOT/tools/importer?authas=" . $u->user . "'>" . $class->ml( 'widget.importstatus.refresh' ) . "</a></td></tr>";
            foreach my $item ( sort keys %{$import_item->{items}} ) {
                my $i = $import_item->{items}->{$item};
                my $color = { init => '#333', ready => '#33a', queued => '#3a3',
                              failed => '#a33', succeeded => '#0f0',
                              aborted => '#f00' }->{$i->{status}};
                my $ago_text = $i->{last_touch} ? LJ::diff_ago_text( $i->{last_touch} ) : "";
                my $status = "<span style='color: $color;'>";
                if ( $i->{status} eq 'init' ) {
                    $status .= $class->ml( "widget.importstatus.status.$i->{status}.$item" );
                } else {
                    $status .= $class->ml( "widget.importstatus.status.$i->{status}" );

                    if ( $i->{status} eq "aborted" ) {
                        unless ( $dbr ) {
                            # do manual connection
                            my $db = $LJ::THESCHWARTZ_DBS[0];
                            $dbr = DBI->connect( $db->{dsn}, $db->{user}, $db->{pass} );
                        }

                        if ( $dbr ) {
                            # get the ids for the function map
                            $funcmap ||= $dbr->selectall_hashref( 'SELECT funcid, funcname FROM funcmap', 'funcname' );

                            $dupect = $dbr->selectrow_array(
                                q{SELECT COUNT(*) from job
                                    WHERE funcid  = ?
                                      AND uniqkey = ? },
                                undef, $funcmap->{$item_to_funcname->{$item}}->{funcid}, join( "-", ( $item, $u->id ) )
                            );
                        }
                    }
                }

                $status .= " " . $class->ml( "widget.importstatus.processingprevious" ) if $dupect;
                $status .= "</span>";

                $ret .= "<tr>";
                $ret .= "<td><em>" . $class->ml( "widget.importstatus.item.$item" ) . "</em></td>";
                $ret .= "<td>";
                $ret .= $ago_text ? $class->ml( 'widget.importstatus.statusasof', { status => $status, timeago => $ago_text } ) : $status;
                $ret .= "</td>";
                $ret .= "<td>" . $class->ml( 'widget.importstatus.createtime', { timeago => LJ::diff_ago_text( $i->{created} ) } ) . "</td>";
                $ret .= "</tr>";

                $import_in_progress = 1 if $i->{status} =~ /^(?:init|ready|queued)$/;
            }
        }

        $ret .= "</table>";
        $ret .= "<p class='queueanother'>" . $class->ml( 'widget.importstatus.importanother' ) . "</p>";

        $ret .= $class->start_form;
        $ret .= $class->html_hidden( import_in_progress => $import_in_progress );
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

    return ( ret => LJ::Widget::ImportChooseSource->render( import_in_progress => $post->{import_in_progress} ) );
}

1;
