#!/usr/bin/perl
#
# DW::Controller::Recent_comments
#
# This controller is for the Recent Comments pages.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Comments;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string('/comments/recent', \&received_handler, app => 1 );
DW::Routing->register_string('/comments/posted', \&posted_handler, app => 1 );

# redirect /tools/recent_comments, /tools/recent_comments.bml
DW::Routing->register_redirect( '/tools/recent_comments', '/comments/recent', app => 1, formats => [ 'html', 'bml' ] );

sub received_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};
    my $remote = $rv->{remote};

    my $dbcr = LJ::get_cluster_reader($u);
    die "Error: can't get DB for user" unless $dbcr;

    my $vars;
    $vars->{u} = $u;
    $vars->{authas_html} = $rv->{authas_html};
    $vars->{getextra} = ( $u ne $remote ) ? ( "?authas=" . $u->user ) : '';

    my %LJ_cmtinfo = %{ LJ::Comment->info( $u ) };
    $LJ_cmtinfo{form_auth} = LJ::form_auth( 1 );

    $vars = initialize_count( $u, $r, $vars );

    my ( @recv, %talkids );
    my %need_userid;
    $need_userid{$u->{userid}} = 1 if $u->is_community; # Need to load the community for logtext
    my %logrow;  # "jid nodeid" -> $logrow
    my %need_logids;  # hash of "journalid jitemid" => [journalid, jitemid]

    my $now = time();

    # Retrieve received
    if ( $u->is_person || $u->is_community ) {
        @recv = $u->get_recent_talkitems( $vars->{count} );
        foreach my $post ( @recv ) {
            $need_userid{$post->{posterid}} = 1 if $post->{posterid};
            $talkids{$post->{jtalkid}} = 1;
            $need_logids{"$u->{userid} $post->{nodeid}"} = [$u->{userid}, $post->{nodeid}]
                if $post->{nodetype} eq "L";
        }
        @recv = sort { $b->{datepostunix} <=> $a->{datepostunix} } @recv;
        my @recv_talkids = map { $_->{'jtalkid'} } @recv;

        my %props;
        LJ::load_talk_props2( $u->{'userid'}, \@recv_talkids, \%props );

        my $us = LJ::load_userids( keys %need_userid );

        # setup the parameter to get_posts_raw
        my @need_logtext;
        foreach my $need ( values %need_logids ) {
            my ( $ownerid, $itemid ) = @$need;
            my $ju = $us->{$ownerid} or next;
            push @need_logtext, [ $ju->{clusterid}, $ownerid, $itemid ];
        }

        my $comment_text = LJ::get_talktext2( $u, keys %talkids );
        my $log_data     = LJ::get_posts_raw( { text_only => 1 }, @need_logtext );
        my $log_text     = $log_data->{text};
        my $root = $u->journal_base;

        # Cycle through comments and skip deleted ones
        foreach my $r ( @recv ) {
            next unless $r->{nodetype} eq "L";
            next if $r->{state} eq "D";

            my $pu = $us->{$r->{posterid}};
            next if $pu && ( $pu->is_expunged || $pu->is_suspended );

            $r->{'props'} = $props{$r->{'jtalkid'}};

            my $lrow = $logrow{"$u->{userid} $r->{nodeid}"} ||= LJ::get_log2_row( $u, $r->{'nodeid'} );
            my $talkid = ( $r->{'jtalkid'} << 8 ) + $lrow->{'anum'};

            my $ditemid = "$root/$lrow->{ditemid}.html";
            my $commentanchor = LJ::Talk::comment_anchor( $talkid );
            my $talkurl = "$root/$lrow->{ditemid}.html?thread=$talkid$commentanchor";

            my $state = "";
            my $tdclass = "";
            if ( $r->{state} eq "S" ) {
                $state = "Screened";
                $tdclass = "screened";
            } elsif ( $r->{state} eq "D" ) {
                $state = "Deleted";
            } elsif ( $r->{state} eq "F" ) {
                $state = "Frozen";
            }

            my $ljcmt = $LJ_cmtinfo{$talkid} = {};
            $ljcmt->{u} = $pu ? $pu->{user} : "";

            my $isanonymous = LJ::isu( $pu ) ? 0 : 1;

            my $hr_ago = LJ::diff_ago_text( $r->{datepostunix}, $now );

            my $del_link = LJ::create_url( "/delcomment", args => {
                journal => $u->{'user'},
                id => $talkid } );
            my $del_img = LJ::img( "btn_del", "", { align => 'absmiddle', hspace => 2 } );

            my $freeze_link;
            my $freeze_img;

            if ( $r->{'state'} ne 'F' ) {
                $freeze_link = LJ::create_url( "/talkscreen", args => {
                    mode => "freeze",
                    journal => $u->{'user'},
                    talkid => $talkid } );
                $freeze_img = LJ::img( "btn_freeze", "", { align => 'absmiddle', hspace => 2 } );
            }
            elsif ( $r->{'state'} eq 'F' ) {
                 $freeze_link = LJ::create_url( "/talkscreen", args => {
                    mode => "unfreeze",
                    journal => $u->{'user'},
                    talkid => $talkid } );
                $freeze_img = LJ::img( "btn_unfreeze", "", { align => 'absmiddle', hspace => 2 } );
            }

            my $screen_link;
            my $screen_img;

            if ( $r->{'state'} ne 'S' ) {
                $screen_link = LJ::create_url( "/talkscreen", args => {
                    mode => "screen",
                    journal => $u->{'user'},
                    talkid => $talkid } );
                $screen_img = LJ::img( "btn_scr", "", { align => 'absmiddle', hspace => 2 } );
            }
            elsif ( $r->{'state'} eq 'S' ) {
                $screen_link = LJ::create_url( "/talkscreen", args => {
                    mode => "unscreen",
                    journal => $u->{'user'},
                    talkid => $talkid } );
                $screen_img = LJ::img( "btn_unscr", "", { align => 'absmiddle', hspace => 2 } );
             }

            # FIXME: (David?) We'll have to make talk_multi.bml understand jtalkids in multiple posts
            #$ret .= " <nobr><input type='checkbox' name='selected_$r->{jtalkid}' id='s$r->{jtalkid}' />";
            #$ret .= " <label for='s$r->{jtalkid}'>$ML{'/talkread.bml.select'}</label></nobr>";

            my $comment_htmlid = LJ::Talk::comment_htmlid( $talkid );

            my $esubject = $log_text->{"$u->{userid}:$r->{nodeid}"}[0] // "";
            LJ::CleanHTML::clean_subject( \$esubject ) if $esubject ne "";

            my $ditemid_undef = defined $lrow->{ditemid} ? 0 : 1;
            my $csubject = LJ::ehtml( $comment_text->{$r->{jtalkid}}[0] );

            if ( !$csubject || $csubject =~ /^Re:\s*$/ ) {
                $csubject = '';
            }

            my $comment = $comment_text->{$r->{jtalkid}}[1];
            LJ::CleanHTML::clean_comment( \$comment, {
                            preformatted => $r->{props}->{opt_preformatted},
                            editor => $r->{props}->{editor},
                            anon_comment => LJ::Talk::treat_as_anon( $pu, $u ),
                            nocss => 1,
            } );

            my $stylemine = 0;
            my $replyurl = LJ::Talk::talkargs($ditemid, "replyto=$talkid", $stylemine);

            push @{ $vars->{comments} }, {
                isanonymous => $isanonymous, # 1 if posted by anonymous user
                pu => $pu, # user that posted the comment
                hr_ago => $hr_ago, # text of time posted
                state => $state, # Screened, Deleted, or Frozen
                del_link => $del_link,
                del_img => $del_img,
                screen_link => $screen_link,
                screen_img => $screen_img,
                freeze_link => $freeze_link,
                freeze_img => $freeze_img,
                comment_htmlid => $comment_htmlid,
                esubject => $esubject,
                ditemid_undef => $ditemid_undef,
                ditemid => $ditemid,
                csubject => $csubject,
                comment => $comment,
                talkurl => $talkurl, # direct link to comment
                replyurl => $replyurl,
                talkid => $talkid, # comment number
                tdclass => $tdclass
            };
        }
    }

    $vars->{LJ_cmtinfo} = LJ::js_dumper( \%LJ_cmtinfo );

    return DW::Template->render_template( 'comments/recent.tt', $vars );
}


