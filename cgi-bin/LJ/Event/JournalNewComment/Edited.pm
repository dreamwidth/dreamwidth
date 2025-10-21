#!/usr/bin/perl
#
# LJ::Event::JournalNewComment::Edited - Event that's fired when someone edits a comment
#
# Authors:
#      Aaron Isaac <aaron.isaac@afourth.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package LJ::Event::JournalNewComment::Edited;
use strict;

use base 'LJ::Event::JournalNewComment';

sub content {
    my ( $self, $target ) = @_;

    my $comment = $self->comment;
    return undef unless $self->_can_view_content( $comment, $target );

    LJ::need_res('js/commentmanage.js');

    my $buttons = $comment->manage_buttons;
    my $dtalkid = $comment->dtalkid;
    my $htmlid  = LJ::Talk::comment_htmlid($dtalkid);

    my $reason = LJ::ehtml( $comment->edit_reason );
    my $comment_body =
        "This comment was edited. " . "Please see the original notification for the updated text.";
    $comment_body .= " "
        . LJ::Lang::get_default_text( "esn.journal_new_comment.edit_reason", { reason => $reason } )
        . "."
        if $reason;

    my $ret = qq {
        <div id="$htmlid" class="JournalNewComment-Edited">
            <div class="ManageButtons">$buttons</div>
            <div class="Body">$comment_body</div>
        </div>
    };

    my $cmt_info = $comment->info;
    $cmt_info->{form_auth} = LJ::form_auth(1);
    my $cmt_info_js = LJ::js_dumper($cmt_info) || '{}';

    my $posterusername = $self->comment->poster ? $self->comment->poster->{user} : "";

    $ret .= qq {
        <script language="JavaScript">
        };

    while ( my ( $k, $v ) = each %$cmt_info ) {
        $k = LJ::ejs($k);
        $v = LJ::ejs($v);
        $ret .= "LJ_cmtinfo['$k'] = '$v';\n";
    }

    my $dtid_cmt_info = { u => $posterusername, rc => [] };

    $ret .= "LJ_cmtinfo['$dtalkid'] = " . LJ::js_dumper($dtid_cmt_info) . "\n";

    $ret .= qq {
        </script>
        };
    $ret .= $self->as_html_actions;

    return $ret;
}

1;
