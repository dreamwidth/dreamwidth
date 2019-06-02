#!/usr/bin/perl
#
# DW::Controller::InviteCodes
#
# Tools for managing invite codes, including generating an image
# that shows the current status of a given invite code.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::InviteCodes;

use strict;
use DW::Routing;
use DW::Template;
use DW::Controller;

use DW::InviteCodes;
use DW::InviteCodeRequests;
use DW::BusinessRules::InviteCodeRequests;

DW::Routing->register_string( '/invite/index', \&management_handler, app => 1 );

sub management_handler {
    my $r = DW::Request->get;
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};

    # check whether we requested more invite codes
    if ( $r->did_post ) {
        my $args = $r->post_args;
        return error_ml('error.invalidform')
            unless LJ::check_form_auth( $args->{lj_form_auth} );

        if ( DW::InviteCodeRequests->create( userid => $remote->id, reason => $args->{reason} ) ) {
            $rv->{req_yes} = 1;
        }
        else {
            $rv->{req_no} = 1;
        }
    }

    $rv->{print_req_form} = DW::BusinessRules::InviteCodeRequests::can_request( user => $remote );
    $rv->{view_full}      = $r->get_args->{full};

    my @invitecodes = DW::InviteCodes->by_owner( userid => $remote->id );

    my @recipient_ids;
    foreach my $code (@invitecodes) {
        push @recipient_ids, $code->recipient if $code->recipient;
    }

    my $recipient_users = LJ::load_userids(@recipient_ids);

    unless ( $rv->{view_full} ) {

        # filter out codes that were used over two weeks ago
        my $two_weeks_ago = time() - ( 14 * 24 * 60 * 60 );
        @invitecodes = grep {
            my $u = $recipient_users->{ $_->recipient };

            # if it's used, we should always have a recipient, but...
            !$_->is_used || ( $u && $u->timecreate ) > $two_weeks_ago
        } @invitecodes;
    }

    # sort so that invite codes end up in this order:
    #  - unsent and unused
    #  - sent but unused, with earliest sent first
    #  - used
    @invitecodes = sort {
        return $a->is_used <=> $b->is_used if $a->is_used != $b->is_used;
        return ( $a->timesent // 0 ) <=> ( $b->timesent // 0 );
    } @invitecodes;

    $rv->{has_codes}   = scalar @invitecodes;
    $rv->{invitecodes} = \@invitecodes;
    $rv->{users}       = $recipient_users;

    $rv->{create_link} = sub {
        my ($code) = @_;
        return "$LJ::SITEROOT/create?from=$remote->{user}&code=$code";
    };
    $rv->{time_to_http} = sub { return $_[0] ? LJ::time_to_http( $_[0] ) : '' };

    return DW::Template->render_template( 'invite/index.tt', $rv );
}

1;
