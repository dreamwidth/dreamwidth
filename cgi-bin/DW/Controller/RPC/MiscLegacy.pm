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
package DW::Controller::RPC::MiscLegacy;

use strict;
use DW::Routing;
use DW::RPC;
use LJ::CreatePage;

# do not put any endpoints that do not have the "forked from LJ" header in this file
DW::Routing->register_rpc( "changerelation",     \&change_relation_handler,      format => 'json' );
DW::Routing->register_rpc( "checkforusername",   \&check_username_handler,       format => 'json' );
DW::Routing->register_rpc( "controlstrip",       \&control_strip_handler,        format => 'json' );
DW::Routing->register_rpc( "ctxpopup",           \&ctxpopup_handler,             format => 'json' );
DW::Routing->register_rpc( "esn_inbox",          \&esn_inbox_handler,            format => 'json' );
DW::Routing->register_rpc( "esn_subs",           \&esn_subs_handler,             format => 'json' );
DW::Routing->register_rpc( "getsecurityoptions", \&get_security_options_handler, format => 'json' );
DW::Routing->register_rpc( "gettags",            \&get_tags_handler,             format => 'json' );
DW::Routing->register_rpc( "load_state_codes",   \&load_state_codes_handler,     format => 'json' );
DW::Routing->register_rpc(
    "profileexpandcollapse",
    \&profileexpandcollapse_handler,
    format => 'json'
);
DW::Routing->register_rpc( "userpicselect", \&get_userpics_handler, format => 'json' );
DW::Routing->register_rpc( "widget",        \&widget_handler,       format => 'json' );

sub change_relation_handler {
    my $r    = DW::Request->get;
    my $post = $r->post_args;

    # get user
    my $remote = LJ::get_remote();
    return DW::RPC->err("Sorry, you must be logged in to use this feature.")
        unless $remote;

    return DW::RPC->err("Invalid auth token")
        unless $remote->check_ajax_auth_token( '/__rpc_changerelation', %$post );

    my ( $target, $action );
    $target = $post->{target} or return DW::RPC->err("No target specified");
    $action = $post->{action} or return DW::RPC->err("No action specified");

    # Prevent XSS attacks
    $target = LJ::ehtml($target);
    $action = LJ::ehtml($action);

    my $targetu = LJ::load_user($target);
    return DW::RPC->err("Invalid user $target")
        unless $targetu;

    my $success = 0;
    my %ret     = ();

    if ( $action eq 'addTrust' ) {
        my $error;
        return DW::RPC->err($error)
            unless $remote->can_trust( $targetu, errref => \$error );

        $success = $remote->add_edge( $targetu, trust => {} );
    }
    elsif ( $action eq 'addWatch' ) {
        my $error;
        return DW::RPC->err($error)
            unless $remote->can_watch( $targetu, errref => \$error );

        $success = $remote->add_edge( $targetu, watch => {} );

        $success &&= $remote->add_to_default_filters($targetu);
    }
    elsif ( $action eq 'removeTrust' ) {
        $success = $remote->remove_edge( $targetu, trust => {} );
    }
    elsif ( $action eq 'removeWatch' ) {
        $success = $remote->remove_edge( $targetu, watch => {} );
    }
    elsif ( $action eq 'join' ) {
        my $error;
        if ( $remote->can_join( $targetu, errref => \$error ) ) {
            $success = $remote->join_community($targetu);
        }
        else {
            if (   $error eq LJ::Lang::ml('edges.join.error.targetnotopen')
                && $targetu->is_moderated_membership )
            {
                $targetu->comm_join_request($remote);
                $ret{note} = LJ::Lang::ml('/community/join.bml.reqsubmitted.body');
            }
            else {
                return DW::RPC->err($error);
            }
        }
    }
    elsif ( $action eq 'leave' ) {
        my $error;
        return DW::RPC->err($error)
            unless $remote->can_leave( $targetu, errref => \$error );

        $success = $remote->leave_community($targetu);
    }
    elsif ( $action eq 'accept' ) {
        $success = $remote->accept_comm_invite($targetu);
    }
    elsif ( $action eq 'setBan' ) {
        my $list_of_banned = LJ::load_rel_user( $remote, 'B' ) || [];

        return DW::RPC->err("Exceeded limit maximum of banned users")
            if @$list_of_banned >= ( $LJ::MAX_BANS || 5000 );

        my $ban_user = LJ::load_user($target);
        $success = $remote->ban_user($ban_user);
        LJ::Hooks::run_hooks( 'ban_set', $remote, $ban_user );
    }
    elsif ( $action eq 'setUnban' ) {
        my $unban_user = LJ::load_user($target);
        $success = $remote->unban_user_multi( $unban_user->{userid} );
    }
    else {
        return DW::RPC->err("Invalid action $action");
    }

    return DW::RPC->out(
        success     => $success,
        is_trusting => $remote->trusts($targetu),
        is_watching => $remote->watches($targetu),
        is_member   => $remote->member_of($targetu),
        is_banned   => $remote->has_banned($targetu),
        %ret,
    );
}

