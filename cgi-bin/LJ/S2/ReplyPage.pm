#!/usr/bin/perl
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;

package LJ::S2;

sub ReplyPage {
    my ( $u, $remote, $opts ) = @_;

    my $p = Page( $u, $opts );
    $p->{'_type'} = "ReplyPage";
    $p->{'view'}  = "reply";

    my $get = $opts->{'getargs'};

    my ( $entry, $s2entry ) = EntryPage_entry( $u, $remote, $opts );
    return if $opts->{'suspendeduser'};

    # reply page of suspended entry cannot be accessed by anyone, even entry poster
    if ( $entry && $entry->is_suspended ) {
        $opts->{suspendedentry} = 1;
        return;
    }

    # read-only users can't comment anywhere
    if ( $remote && $remote->is_readonly ) {
        $opts->{readonlyremote} = 1;
        return;
    }

    # no one can comment in a read-only journal
    if ( $u->is_readonly ) {
        $opts->{readonlyjournal} = 1;
        return;
    }

    return if $opts->{'handler_return'};
    return if $opts->{'redir'};
    return if $opts->{internal_redir};

    my $ditemid   = $entry->ditemid;
    my $replytoid = $get->{replyto} ? $get->{replyto} : 0;

    # canonical link to the entry or comment thread
    $p->{head_content} .= LJ::canonical_link( $entry->url, $replytoid );

    $p->{'head_content'} .= $LJ::COMMON_CODE{'chalresp_js'};

    LJ::need_res('stc/display_none.css');
    LJ::need_res( LJ::S2::tracking_popup_js() );

    # include JS for quick reply, icon browser, and ajax cut tag
    my $handle_with_siteviews = $opts->{handle_with_siteviews_ref}
        && ${ $opts->{handle_with_siteviews_ref} };
    LJ::Talk::init_s2journal_js(
        iconbrowser => $remote && $remote->can_use_userpic_select,
        siteskin    => $handle_with_siteviews,
        noqr        => 1
    );

    if ( $u->should_block_robots || $entry->should_block_robots ) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    $p->{'entry'} = $s2entry;
    LJ::Hooks::run_hook( 'notify_event_displayed', $entry );

    # setup the replying item
    my $replyto = $s2entry;
    my $editid  = $get->{edit} ? $get->{edit} : 0;
    my $parpost;
    my $parentcomment;

    my $comment;
    my %comment_values;
    if ($editid) {
        my $errref;
        $comment = LJ::Comment->new( $u, dtalkid => $editid );
        unless ($remote) {
            my $redir = LJ::eurl( LJ::create_url( undef, keep_args => 1 ) );
            $opts->{'redir'} = "$LJ::SITEROOT/?returnto=$redir&errmsg=notloggedin";
            return;
        }
        unless ( $comment->remote_can_edit( \$errref ) ) {
            if ($errref) {
                $opts->{status} = "403 Forbidden";
                return "<p>$errref</p>";
            }
            $opts->{'handler_return'} = 403;
            return;
        }

        $parpost = $comment->parent;

# for comments where the parent comment is deleted, we pretend the parent comment doesn't exist so the user can edit
        $parpost   = undef if $parpost && $parpost->is_deleted;
        $replytoid = $parpost ? $comment->parent->dtalkid : 0;

        $comment_values{edit}                  = $editid;
        $comment_values{replyto}               = $replytoid;
        $comment_values{subject}               = $comment->subject_orig;
        $comment_values{body}                  = $comment->body_orig;
        $comment_values{subjecticon}           = $comment->prop('subjecticon');
        $comment_values{prop_opt_preformatted} = $comment->prop('opt_preformatted');
        $comment_values{prop_picture_keyword}  = $comment->userpic_kw;
    }

    if ($replytoid) {
        my $re_talkid = int( $replytoid >> 8 );
        my $re_anum   = $replytoid % 256;
        unless ( $re_anum == $entry->anum ) {
            $opts->{'handler_return'} = 404;
            return;
        }

        my $dtalkid = $re_talkid * 256 + $entry->anum;

        # FIXME: Why are we loading the comment manually when we do LJ::Comment->new below
        # and could do everything through there.
        my $sql =
              "SELECT jtalkid, posterid, state, datepost FROM talk2 "
            . "WHERE journalid=$u->{'userid'} AND jtalkid=$re_talkid "
            . "AND nodetype='L' AND nodeid="
            . $entry->jitemid;
        foreach my $pass ( 1, 2 ) {
            my $db = $pass == 1 ? LJ::get_cluster_reader($u) : LJ::get_cluster_def_reader($u);
            $parpost = $db->selectrow_hashref($sql);
            last if $parpost;
        }
        my $parentcomment = LJ::Comment->new( $u, jtalkid => $re_talkid );
        unless ( $parpost and $parpost->{'state'} ne 'D' ) {

            # FIXME: This is a hack. See below...

            $opts->{status} = "404 Not Found";
            return "<p>This comment has been deleted; you cannot reply to it.</p>";
        }
        if ( $parpost->{state} eq 'S' && !$parentcomment->visible_to($remote) ) {
            $opts->{'handler_return'} = 403;
            return;
        }
        if ( $parpost->{'state'} eq 'F' ) {

            # frozen comment, no replies allowed

            # FIXME: eventually have S2 ErrorPage to handle this and similar
            #    For now, this hack will work; this error is pretty uncommon anyway.
            $opts->{status} = "403 Forbidden";
            return "<p>This thread has been frozen; no more replies are allowed.</p>";
        }
        if ( $entry->is_suspended ) {
            $opts->{status} = "403 Forbidden";
            return "<p>This entry has been suspended; you cannot reply to it.</p>";
        }
        if ( $remote && $remote->is_readonly ) {
            $opts->{status} = "403 Forbidden";
            return "<p>You are read-only.  You cannot reply to this entry.</p>";
        }

        my $tt = LJ::get_talktext2( $u, $re_talkid );
        $parpost->{'subject'} = $tt->{$re_talkid}->[0];
        $parpost->{'body'}    = $tt->{$re_talkid}->[1];
        $parpost->{'props'} =
            LJ::load_talk_props2( $u, [$re_talkid] )->{$re_talkid} || {};
        $parpost->{'dtid'} = $dtalkid;

        if ( $parpost->{'props'}->{'unknown8bit'} ) {
            LJ::item_toutf8( $u, \$parpost->{'subject'}, \$parpost->{'body'}, {} );
        }

        my $datetime = DateTime_unix( LJ::mysqldate_to_time( $parpost->{'datepost'} ) );

        my $comment_userpic;
        my $s2poster;

        my $pu = $parentcomment->poster;
        if ($pu) {
            return $opts->{handler_return} = 403
                if $pu->is_suspended;    # do not show comments by suspended users
            $s2poster = UserLite($pu);

            my ( $pic, $pickw ) = $parentcomment->userpic;
            $comment_userpic = Image_userpic( $pu, $pic ? $pic->picid : 0, $pickw );
        }

        my $anon_comment = LJ::Talk::treat_as_anon( $pu, $u );
        LJ::CleanHTML::clean_comment(
            \$parpost->{'body'},
            {
                preformatted => $parpost->{props}->{opt_preformatted},
                anon_comment => $anon_comment,
                nocss        => $anon_comment,
                editor       => $parpost->{props}->{editor},
            }
        );

        my $cmtobj = LJ::Comment->new( $u, dtalkid => $dtalkid );

        my $tz_remote;
        my $datetime_remote;
        my $datetime_poster;
        if ($remote) {
            my $tz = $remote->prop("timezone");
            $tz_remote = $tz ? eval { DateTime::TimeZone->new( name => $tz ); } : undef;
        }

        $datetime_remote = $tz_remote ? DateTime_tz( $cmtobj->unixtime, $tz_remote ) : undef;
        $datetime_poster =
            $parentcomment ? DateTime_tz( $cmtobj->unixtime, $parentcomment->poster ) : undef;

        my $replyargs = LJ::viewing_style_args(%$get);
        $replyto = {
            '_type'          => 'Comment',
            'subject'        => LJ::ehtml( $parpost->{'subject'} ),
            'text'           => $parpost->{'body'},
            'userpic'        => $comment_userpic,
            'poster'         => $s2poster,
            'journal'        => $s2entry->{'journal'},
            'metadata'       => {},
            'permalink_url'  => $cmtobj->url($replyargs),
            'depth'          => 1,
            'parent_url'     => $cmtobj->parent_url($replyargs),
            'threadroot_url' => $cmtobj->threadroot_url($replyargs),
            'time'           => $datetime,
            'system_time'    => $datetime,
            'time_remote'    => $datetime_remote,
            'time_poster'    => $datetime_poster,
            'tags'           => [],
            'talkid'         => $dtalkid,
            'link_keyseq'    => ['delete_comment'],
            'screened'       => $parpost->{'state'} eq "S" ? 1 : 0,
            'frozen'         => $parpost->{'state'} eq "F" ? 1 : 0,
            'deleted'        => $parpost->{'state'} eq "D" ? 1 : 0,
            'full'           => 1,
            timeformat24     => $remote && $remote->use_24hour_time,
            admin_post       => $cmtobj->admin_post ? 1 : 0,
        };

        # Conditionally add more links to the keyseq
        my $link_keyseq = $replyto->{'link_keyseq'};
        push @$link_keyseq, $replyto->{'screened'} ? 'unscreen_comment' : 'screen_comment';
        push @$link_keyseq, $replyto->{'frozen'}   ? 'unfreeze_thread'  : 'freeze_thread';
        push @$link_keyseq, "watch_thread"    if LJ::is_enabled('esn');
        push @$link_keyseq, "unwatch_thread"  if LJ::is_enabled('esn');
        push @$link_keyseq, "watching_parent" if LJ::is_enabled('esn');
        unshift @$link_keyseq, "edit_comment" if LJ::is_enabled('edit_comments');
    }

    $p->{'replyto'} = $replyto;

    $p->{'form'} = {
        '_type'      => "ReplyForm",
        '_remote'    => $remote,
        '_u'         => $u,
        '_ditemid'   => $ditemid,
        '_parpost'   => $parpost,
        '_values'    => \%comment_values,
        '_styleopts' => $p->{_styleopts},
    };

    $p->{'isedit'} = $editid ? 1 : 0;

    return $p;
}

package S2::Builtin::LJ;

sub ReplyForm__print {
    my ( $ctx, $form ) = @_;
    my $remote  = $form->{'_remote'};
    my $u       = $form->{'_u'};
    my $parpost = $form->{'_parpost'};
    my $parent  = $parpost ? $parpost->{'jtalkid'} : 0;
    my $dtid    = $parpost ? $parpost->{dtid} : 0;

    my $post_vars = DW::Request->get->post_args;
    $post_vars = $form->{_values} unless keys %$post_vars;

    $S2::pout->(
        LJ::Talk::talkform(
            {
                'remote'     => $remote,
                'journalu'   => $u,
                'parpost'    => $parpost,
                'replyto'    => $parent,
                'dtid'       => $dtid,
                'ditemid'    => $form->{'_ditemid'},
                'styleopts'  => $form->{_styleopts},
                'form'       => $post_vars,
                'do_captcha' => LJ::Talk::Post::require_captcha_test(
                    $remote, $u, $post_vars->{body}, $form->{'_ditemid'}
                )
            }
        )
    );

}

1;
