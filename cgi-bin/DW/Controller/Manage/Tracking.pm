#!/usr/bin/perl
#
# DW::Controller::Manage::Tracking
#
# converted /manage/tracking pages
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Tracking;

use strict;
use warnings;

use Carp qw(confess);

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Subscription;
use LJ::Entry;
use LJ::Comment;

our $ml_scope = "/tracking/manage.tt";

DW::Routing->register_string( "/manage/tracking/comments", \&comments_handler, app => 1 );
DW::Routing->register_string( "/manage/tracking/entry",    \&entry_handler,    app => 1 );
DW::Routing->register_string( "/manage/tracking/user",     \&user_handler,     app => 1 );

sub _tracking_controller {
    return ( 0, error_ml("$ml_scope.error.disabled") ) unless LJ::is_enabled('esn');

    my ( $ok, $rv ) = controller( anonymous => 0 );
    return ( 0, $rv ) unless $ok;

    my $r    = $rv->{r};
    my $get  = $r->get_args;
    my $post = $r->post_args;

    my $journalname = $post->{journal} || $get->{journal};
    return ( 0, error_ml("$ml_scope.error.nojournal") ) unless $journalname;
    my $journal = LJ::load_user($journalname);
    return ( 0, error_ml( "$ml_scope.error.invalidjournal", { journal => $journalname } ) )
        unless $journal;

    $rv->{journal} = $journal;
    return ( 1, $rv );
}

sub _validate_referer {
    my $referer = DW::Request->get->header_in("Referer");
    $referer = $LJ::SITEROOT . $referer if $referer && $referer =~ '^/';
    return undef unless DW::Controller::validate_redirect_url($referer);
    my ( $url, $args ) = ( $referer =~ /^(.*)\?(.*)$/ );
    return $referer unless $url && $args;

    # validate args
    my %args = map { split( /=/, $_ ) } split( /&/, $args );
    $args = LJ::viewing_style_args(%args);
    return $args ? "$url?$args" : $url;
}

sub _page_template {
    my ($rv) = @_;

    my $vars = {
        ret_url             => $rv->{ret_url},
        subscribe_interface => LJ::subscribe_interface(
            $rv->{remote},
            journal                        => $rv->{journal},
            categories                     => $rv->{categories},
            default_selected_notifications => $rv->{default_selected},
        )
    };

    return DW::Template->render_template( 'tracking/manage.tt', $vars );
}

