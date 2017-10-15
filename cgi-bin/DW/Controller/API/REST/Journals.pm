#!/usr/bin/perl
#
# DW::Controller::API::REST::Journals
#
# API controls for fetching journal-related information
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

package DW::Controller::API::REST::Journals;
use DW::Controller::API::REST qw(path);

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use JSON;
use Data::Dumper;
#use DW::API::Path qw(path);

################################################
# /journals/{journal}/accesslists
#
# Get a list of accesslists, or create a new accesslist
################################################

my $accesslists_all = path('journals/accesslists_all.yaml', 1, { get => \&accesslists_get, post => \&accesslists_new});

sub accesslists_get {
    my ( $self, $opts, $journalname) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless $user == $remote;

    my @trust_groups = $user->trust_groups;
    my @accesslists = ();

    #push the names and group ids of the user's trust groups to the list.
    foreach my $group ( @trust_groups ) {
        my $group_hash = { "id" => $group->{groupnum}, "name" => $group->{groupname}};
        push(@accesslists, $group_hash);
    }

    return $self->rest_ok( \@accesslists );
    }

sub accesslists_new {
    my ( $self, $opts, $journalname ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless $user == $remote;

    my $post = $rv->{r}->json();

    my $group = $user->create_trust_group(name => $post->{name}, sortorder => $post->{sortorder}, is_public => $post->{is_public});

    return $self->rest_ok( $group );
    }


################################################
# /journals/{journal}/accesslists/{id}
#
# Get details about a specific accesslist
################################################

my $accesslists = path('journals/accesslists.yaml', 1, { get => \&accesslist_get, post => \&accesslist_edit});

sub accesslist_get {
    my ( $self, $opts, $journalname, $id) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless $user == $remote;

    my $group_members = $user->trust_group_members(id => $id);
    my @accesslist;
    my $members = LJ::load_userids( keys %$group_members );

    #push the names and group ids of the user's trust groups to the list.
    foreach my $userid ( keys %$members ) {
        my $name = $members->{$userid}->user;
        push(@accesslist, $name);
    }

    return $self->rest_ok( \@accesslist );
    }

sub accesslist_edit {
    my ( $self, $opts, $journalname, $id ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{POST}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'POST', 404 ) unless $user;
    return $self->rest_error( 'POST', 403 ) unless $user == $remote;

    my $post = $rv->{r}->json();
    my @journals = $post->{journals};
    my $trust_group = $user->trust_groups({id => $id});
    my $groupmask = $trust_group->{groupmask};

    foreach my $journal (@journals) {
        my $trusted_u = LJ::load_user( $journal );
        # User might have been removed from circle between load and
        # submit; don't re-add.
        next unless $trusted_u && $user->trusts( $trusted_u );
            $user->add_edge( $trusted_u, trust => {
                mask => $groupmask,
                nonotify => 1,
                } );
        }
    return $self->rest_ok( "added successfully" );
    }

################################################
# /journals/{journal}/tags
#
# Get a list of tags, create new tags, or delete tags
################################################

my $tags = path('journals/tags.yaml', 1, { get => \&tags_get, post => \&tags_post, delete => \&tags_delete});

sub tags_get {
    my ( $self, $opts, $journalname) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;

    # get tags for the page to display
    my @taglist;
    my $tags = LJ::Tags::get_usertags($user, { remote => $remote });
    foreach my $kwid (keys %{$tags}) {
        # only show tags for display
        next unless $tags->{$kwid}->{display};
        print Dumper($tags->{$kwid});
        push @taglist, LJ::S2::TagDetail($user, $kwid => $tags->{$kwid});
    }
    @taglist = sort { $a->{name} cmp $b->{name} } @taglist;

    return $self->rest_ok( \@taglist );
    }

sub tags_post {
    my ( $self, $opts, $journalname, $ditemid ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless LJ::Tags::can_control_tags($user, $remote);
    
    my $post = $rv->{r}->json();
    my $tagerr = "";
    my @errors;

    my @tags = $post->{tags};
    #push the usernames for all comms the user has posting access to onto the list.
    foreach my $tag ( @tags ) {

            my $rv = LJ::Tags::create_usertag($user, $tag, { display => 1, err_ref => \$tagerr });
            push @errors, $tagerr unless $rv;
    }

    return $self->rest_error('GET', 400) if $#errors > 0;
    return $self->rest_ok( \@tags );
    }

sub tags_delete {
    my ( $self, $opts, $journalname, $ditemid ) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless $user == $remote;

    my $post = $rv->{r}->json();

    my @tags = $post->{tags};

    #push the usernames for all comms the user has posting access to onto the list.
    foreach my $tag ( @tags ) {

        LJ::Tags::delete_usertag( $user, 'name', $tag );
    }

    return $self->rest_ok( \@tags );
    }


################################################
# /journals/{journal}/xpostaccounts
#
# Get a list of crosspost accounts
################################################

my $xpost = path('journals/xpostaccounts.yaml', 1, { get => \&xpost_get});

sub xpost_get {
    my ( $self, $opts, $journalname) = @_;
    my ( $ok, $rv ) = controller( anonymous => 1 );
    my $responses = $self->{path}{methods}{GET}{responses};

    my $user = LJ::load_user( $journalname );
    my $remote = $rv->{remote};
    return $self->rest_error( 'GET', 404 ) unless $user;
    return $self->rest_error( 'GET', 403 ) unless $user == $remote;

    my @xpostaccounts = DW::External::Account->get_external_accounts( $user );
    my @accountlist;

    #FIXME: print minsecurity as well? Weird encoding bugs though.
    foreach my $account (@xpostaccounts) {
        my $accounthash = { name => $account->displayname,  
                            xpostbydefault => $account->{xpostbydefault} 
                          };
        push @accountlist, $accounthash;

    }

    return $self->rest_ok( \@accountlist );
    }

    1;