sub check_username_handler {
    my $r     = DW::Request->get;
    my $args  = $r->get_args;
    my $error = LJ::CreatePage->verify_username( $args->{user} );

    return DW::RPC->err($error);
}

sub control_strip_handler {
    my $r    = DW::Request->get;
    my $args = $r->get_args;

    my $control_strip;
    my $user = $args->{user};
    if ( defined $user ) {
        unless ( defined LJ::get_active_journal() ) {
            LJ::set_active_journal( LJ::load_user($user) );
        }
        $control_strip = LJ::control_strip(
            user => $user,
            host => $args->{host},
            uri  => $args->{uri},
            args => $args->{args},
            view => $args->{view}
        );
    }

    return DW::RPC->out( control_strip => $control_strip );
}

sub ctxpopup_handler {
    my $r   = DW::Request->get;
    my $get = $r->get_args;

    my $get_user = sub {

        # three ways to load a user:

        # username:
        if ( defined $get->{user} && ( my $user = LJ::canonical_username( $get->{user} ) ) ) {
            return LJ::load_user($user);
        }

        # identity:
        if ( defined $get->{userid} && ( my $userid = $get->{userid} ) ) {
            return undef unless $userid =~ /^\d+$/;
            my $u = LJ::load_userid($userid);
            return undef unless $u && $u->identity;
            return $u;
        }

        # based on userpic url
        if ( defined $get->{userpic_url} && ( my $upurl = $get->{userpic_url} ) ) {
            return undef unless $upurl =~ m!(\d+)/(\d+)!;
            my ( $picid, $userid ) = ( $1, $2 );
            my $u  = LJ::load_userid($userid);
            my $up = LJ::Userpic->instance( $u, $picid );
            return $up->valid ? $u : undef;
        }
    };

    my $remote = LJ::get_remote();
    my $u      = $get_user->();
    my %ret    = $u ? $u->info_for_js : ();
    my $reason = $u ? $u->prop('delete_reason') : '';
    $reason = $reason ? "Reason given: " . $reason : "No reason given.";

    return DW::RPC->err("Error: Invalid mode")
        unless $get->{mode} eq 'getinfo';
    return DW::RPC->out( error => "No such user", noshow => 1 )
        unless $u;
    return DW::RPC->err( "This user's account is deleted.<br />" . $reason )
        if $u->is_deleted;
    return DW::RPC->err("This user's account is deleted and purged.")
        if $u->is_expunged;
    return DW::RPC->err("This user's account is suspended.")
        if $u->is_suspended;

    # uri for changerelation auth token
    my $uri = '/__rpc_changerelation';

    # actions to generate auth tokens for
    my @actions = ();

    $ret{url_addtrust} = "$LJ::SITEROOT/circle/" . $u->{user} . "/edit?action=access";
    $ret{url_addwatch} = "$LJ::SITEROOT/circle/" . $u->{user} . "/edit?action=subscribe";

    my $up = $u->userpic;
    if ($up) {
        $ret{url_userpic} = $up->url;
        $ret{userpic_w}   = $up->width;
        $ret{userpic_h}   = $up->height;
    }
    else {
        # if it's a feed, make their userpic the feed icon
        if ( $u->is_syndicated ) {
            $ret{url_userpic} = "$LJ::IMGPREFIX/feed100x100.png";
        }
        elsif ( $u->is_identity ) {
            $ret{url_userpic} = "$LJ::IMGPREFIX/identity_100x100.png";
        }
        else {
            $ret{url_userpic} = "$LJ::IMGPREFIX/nouserpic.png";
        }
        $ret{userpic_w} = 100;
        $ret{userpic_h} = 100;
    }

    if ($remote) {
        $ret{is_trusting}        = $remote->trusts($u);
        $ret{is_trusted_by}      = $u->trusts($remote);
        $ret{is_watching}        = $remote->watches($u);
        $ret{is_watched_by}      = $u->watches($remote);
        $ret{is_requester}       = $remote->equals($u);
        $ret{other_is_identity}  = $u->is_identity;
        $ret{self_is_identity}   = $remote->is_identity;
        $ret{can_message}        = $u->can_receive_message($remote);
        $ret{url_message}        = $u->message_url;
        $ret{can_receive_vgifts} = $u->can_receive_vgifts_from($remote);
        $ret{url_vgift}          = $u->virtual_gift_url;
    }

    $ret{is_logged_in} = $remote ? 1 : 0;

    if ( $u->is_comm ) {
        $ret{url_joincomm}         = "$LJ::SITEROOT/circle/" . $u->{user} . "/edit";
        $ret{url_leavecomm}        = "$LJ::SITEROOT/circle/" . $u->{user} . "/edit";
        $ret{url_acceptinvite}     = "$LJ::SITEROOT/manage/invites";
        $ret{is_member}            = $remote->member_of($u) if $remote;
        $ret{is_closed_membership} = $u->is_closed_membership;
        my $pending = $remote ? ( $remote->get_pending_invites || [] ) : [];
        $ret{is_invited} = ( grep { $_->[0] == $u->id } @$pending ) ? 1 : 0;

        push @actions, 'join', 'leave', 'accept';
    }

    # generate auth tokens
    if ($remote) {
        push @actions, 'addTrust', 'addWatch', 'removeTrust', 'removeWatch', 'setBan', 'setUnban';
        foreach my $action (@actions) {
            $ret{"${action}_authtoken"} = $remote->ajax_auth_token(
                $uri,
                target => $u->user,
                action => $action,
            );
        }
    }

    my %extrainfo = LJ::Hooks::run_hook( "ctxpopup_extra_info", $u ) || ();
    %ret = ( %ret, %extrainfo ) if %extrainfo;

    $ret{is_banned} = $remote->has_banned($u) ? 1 : 0 if $remote;

    $ret{success} = 1;
    return DW::RPC->out(%ret);
}

