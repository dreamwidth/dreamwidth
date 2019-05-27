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

# these are needed for S2::PROPS
use DW;
use lib DW->home . "/src/s2";
use S2;

sub EntryPage {
    my ( $u, $remote, $opts ) = @_;

    my $get = $opts->{'getargs'};

    my $p = Page( $u, $opts );
    $p->{'_type'}          = "EntryPage";
    $p->{'view'}           = "entry";
    $p->{'comment_pages'}  = undef;
    $p->{'comment_navbar'} = undef;
    $p->{'comments'}       = [];

    # setup viewall options
    my ( $viewall, $viewsome ) = ( 0, 0 );
    if ($remote) {

        # we don't log here, as we don't know what entry we're viewing yet.
        # the logging is done when we call EntryPage_entry below.
        ( $viewall, $viewsome ) =
            $remote->view_priv_check( $u, $get->{viewall} );
    }

    my ( $entry, $s2entry ) = EntryPage_entry( $u, $remote, $opts );
    return if $opts->{'suspendeduser'};
    return if $opts->{'suspendedentry'};
    return if $opts->{'readonlyremote'};
    return if $opts->{'readonlyjournal'};
    return if $opts->{'handler_return'};
    return if $opts->{'redir'};
    return if $opts->{'internal_redir'};

    $p->{'multiform_on'} = $entry->comments_manageable_by($remote);

    my $itemid    = $entry->jitemid;
    my $permalink = $entry->url;
    my $style_arg = LJ::viewing_style_args(%$get);

    if ( $u->should_block_robots || $entry->should_block_robots ) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    $p->{'head_content'} .=
          '<meta http-equiv="Content-Type" content="text/html; charset='
        . $opts->{'saycharset'}
        . "\" />\n";

    my $prev_url = S2::Builtin::LJ::Entry__get_link( $opts->{ctx}, $s2entry, "nav_prev" )->{url};
    $p->{head_content} .= qq{<link rel="prev" href="$prev_url" />\n} if $prev_url;

    my $next_url = S2::Builtin::LJ::Entry__get_link( $opts->{ctx}, $s2entry, "nav_next" )->{url};
    $p->{head_content} .= qq{<link rel="next" href="$next_url" />\n} if $next_url;

    # canonical link to the entry or comment thread
    $p->{head_content} .= LJ::canonical_link( $permalink, $get->{thread} );

    # include JS for quick reply, icon browser, and ajax cut tag
    my $handle_with_siteviews = $opts->{handle_with_siteviews_ref}
        && ${ $opts->{handle_with_siteviews_ref} };
    LJ::Talk::init_s2journal_js(
        iconbrowser => $remote && $remote->can_use_userpic_select,
        siteskin    => $handle_with_siteviews
    );

    $p->{'entry'} = $s2entry;
    LJ::Hooks::run_hook( 'notify_event_displayed', $entry );

    # add the comments
    my $view_arg      = $get->{'view'} || "";
    my $flat_mode     = ( $view_arg =~ /\bflat\b/ );
    my $top_only_mode = ( $view_arg =~ /\btop-only\b/ );
    my $view_num      = ( $view_arg =~ /(\d+)/ ) ? $1 : undef;

    my $expand_all = ( $u->thread_expand_all($remote) && $get->{'expand_all'} );

    my %userpic;
    my %user;
    my $copts = {
        'flat'       => $flat_mode,
        'top-only'   => $top_only_mode,
        'thread'     => $get->{thread} ? ( $get->{thread} >> 8 ) : 0,
        'page'       => $get->{'page'},
        'view'       => $view_num,
        'userpicref' => \%userpic,
        'userref'    => \%user,

        # user object is cached from call just made in EntryPage_entry
        'up'         => LJ::load_user( $s2entry->{'poster'}->{'user'} ),
        'viewall'    => $viewall,
        'expand_all' => $expand_all,
        'filter'     => $get->{comments},
    };

    my $userlite_journal = UserLite($u);

    # Only load comments if commenting is enabled on the entry
    my @comments;
    if ( $p->{'entry'}->{'comments'}->{'enabled'} ) {
        @comments = LJ::Talk::load_comments( $u, $remote, "L", $itemid, $copts );
    }

    my $tz_remote;
    if ($remote) {
        my $tz = $remote->prop("timezone");
        $tz_remote = $tz ? eval { DateTime::TimeZone->new( name => $tz ); } : undef;
    }

    my ( $last_talkid, $last_jid ) = LJ::get_lastcomment();

    my $convert_comments = sub {
        my ( $self, $destlist, $srclist, $depth ) = @_;

        foreach my $com (@$srclist) {
            my $pu = $com->{'posterid'} ? $user{ $com->{'posterid'} } : undef;

            my $dtalkid = $com->{'talkid'} * 256 + $entry->anum;
            my $text    = LJ::CleanHTML::quote_html( $com->{body}, $get->{nohtml} );

            my $anon_comment = LJ::Talk::treat_as_anon( $pu, $u );
            LJ::CleanHTML::clean_comment(
                \$text,
                {
                    preformatted => $com->{props}->{opt_preformatted},
                    anon_comment => $anon_comment,
                    nocss        => $anon_comment,
                    editor       => $com->{props}->{editor}
                }
            );

            # local time in mysql format to gmtime
            my $datetime = DateTime_unix( $com->{'datepost_unix'} );
            my $datetime_remote =
                $tz_remote ? DateTime_tz( $com->{'datepost_unix'}, $tz_remote ) : undef;
            my $seconds_since_entry = $com->{'datepost_unix'} - $entry->logtime_unix;
            my $datetime_poster     = DateTime_tz( $com->{'datepost_unix'}, $pu );

            my $threadroot_url;

            my ( $edited, $edit_url, $editreason, $edittime, $edittime_remote, $edittime_poster );

            # in flat mode, promote the parenttalkid_actual
            if ($flat_mode) {
                $com->{'parenttalkid'} ||= $com->{'parenttalkid_actual'};
            }

            if ( $com->{_loaded} ) {
                my $comment = LJ::Comment->new( $u, jtalkid => $com->{talkid} );

                $edited   = $comment->is_edited;
                $edit_url = LJ::Talk::talkargs( $comment->edit_url, $style_arg );
                if ($edited) {
                    $editreason = LJ::ehtml( $comment->edit_reason );
                    $edittime   = DateTime_unix( $comment->edit_time );
                    $edittime_remote =
                        $tz_remote ? DateTime_tz( $comment->edit_time, $tz_remote ) : undef;
                    $edittime_poster = DateTime_tz( $comment->edit_time, $pu );
                }

                $threadroot_url = $comment->threadroot_url($style_arg) if $com->{parenttalkid};
                $com->{admin_post} = $comment->admin_post;
            }

            my $subject_icon = undef;
            if ( my $si = $com->{'props'}->{'subjecticon'} ) {
                my $pic = LJ::Talk::get_subjecticon_by_id($si);
                $subject_icon =
                    Image( "$LJ::IMGPREFIX/talk/$pic->{'img'}", $pic->{'w'}, $pic->{'h'} )
                    if $pic;
            }

            my $comment_userpic;

            my $userpic_position = S2::get_property_value( $opts->{ctx}, 'userpics_position' );
            my $comment_userpic_style =
                S2::get_property_value( $opts->{ctx}, 'comment_userpic_style' ) || "";
            unless ( $userpic_position eq "none" ) {
                if ( defined $com->{picid} && ( my $pic = $userpic{ $com->{picid} } ) ) {
                    my $width  = $pic->{width};
                    my $height = $pic->{height};

                    if ( $comment_userpic_style eq 'small' ) {
                        $width  = $width * 3 / 4;
                        $height = $height * 3 / 4;
                    }
                    elsif ( $comment_userpic_style eq 'smaller' ) {
                        $width  = $width / 2;
                        $height = $height / 2;
                    }

                    $comment_userpic = Image_userpic( $com->{upost}, $com->{picid}, $com->{pickw},
                        $width, $height );
                }
            }

            my $reply_url = LJ::Talk::talkargs( $permalink, "replyto=$dtalkid", $style_arg );

            my $par_url;

            if ( $com->{'parenttalkid'} ) {
                my $dparent = ( $com->{'parenttalkid'} << 8 ) + $entry->anum;
                $par_url = LJ::Talk::talkargs( $permalink, "thread=$dparent", $style_arg )
                    . LJ::Talk::comment_anchor($dparent);
            }

            my $poster;
            if ( $com->{'posterid'} ) {
                if ($pu) {
                    $poster = UserLite($pu);
                }
                else {
                    # posterid is invalid userid
                    # we don't have the info, so fake a UserLite
                    $poster = {
                        _type        => 'UserLite',
                        username     => undef,
                        user         => undef,
                        name         => undef,
                        journal_type => 'P',          # best guess
                    };
                }
            }

            # Comment Posted Notice
            my $same_talkid = ( $last_talkid || 0 ) == ( $dtalkid || 0 );
            my $same_jid    = ( $last_jid    || 0 ) == ( $remote ? $remote->userid : 0 );
            my $commentposted = "";
            $commentposted = 1 if $same_talkid && $same_jid;

            my $s2com = {
                '_type'    => 'Comment',
                'journal'  => $userlite_journal,
                'metadata' => {
                    'picture_keyword' => $com->{pickw},
                },
                'permalink_url' => "$permalink?thread=$dtalkid"
                    . LJ::Talk::comment_anchor($dtalkid),
                'reply_url'    => $reply_url,
                'poster'       => $poster,
                'replies'      => [],
                'subject'      => LJ::ehtml( $com->{'subject'} ),
                'subject_icon' => $subject_icon,
                'talkid'       => $dtalkid,
                'ditemid'      => $entry->ditemid,
                'text'         => $text,
                'userpic'      => $comment_userpic,
                'time'         => $datetime,
                'system_time'  => $datetime,                     # same as regular time for comments
                'edittime'     => $edittime,
                'editreason'   => $editreason,
                'tags'         => [],
                'full'         => $com->{'_loaded'} ? 1 : 0,
                'depth'        => $depth,
                'parent_url'   => $par_url,
                threadroot_url => $threadroot_url,
                'screened'     => $com->{'state'} eq "S" ? 1 : 0,
                'screened_noshow'     => 0,
                'frozen'              => $com->{'state'} eq "F" ? 1 : 0,
                'deleted'             => 0,
                'fromsuspended'       => 0,
                'link_keyseq'         => ['delete_comment'],
                'anchor'              => LJ::Talk::comment_htmlid($dtalkid),
                'dom_id'              => LJ::Talk::comment_htmlid($dtalkid),
                'comment_posted'      => $commentposted,
                'edited'              => $edited ? 1 : 0,
                'time_remote'         => $datetime_remote,
                'time_poster'         => $datetime_poster,
                'seconds_since_entry' => $seconds_since_entry,
                'edittime_remote'     => $edittime_remote,
                'edittime_poster'     => $edittime_poster,
                'edit_url'            => $edit_url,
                timeformat24          => $remote && $remote->use_24hour_time,
                'showable_children'   => $com->{'showable_children'},
                'hide_children'       => $com->{'hide_children'},
                'hidden_child'        => $com->{'hidden_child'},
                'echi'                => $com->{echi},
                admin_post            => $com->{'admin_post'} ? 1 : 0,
            };

            # don't show info from suspended users
            # FIXME: ideally the load_comments should only return these
            # items if there are children, otherwise they should be hidden entirely
            if ( $pu && $pu->is_suspended && !$viewsome ) {
                $s2com->{'fromsuspended'} = 1;
                $s2com->{'full'}          = 0;
                $s2com->{'poster'}        = undef;
                $s2com->{'userpic'}       = undef;
                $s2com->{'subject'}       = "";
                $s2com->{'subject_icon'}  = undef;
                $s2com->{'text'}          = "";
                $s2com->{'screened'}      = undef;
            }

            # don't show info for deleted comments
            if ( $com->{'state'} eq "D" ) {
                $s2com->{'deleted'}      = 1;
                $s2com->{'full'}         = 0;
                $s2com->{'poster'}       = undef;
                $s2com->{'userpic'}      = undef;
                $s2com->{'subject'}      = "";
                $s2com->{'subject_icon'} = undef;
                $s2com->{'text'}         = "";
                $s2com->{'screened'}     = undef;
            }

            # don't show info for screened comments if user can't see
            if ( $com->{'state'} eq "S" && !$com->{'_show'} ) {
                $s2com->{'screened'}        = 1;
                $s2com->{'screened_noshow'} = 1;
                $s2com->{'full'}            = 0;
                $s2com->{'poster'}          = undef;
                $s2com->{'userpic'}         = undef;
                $s2com->{'subject'}         = "";
                $s2com->{'subject_icon'}    = undef;
                $s2com->{'text'}            = "";
            }

            # Conditionally add more links to the keyseq
            my $link_keyseq = $s2com->{'link_keyseq'};
            push @$link_keyseq, $s2com->{'screened'} ? 'unscreen_comment' : 'screen_comment';
            push @$link_keyseq, $s2com->{'frozen'}   ? 'unfreeze_thread'  : 'freeze_thread';
            push @$link_keyseq, "watch_thread"    if LJ::is_enabled('esn');
            push @$link_keyseq, "unwatch_thread"  if LJ::is_enabled('esn');
            push @$link_keyseq, "watching_parent" if LJ::is_enabled('esn');
            unshift @$link_keyseq, "edit_comment" if LJ::is_enabled('edit_comments');

# always populate expand url; let get_link sort out whether this link should be printed or not
# the value of expand_url is not directly exposed via s2. It is used by the get_link backend function
            $s2com->{expand_url} = LJ::Talk::talkargs( $permalink, "thread=$dtalkid", $style_arg )
                . LJ::Talk::comment_anchor($dtalkid);
            $s2com->{thread_url} = $s2com->{expand_url} if @{ $com->{children} };

            # add the poster_ip metadata if remote user has
            # access to see it.
            $s2com->{metadata}->{poster_ip} = $com->{props}->{poster_ip}
                if $com->{props}->{poster_ip}
                && $remote
                && ( $remote->userid == $entry->posterid
                || $remote->can_manage($u)
                || $viewall );

            $s2com->{metadata}->{imported_from} = $com->{props}->{imported_from}
                if $com->{props}->{imported_from};

            push @$destlist, $s2com;

            $self->( $self, $s2com->{'replies'}, $com->{'children'}, $depth + 1 );
        }
    };
    $p->{'comments'} = [];
    $convert_comments->( $convert_comments, $p->{'comments'}, \@comments, 1 );

    # prepare the javascript data structure to put in the top of the page
    # if the remote user is a manager of the comments
    my $do_commentmanage_js = $p->{'multiform_on'} && LJ::is_enabled( 'commentmanage', $remote );

    # print comment info
    {
        my $cmtinfo = LJ::Comment->info($u);
        $cmtinfo->{form_auth} = LJ::ejs( LJ::eurl( LJ::form_auth(1) ) );

        my $recurse = sub {
            my ( $self, $array ) = @_;

            foreach my $i (@$array) {
                my $cmt = LJ::Comment->new( $u, dtalkid => $i->{talkid} );

                my $has_threads = scalar @{ $i->{'replies'} };
                my $poster      = $i->{'poster'} ? $i->{'poster'}{'username'} : "";
                my @child_ids   = map { $_->{'talkid'} } @{ $i->{'replies'} };
                $cmtinfo->{ $i->{talkid} } = {
                    rc       => \@child_ids,
                    u        => $poster,
                    parent   => $cmt->parent ? $cmt->parent->dtalkid : undef,
                    full     => ( $i->{full} ),
                    deleted  => $cmt->is_deleted,
                    screened => $cmt->is_screened,
                };
                $self->( $self, $i->{'replies'} ) if $has_threads;
            }
        };

        $recurse->( $recurse, $p->{'comments'} );

        my $js =
            "<script>\n// don't crawl this.  read http://www.livejournal.com/developer/exporting\n";
        $js .= "var LJ_cmtinfo = " . LJ::js_dumper($cmtinfo) . "\n";
        $js .= '</script>';
        $p->{'LJ_cmtinfo'} = $js if $opts->{'need_cmtinfo'};
        $p->{'head_content'} .= $js;
    }

    LJ::need_res(
        { group => "jquery" }, qw(
            js/jquery/jquery.ui.core.js
            js/jquery/jquery.ui.tooltip.js
            js/jquery.ajaxtip.js
            js/jquery/jquery.ui.button.js
            js/jquery/jquery.ui.dialog.js
            js/jquery.commentmanage.js
            js/jquery/jquery.ui.position.js
            stc/jquery/jquery.ui.core.css
            stc/jquery/jquery.ui.tooltip.css
            stc/jquery/jquery.ui.button.css
            stc/jquery/jquery.ui.dialog.css
            stc/jquery.commentmanage.css
            )
    );
    LJ::need_res( LJ::S2::tracking_popup_js() );

    # init shortcut js if selected
    LJ::Talk::init_s2journal_shortcut_js( $remote, $p );

    $p->{'_picture_keyword'} = $get->{'prop_picture_keyword'};

    $p->{'viewing_thread'} = $get->{'thread'} ? 1 : 0;
    $p->{_viewing_thread_id} = $get->{thread} ? $get->{thread} + 0 : 0;

    # default values if there were no comments, because
    # LJ::Talk::load_comments() doesn't provide them.
    my $out_error = $copts->{out_error} || '';
    if ( $out_error eq 'noposts' || scalar @comments < 1 ) {
        $copts->{'out_pages'}     = $copts->{'out_page'}     = 1;
        $copts->{'out_items'}     = 0;
        $copts->{'out_itemfirst'} = $copts->{'out_itemlast'} = undef;
    }

    my $show_expand_all =
        $u->thread_expand_all($remote) && $copts->{out_has_collapsed} && !$top_only_mode;

    # creates the comment nav bar
    $p->{'comment_nav'} = CommentNav(
        {
            'view_mode'       => $flat_mode ? "flat" : $top_only_mode ? "top-only" : "threaded",
            'url'             => $entry->url( style_opts => LJ::viewing_style_opts(%$get) ),
            'current_page'    => $copts->{'out_page'},
            'show_expand_all' => $show_expand_all,
        }
    );

    $p->{'comment_pages'} = ItemRange(
        {
            'all_subitems_displayed' => ( $copts->{'out_pages'} == 1 ),
            'current'                => $copts->{'out_page'},
            'from_subitem'           => $copts->{'out_itemfirst'},
            'num_subitems_displayed' => scalar @comments,
            'to_subitem'             => $copts->{'out_itemlast'},
            'total'                  => $copts->{'out_pages'},
            'total_subitems'         => $copts->{'out_items'},
            '_url_of'                => sub {
                my $sty = $flat_mode ? "view=flat&" : $top_only_mode ? "view=top-only&" : "";
                return
                      "$permalink?${sty}page="
                    . int( $_[0] )
                    . ( $style_arg ? "&$style_arg" : '' );
            },
        }
    );

    return $p;
}

