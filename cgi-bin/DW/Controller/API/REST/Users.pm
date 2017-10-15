#!/usr/bin/perl
#
# DW::Controller::API::REST::Users
#
# API controls for fetching user-related information
#
# Authors:
#      Ruth Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::REST::Users;
use DW::Controller::API::REST qw(path);

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;
use Data::Dumper;

################################################
# /user/{username}/journals
#
# Get a list of journals a user has posting access to
################################################

my $post_access = path('users/post_access.yaml', 1, { get => \&post_access_get});

sub post_access_get {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;

    my @journals = $user->posting_access_list;

    #user always has posting access to themselves
    my @journalnames = ($user->user);

    #push the usernames for all comms the user has posting access to onto the list.
    foreach my $journal ( @journals ) {
        my $name = $journal->user;
        push(@journalnames, $name);
    }

    return $self->rest_ok( \@journalnames );
    }

################################################
# /user/{username}/grants
#
# Get a list of journals a user grants reading access to
################################################
my $trust = path('users/trust.yaml', 1, { get => \&trust_get, post => \&trust_post, delete => \&trust_delete});

sub trust_get {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;

    my $trust_list = $user->trust_list;
    my $trusted_users = LJ::load_userids( keys %$trust_list );
    my @banned_userids = @{$user->banned_userids || []};
    my @journalnames = ();

    #push the usernames for all comms the user has posting access to onto the list.
    foreach my $userid (keys %$trust_list) {
        next if grep {$_ == $userid} @banned_userids;
        my $name = $trusted_users->{$userid}->user;
        push(@journalnames, $name);
    }

    return $self->rest_ok( \@journalnames );
}

sub trust_post {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $r = $rv->{r};
    my $post = $r->json();

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless $user == $remote;

    my @not_user;
    my @journals = $post->{journals};


    foreach my $journal (@journals) {
        my $other_u = LJ::load_user_or_identity( $journal );
        unless ( $other_u ) {
            push @not_user, $journal;
            next;
        }
        if ( $other_u->is_redirect && $other_u->prop( 'renamedto' ) ) {
            $other_u = $other_u->get_renamed_user;
        }

        my $trusted_nonotify = $user->trusts( $other_u ) ? 1 : 0;
        $user->add_edge( $other_u, trust => {
                        nonotify => $trusted_nonotify ? 1 : 0,
                    } );
    }

    my $response = {"invalid usernames" => @not_user};

    return $self->rest_ok( $response );
}

sub trust_delete {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $r = $rv->{r};
    my $post = $r->json();

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless $user == $remote;

    my @not_user;
    my @journals = $post->{journals};


    foreach my $journal (@journals) {
        my $other_u = LJ::load_user_or_identity( $journal );
        unless ( $other_u ) {
            push @not_user, $journal;
            next;
        }
        if ( $other_u->is_redirect && $other_u->prop( 'renamedto' ) ) {
            $other_u = $other_u->get_renamed_user;
        }

        my $trusted_nonotify = $user->trusts( $other_u ) ? 1 : 0;
        $user->remove_edge( $other_u, trust => {
                        nonotify => $trusted_nonotify ? 1 : 0,
                    } );
    }

    my $response = {"invalid usernames" => @not_user};

    return $self->rest_ok( $response );
}



################################################
# /user/{username}/subscriptions
#
# Get a list of journals a user subscribes to
################################################
my $watch = path('users/watch.yaml', 1, { get => \&watch_get});

sub watch_get {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;

    my $watch_list = $user->watch_list;
    my $watched_users = LJ::load_userids( keys %$watch_list );
    my @banned_userids = @{$user->banned_userids || []};

    my @journalnames = ();

    #push the usernames for all comms the user has posting access to onto the list.
    foreach my $userid ( keys %$watch_list ) {
        next if grep {$_ == $userid} @banned_userids;
        my $name = $watched_users->{$userid}->user;
        push(@journalnames, $name);
    }

    return $self->rest_ok( \@journalnames );
}


################################################
# /user/{username}
#
# Get a list of information about a user
################################################
my $info = path('users.yaml', 1, { get => \&info_get});

sub info_get {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;

    my $profile = $user->profile_page($remote);
    my $type = DW::Pay::get_account_type_name( $user );
    my $name = $user->name_raw;
    my $bio = $user->bio;
    my $last_updated = LJ::mysql_time( $user->timeupdate );
    my $created = LJ::mysql_time( $user->timecreate );
    my $num_received_raw = $user->num_comments_received;
    my $num_posted_raw = $user->num_comments_posted;
    my $tags_count = scalar keys %{ $user->tags || {} };
    my $memories_count = LJ::Memories::count( $user->id ) || 0;
    my $userid = $user->{userid};
    my $title = $user->prop( "journaltitle" ) || "";
    my $subtitle = $user->prop( "journalsubtitle" ) || "";
    my $entries_count = $user->number_of_posts;


    my $info_hash = {
        account_type => $type,
        name => $name,
        bio => $bio,
        comments_recieved => $num_received_raw,
        comments_posted => $num_posted_raw,
        tags_count => $tags_count,
        memories_count => $memories_count,
        created => $created,
        last_updated => $last_updated,
        userid => $userid,
        journal_title => $title,
        journal_subtitle => $subtitle,
        entries_count => $entries_count,
    };


    return $self->rest_ok( $info_hash );
}

    1;