sub esn_inbox_handler {
    my $r    = DW::Request->get;
    my $post = $r->post_args;

    my $remote = LJ::get_remote();
    return DW::RPC->err("Sorry, you must be logged in to use this feature.")
        unless $remote;

    my $authas = delete $post->{authas};

    my $action = $post->{action};
    return DW::RPC->err("No action specified") unless $action;

    my $success = 0;
    my %ret;

    # do authas
    my $u = LJ::get_authas_user($authas) || $remote;
    return DW::RPC->err("You could not be authenticated as the specified user.")
        unless $u;

    # get qids
    my @qids;
    @qids = split( ',', $post->{qids} ) if $post->{qids};

    my @items;

    if ( scalar @qids ) {
        foreach my $qid (@qids) {
            my $item = eval { LJ::NotificationItem->new( $u, $qid ) };
            push @items, $item if $item;
        }
    }

    $ret{items} = [];
    my $inbox      = $u->notification_inbox;
    my $cur_folder = $post->{cur_folder} || 'all';
    my $itemid     = $post->{itemid} && $post->{itemid} =~ /^\d+$/ ? $post->{itemid} + 0 : 0;

    # do actions
    if ( $action eq 'mark_read' ) {
        $_->mark_read foreach @items;
        $success = 1;
    }
    elsif ( $action eq 'mark_unread' ) {
        $_->mark_unread foreach @items;
        $success = 1;
    }
    elsif ( $action eq 'delete' ) {
        foreach my $item (@items) {
            push @{ $ret{items} }, { qid => $item->qid, deleted => 1 };
            $item->delete;
        }

        $success = 1;
    }
    elsif ( $action eq 'delete_all' ) {
        @items = $inbox->delete_all( $cur_folder, itemid => $itemid );

        foreach my $item (@items) {
            push @{ $ret{items} }, { qid => $item->{qid}, deleted => 1 };
        }

        $success = 1;
    }
    elsif ( $action eq 'mark_all_read' ) {
        $inbox->mark_all_read( $cur_folder, itemid => $itemid );

        $success = 1;
    }
    elsif ( $action eq 'set_default_expand_prop' ) {
        $u->set_prop( 'esn_inbox_default_expand', $post->{default_expand} eq 'Y' ? 'Y' : 'N' );
    }
    elsif ( $action eq 'get_unread_items' ) {
        $ret{unread_count} = $u->notification_inbox->unread_count;
    }
    elsif ( $action eq 'toggle_bookmark' ) {
        my $up;
        $up = LJ::Hooks::run_hook( 'upgrade_message', $u, 'bookmark' );
        $up = "<br />$up" if ($up);

        foreach my $item (@items) {
            my $ret = $u->notification_inbox->toggle_bookmark( $item->qid );
            return DW::RPC->err("Max number of bookmarks reached.$up") unless $ret;
        }
        $success = 1;
    }
    else {
        return DW::RPC->err("Invalid action $action");
    }

    foreach my $item ( $u->notification_inbox->items ) {
        my $class = $item->event->class;
        $class =~ s/LJ::Event:://;
        push @{ $ret{items} },
            {
            read       => $item->read,
            qid        => $item->qid,
            bookmarked => $u->notification_inbox->is_bookmark( $item->qid ),
            category   => $class,
            };
    }

    return DW::RPC->out(
        success              => $success,
        unread_all           => $inbox->all_event_count,
        unread_usermsg_recvd => $inbox->usermsg_recvd_event_count,
        unread_friend        => $inbox->circle_event_count,
        unread_entrycomment  => $inbox->entrycomment_event_count,
        unread_pollvote      => $inbox->pollvote_event_count,
        unread_usermsg_sent  => $inbox->usermsg_sent_event_count,
        %ret,
    );
}

