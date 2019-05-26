#!/usr/bin/perl
#
# DW::Widget::QuickUpdate
#
# Quick update form
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

package DW::Widget::QuickUpdate;

use strict;
use base qw/ LJ::Widget /;

sub need_res { qw( stc/widgets/quickupdate.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $remote = LJ::get_remote()
        or return;

    my $ret = "<h2>" . $class->ml('widget.quickupdate.title') . "</h2>";
    $ret .=
          "<div class='sidebar'>"
        . LJ::Hooks::run_hook( 'entryforminfo', $remote->user, $remote )
        . "</div>";
    $ret .= "<div class='contents'>";

    # not using the LJ::Widget form of the HTML methods, because we're directing this to update.bml
    $ret .= $class->start_form( action => "/update" );
    $ret .= LJ::entry_form_date_widget();
    $ret .= LJ::entry_form_xpost_widget($remote);

    $ret .= LJ::labelfy( "subject", $class->ml('widget.quickupdate.subject') );
    $ret .= LJ::entry_form_subject_widget();
    $ret .= LJ::labelfy( "event",   $class->ml('widget.quickupdate.entry') );
    $ret .= LJ::entry_form_entry_widget();

    $ret .= "<div class='metadata'>";
    $ret .= "<div class='form-input'>";
    $ret .= LJ::labelfy( "usejournal", $class->ml('entryform.postto') );
    $ret .= LJ::entry_form_postto_widget($remote) || "";
    $ret .= "</div>";
    $ret .= "<div class='form-input'>";
    $ret .= LJ::labelfy( "security", $class->ml('entryform.security') );
    $ret .= LJ::entry_form_security_widget();
    $ret .= "</div>";
    $ret .= "<div class='form-input'>";
    $ret .= LJ::labelfy( "prop_picture_keyword", $class->ml('entryform.userpic') );
    $ret .= LJ::entry_form_usericon_widget($remote);
    $ret .= "</div>";
    $ret .= "<div class='form-input'>";
    $ret .= LJ::labelfy( "prop_taglist", $class->ml('entryform.tags') );
    $ret .= LJ::entry_form_tags_widget();
    $ret .= "</div>";
    $ret .= "</div>";

    $ret .= "<div class='submit'>";
    $ret .= LJ::html_submit( $class->ml('widget.quickupdate.update') );
    $ret .= LJ::html_submit( 'moreoptsbtn', $class->ml('widget.quickupdate.moreopts') );
    $ret .= "</div>";
    $ret .= $class->end_form;
    $ret .= "</div>";

    return $ret;
}

1;