sub comments_handler {
    my ( $ok, $rv ) = _tracking_controller();
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $get  = $r->get_args;
    my $post = $r->post_args;

    my $ditemid = $post->{itemid} || $get->{itemid} || $post->{ditemid} || $get->{ditemid};
    my $dtalkid = $post->{talkid} || $get->{talkid} || $post->{dtalkid} || $get->{dtalkid};
    return error_ml("$ml_scope.error.talkid") unless $dtalkid && $dtalkid =~ /^\d+$/;

    my $remote  = $rv->{remote};
    my $journal = $rv->{journal};
    my $comment = LJ::Comment->new( $journal, dtalkid => $dtalkid );

    return error_ml("$ml_scope.error.invalidcomment")
        unless $comment && $comment->visible_to($remote);
    return error_ml("$ml_scope.error.nocomment") if $comment->is_deleted;

    my $entry = $comment->entry;
    $ditemid = undef unless $ditemid =~ /^\d+$/;
    $ditemid ||= $entry->ditemid;

    # build the list of notification classes to display on this page
    my $build = sub {
        my ( $event, %opts ) = @_;
        confess "No event defined" unless $event;

        $opts{event}   = $event;
        $opts{journal} = $journal;
        $opts{flags}   = LJ::Subscription::TRACKING;

        return LJ::Subscription::Pending->new( $remote, %opts );
    };

    my $cat_title = 'Track Comments';
    my @notifs;

    my $thread_sub = $build->(
        "JournalNewComment",
        arg2             => $comment && $comment->jtalkid,
        default_selected => 1,
    );

    # $thread_sub will be disabled by subscribe_interface if it's not available;
    # but the availability also affects other form fields on the page below
    my $can_watch = $thread_sub->available_for_user;

    push @notifs, $thread_sub;
    push @notifs, $build->(
        "JournalNewComment",
        arg1             => $ditemid,
        default_selected => $can_watch ? 0 : 1,    # only if they can't watch the subthread above
    );
    push @notifs, $build->("JournalNewComment")
        if $remote->can_track_all_community_comments($journal);

    $rv->{categories}       = [ { $cat_title => \@notifs } ];
    $rv->{default_selected} = ['LJ::NotificationMethod::Email'];

    my $referer    = $r->header_in("Referer") // '';
    my ($args)     = ( $referer =~ /\?(.*)$/ );
    my %style_args = map { split( /=/, $_ ) } split( /&/, ( $args // '' ) );

    $rv->{ret_url} =
          $can_watch
        ? $comment->url( LJ::viewing_style_args(%style_args) )
        : $entry->url( style_opts => LJ::viewing_style_opts(%style_args) );

    return _page_template($rv);
}

sub entry_handler {
    my ( $ok, $rv ) = _tracking_controller();
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $get  = $r->get_args;
    my $post = $r->post_args;

    my $ditemid = $post->{itemid} || $get->{itemid} || $post->{ditemid} || $get->{ditemid};
    return error_ml("$ml_scope.error.noentry") unless $ditemid && $ditemid =~ /^\d+$/;

    my $remote  = $rv->{remote};
    my $journal = $rv->{journal};
    my $entry   = LJ::Entry->new( $journal, ditemid => $ditemid );

    return error_ml("$ml_scope.error.invalidentry") unless $entry && $entry->valid;
    return error_ml("$ml_scope.error.hiddenentry")  unless $entry->visible_to($remote);

    # build the list of notification classes to display on this page
    my $build = sub {
        my ( $event, %opts ) = @_;
        confess "No event defined" unless $event;

        $opts{event}   = $event;
        $opts{journal} = $journal;
        $opts{flags}   = LJ::Subscription::TRACKING;

        return LJ::Subscription::Pending->new( $remote, %opts );
    };

    my $entry_cat_title   = 'Track Entry';
    my $journal_cat_title = 'Track Journal';

    my @e_notifs = (
        $build->( "JournalNewComment",           arg1 => $ditemid, default_selected => 1 ),
        $build->( "JournalNewComment::TopLevel", arg1 => $ditemid, default_selected => 0 ),
    );

    my @j_notifs;

    # all comments in a community
    push @j_notifs, $build->("JournalNewComment")
        if $remote->can_track_all_community_comments($journal);
    push @j_notifs, $build->("JournalNewEntry");

    # passing arg1 => '?' here is a magic invocation for tracking by entry tag
    push @j_notifs, $build->( "JournalNewEntry", arg1 => '?', entry => $entry );

    # new community entries by a specific poster
    push @j_notifs, $build->( "JournalNewEntry", arg2 => $entry->posterid )
        if $journal->is_community;

    $rv->{categories} =
        [ { $entry_cat_title => \@e_notifs }, { $journal_cat_title => \@j_notifs } ];
    $rv->{default_selected} = ['LJ::NotificationMethod::Email'];

    my $referer    = $r->header_in("Referer") // '';
    my ($args)     = ( $referer =~ /\?(.*)$/ );
    my %style_args = map { split( /=/, $_ ) } split( /&/, ( $args // '' ) );

    $rv->{ret_url} = $entry->url( style_opts => LJ::viewing_style_opts(%style_args) );

    return _page_template($rv);
}

sub user_handler {
    my ( $ok, $rv ) = _tracking_controller();
    return $rv unless $ok;

    my $remote  = $rv->{remote};
    my $journal = $rv->{journal};

    my $r = $rv->{r};
    return $r->redirect("$LJ::SITEROOT/manage/settings/?cat=notifications")
        if $remote->equals($journal);

    # build the list of notification classes to display on this page
    my $build = sub {
        my ( $event, $disabled, $arg1 ) = @_;
        confess "No event defined" unless $event;

        return LJ::Subscription::Pending->new(
            $remote,
            journal  => $journal,
            flags    => LJ::Subscription::TRACKING,
            event    => $event,
            arg1     => $arg1,
            disabled => $disabled,
        );
    };

    my $cat_title = 'Track User';
    my @notifs;

    # passing arg1 => '?' here is a magic invocation for tracking by entry tag
    push @notifs, $build->( "JournalNewEntry", undef, '?' ) if $journal->is_visible;
    push @notifs, $build->("JournalNewEntry") if $journal->is_visible;
    push @notifs, $build->("UserExpunged") unless LJ::User->is_protected_username( $journal->user );
    push @notifs, $build->("JournalNewComment")
        if $remote->can_track_all_community_comments($journal) && $journal->is_visible;
    push @notifs, $build->( "NewUserpic", !$remote->can_track_new_userpic ) if $journal->is_visible;
    push @notifs, $build->("Birthday") if $journal->is_visible;

    $rv->{categories} = [ { $cat_title => \@notifs } ];
    $rv->{ret_url}    = _validate_referer();

    return _page_template($rv);
}

1;