sub esn_subs_handler {
    my $r    = DW::Request->get;
    my $post = $r->post_args;

    return DW::RPC->err("Sorry async ESN is not enabled") unless LJ::is_enabled('esn_ajax');

    my $remote = LJ::get_remote();
    return DW::RPC->err("Sorry, you must be logged in to use this feature.")
        unless $remote;

    # check auth token
    return DW::RPC->err("Invalid auth token")
        unless $remote->check_ajax_auth_token( '/__rpc_esn_subs', %$post );

    my $action  = $post->{action} or return DW::RPC->err("No action specified");
    my $success = 0;
    my %ret;

    if ( $action eq 'delsub' ) {
        my $subid  = $post->{subid} or return DW::RPC->err("No subid");
        my $subscr = LJ::Subscription->new_by_id( $remote, $subid );
        return DW::RPC->out( success => 0 )
            unless $subscr;

        my %postauth;
        foreach my $subkey (qw(journalid arg1 arg2 etypeid)) {
            $ret{$subkey}      = $subscr->$subkey || 0;
            $postauth{$subkey} = $ret{$subkey} if $ret{$subkey};
        }

        $ret{event_class} = $subscr->event_class;

        $subscr->delete;
        $success         = 1;
        $ret{msg}        = "Notification Tracking Removed";
        $ret{subscribed} = 0;

        my $auth_token = $remote->ajax_auth_token(
            '/__rpc_esn_subs',
            action => 'addsub',
            %postauth,
        );

        if ( $subscr->event_class eq 'LJ::Event::JournalNewEntry' ) {
            $ret{newentry_token} = $auth_token;
        }
        else {
            $ret{auth_token} = $auth_token;
        }
    }
    elsif ( $action eq 'addsub' ) {

        return DW::RPC->err(
            "Reached limit of " . $remote->count_max_subscriptions . " active notifications" )
            unless $remote->can_add_inbox_subscription;

        my %subparams = ();

        return DW::RPC->err("Invalid notification tracking parameters")
            unless ( defined $post->{journalid} ) && $post->{etypeid} + 0;

        foreach my $param (qw(journalid etypeid arg1 arg2)) {
            $subparams{$param} = $post->{$param} + 0;
        }

        $subparams{method} = 'Inbox';

        my ($subscr) = $remote->has_subscription(%subparams);

        $subparams{flags} = LJ::Subscription::TRACKING;
        eval { $subscr ||= $remote->subscribe(%subparams) };
        return DW::RPC->err($@) if $@;

        if ($subscr) {
            $subscr->activate;
            $success          = 1;
            $ret{msg}         = "Notification Tracking Added";
            $ret{subscribed}  = 1;
            $ret{event_class} = $subscr->event_class;
            my %sub_info = $subscr->sub_info;
            $ret{sub_info} = \%sub_info;

            # subscribe to email as well
            my %email_sub_info = %sub_info;
            $email_sub_info{method} = "Email";
            $remote->subscribe(%email_sub_info);

            # special case for JournalNewComment: need to return dtalkid for
            # updating of tracking icons (on subscriptions with jtalkid)
            if ( $subscr->event_class eq 'LJ::Event::JournalNewComment' && $subscr->arg2 ) {
                my $cmt = LJ::Comment->new( $subscr->journal, jtalkid => $subscr->arg2 );
                $ret{dtalkid} = $cmt->dtalkid if $cmt;
            }

            my $auth_token = $remote->ajax_auth_token(
                '/__rpc_esn_subs',
                subid  => $subscr->id,
                action => 'delsub'
            );

            if ( $subscr->event_class eq 'LJ::Event::JournalNewEntry' ) {
                $ret{newentry_token} = $auth_token;
                $ret{newentry_subid} = $subscr->id;
            }
            else {
                $ret{auth_token} = $auth_token;
                $ret{subid}      = $subscr->id;
            }
        }
        else {
            $success = 0;
            $ret{subscribed} = 0;
        }
    }
    else {
        return DW::RPC->err("Invalid action $action");
    }

    return DW::RPC->out(
        success => $success,
        %ret,
    );
}

