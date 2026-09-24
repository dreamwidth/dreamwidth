#!/usr/bin/perl
#
# DW::Controller::Inbox
#
# Pages for exporting journal content.
#
# Authors:
#      Ruth Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2015-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Inbox;

use v5.10;
use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use LJ::Hooks;

# Canonical native inbox URLs. /inbox and /inbox/ are registered separately
# (like /poll and /poll/ in DW::Controller::Poll) so neither auto-redirects
# to the other; /inbox/index covers the .bml-suffix-stripped form of the
# retained /inbox/index.bml link.
DW::Routing->register_string( '/inbox',       \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string( '/inbox/',      \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string( '/inbox/index', \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string( '/inbox/compose',  \&compose_handler,  app => 1 );
DW::Routing->register_string( '/inbox/markspam', \&markspam_handler, app => 1 );

# Retained old links are routed to the same handlers (not register_redirect):
# a GET there still redirects to the canonical URL (see _redirect_old_get
# below), but a POST must never hit a redirect, since a 303/302 turns a
# browser's POST into a bodyless GET and silently discards the submission.
# The trailing-slash form is registered explicitly with no_redirects too,
# since register_string's own default page/ -> page redirect is just as
# body-dropping for a POST as the register_redirect it replaces.
DW::Routing->register_string( '/inbox/new',  \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string( '/inbox/new/', \&index_handler, app => 1, no_redirects => 1 );
DW::Routing->register_string(
    '/inbox/new/compose', \&compose_handler,
    app          => 1,
    no_redirects => 1
);
DW::Routing->register_string(
    '/inbox/new/compose/', \&compose_handler,
    app          => 1,
    no_redirects => 1
);
DW::Routing->register_string(
    '/inbox/new/markspam', \&markspam_handler,
    app          => 1,
    no_redirects => 1
);
DW::Routing->register_string(
    '/inbox/new/markspam/', \&markspam_handler,
    app          => 1,
    no_redirects => 1
);

DW::Routing->register_rpc( 'inbox_actions', \&action_handler, format => 'json' );

my $PAGE_LIMIT = 15;

# A GET to a retained /inbox/new* link still redirects to its canonical URL;
# a POST there must fall through and be handled natively by the caller
# instead, since a redirect response would silently drop the submitted body.
# $r->uri is the raw request path: routing strips a trailing ".bml" only for
# matching purposes, so an explicit old-link.bml hit (or a trailing slash)
# must be matched here too, or it would render natively without ever
# canonicalizing.
sub _redirect_old_get {
    my ( $r, $old_uri, $canonical ) = @_;
    return undef unless $r->method eq 'GET';
    return undef unless $r->uri =~ m{^\Q$old_uri\E(?:\.bml)?/?$};
    return $r->redirect( LJ::create_url( $canonical, keep_args => 1 ) );
}

# Take a supplied filter but default it to 'all' unless it is a real,
# callable NotificationInbox view method. This is the only validation that
# makes items_by_view's method-name lookup below safe to call.
sub _validated_view {
    my ($view) = @_;
    return 'all' unless defined $view && length $view;
    $view = undef if $view              && $view =~ /\W/;
    $view = undef if $view eq 'archive' && !LJ::is_enabled('esn_archive');
    $view = undef if $view              && !LJ::NotificationInbox->can("${view}_items");
    return $view || 'all';
}

sub index_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    if ( my $redirect = _redirect_old_get( $r, '/inbox/new', '/inbox' ) ) {
        return $redirect;
    }
    my $POST   = $r->post_args;
    my $GET    = $r->get_args;
    my $remote = $rv->{remote};
    my $vars;
    my $scope  = '/inbox/index.tt';
    my $errors = DW::FormErrors->new;

    return error_ml("$scope.error.not_ready") unless $remote->can_use_esn;

    my $inbox = $remote->notification_inbox
        or return error_ml( "$scope.error.couldnt_retrieve_inbox", { user => $remote->{user} } );

    my $view = _validated_view( $GET->{view} || $POST->{view} );

    my $itemid = $view eq "singleentry" ? int( $POST->{itemid} || $GET->{itemid} || 0 ) : 0;
    my $expand = $GET->{expand};

    my $page = int( $POST->{page} || $GET->{page} || 1 );
    if ( $r->did_post ) {
        my $action;

        if ( $POST->{mark_read} ) {
            $action = 'mark_read';
        }
        elsif ( $POST->{mark_unread} ) {
            $action = 'mark_unread';
        }
        elsif ( $POST->{delete_all} ) {
            $action = 'delete_all';
        }
        elsif ( $POST->{mark_all} ) {
            $action = 'mark_all';
        }
        elsif ( $POST->{delete} ) {
            $action = 'delete';
        }
        my @item_ids;
        for my $key ( keys %{$POST} ) {
            next unless $key =~ /check_(\d+)/;
            push @item_ids, $POST->{$key};
        }
        my $res = handle_post( $remote, $action, $view, $itemid, \@item_ids );
        unless ( $res->{success} ) {
            for my $error ( @{ $res->{errors} } ) {
                $errors->add_string( undef, $error );
            }
        }
    }

    # Allow bookmarking to work without Javascript or before JS events are
    # bound. This mutates state via a plain GET, so (unlike a POST) it is
    # not covered by controller's automatic form_auth check above and needs
    # its own token, validated against msg_list.tt's rendered links.
    my $bookmark_link_auth = LJ::check_form_auth( $GET->{lj_form_auth} );
    my $bookmark_toggled;
    if ( $GET->{bookmark_off} && $GET->{bookmark_off} =~ /^\d+$/ && $bookmark_link_auth ) {
        if ( $inbox->add_bookmark( $GET->{bookmark_off} ) ) {
            $bookmark_toggled = 1;
        }
        else {
            $errors->add( undef, "$scope.error.max_bookmarks" );
        }
    }
    if ( $GET->{bookmark_on} && $GET->{bookmark_on} =~ /^\d+$/ && $bookmark_link_auth ) {
        $inbox->remove_bookmark( $GET->{bookmark_on} );
        $bookmark_toggled = 1;
    }

    # Once the one-time token has done its job, drop it (and the toggle
    # params) from the address bar/history rather than leave a live CSRF
    # token sitting in a bookmarked or shared URL.
    if ($bookmark_toggled) {
        my %clean_args;
        $clean_args{page}   = $page   if $GET->{page};
        $clean_args{view}   = $view   if $view && $view ne 'all';
        $clean_args{itemid} = $itemid if $itemid;
        return $r->redirect( LJ::create_url( '/inbox', args => \%clean_args ) );
    }

    # Pagination

    my $viewarg   = $view   ? "&view=$view"     : "";
    my $itemidarg = $itemid ? "&itemid=$itemid" : "";

    # Filter by view if specified
    my @all_items = @{ items_by_view( $inbox, $view, $itemid ) };

    my $itemcount = scalar @all_items;
    $vars->{view}      = $view;
    $vars->{itemcount} = $itemcount;

    # pagination

    $page = 1 if $page < 1;
    my $last_page = POSIX::ceil( ( scalar @all_items ) / $PAGE_LIMIT );
    $last_page ||= 1;
    $page = $last_page if $page > $last_page;

    $vars->{page}      = $page;
    $vars->{last_page} = $last_page;

    $vars->{item_html}   = render_items( $page, $view, $remote, \@all_items, $expand );
    $vars->{folder_html} = render_folders( $remote, $view );

    # choose button text depending on whether user is viewing all emssages or only a subfolder
    # to avoid any confusion as to what deleting and marking read will do
    my $mark_all_text   = "";
    my $delete_all_text = "";
    if ( $view eq "all" ) {
        $mark_all_text   = "widget.inbox.menu.mark_all_read.btn";
        $delete_all_text = "widget.inbox.menu.delete_all.btn";
    }
    elsif ( $view eq "singleentry" ) {
        $mark_all_text   = "widget.inbox.menu.mark_all_read.entry.btn";
        $delete_all_text = "widget.inbox.menu.delete_all.entry.btn";
        $vars->{itemid}  = $itemid;
    }
    else {
        $mark_all_text   = "widget.inbox.menu.mark_all_read.subfolder.btn";
        $delete_all_text = "widget.inbox.menu.delete_all.subfolder.btn";
    }

    $vars->{mark_all}   = $mark_all_text;
    $vars->{delete_all} = $delete_all_text;
    $vars->{errors}     = $errors;

    return DW::Template->render_template( 'inbox/index.tt', $vars );
}

sub render_items {
    my ( $page, $view, $remote, $items_ref, $expand ) = @_;

    my $inbox = $remote->notification_inbox
        or return error_ml( "/inbox/index.tt.error.couldnt_retrieve_inbox",
        { 'user' => $remote->{user} } );
    my $starting_index = ( $page - 1 ) * $PAGE_LIMIT;
    my $ending_index   = $starting_index - 1 + $PAGE_LIMIT;
    my @display_items  = @$items_ref;
    @display_items = sort { $b->when_unixtime <=> $a->when_unixtime } @display_items;
    @display_items = @display_items[ $starting_index .. $ending_index ];

    my @cleaned_items;
    foreach my $item (@display_items) {
        last unless $item;
        my $cleaned = {
            'qid'   => $item->qid,
            'title' => $item->title,
            'read'  => ( $item->read ? "read" : "unread" ),

        };
        my $bookmark = 'bookmark_' . ( $inbox->is_bookmark( $item->qid ) ? "on" : "off" );
        $cleaned->{bookmark_img} = LJ::img( $bookmark, "", { 'class' => 'item_bookmark' } );
        $cleaned->{bookmark}     = $bookmark;

        # For clarity, we display both a relative time (e.g. "5 days ago")
        # and an absolute time (e.g. "2019-05-11 14:34 UTC") in the
        # notification list.
        my $event_time = $item->when_unixtime;
        $cleaned->{rel_time} = LJ::diff_ago_text($event_time);
        $cleaned->{abs_time} = LJ::S2::sitescheme_secs_to_iso( $event_time, { tz => "UTC" } );

        my $contents = $item->as_html || '';

        my $expanded = '';

        if ($contents) {
            LJ::ehtml( \$contents );

            my $is_expanded = $expand && $expand == $item->qid;
            $is_expanded ||= $remote->prop('esn_inbox_default_expand');
            $is_expanded = 0 if $item->read;

            $is_expanded = 1 if ( $view eq "usermsg_sent_last" );
            $expanded    = $is_expanded ? "inbox_expand" : "inbox_collapse";

        }
        $cleaned->{expanded_img} = LJ::img( $expanded, "", { 'class' => 'item_expand' } );
        $cleaned->{expanded}     = $expanded;
        $cleaned->{contents}     = $contents;
        push @cleaned_items, $cleaned;

    }

    my $vars = {
        messages => \@cleaned_items,
        page     => $page,
        view     => $view,

        # These no-JS bookmark toggle links mutate state via a plain GET, so
        # they need their own CSRF token; index_handler validates it. Escape
        # it here since it is embedded directly into a query string.
        form_auth_token => LJ::eurl( LJ::form_auth(1) ),
    };

    return DW::Template->template_string( 'inbox/msg_list.tt', $vars );

}

sub render_folders {
    my ( $remote, $view ) = @_;
    my $user_messsaging = LJ::is_enabled('user_messaging');
    my $inbox           = $remote->notification_inbox
        or return error_ml( "/inbox/index.tt.error.couldnt_retrieve_inbox",
        { 'user' => $remote->{user} } );

    my $vars;

    my @children = (
        {
            view     => 'circle',
            label    => 'circle_updates',
            unread   => $inbox->circle_event_count,
            children => [
                { view => 'birthday',  label => 'birthdays' },
                { view => 'encircled', label => 'encircled' }
            ]
        },
        {
            view   => 'entrycomment',
            label  => 'entries_and_comments',
            unread => $inbox->entrycomment_event_count
        },
        { view => 'pollvote', label => 'poll_votes', unread => $inbox->pollvote_event_count },
        {
            view   => 'communitymembership',
            label  => 'community_membership',
            unread => $inbox->communitymembership_event_count
        },
        {
            view   => 'sitenotices',
            label  => 'site_notices',
            unread => $inbox->sitenotices_event_count
        }

    );

    if ($user_messsaging) {

       # push links for recieved PMs and sent PMs to the beginning and end of the list, respectively
        unshift @children,
            {
            view   => 'usermsg_recvd',
            label  => 'messages',
            unread => $inbox->usermsg_recvd_event_count
            };
        push @children,
            { view => 'usermsg_sent', label => 'sent', unread => $inbox->usermsg_sent_event_count };
    }

    # put 'unread' at the very top
    unshift @children, { view => 'unread', label => 'unread', unread => $inbox->all_event_count };
    push @children, { view => 'bookmark', label => 'bookmarks', unread => $inbox->bookmark_count };
    push @children, { view => 'archived', label => 'archive' } if LJ::is_enabled('esn_archive');

    $vars->{folder_links} = {
        view     => 'all',
        label    => 'all',
        unread   => $inbox->all_event_count,
        children => \@children
    };
    $vars->{user_messaging} = $user_messsaging;
    $vars->{view}           = $view;
    return DW::Template->template_string( 'inbox/folders.tt', $vars );
}

sub action_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    # gets the request and args
    my $r         = $rv->{r};
    my $args      = $r->json;
    my $action    = $args->{action};
    my $ids       = $args->{'ids'};
    my $view      = _validated_view( $args->{view} );
    my $page      = $args->{page} || 1;
    my $itemid    = $args->{itemid} || 0;
    my $remote    = $rv->{remote};
    my $form_auth = $args->{lj_form_auth};
    my $expand;

    if ( $action eq 'expand' ) {
        $expand = $ids;
    }
    else {
        return DW::RPC->err( LJ::Lang::ml('/inbox/index.tt.error.invalidform') )
            unless LJ::check_form_auth($form_auth);
        my $res = handle_post( $remote, $action, $view, $itemid, $ids );
        unless ( $res->{success} ) {
            return DW::RPC->out( errors => $res->{errors} );
        }
    }

    my $getextra = {};
    if ( $view eq 'singleentry' ) {
        $getextra->{view}   = $view;
        $getextra->{itemid} = $itemid;

    }
    elsif ( $view ne 'all' ) {
        $getextra->{view} = $view;
    }

    my $inbox       = $remote->notification_inbox;
    my $folder_html = render_folders( $remote, $view );

    # if we've removed items from the view, we need to rebuild the list and recalculate pages
    if ( $action eq 'delete' || $action eq 'delete_all' ) {

        my $display_items = items_by_view( $inbox, $view, $itemid );
        my $last_page     = POSIX::ceil( ( scalar @$display_items ) / $PAGE_LIMIT );
        $last_page ||= 1;
        $page = $last_page if $page > $last_page;

        my $items_html = render_items( $page, $view, $remote, $display_items, $expand );
        my $path       = "/inbox";
        my $pages_html = DW::Template->template_string( 'components/pagination.tt',
            { current => $page, total_pages => $last_page, path => $path, cur_args => $getextra } );

        return DW::RPC->out(
            success => {
                items        => $items_html,
                folders      => $folder_html,
                pages        => $pages_html,
                unread_count => $inbox->unread_count
            }
        );
    }
    else {
        return DW::RPC->out(
            success => {
                unread_count => $inbox->unread_count,
                folders      => $folder_html,
            }
        );
    }
}

sub handle_post {
    my ( $remote, $action, $view, $itemid, $item_ids ) = @_;
    my @errors;

    my $inbox = $remote->notification_inbox
        or return error_ml( "/inbox/index.tt.error.couldnt_retrieve_inbox",
        { 'user' => $remote->{user} } );
    return { 'errors' => ["No action specified!"] } unless $action;

    if ( $action eq 'mark_all' ) {
        $inbox->mark_all_read( $view, itemid => $itemid );
    }
    elsif ( $action eq 'delete_all' ) {
        $inbox->delete_all( $view, itemid => $itemid );
    }
    elsif ( $action eq 'bookmark_off' ) {
        push @errors, LJ::Lang::ml("/inbox/index.tt.error.max_bookmarks")
            unless $inbox->add_bookmark($item_ids);
    }
    elsif ( $action eq 'bookmark_on' ) {
        $inbox->remove_bookmark($item_ids);
    }
    else {
        foreach my $id (@$item_ids) {
            my $item = LJ::NotificationItem->new( $remote, $id );
            next unless $item->valid;

            if ( $action eq 'mark_read' ) {
                $item->mark_read;
            }
            elsif ( $action eq 'mark_unread' ) {
                $item->mark_unread;
            }
            elsif ( $action eq 'delete' ) {
                $item->delete;
            }
        }

    }

    if (@errors) {
        return { 'errors' => \@errors };
    }
    else {
        return { 'success' => 1 };
    }

}

sub items_by_view {
    my ( $inbox, $view, $itemid ) = @_;

    $itemid ||= 0;
    my @all_items;
    if ($view) {
        if ( $view eq "singleentry" ) {
            @all_items = $inbox->singleentry_items($itemid);
        }
        else {
            my $method = $inbox->can("${view}_items");
            @all_items = $method ? $inbox->$method() : ();
        }
    }
    else {
        @all_items = $inbox->all_items;
    }

    return \@all_items;
}

sub compose_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    # gets the request and args
    my $r = $rv->{r};
    if ( my $redirect = _redirect_old_get( $r, '/inbox/new/compose', '/inbox/compose' ) ) {
        return $redirect;
    }
    my $POST   = $r->post_args;
    my $GET    = $r->get_args;
    my $remote = $rv->{remote};
    my $errors = DW::FormErrors->new;

    my $scope = '/inbox/compose.tt';

    return $r->msg_redirect( LJ::Lang::ml("$scope.messaging.disabled"),
        $r->ERROR, "$LJ::SITEROOT/inbox" )
        unless LJ::is_enabled('user_messaging');

    # Legacy (htdocs/inbox/compose.bml) required a validated sender before
    # allowing composition; this was dropped in the native port.
    return $r->msg_redirect(
        LJ::Lang::ml(
            'protocol.not_validated', { sitename => $LJ::SITENAMESHORT, siteroot => $LJ::SITEROOT }
        ),
        $r->ERROR,
        "$LJ::SITEROOT/inbox"
    ) unless $remote->is_validated;

    return $r->msg_redirect( LJ::Lang::ml('.suspended.cannot.send'), $r->ERROR,
        "$LJ::SITEROOT/inbox" )
        if $remote->is_suspended;

    my $remote_id = $remote->{userid};
    my $reply_to;    # User replying to
    my $reply_u;     # User replying to
    my $disabled_to = 0;     # disable To field if sending a reply message
    my $msg_subject = '';    # reply subject
    my $msg_body    = '';    # reply body
    my $msg_parent  = '';    # Hidden msg field containing id of parent message
    my $msg_limit     = $remote->count_usermessage_length;
    my $subject_limit = 255;
    my $force = 0;           # flag for if user wants to force an empty PM

    # Submitted message
    if ( $r->did_post ) {
        my $mode = $POST->{'mode'};

        if ( $mode eq 'send' ) {

            # test encoding
            $msg_subject = $POST->{'msg_subject'};
            $errors->add( 'msg_subject', "$scope.error.text.encoding.subject" )
                unless LJ::text_in($msg_subject);
            my ( $subject_length_b, $subject_length_c ) = LJ::text_length($msg_subject);
            $errors->add(
                'msg_subject',
                "$scope.error.subject.length",
                {
                    subject_length => LJ::commafy($subject_length_c),
                    subject_limit  => LJ::commafy($subject_limit),
                }
            ) unless $subject_length_c <= $subject_limit;

            # test encoding and length
            $msg_body = $POST->{'msg_body'};
            $errors->add( 'msg_body', "$scope.error.text.encoding.text" )
                unless LJ::text_in($msg_body);
            my ( $msg_len_b, $msg_len_c ) = LJ::text_length($msg_body);
            $errors->add(
                'msg_body',
                ".error.message.length",
                {
                    msg_length => LJ::commafy($msg_len_c),
                    msg_limit  => LJ::commafy($msg_limit)
                }
            ) unless ( $msg_len_c <= $msg_limit );

            # checks if the PM is empty (no text)
            $force = $POST->{'force'};
            unless ( $msg_len_c > 0 || $force ) {
                $errors->add( 'msg_body', '.warning.empty.message' );
                $force = 1;
            }

            # Get list of recipients
            my $to_field = $POST->{'msg_to'};
            $to_field =~ s/\s//g;

            # Get recipient list without duplicates
            my %to_hash = map { lc($_), 1 } split( ",", $to_field );
            my @to_list = keys %to_hash;

            # must be at least one username
            $errors->add( 'msg_to', "$scope.error.no.username" ) unless ( scalar(@to_list) > 0 );

            push @to_list, $remote->username if $POST->{'cc_msg'};
            my @msg_list;

            # persist the default value of the cc_msg option
            $remote->cc_msg( $POST->{'cc_msg'} ? 1 : 0 );

            # Check each user being sent a message
            foreach my $to (@to_list) {

                # Check the To field
                my $tou = LJ::load_user_or_identity($to);
                unless ($tou) {
                    $errors->add( 'msg_to', "$scope.error.invalid.username", { to => $to } );
                    next;
                }

                # Can only send to other individual users
                unless ( $tou->is_person || $tou->is_identity || $tou->is_renamed ) {
                    $errors->add( 'msg_to', 'error.message.individual',
                        { ljuser => $tou->ljuser_display } );
                    next;
                }

                # Can't send to unvalidated users
                unless ( $tou->is_validated || $remote->has_priv( "siteadmin", "*" ) ) {
                    $errors->add( 'msg_to', 'error.message.unvalidated',
                        { ljuser => $tou->ljuser_display } );
                    next;
                }

                # Will target user accept messages from sender
                unless ( $tou->can_receive_message($remote) ) {

                    $errors->add( 'msg_to', 'error.message.canreceive',
                        { ljuser => $tou->ljuser_display } );
                    next;
                }

                my $msguserpic;
                $msguserpic = $POST->{'prop_picture_keyword'}
                    if ( defined $POST->{'prop_picture_keyword'} );

                push @msg_list,
                    LJ::Message->new(
                    {
                        journalid    => $remote_id,
                        otherid      => $tou->{userid},
                        subject      => $msg_subject,
                        body         => $msg_body,
                        parent_msgid => $POST->{'msg_parent'} || undef,
                        userpic      => $msguserpic,
                    }
                    );

            }

            # Check that the rate limit will not be exceeded
            # This is only necessary if there are multiple recipients
            if ( scalar(@msg_list) > 1 ) {
                my $up;
                $up = LJ::Hooks::run_hook( 'upgrade_message', $remote, 'message' );
                $up = "<br />$up" if ($up);
                $errors->add( undef, ".error.rate.limit", { up => $up } )
                    unless LJ::Message::ratecheck_multi(
                    userid   => $remote_id,
                    msg_list => \@msg_list
                    );
            }

            # check if any of the messages will throw an error
            unless ( $errors->exist ) {
                my @errors;
                foreach my $msg (@msg_list) {
                    $msg->can_send( \@errors );
                }
                foreach my $error (@errors) {
                    $errors->add_string( undef, $error );
                }
            }

            # send all the messages and display confirmation
            unless ( $errors->exist ) {
                my @errors;
                foreach my $msg (@msg_list) {
                    $msg->send( \@errors );
                }
                foreach my $error (@errors) {
                    $errors->add_string( undef, $error );
                }
                return $r->msg_redirect( LJ::Lang::ml("$scope.message.sent"),
                    $r->SUCCESS, "$LJ::SITEROOT/inbox" )
                    unless $errors->exist;
            }
        }
    }

    # Sending a reply to a message
    if ( ( $GET->{mode} && $GET->{mode} eq 'reply' ) || $POST->{'msgid'} ) {
        my $msgid = $GET->{'msgid'} || $POST->{'msgid'};
        next unless $msgid;

        my $msg = LJ::Message->load( { msgid => $msgid, journalid => $remote_id } );

        return $r->msg_redirect( LJ::Lang::ml("$scope.error.cannot.reply"),
            $r->ERROR, "$LJ::SITEROOT/inbox" )
            unless $msg->can_reply( $msgid, $remote_id );

        $reply_u     = $msg->other_u;
        $reply_to    = $reply_u->display_name;
        $disabled_to = 1;
        $msg_subject = $msg->subject_raw || "(no subject)";
        $msg_subject = "Re: " . $msg_subject
            unless $msg_subject =~ /Re: /;
        $msg_body = $msg->body_raw;
        $msg_body =~ s/(.{70}[^\s]*)\s+/$1\n/g;
        $msg_body =~ s/(^.*)/\> $1/gm;
        $msg_body = "\n\n--- $reply_to wrote:\n" . $msg_body;
        $msg_parent .= LJ::html_hidden(
            {
                name  => 'msg_parent',
                value => "$msgid",
            }
        );
    }

    # autocomplete To field with trusted and watched people
    my @flist = ();
    if ( LJ::isu($remote) ) {
        my %trusted_and_watched_userids =
            map { $_ => 1 } ( $remote->trusted_userids, $remote->watched_userids );
        my $us = LJ::load_userids( keys %trusted_and_watched_userids );
        @flist =
            map  { $us->{$_}->display_name }
            grep { $us->{$_}->is_personal || $us->{$_}->is_identity }
            keys %trusted_and_watched_userids;
    }

    # Are we sending a copy of the message to the user?
    my $cc_msg_option = $remote->cc_msg;

    my $current_icon_kw = $POST->{prop_picture_keyword};
    my $current_icon    = LJ::Userpic->new_from_keyword( $remote, $current_icon_kw );

    my $vars = {
        errors          => $errors,
        msg_to          => ( $POST->{msg_to} || $GET->{'user'} || undef ),
        msg_body        => $msg_body,
        msg_subject     => $msg_subject,
        msg_parent      => $msg_parent,
        reply_u         => $reply_u,
        reply_to        => $reply_to,
        autocomplete    => \@flist,
        cc_msg_option   => $cc_msg_option,
        disabled_to     => $disabled_to,
        folder_html     => render_folders($remote),
        commafy         => \&LJ::commafy,
        remote          => $remote,
        msg_limit       => $msg_limit,
        subject_limit   => $subject_limit,
        current_icon_kw => $current_icon_kw,
        current_icon    => $current_icon,
        force           => $force
    };

    return DW::Template->render_template( 'inbox/compose.tt', $vars );

}

sub markspam_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    # gets the request and args
    my $r = $rv->{r};
    if ( my $redirect = _redirect_old_get( $r, '/inbox/new/markspam', '/inbox/markspam' ) ) {
        return $redirect;
    }
    my $POST   = $r->post_args;
    my $GET    = $r->get_args;
    my $remote = $rv->{remote};
    my $errors = DW::FormErrors->new;

    my $remote_id = $remote->{'userid'};
    my $msg_id    = $GET->{msgid} || $POST->{msgid};
    my $msg       = LJ::Message->load( { msgid => $msg_id, journalid => $remote_id } );

    return $r->msg_redirect( "Message cannot be loaded.", $r->ERROR, "$LJ::SITEROOT/inbox" )
        unless $msg && $msg->valid;

    return $r->msg_redirect( "You cannot report a message you sent as spam.",
        $r->ERROR, "$LJ::SITEROOT/inbox" )
        if $msg->type eq "out";

    return $r->msg_redirect( "You are not allowed to report messages as spam.",
        $r->ERROR, "$LJ::SITEROOT/inbox" )
        if LJ::sysban_check( 'spamreport', $remote->user );

    if ( $r->did_post && $POST->{'confirm'} ) {

        # Some action must be selected
        $errors->add_string( undef, 'No action selected' )
            unless ( $POST->{spam} || $POST->{'ban'} );

        return DW::Template->render_template( 'inbox/markspam.tt',
            { errors => $errors, msg_user => $msg->other_u, msgid => $msg_id } )
            if $errors->exist;

        # Mark as spam
        if ( $POST->{spam} ) {
            $r->add_msg( "Message marked as spam.", $r->SUCCESS )
                if $msg->mark_as_spam;
        }

        # Ban user
        if ( $POST->{'ban'} ) {
            LJ::set_rel( $remote_id, $msg->otherid, 'B' );
            $remote->log_event( 'ban_set', { actiontarget => $msg->otherid, remote => $remote } );
            $r->add_msg( "User banned.", $r->SUCCESS );
        }
        return $r->redirect("$LJ::SITEROOT/inbox");
    }
    my $vars = {
        errors   => $errors,
        msg_user => $msg->other_u,
        msgid    => $msg_id,
    };

    return DW::Template->render_template( 'inbox/markspam.tt', $vars );

}
1;
