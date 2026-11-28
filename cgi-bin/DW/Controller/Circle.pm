#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Controller::Circle;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;

=head1 NAME

DW::Controller::Circle - Circle management

=cut

DW::Routing->register_regex( '^/circle/(.+)/edit$', \&individual_edit_handler, app => 1 );

DW::Routing->register_redirect(
    '/manage/circle/add',
    sub { "/circle/$_[0]->{user}/edit" },
    keep_args => ["action"]
);
DW::Routing->register_redirect( '/community/join',  sub { "/circle/$_[0]->{comm}/edit" } );
DW::Routing->register_redirect( '/community/leave', sub { "/circle/$_[0]->{comm}/edit" } );

sub individual_edit_handler {
    my ( $opts, $username ) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r        = $rv->{r};
    my $remote   = $rv->{remote};
    my $get      = $r->get_args;
    my $ml_scope = "/circle/individual-edit.tt";

    my $target_u = LJ::load_user($username);
    return error_ml( "$ml_scope.error.invalidaccount", { user => LJ::ehtml($username) } )
        unless $target_u;

    if ( $target_u->is_redirect && $target_u->prop('renamedto') ) {
        return $r->redirect(
            LJ::create_url( "/circle/" . $target_u->prop('renamedto') . "/edit" ) );
    }

    my %edges;
    my $access_error          = 'Could not save access changes. Reload the page and try again.';
    my $calculate_member_edge = sub {
        my $edge = {
            show => 1,
            type => "membership",
            on   => $remote->member_of($target_u),
        };

        my $did_check_membership_type;
        $edge->{can_change} =
              $edge->{on}
            ? $remote->can_leave( $target_u, errref => \$edge->{error} )
            : $remote->can_join(
            $target_u,
            errref         => \$edge->{error},
            membership_ref => \$did_check_membership_type
            );

        # add to the error message if we have closed membership
        my $want_join                  = !$edge->{on};
        my $has_membership_limitations = !$target_u->is_open_membership;
        my $has_postlevel_limitations =
            $target_u->post_level eq 'select' && !$target_u->prop('comm_postlevel_new');

        if ( !$want_join && $has_membership_limitations ) {
            $edge->{needs_leave_warning} = $target_u->is_closed_membership ? "closed" : "moderated";
        }

        if ( $want_join && ( $has_membership_limitations || $has_postlevel_limitations ) ) {
            my $us = LJ::load_userids( $target_u->maintainer_userids );
            my @admins;
            foreach ( sort { $a->{user} cmp $b->{user} } values %$us ) {
                next unless $_ && $_->is_visible;
                push @admins, $_->ljuser_display;
            }

            if ( $target_u->is_closed_membership ) {
                $edge->{error} .= " "
                    . LJ::Lang::ml( "/circle/individual-edit.tt.error.membership_closed",
                    { admins => join ", ", @admins } );
            }
            elsif ( $target_u->is_moderated_membership && $did_check_membership_type ) {

# a bit weird here because we want to cancel out the error message if we have moderated membership
# (but only if there's not some other reason preventing us from joining the community)
# that is, it would be bad if we allowed users to request membership to moderated communities they're banned from!
                $edge->{error}                = undef;
                $edge->{moderated_membership} = 1;
                $edge->{can_change}           = 1;
            }

            # moderated posting, and new members are *not* given posting access upon joining
            if ($has_postlevel_limitations) {
                $edge->{moderated_posting} = 1;
                $edge->{admin_list}        = \@admins;
            }
        }

        $edge->{lastadmin_deletedcomm} = 1
            if $target_u->is_deleted
            && $remote->can_manage($target_u)
            && length( $target_u->maintainer_userids ) == 1;
        return $edge;
    };

    my $calculate_access_edge = sub {
        my $edge = {
            show => !$remote->equals($target_u) && $target_u->is_individual,
            type => "access",
            on   => $remote->trusts($target_u),
        };

        # always allow to remove access, but only conditionally allow to grant access
        my $error;
        my $can_trust = $remote->can_trust( $target_u, errref => \$error );
        $edge->{can_change} = $edge->{on} ? 1 : $can_trust;
        $edge->{error}      = $error unless $edge->{can_change};

# populate access filters (only allow to modify access filters if we can still grant access -- if we can't, no filters for them;
# only thing they can do is remove existing access)
        my @access_filters;
        if ($can_trust) {
            my $lock     = $remote->lock_trust_groups;
            my $groups   = $lock && $remote->trust_groups( force_database => 1 );
            my $revision = $groups ? $remote->trust_group_revision : undef;
            my $mask     = defined $revision ? $remote->trustmask_from_primary($target_u) : undef;
            if ( defined $mask ) {
                $edge->{on}             = $mask & 1;
                $edge->{group_revision} = $revision;
                foreach my $filter (
                    sort {
                               $a->{sortorder} <=> $b->{sortorder}
                            || $a->{groupname} cmp $b->{groupname}
                    } values %$groups
                    )
                {
                    my $bit = $filter->{groupnum};
                    push @access_filters,
                        {
                        label    => $filter->{groupname},
                        name     => "bit_$bit",
                        selected => $mask & ( 1 << $bit ),
                        };
                }
            }
            else {
                $edge->{status_error} =
                    'Could not load access filters. Reload the page and try again.';
            }
        }
        $edge->{filters} = \@access_filters;
        my $action = $get->{action} // '';
        $edge->{expand_filters} = $edge->{on} || ( $action eq "access" );
        return $edge;
    };

    my $calculate_subscribe_edge = sub {
        my $edge = {
            show => 1,
            type => "subscribe",
            on   => $remote->watches($target_u),
        };

        # always allow to remove subscription, but only conditionally allow to subscribe
        my $error;
        my $can_watch = $remote->can_watch( $target_u, errref => \$error );
        $edge->{can_change} = $edge->{on} ? 1 : $can_watch;
        $edge->{error}      = $error unless $edge->{can_change};

        # populate content filters
        my @content_filters;
        foreach my $filter (
            $can_watch
            ? sort { $a->{sortorder} <=> $b->{sortorder} } $remote->content_filters
            : ()
            )
        {
            my $ck = $filter->contains_userid( $target_u->userid )
                || ( $filter->is_default && !$edge->{on} );
            my $fid = $filter->id;
            push @content_filters,
                {
                label    => $filter->{name},
                name     => "content_$fid",
                selected => $ck,
                };
        }
        $edge->{filters} = \@content_filters;
        my $action = $get->{action} // '';
        $edge->{expand_filters} = $edge->{on} || ( $action eq "subscribe" );
        return $edge;
    };

    my $calculate_edges = sub {
        my $which = $_[0] || "all";

        # each edge hash looks like this:
        #   show => 1 / 0
        #   type => "membership",
        #   on => $remote->member_of( $target_u ),
        #   can_change => ...
        #   error => ...
        #   filters => ...
        #   (edge-specific items)

        if ( $target_u->is_community ) {
            $edges{member} = $calculate_member_edge->() if $which eq "member" || $which eq "all";
        }
        else {
            $edges{access} = $calculate_access_edge->() if $which eq "access" || $which eq "all";
        }
        $edges{subscribe} = $calculate_subscribe_edge->()
            if $which eq "subscribe" || $which eq "all";
    };

    $calculate_edges->();
    if ( $r->did_post ) {
        my $post = $r->post_args;

        my $member_status_new = $post->{"action:membership"};
        if ( $member_status_new && !$edges{member}->{error} ) {
            if ( $post->{new_state} eq "on" ) {

                # join

                # can members join this community openly?
                if ( $target_u->is_moderated_membership ) {

                    # hit up the maintainers to let them know a join was requested
                    $target_u->comm_join_request($remote);
                    $edges{member}->{status_ok} = LJ::Lang::ml("$ml_scope.success.join_request");
                }
                else {
                    # join unconditionally
                    my $joined = $remote->join_community($target_u);
                    if ($joined) {

                        # update the display status
                        $calculate_edges->("member");

                        # show success messages and links
                        my $message = LJ::Lang::ml( "$ml_scope.success.join",
                            { user => $target_u->ljuser_display } );

                        my $show_join_post_link = $target_u->hide_join_post_link ? 0 : 1;
                        my $post_url;
                        $post_url = "$LJ::SITEROOT/entry/" . $target_u->user . "/new"
                            if $show_join_post_link && $remote->can_post_to($target_u);
                        my $posting_guidelines_entry_url;
                        if ( $target_u->posting_guidelines_location eq "E" ) {
                            $posting_guidelines_entry_url = $target_u->posting_guidelines_url;
                        }
                        elsif ( $target_u->posting_guidelines_location eq "P" ) {
                            $posting_guidelines_entry_url = $target_u->profile_url;
                        }

                        if ( $post_url || $posting_guidelines_entry_url ) {
                            $message .= "<ul>";
                            $message .=
                                  "<li><a href='$post_url'>"
                                . LJ::Lang::ml("$ml_scope.success.join.actions.post")
                                . "</a></li>"
                                if $post_url;
                            $message .=
                                  "<li><a href='$posting_guidelines_entry_url'>"
                                . LJ::Lang::ml("$ml_scope.success.join.actions.guidelines")
                                . "</a></li>"
                                if $posting_guidelines_entry_url;
                            $message .= "</ul>";
                        }

                        $edges{member}->{status_ok} = $message;
                    }
                    else {
                        # show the error (from LJ::last_error)
                        $edges{member}->{status_error} = LJ::last_error();
                    }
                }

            }
            else {
                # leave
                $remote->leave_community($target_u);
                $calculate_edges->("member");
            }
        }
        my $access_state = $post->{"action:access"} ? ( $post->{new_state} // '' ) : '';
        if (   $edges{access}
            && !$edges{access}->{error}
            && ( $access_state =~ /\A(?:on|off)\z/ || $post->{"action:accessfilters"} ) )
        {
            my $saved = $remote->with_trust_groups_lock(
                sub {
                    if ( $access_state eq 'off' ) {
                        return $remote->remove_edge( $target_u, trust => {} );
                    }

                    my $current = $remote->trustmask_from_primary($target_u);
                    return 0 unless defined $current;
                    my $groups   = $remote->trust_groups( force_database => 1 ) or return 0;
                    my $revision = $remote->trust_group_revision;
                    return 0
                        unless defined $revision
                        && defined $post->{group_revision}
                        && $post->{group_revision} eq $revision;

                    my $mask = 1;
                    foreach my $bit ( 1 .. 60 ) {
                        next unless $groups->{$bit} && $post->{"bit_$bit"};
                        $mask |= 1 << $bit;
                    }
                    return $remote->add_edge(
                        $target_u,
                        trust => {
                            mask     => $mask,
                            nonotify => ( $current & 1 ) ? 1 : 0,
                        }
                    );
                }
            );
            $calculate_edges->("access");
            $edges{access}->{status_error} = $access_error unless $saved;
        }

        unless ( $edges{subscribe}->{error} ) {
            my $already_watched = $remote->watches($target_u) ? 1 : 0;

            my $did_change_subscribe         = $post->{"action:subscribe"};
            my $did_change_subscribe_filters = $post->{"action:subscribefilters"};

            my $do_subscribe = ( $did_change_subscribe && $post->{new_state} eq "on" )
                || ( $did_change_subscribe_filters && !$already_watched );
            my $do_unsubscribe    = $did_change_subscribe && $post->{new_state} eq "off";
            my $do_update_filters = $did_change_subscribe_filters || $do_subscribe;
            my $saved             = 1;

            if ($do_subscribe) {

                #my $fg = LJ::color_to_db( "#000000" );
                #my $bg = LJ::color_to_db( "#ffffff" );

                # subscribe
                $saved = $remote->add_edge(
                    $target_u,
                    watch => {

                        #   fgcolor => $fg,
                        #   bgcolor => $bg,
                        nonotify => $already_watched ? 1 : 0,
                    }
                );
            }

            if ($do_unsubscribe) {
                $saved = $remote->remove_edge(
                    $target_u,
                    watch => {
                        nonotify => $already_watched ? 0 : 1,
                    }
                );
            }

            if ( $saved && $do_update_filters ) {
                my @content_filters = $remote->content_filters;
                my $filter_id;
                foreach my $filter (@content_filters) {
                    $filter_id = $filter->id;

                    # add to filter if box was checked and user is not already in filter
                    $filter->add_row( userid => $target_u->userid )
                        if $post->{"content_$filter_id"}
                        && !$filter->contains_userid( $target_u->userid );

                    # remove from filter if box was not checked and user is in filter
                    $filter->delete_row( $target_u->userid )
                        if !$post->{"content_$filter_id"}
                        && $filter->contains_userid( $target_u->userid );
                }
            }

            $calculate_edges->("subscribe");
            $edges{subscribe}->{status_error} = 'Could not save subscription changes. Try again.'
                unless $saved;
        }
    }

    my $vars = {
        u     => $target_u,
        edges => \%edges,

        form_url => LJ::create_url(),
    };

    return DW::Template->render_template( 'circle/individual-edit.tt', $vars );
}

1;