sub get_security_options_handler {
    my $r    = DW::Request->get;
    my $args = $r->get_args;

    my $remote = LJ::get_remote();
    my $user   = $args->{user};
    my $u      = LJ::load_user($user);

    return DW::RPC->out
        unless $u;

    my %ret = (
        is_comm => $u->is_comm ? 1 : 0,
        can_manage => $remote && $remote->can_manage($u) ? 1 : 0,
    );

    return DW::RPC->out( ret => \%ret )
        unless $remote && $remote->can_post_to($u);

    unless ( $ret{is_comm} ) {
        my $friend_groups = $u->trust_groups;
        $ret{friend_groups_exist} = keys %$friend_groups ? 1 : 0;
    }

    $ret{minsecurity} = $u->newpost_minsecurity;

    return DW::RPC->out( ret => \%ret );
}

sub get_tags_handler {
    my $r    = DW::Request->get;
    my $args = $r->get_args;

    my $remote = LJ::get_remote();
    my $user   = $args->{user};
    my $u      = LJ::load_user($user);
    my $tags   = $u ? $u->tags : {};

    return DW::RPC->alert("You cannot view this journal's tags.")
        unless $remote && $remote->can_post_to($u);
    return DW::RPC->alert("You cannot use this journal's tags.")
        unless $remote->can_add_tags_to($u);

    my @tag_names;
    if ( keys %$tags ) {
        @tag_names = map  { $_->{name} } values %$tags;
        @tag_names = sort { lc $a cmp lc $b } @tag_names;
    }

    return DW::RPC->out( tags => \@tag_names );
}

