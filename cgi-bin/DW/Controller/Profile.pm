#!/usr/bin/perl
#
# DW::Controller::Profile
#
# Displays information about an account in a viewer friendly manner.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
#      Jen Griffin <kareila@livejournal.com> -- TT conversion
#
# Copyright (c) 2009-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Profile;

use strict;

use DW::Controller;
use DW::Routing;

DW::Routing->register_string( '/profile', \&profile_handler, app => 1 );

sub profile_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r   = $rv->{r};
    my $get = $r->get_args;

    my $is_full = $get->{mode} && $get->{mode} eq 'full' ? 1 : 0;

    my $scope = '/profile/main.tt';

    my $remote = $rv->{remote};
    my $u;

    # figure out what $u should be
    {
        my $userarg = $get->{user};

        # when using user domain URLs, get userarg from the request notes,
        # which was set in LiveJournal.pm
        $userarg ||= $r->note('_journal');

        my $username = LJ::canonical_username($userarg);

        # usually we're going off username, but under some circumstances
        # we may be given a userid instead, so check for that first

        if ( my $userid = ( $get->{userid} || 0 ) + 0 ) {
            $u = LJ::load_userid($userid);

            # only users with finduser can view profiles by userid, unless
            # we are viewing the profile of an identity (OpenID) account
            unless ( ( $remote && $remote->has_priv('finduser') )
                || ( $get->{t} && $get->{t} eq "I" && $u && $u->is_identity ) )
            {
                return error_ml("$scope.error.reqfinduser");
            }
        }
        elsif ($username) {
            $u = LJ::load_user($username);

            # redirect identity accounts to standard identity url
            if ( $u && $u->is_identity ) {
                return $r->redirect( $u->profile_url( full => $is_full ) );
            }
        }
        elsif ($remote) {
            $u = $remote;
        }
        else {    # visited $LJ::SITEROOT/profile with no userargs while logged out
            return DW::Controller::needlogin();
        }

        # at this point, if we still don't have $u, give up
        return error_ml( "$scope.error.nonexist", { user => $username } ) unless $u;

        LJ::set_active_journal($u);
    }

    # error if account is purged
    return DW::Template->render_template('error/purged.tt') if $u->is_expunged;

    # redirect non-identity profiles to their subdomain urls
    if ( !$u->is_identity ) {
        my $url = $u->profile_url( full => $is_full );

        # use regexps to extract the user domain from $url and compare to $r
        my $good_domain = $url;
        $good_domain =~ s!^https?://!!;
        $good_domain =~ s!/.*!!;
        if ( $r->header_in("Host") ne $good_domain ) {
            return $r->redirect($url);
        }
    }

    # rename redirect?
    {
        my $renamed_u = $u->get_renamed_user;
        unless ( $u->equals($renamed_u) ) {
            my $urlargs = { user => $renamed_u->user };
            $urlargs->{mode} = 'full' if $is_full;
            return $r->redirect( LJ::create_url( '/profile', args => $urlargs ) );
        }
    }

    # can't view suspended/deleted profiles unless you have viewall
    my $viewall = 0;
    ($viewall) = $remote->view_priv_check( $u, $get->{viewall}, 'profile' ) if $remote;

    unless ($viewall) {
        return DW::Template->render_template( 'error/suspended.tt', { u => $u } )
            if $u->is_suspended;

        return $u->display_journal_deleted($remote) if $u->is_deleted;
    }

    # DONE with error pages and redirects - begin building the page!

    LJ::need_res("js/profile.js");
    LJ::need_res( { priority => $LJ::OLD_RES_PRIORITY }, "stc/profile.css" );

    my $vars = { u => $u, remote => $remote, is_full => $is_full };

    $vars->{profile} = $u->profile_page( $remote, viewall => $viewall );

    # block robots?
    $vars->{robot_meta_tags} = LJ::robot_meta_tags()
        if !$u->is_visible || $u->should_block_robots;

    # TODO: stop profile choking on large numbers of subscribers or members
    $vars->{force_empty} = exists $LJ::FORCE_EMPTY_SUBSCRIPTIONS{ $u->id } ? 1 : 0;

    $vars->{load_userids} = sub { LJ::load_userids( @{ $_[0] } ) };

    $vars->{sort_by_username} = sub {
        my ( $list, $us ) = @_;
        my $sort = sub { $a->display_name cmp $b->display_name };
        $sort = sub { $us->{$a}->display_name cmp $us->{$b}->display_name }
            if $us;
        return [ sort $sort @$list ];
    };

    $vars->{createdate} = LJ::mysql_time( $u->timecreate );
    $vars->{accttype}   = DW::Pay::get_account_type_name($u);
    $vars->{expiretime} = sub {
        my $expiretime = DW::Pay::get_account_expiration_time($u);
        return DateTime->from_epoch( epoch => $expiretime )->date
            if $expiretime > 0;
    };

    # given a single item (scalar or hashref), linkify it and return string
    $vars->{linkify} = sub {
        my $l = $_[0];
        return $l unless ref $l eq 'HASH';

        if ( $l->{text} ) {
            my $ret = "";
            $ret .= $l->{secimg} if $l->{secimg};
            $ret .= $l->{url} ? qq(<a href="$l->{url}">$l->{text}</a>) : $l->{text};
            return $ret;
        }
        elsif ( $l->{email} ) {

            # the ehtml call here shouldn't be necessary, but just in case
            # they slip in an email that contains Bad Stuff, escape it
            my $mangled_email = LJ::CleanHTML::mangle_email_address( LJ::ehtml( $l->{email} ) );

            # return the mangled email with a privacy icon if there is one
            $mangled_email = $l->{secimg} . $mangled_email if $l->{secimg};
            return $mangled_email;
        }
        else {
            return LJ::Lang::ml("$scope.error.linkify");
        }
    };

    # given multiple items in an arrayref, linkify each one appropriately
    # and return them as one string with the join_string separating each item
    # (the join_string will be the first item in the arrayref)
    $vars->{linkify_multiple} = sub {
        my $r = $_[0];
        return $r unless ref $r eq 'ARRAY';

        return $vars->{linkify}->( $r->[0] ) unless @$r > 1;

        my $join_string = shift @$r;
        my @links;
        foreach my $l (@$r) {
            next unless $l;
            push @links, $vars->{linkify}->($l);
        }

        return join( $join_string, @links );
    };

    # helper function for repetitive link array construction
    $vars->{cb_links} = sub {
        my $opts = $_[0];
        my @ret;
        push @ret, { url => $opts->{editurl}, text => LJ::Lang::ml("$scope.section.edit") }
            if $remote && $remote->can_manage($u) && $opts->{editurl};
        my $extra = $opts->{extra} // [];
        push( @ret, $_ ) foreach @$extra;
        return \@ret;
    };

    # code for separating OpenID users by site
    $vars->{parse_openids} = sub {
        my ($openids) = @_;
        return unless $openids;

        my %sites;
        my %shortnames;

        my $sitestore = sub {
            my ( $site, $u, $name ) = @_;
            $sites{$site}      ||= [];
            $shortnames{$site} ||= [];

            push @{ $sites{$site} },      $u;
            push @{ $shortnames{$site} }, $name;
        };

        # TODO: use DW::External methods here?
        foreach my $u (@$openids) {
            my $id    = $u->display_name;
            my @parts = split /\./, $id;
            if ( @parts < 2 ) {

                # we don't know how to parse this, so don't
                $sitestore->( 'unknown', $u, $id );
                next;
            }

            my ( $name, $site );

            # if this looks like a URL, hope the username is at the end
            if ( $parts[-1] =~ m=/([^/]+)/?$= ) {
                $name = $1;
                ($site) = ( $id =~ m=([^/.]+\.[^/]+)= );

            }
            else {    # assume the username is the hostname
                my $host = shift @parts;
                ($name) = ( $host =~ m=([^/]+)$= );
                $site = join '.', @parts;
            }

            $sitestore->( $site, $u, $name );
        }

        return { sites => \%sites, shortnames => \%shortnames };
    };

    # organize filtering subs for various watch/trust/etc. lists
    $vars->{includeuser} = {
        trusted                 => sub { 1 },
        trusted_by              => sub { $is_full || !$_[0]->is_inactive },
        mutually_trusted        => sub { $_[0]->is_individual },
        not_mutually_trusted    => sub { 1 },
        not_mutually_trusted_by => sub { $is_full || !$_[0]->is_inactive },
        watched => sub {    # this one filters on journaltype
            ( $_[0]->journaltype =~ /^[\Q$_[1]\E]$/ )    #  'PI', 'C', 'Y'
                && ( $_[1] eq 'C' ? $is_full || !$_[0]->is_inactive : 1 );
        },
        watched_by              => sub { $is_full || !$_[0]->is_inactive },
        mutually_watched        => sub { $_[0]->is_individual },
        not_mutually_watched    => sub { $_[0]->is_individual },
        not_mutually_watched_by => sub { $is_full || !$_[0]->is_inactive },
        members                 => sub { 1 },
        member_of               => sub { $is_full || !$_[0]->is_inactive },
        admin_of                => sub { $is_full || !$_[0]->is_inactive },
        posting_access_to       => sub { $is_full || !$_[0]->is_inactive },
        posting_access_from     => sub { 1 },
    };

    return DW::Template->render_template( 'profile/main.tt', $vars );
}

1;
