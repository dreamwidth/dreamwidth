#!/usr/bin/perl
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


package DW::Controller::Community;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

=head1 NAME

DW::Controller::Community - Community management pages

=cut

DW::Routing->register_string( "/communities/index", \&index_handler, app => 1 );
DW::Routing->register_string( "/communities/list", \&list_handler, app => 1 );
DW::Routing->register_string( "/communities/new", \&new_handler, app => 1 );


DW::Routing->register_redirect( "/community/index", "/communities/index" );
DW::Routing->register_redirect( "/community/manage", "/communities/list" );
DW::Routing->register_redirect( "/community/create", "/communities/new" );

sub index_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $vars = {
        remote => $rv->{remote},
        remote_admins_communities => @{LJ::load_rel_target( $rv->{remote}, 'A' ) || []} ? 1 : 0,
        community_manage_links => LJ::Hooks::run_hook( 'community_manage_links' ) || "",

        # implemented as a hook because most/all the links are to
        # dreamwidth.org-specific FAQs. see cgi-bin/DW/Hooks/Community.pm
        # in dw-nonfree as an example to create your own.
        faq_links => LJ::Hooks::run_hook( 'community_faqs' ) || "",

        # hook is to list dw-community-promo;
        # define your own in a hook if you have a similar community or want to
        # add other links to the list.
        community_search_links => LJ::Hooks::run_hook( 'community_search_links' ) || "",

        recently_active_comms => DW::Widget::RecentlyActiveComms->render,
        newly_created_comms => DW::Widget::NewlyCreatedComms->render,
        official_comms => LJ::Hooks::run_hook( 'official_comms' ) || "",
    };

    return DW::Template->render_template( 'communities/index.tt', $vars );
}

sub list_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};

    my @comms_managed = $remote->communities_managed_list;
    my @comms_moderated = $remote->communities_moderated_list;

    # 'foo' => {
    #   user      => 'foo'
    #   ljuser    => '<.... user=foo>'
    #   title     => 'Community for Foo Enthusiasts',
    #   mod_queue_count         => 123,
    #   pending_members_count   => 456,
    # }
    my %communities;

    foreach my $cu ( @comms_managed, @comms_moderated ) {
        $communities{$cu->user} = {
            user     => $cu->user,
            ljuser   => $cu->ljuser_display,
            title    => $cu->name_raw,
        };
    }

    foreach my $cu ( @comms_managed ) {
        my $comm_representation = $communities{$cu->user};
        $comm_representation->{admin} = 1;

        my $pending_members = $cu->is_moderated_membership
                                ? $cu->get_pending_members_count
                                : 0;
        $comm_representation->{pending_members_count} = $pending_members;
    }

    foreach my $cu ( @comms_moderated ) {
        my $comm_representation = $communities{$cu->user};
        $comm_representation->{moderator} = 1;

        # we don't rely on $cu->has_moderated_posting
        # because we may still have posts in the queue
        # e.g., after a switch from moderated posting to non-moderated posting
        my $mod_queue = $cu->get_mod_queue_count;
        my $should_show_queue = $cu->has_moderated_posting || $mod_queue;
        $comm_representation->{show_mod_queue_count} = $should_show_queue;
        $comm_representation->{mod_queue_count} = $cu->get_mod_queue_count
            if $should_show_queue;
    }

    my @sorted_communities = sort { $a cmp $b }
                keys %communities;
    my $vars = {
        community_list => [ @communities{@sorted_communities} ],
    };

    return DW::Template->render_template( 'communities/list.tt', $vars );
}

sub new_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    my $r = $rv->{r};
    my $post;
    my $get;

    return error_ml( 'bml.badinput.body' ) unless LJ::text_in( $post );
    return error_ml( '/communities/new.tt.error.notactive' ) unless $remote->is_visible;
    return error_ml( '/communities/new.tt.error.notconfirmed', {
            confirm_url => "$LJ::SITEROOT/register",
        }) unless $remote->is_validated;

    my %default_options = (
        membership  => 'open',
        postlevel   => 'members',
        moderated   => '0',
        nonmember_posting   => '0',
        age_restriction     => 'none'
    );

    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        $post = $r->post_args;

        # checks that the POSTed option is valid
        # if not, force it to the default option
        my $validate = sub {
            my ( $key, $regex ) = @_;

            $post->set( $key, $default_options{$key} )
                unless $post->{$key} =~ $regex;
        };

        $validate->( "membership",          qr/^(?:open|moderated|closed)$/ );
        $validate->( "postlevel",           qr/^(?:members|select)$/ );
        $validate->( "nonmember_posting",   qr/^[01]$/ );
        $validate->( "moderated",           qr/^[01]$/ );
        $validate->( "age_restriction",     qr/^(?:none|concepts|explicit)$/ );


        my $new_user = LJ::canonical_username( $post->{user} );
        my $title = $post->{title} || $new_user;

        if ( LJ::sysban_check( 'email', $remote->email_raw ) ) {
            LJ::Sysban::block( 0, "Create user blocked based on email",
                        { new_user => $new_user, email => $remote->email_raw, name => $new_user } );
            return $r->HTTP_SERVICE_UNAVAILABLE;
        }

        if ( ! $post->{user} ) {
            $errors->add( "user", ".error.user.mustenter" );
        } elsif( ! $new_user ) {
            $errors->add( "user", "error.usernameinvalid" );
        } elsif ( length $new_user > 25 ) {
            $errors->add( "user", "error.usernamelong" );
        }

        # disallow creating communities matched against the deny list
        $errors->add( "user", ".error.user.reserved" )
            if LJ::User->is_protected_username( $new_user );

        # now try to actually create the community
        my $second_submit;
        my $cu = LJ::load_user( $new_user );

        if ( $cu && $cu->is_expunged ) {
            $errors->add( "user", "widget.createaccount.error.username.purged",
                                        { aopts => "href='$LJ::SITEROOT/rename/'" } );
        } elsif ( $cu ) {
            # community was created in the last 10 minutes?
            my $recent_create = ( $cu->timecreate > (time() - (10*60)) ) ? 1 : 0;
            $second_submit = ( $cu->is_community && $recent_create
                                && $remote->can_manage_other( $cu ) ) ? 1 : 0;
            $errors->add( "user", ".error.user.inuse" ) unless $second_submit;
        }

        unless ( $errors->exist ) {
            # rate limit
            return error_ml( "/communities/new.tt.error.ratelimited" )
                unless $remote->rate_log( 'commcreate', 1 );

            $cu = LJ::User->create_community (
                    user        => $new_user,
                    status      => $remote->email_status,
                    name        => $title,
                    email       => $remote->email_raw,
                    membership  => $post->{membership},
                    postlevel   => $post->{postlevel},
                    moderated   => $post->{moderated},
                    nonmember_posting       => $post->{nonmember_posting},
                    journal_adult_settings  => $post->{age_restriction},
                ) unless $second_submit;

            return DW::Template->render_template( 'communities/new-success.tt', {
                community => {
                    ljuser  => $cu->ljuser_display,
                    user    => $cu->user,
                }
            }) if $cu;
        }
    } else {
        $get = $r->get_args;
    }

    my $vars = {
        age_restriction_enabled => LJ::is_enabled( 'adult_content' ),

        errors => $errors,
    };

    $vars->{formdata} = $post || {
                                user => $get->{user},
                                title => $get->{title},

                                # initial radio button selection
                                %default_options
                            };

    return DW::Template->render_template( 'communities/new.tt', $vars );
}

1;