sub load_state_codes_handler {
    my $r    = DW::Request->get;
    my $post = $r->post_args;

    my $country = $post->{country};
    return DW::RPC->err("no country parameter") unless $country;

    my %states;
    my $states_type = $LJ::COUNTRIES_WITH_REGIONS{$country}->{type};
    LJ::load_codes( { $states_type => \%states } ) if defined $states_type;

    return DW::RPC->out(
        states => [
            map { $_, $states{$_} }
                sort { $states{$a} cmp $states{$b} }
                keys %states
        ],
        head => LJ::Lang::ml('states.head.defined'),
    );
}

sub profileexpandcollapse_handler {
    my $r   = DW::Request->get;
    my $get = $r->get_args;

    # if any opts aren't defined, they'll be passed in as empty strings
    # (actually header and expand are sometimes undefined in my testing,
    #  hence the updates below.  --kareila 2015/08/19)
    my $mode = $get->{mode} eq "save" ? "save" : "load";
    my $header = ( defined $get->{header} && $get->{header} eq "" )      ? undef : $get->{header};
    my $expand = ( defined $get->{expand} && $get->{expand} eq "false" ) ? 0     : 1;

    my $remote = LJ::get_remote();
    return unless $remote;

    if ( $mode eq "save" ) {
        return unless $header && $header =~ /_header$/;
        $header =~ s/_header$//;

        my %is_collapsed = map { $_ => 1 } split( /,/, $remote->prop("profile_collapsed_headers") );

        # this header is already saved as expanded or collapsed, so we don't need to do anything
        return if $is_collapsed{$header}  && !$expand;
        return if !$is_collapsed{$header} && $expand;

        # remove header from list if expanding
        # add header to list if collapsing
        if ($expand) {
            delete $is_collapsed{$header};
            $remote->set_prop( profile_collapsed_headers => join( ",", keys %is_collapsed ) );
        }
        else {    # collapse
            $is_collapsed{$header} = 1;
            $remote->set_prop( profile_collapsed_headers => join( ",", keys %is_collapsed ) );
        }
    }
    else {        # load
        my $profile_collapsed_headers = $remote->prop("profile_collapsed_headers") // '';
        return DW::RPC->out( headers => [ split( /,/, $profile_collapsed_headers ) ] );
    }
}

