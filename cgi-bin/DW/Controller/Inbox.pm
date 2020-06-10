package DW::Controller::Inbox;
use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use LJ::Hooks;
use Data::Dumper;

DW::Routing->register_string( '/inbox', \&index_handler,    app => 1 );
DW::Routing->register_rpc( "inbox_actions",  \&action_handler,  format => 'html' );

my $PAGE_LIMIT = 15;

sub index_handler {
    my ($ok, $rv) = controller( form_auth => 1);
    return $rv unless $ok;

    my $r = $rv->{r};
    my $POST = $r->post_args;
    my $GET = $r->get_args;
    my $remote = $rv->{remote};
    my $vars;
    my $scope = '/inbox/index.tt';

    return error_ml("$scope.error.not_ready") unless $remote->can_use_esn;

    my $inbox = $remote->notification_inbox
        or return error_ml("$scope.error.couldnt_retrieve_inbox", { 'user' => $remote->{user} });

    # Take a supplied filter but default it to undef unless it is valid
    my $view = $GET->{view} || $POST->{view} || undef;
    $view = undef if $view eq 'archive' && ! LJ::is_enabled('esn_archive');
    $view = undef if $view && !LJ::NotificationInbox->can("${view}_items");
    $view ||= 'all';

    my $itemid = $view eq "singleentry" ? int( $POST->{itemid} || $GET->{itemid} || 0 ) : 0;
    my $expand = $GET->{expand};

    my $page = int($POST->{page} || $GET->{page} || 1);
    my @errors;
    if ($r->did_post) {
        warn Dumper($r);
        my $action;

        if ($POST->{mark_read}) {
            $action = 'mark_read';
        } elsif ($POST->{mark_unread}) {
            $action = 'mark_unread';
        } elsif ($POST->{delete_all}) {
            $action = 'delete_all';
        } elsif ($POST->{mark_all}) {
            $action = 'mark_all';
        } elsif ($POST->{delete}) {
            $action = 'delete';
        }
        my @item_ids;
        for my $key (keys %{$POST}) {
            next unless $key =~ /check_(\d+)/;
            push @item_ids, $POST->{$key};
        }
        handle_post($remote, $action, $view, $itemid, \@item_ids);
    }

        # Allow bookmarking to work without Javascript
    # or before JS events are bound
    if ($GET->{bookmark_off} && $GET->{bookmark_off} =~ /^\d+$/) {
        push @errors, LJ::Lang::ml('.error.max_bookmarks')
            unless $inbox->add_bookmark($GET->{bookmark_off});
    }
    if ($GET->{bookmark_on} && $GET->{bookmark_on} =~ /^\d+$/) {
        $inbox->remove_bookmark($GET->{bookmark_on});
    }
    # Pagination

    my $viewarg = $view  ? "&view=$view" : "";
    my $itemidarg = $itemid ? "&itemid=$itemid" : "";

    # Filter by view if specified
    my @all_items = @{items_by_view($inbox, $view, $itemid)};

    my $itemcount = scalar @all_items;

    my $user_messsaging = LJ::is_enabled('user_messaging');
    $vars->{user_messaging} = $user_messsaging;
    $vars->{view} = $view;
    $vars->{itemcount} = $itemcount;

    my @children = (
        { view => 'circle', label => 'circle_updates', unread => $inbox->circle_event_count, children => [
            {view => 'birthday', label => 'birthdays'}, {view => 'encircled', label => 'encircled'}
        ] },
        {view => 'entrycomment', label => 'entries_and_comments', unread =>  $inbox->entrycomment_event_count},
        {view => 'pollvote', label => 'poll_votes', unread =>  $inbox->pollvote_event_count },
        {view => 'communitymembership', label => 'community_membership', unread =>  $inbox->communitymembership_event_count },
        {view => 'sitenotices', label => 'site_notices', unread =>   $inbox->sitenotices_event_count}


    );

    if ($user_messsaging) {
        # push links for recieved PMs and sent PMs to the beginning and end of the list, respectively
        unshift @children, { view => 'usermsg_recvd', label => 'messages', unread => $inbox->usermsg_recvd_event_count };
        push @children,         {view => 'usermsg_sent', label => 'sent', unread =>   $inbox->usermsg_sent_event_count};
    };
    push @children, {view => 'bookmark', label => 'bookmarks', unread =>   $inbox->bookmark_count};
    push @children, {view => 'archived', label => 'archive'} if LJ::is_enabled('esn_archive');

    $vars->{folder_links} = {view => 'all', label => 'all', unread =>  $inbox->all_event_count, children => \@children };

    # pagination

    $page = 1 if $page < 1;
    my $last_page = POSIX::ceil( ( scalar @all_items ) / $PAGE_LIMIT );
    $last_page ||= 1;
    $page = $last_page if $page > $last_page;

    $vars->{page} = $page;
    $vars->{last_page} = $last_page;


    $vars->{item_html} = render_items( $page, $view, $remote, \@all_items, $expand );

        # choose button text depending on whether user is viewing all emssages or only a subfolder
    # to avoid any confusion as to what deleting and marking read will do
    my $mark_all_text   = "";
    my $delete_all_text = "";
    if ( $view eq "all" ) {
        $mark_all_text   = ".menu.mark_all_read.btn";
        $delete_all_text = ".menu.delete_all.btn";
    }
    elsif ( $view eq "singleentry" ) {
        $mark_all_text   = "widget.inbox.menu.mark_all_read.entry.btn";
        $delete_all_text = "widget.inbox.menu.delete_all.entry.btn";
    }
    else {
        $mark_all_text   = "widget.inbox.menu.mark_all_read.subfolder.btn";
        $delete_all_text = "widget.inbox.menu.delete_all.subfolder.btn";
    }

    $vars->{mark_all} = $mark_all_text;
    $vars->{delete_all} = $delete_all_text;
    $vars->{img} = &LJ::img;


    return DW::Template->render_template( 'inbox/index.tt', $vars );
}