sub posted_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{u};
    my $remote = $rv->{remote};

    my $vars;
    $vars->{u} = $u;
    $vars->{authas_html} = $rv->{authas_html};
    $vars->{getextra} = ( $u ne $remote) ? ( "?authas=" . $u->user ) : '';

    my %LJ_cmtinfo = %{ LJ::Comment->info( $u ) };
    $LJ_cmtinfo{form_auth} = LJ::form_auth( 1 );

    my $dbcr = LJ::get_cluster_reader($u);
    die "Error: can't get DB for user" unless $dbcr;

    $vars = initialize_count( $u, $r, $vars );

    my ( @posted, %talkids );
    my %need_userid;
    $need_userid{$u->{userid}} = 1 if $u->is_community; # Need to load the community for logtext
    my %logrow;  # "jid nodeid" -> $logrow
    my %need_logids;  # hash of "journalid jitemid" => [journalid, jitemid]

    my $now = time();
    my $sth;

    $vars->{canedit} = $remote->can_edit_comments;

    # Retrieve posted
    if ($u->is_individual) {
        $sth = $dbcr->prepare("SELECT posttime, journalid, nodetype, nodeid, jtalkid, publicitem ".
                              "FROM talkleft ".
                              "WHERE userid=?  ORDER BY posttime DESC LIMIT $vars->{count}");
        $sth->execute( $u->{'userid'} );
        my %jcount;  # jid -> ct
        while ( my $r = $sth->fetchrow_hashref ) {
            push @posted, $r;
            $need_logids{"$r->{journalid} $r->{nodeid}"} = [$r->{journalid}, $r->{nodeid}]
                if $r->{nodetype} eq "L";
            $need_userid{$r->{journalid}} = 1;
        }

        my $us = LJ::load_userids(keys %need_userid);

        # setup the parameter to get_posts_raw
        my @need_logtext;
        foreach my $need ( values %need_logids ) {
            my ( $ownerid, $itemid ) = @$need;
            my $ju = $us->{$ownerid} or next;
            push @need_logtext, [ $ju->{clusterid}, $ownerid, $itemid ];
        }

        my $log_data     = LJ::get_posts_raw( { text_only => 1 }, @need_logtext );
        my $log_text     = $log_data->{text};
        my $root = $u->journal_base;

        # Cycle through each comment to extract necessary data
        foreach my $r ( @posted ) {
            $jcount{$r->{'journalid'}}++;
            next unless $r->{'nodetype'} eq "L";   # log2 comment

            my $ju = $us->{$r->{journalid}};
            my $lrow = $logrow{"$ju->{userid} $r->{nodeid}"} ||= LJ::get_log2_row( $ju, $r->{'nodeid'} );

            my $hr_ago = LJ::diff_ago_text( $r->{posttime}, $now );

            # if entry exists
            if ( defined $lrow->{ditemid} ) {
                my $talkid = ( $r->{'jtalkid'} << 8 ) + $lrow->{'anum'};
                my $ljcmt = $LJ_cmtinfo{$talkid} = {};
                $ljcmt->{u} = $u->{user};
                $ljcmt->{postedin} = $ju ? $ju->{user} : "";

                my $comment = LJ::Comment->new( $ju, dtalkid => $talkid );

                my $logurl = $ju->journal_base . "/$lrow->{ditemid}.html";
                my $commentanchor = LJ::Talk::comment_anchor( $talkid );
                my $talkurl = "$logurl?thread=$talkid$commentanchor";

                my $subject = $log_text->{"$r->{journalid}:$r->{nodeid}"}[0] || "$lrow->{ditemid}.html";
                LJ::CleanHTML::clean_subject( \$subject );

                # add a sign if the comment has replies
                my $hasreplies = $comment->has_nondeleted_children ? "*" : '';

                # delete link, very helpful for when the user does not have access to that entry anymore
                my $delete = $comment->is_deleted ? '' : LJ::create_url( "/delcomment", args => {
                journal => $ju->{'user'},
                id => $talkid } );

                # edit link, if comment can be edited
                my $editlink = $comment->remote_can_edit ? LJ::Talk::talkargs( $comment->edit_url ) : '';

                push @{ $vars->{comments} }, {
                    ju => $ju, # journal comment was posted in
                    talkurl => $talkurl, # direct link to comment
                    logurl => $logurl, # link to entry holding comment
                    subject => $subject, # subject of entry
                    candelete => $hasreplies, # '*' if comment has replies and cannot be deleted
                    hr_ago => $hr_ago, # text of time posted
                    deletelink => $delete, # link to delete comment (if available, otherwise blank)
                    editlink => $editlink, # link to edit comment (if available, otherwise blank)
                    talkid => $talkid # comment number
                };

            }
            # entry has been deleted
            else {
                push @{ $vars->{comments} }, {
                    postdeleted => 1, # entry deleted
                    hr_ago => $hr_ago,
                    ju => $ju
                };
            }
        }
    }

    $vars->{LJ_cmtinfo} = LJ::js_dumper( \%LJ_cmtinfo );

    return DW::Template->render_template( 'comments/posted.tt', $vars );
}

# Ascertain number of comments to show
sub initialize_count {
    my ( $u, $r, $vars ) = @_;

    my $max = $u->count_recent_comments_display;
    my $show = $r->get_args->{show} // 25;

    # how many comments to display by default
    $show = $max if $show > $max;
    $show = 0 if $show < 1;
    my $count = $show || ( $max > 25 ? 25 : $max );
    $show = $max > 25 ? 25 : $max;
    $vars->{count} = $count;
    $vars->{show} = $show;
    $vars->{max} = $max;

    my @values = qw( 10 25 50 100 );
    push @values, $count
        unless grep { $count == $_ } @values;
    push @values, $max
        unless grep { $max == $_ } @values;

    @values = sort { $a <=> $b } @values;
    $vars->{values} = \@values;
    $vars->{sitemax} = $LJ::TOOLS_RECENT_COMMENTS_MAX;

    return $vars;
}

1;