sub get_userpics_handler {
    my $r   = DW::Request->get;
    my $get = $r->get_args;

    my $remote = LJ::get_remote();

    my $alt_u;
    $alt_u = LJ::load_user( $get->{user} )
        if $get->{user} && $remote->has_priv("supporthelp");

    # get user
    my $u = ( $alt_u || $remote );
    return DW::RPC->alert("Sorry, you must be logged in to use this feature.")
        unless $u;

    # get userpics
    my @userpics = LJ::Userpic->load_user_userpics($u);

    my %upics = ();    # info to return
    $upics{pics} = {}; # upicid -> hashref of metadata

    foreach my $upic (@userpics) {
        next if $upic->inactive;

        my $id = $upic->id;
        $upics{pics}{$id} = {
            url    => $upic->url,
            state  => $upic->state,
            width  => $upic->width,
            height => $upic->height,

            # we don't want the full version of alttext here, because the keywords, etc
            # will already likely be displayed by the icon

            # We don't want to use ehtml, because we want the JSON converter
            # handle escaping ", ', etc. We just escape the < and > ourselves
            alt => LJ::etags( $upic->description ),

            comment => LJ::strip_html( $upic->comment ),

            id       => $id,
            keywords => [ map { LJ::strip_html($_) } $upic->keywords ],
        };
    }

    $upics{ids} = [ sort { $a <=> $b } keys %{ $upics{pics} } ];

    return DW::RPC->out(%upics);
}

sub widget_handler {
    my $r    = DW::Request->get;
    my $get  = $r->get_args;
    my $post = $r->post_args;

    return DW::RPC->err("Sorry widget AJAX is not enabled")
        unless LJ::is_enabled('widget_ajax');

    my $remote       = LJ::get_remote();
    my $widget_class = LJ::ehtml( $post->{_widget_class} || $get->{_widget_class} );
    return DW::RPC->err("Invalid widget class $widget_class")
        unless $widget_class =~ /^(IPPU::)?\w+$/gm;
    $widget_class = "LJ::Widget::$widget_class";

    return DW::RPC->err("Cannot do AJAX request to $widget_class")
        unless $widget_class->ajax;

    # hack to circumvent a bigip/perlbal interaction
    # that sometimes closes keepalive POST requests under
    # certain conditions. accepting GETs makes it work fine
    if ( %$get && $widget_class->can_fake_ajax_post ) {
        $post->clear;
        $post->{$_} = $get->{$_} foreach keys %$get;
    }

    my $widget_id   = $post->{_widget_id};
    my $widget_ippu = $post->{_widget_ippu};
    my $doing_post  = delete $post->{_widget_post};

    my %ret = (
        _widget_id    => $widget_id,
        _widget_class => $widget_class,
    );

    # make sure that we're working with the right user
    if ( $post->{authas} ) {
        if ( $widget_class->authas ) {
            my $u = LJ::get_authas_user( $post->{authas} );
            return DW::RPC->err("Invalid user.") unless $u;
        }
        else {
            return DW::RPC->err("Widget does not support authas authentication.");
        }
    }

    if ($doing_post) {

        # just a normal post request, handle it and then return status

        local $LJ::WIDGET_NO_AUTH_CHECK = 1
            if LJ::Auth->check_ajax_auth_token( $remote, "/_widget",
            auth_token => delete $post->{auth_token} );

        my %res;

        # set because LJ::Widget->handle_post uses this global variable
        @BMLCodeBlock::errors = ();
        eval { %res = LJ::Widget->handle_post( $post, $widget_class ); };

        $ret{res}          = \%res;
        $ret{errors}       = $@ ? [$@] : \@BMLCodeBlock::errors;
        $ret{_widget_post} = 1;

        # generate new auth token for future requests if succesfully checked auth token
        $ret{auth_token} = LJ::Auth->ajax_auth_token( $remote, "/_widget" )
            if $LJ::WIDGET_NO_AUTH_CHECK;
    }

    if ( delete $post->{_widget_update} ) {

        # render the widget and return it

        # remove the widget prefix from the POST vars
        foreach my $key ( keys %$post ) {
            my $orig_key = $key;
            if ( $key =~ s/^Widget\[\w+?\]_// ) {
                $post->{$key} = $post->{$orig_key};
                delete $post->{$orig_key};
            }
        }
        $ret{_widget_body}   = eval { $widget_class->render_body(%$post); };
        $ret{_widget_body}   = "Error: $@" if $@;
        $ret{_widget_update} = 1;
    }

    return DW::RPC->out(%ret);
}

1;