sub render_items {
    my ($page, $view, $remote, $items_ref, $expand ) = @_;

    my $inbox = $remote->notification_inbox
        or return error_ml("/inbox/index.tt.error.couldnt_retrieve_inbox", { 'user' => $remote->{user} });
    my $starting_index = ( $page - 1 ) * $PAGE_LIMIT;
    my $ending_index = $starting_index + $PAGE_LIMIT;
    my @display_items = @$items_ref;
    @display_items = sort { $b->when_unixtime <=> $a->when_unixtime } @display_items;
    @display_items = @display_items[$starting_index..$ending_index];

    my @cleaned_items;
    foreach my $item (@display_items){
        last unless $item;
        my $cleaned = {
            'qid'        => $item->qid,
            'title'      => $item->title,
            'read'       => ($item->read ? "read" : "unread"),

        };
        my $bookmark = 'bookmark_' . ( $inbox->is_bookmark($item->qid) ? "on" : "off" );
        $cleaned->{bookmark_img} = LJ::img($bookmark, "", {'class' => 'item_bookmark'});
        $cleaned->{bookmark} = $bookmark;
        # For clarity, we display both a relative time (e.g. "5 days ago")
        # and an absolute time (e.g. "2019-05-11 14:34 UTC") in the
        # notification list.
        my $event_time    = $item->when_unixtime;
        $cleaned->{rel_time} = LJ::diff_ago_text($event_time);
        $cleaned->{abs_time} = LJ::S2::sitescheme_secs_to_iso( $event_time, { tz => "UTC" } );

        my $contents = $item->as_html || '';

        my $expanded   = '';

        if ($contents) {
            BML::ebml( \$contents );

            my $is_expanded = $expand && $expand == $item->qid;
            $is_expanded ||= $remote->prop('esn_inbox_default_expand');
            $is_expanded = 0 if $item->read;

            $is_expanded = 1 if ( $view eq "usermsg_sent_last" );
            $expanded = $is_expanded ? "inbox_expand" : "inbox_collapse";

        }
        $cleaned->{expanded_img} = LJ::img($expanded, "", {'class' => 'item_expand'});
        $cleaned->{expanded} = $expanded;
        $cleaned->{contents} = $contents;
        push @cleaned_items, $cleaned;

    }

    my $vars = {messages => \@cleaned_items,
                page => $page};

    return DW::Template->template_string( 'inbox/msg_list.tt', $vars );

}

sub action_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    # gets the request and args
    my $r        = $rv->{r};
    my $args     = $r->json;
    my $action  = $args->{action};
    my $ids = $args->{'ids'};
    my $view = $args->{view} || 'all';
    my $page = $args->{page} || 1;
    my $itemid = $args->{itemid} || 0;
    my $remote = LJ::get_remote();
    my $form_auth  = $args->{lj_form_auth};
    my $expand;

    if ($action eq 'expand') {
        $expand = $ids;
    } else {
        handle_post($remote, $action, $view, $itemid, $ids);
    }

    my $inbox = $remote->notification_inbox;
    my $display_items = items_by_view($inbox, $view, $itemid);
    my $items_html = render_items($page, $view, $remote, $display_items, $expand);

    $r->print( $items_html );
    return $r->OK;

}

sub handle_post {
    my ($remote, $action, $view, $itemid, $item_ids) = @_;
    my @errors;

    my $inbox = $remote->notification_inbox
        or return error_ml("/inbox/index.tt.error.couldnt_retrieve_inbox", { 'user' => $remote->{user} });
    return 0 unless $action;

    if ($action eq 'mark_all') {
        $inbox->mark_all_read( $view, itemid => $itemid );
    } elsif ($action eq 'delete_all') {
        $inbox->delete_all( $view, itemid => $itemid );
    } elsif ($action eq 'bookmark_off') {
        push @errors, LJ::Lang::ml('.error.max_bookmarks')
            unless $inbox->add_bookmark($item_ids);
    } elsif($action eq 'bookmark_on') {
        $inbox->remove_bookmark($item_ids);
    } else {
        foreach my $id (@$item_ids) {
            my $item = LJ::NotificationItem->new($remote, $id);
            next unless $item->valid;

            if ($action eq 'mark_read') {
                $item->mark_read;
            } elsif ($action eq 'mark_unread') {
                $item->mark_unread;
            } elsif ($action eq 'delete') {
                $item->delete;
            }
        }

    }
    return 1;

}

sub items_by_view {
    my ($inbox, $view, $itemid) = @_;

    $itemid ||= 0;
    my @all_items;
    if ($view) {
        if ( $view eq "singleentry" ) {
            @all_items = $inbox->singleentry_items( $itemid );
        } else {
            @all_items = eval "\$inbox->${view}_items";
        }
    } else {
        @all_items = $inbox->all_items;
    }
    return \@all_items;
}

1;