sub EntryPage_entry {
    my ( $u, $remote, $opts ) = @_;
    my $entry = $opts->{ljentry};    # only defined in named-URI case.  otherwise undef.

    my $apache_r    = $opts->{r};
    my $uri         = $apache_r->uri;
    my $ditemid_uri = ( $uri =~ /^\/(\d+)\.html$/ ) ? 1 : 0;

    unless ( $entry || $ditemid_uri ) {
        $opts->{'handler_return'} = 404;
        return;
    }

    $entry ||= LJ::Entry->new( $u, ditemid => $1 );
    if ( $ditemid_uri && !$entry->correct_anum ) {
        $opts->{'handler_return'} = 404;
        return;
    }

    my $ditemid = $entry->ditemid;
    my $itemid  = $entry->jitemid;

    my $pu = $entry->poster;

    my $userlite_journal = UserLite($u);
    my $userlite_poster  = UserLite($pu);

    # do they have the viewall priv?
    my $get     = $opts->{'getargs'};
    my $canview = $get->{viewall} && $remote && $remote->has_priv("canview");
    my ( $viewall, $viewsome ) = ( 0, 0 );
    if ($canview) {
        ( $viewall, $viewsome ) =
            $remote->view_priv_check( $u, $get->{viewall}, 'entry', $itemid );
    }

    # check using normal rules
    unless ( $entry->visible_to( $remote, $canview ) ) {

        # check whether the entry is suspended
        if ( $pu && $pu->is_suspended && !$viewsome ) {
            $opts->{suspendeduser} = 1;
            return;
        }

        if ( $entry && $entry->is_suspended_for($remote) ) {
            $opts->{suspendedentry} = 1;
            return;
        }

        # this checks to see why the logged-in user is not allowed to see
        # the given content.
        if ( defined $remote ) {
            my $journal = $entry->journal;

            if (   $journal->is_community
                && !$journal->is_closed_membership
                && $remote
                && $entry->security ne "private" )
            {
                $apache_r->notes->{error_key}   = ".comm.open";
                $apache_r->notes->{journalname} = $journal->username;
            }
            elsif ( $journal->is_community && $journal->is_closed_membership ) {
                $apache_r->notes->{error_key}   = ".comm.closed";
                $apache_r->notes->{journalname} = $journal->username;
            }
        }

        $opts->{internal_redir} = "/protected";
        $apache_r->notes->{journalid} = $entry->journalid;
        $apache_r->notes->{returnto} = LJ::create_url( undef, keep_args => 1 );
        return;
    }

    my $style_args = LJ::viewing_style_args(%$get);

    my $userpic_position = S2::get_property_value( $opts->{ctx}, 'userpics_position' );

    # load the userpic; include the keyword selected by the user
    # as a backup for the alttext
    my $userpic;
    unless ( $userpic_position eq "none" ) {
        my ( $pic, $pickw ) = $entry->userpic;
        $userpic = Image_userpic( $pu, $pic ? $pic->picid : 0, $pickw );
    }

    my $comments = CommentInfo(
        $entry->comment_info(
            u          => $u,
            remote     => $remote,
            style_args => $style_args,
            viewall    => $viewall
        )
    );
    my $get_mode = $get->{mode} || '';
    $comments->{show_postlink} &&= $get_mode ne 'reply';
    $comments->{show_readlink} &&= $get_mode eq 'reply';

    my $subject = LJ::CleanHTML::quote_html( $entry->subject_html, $get->{nohtml} );
    my $event   = LJ::CleanHTML::quote_html( $entry->event_html,   $get->{nohtml} );

    # load tags
    my @taglist;
    $event .= TagList( $entry->tag_map, $u, $itemid, $opts, \@taglist );

    if ( $entry->security eq "public" ) {
        $LJ::REQ_GLOBAL{'text_of_first_public_post'} = $event;

        if (@taglist) {
            $LJ::REQ_GLOBAL{'tags_of_first_public_post'} = [ map { $_->{name} } @taglist ];
        }
    }

    my $s2entry = Entry(
        $u,
        {
            subject             => $subject,
            text                => $event,
            dateparts           => LJ::alldatepart_s2( $entry->eventtime_mysql ),
            system_dateparts    => LJ::alldatepart_s2( $entry->logtime_mysql ),
            security            => $entry->security,
            adult_content_level => $entry->adult_content_calculated || $u->adult_content_calculated,
            allowmask           => $entry->allowmask,
            props               => $entry->props,
            itemid              => $ditemid,
            comments            => $comments,
            journal             => $userlite_journal,
            poster              => $userlite_poster,
            tags                => \@taglist,
            new_day             => 0,
            end_day             => 0,
            userpic             => $userpic,
            userpic_style       => S2::get_property_value( $opts->{ctx}, 'entry_userpic_style' ),
            permalink_url       => $entry->url,
            timeformat24        => $remote && $remote->use_24hour_time,
            admin_post          => $entry->admin_post
        }
    );

    return ( $entry, $s2entry );
}

1;
