#!/usr/bin/perl
#
# DW::Controller::RPC::Misc
#
# The AJAX endpoint for general calls.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Controller::RPC::Misc;

use strict;
use LJ::JSON;
use DW::Routing;
use DW::Controller;

DW::Routing->register_rpc( "contentfilters", \&contentfilters_handler, format => 'json' );
DW::Routing->register_rpc( "extacct_auth", \&extacct_auth_handler, format => 'json' );
DW::Routing->register_rpc( "general", \&general_handler, format => 'json' );
DW::Routing->register_rpc( "addcomment", \&addcomment_handler, format => 'json', methods => { POST => 1 } );

sub contentfilters_handler {
    my $r = DW::Request->get;
    my $get = $r->get_args;
    my $post = $r->post_args;

    # make sure we have a user of some sort
    my $remote = LJ::get_remote();
    my $remote_user = $remote ? $remote->user : undef;
    my $u = LJ::get_authas_user( $get->{user} || $remote_user );
    return DW::RPC->alert( 'Unable to load user for call.' ) unless $u;

    # in theory, they're passing a mode in the GET arguments
    my $mode = $get->{mode}
        or return DW::RPC->alert( 'No mode passed.' );

    my %ret;

    # list_filters mode is very simple: it returns an array of the filters with the
    # pertinent information about those filters
    if ( $mode eq 'list_filters' ) {
        $ret{filters} = {};

        my @filters = $u->content_filters;
        foreach my $filt ( @filters ) {
            $ret{filters}->{$filt->id} =
                {
                    id => $filt->id,
                    name => $filt->name,
                    sortorder => $filt->sortorder,
                    public => $filt->public,
                };
        }

    # list the names of the people who are on a filter
    } elsif ( $mode eq 'list_members' ) {
        $ret{members} = {};

        my $filter = $u->content_filters( id => $get->{filterid} )
            or return DW::RPC->alert( 'No such filter.' );

        my $data = $filter->data;
        foreach my $uid ( keys %$data ) {
            my $member = $data->{$uid};

            # FIXME: use load_userids_multiple to get the user objects...
            $ret{members}->{$uid} = {
                user => LJ::load_userid( $uid )->user,
                adultcontent => $member->{adultcontent} || 'any',
                postertype => $member->{postertype} || 'any',
                tagmode => $member->{tagmode} || 'any_of',
                tags => { map { $_ => 1 } @{ $member->{tags} || [] } },
            };
        }

    # called to make a brand new filter
    } elsif ( $mode eq 'create_filter' ) {
        return DW::RPC->alert( 'Can only create filters for people.' )
            unless $u->is_individual;

        return DW::RPC->alert( 'No name provided.' )
            unless $get->{name} =~ /\S/;

        my $fid = $u->create_content_filter( name => $get->{name} );
        return DW::RPC->alert( 'Failed to create content filter.' )
            unless $fid;

        my $cf = $u->content_filters( id => $fid );
        return DW::RPC->alert( 'Failed to retrieve content filter.' )
            unless $cf;

        %ret = (
            id => $cf->id,
            name => $cf->name,
            public => $cf->public,
            sortorder => $cf->sortorder,
        );

    # delete a content filter
    } elsif ( $mode eq 'delete_filter' ) {
        return DW::RPC->alert( 'Can only create filters for people.' )
            unless $u->is_individual;

        return DW::RPC->alert( 'No/invalid id provided.' )
            unless $get->{id} =~ /^\d+$/;

        my $id = $u->delete_content_filter( id => $get->{id} );
        return DW::RPC->alert( 'Failed to delete the content filter.' )
            unless $id == $get->{id};

        $ret{ok} = 1;

    # save incoming changes
    } elsif ( $mode eq 'save_filters' ) {
        my $obj = from_json( $post->{json} );

        foreach my $fid ( keys %$obj ) {
            my $filt = $obj->{$fid};

            # load this filter
            my $cf = $u->content_filters( id => $fid );
            return DW::RPC->alert( "Filter id $fid does not exist." )
                unless $cf;

            # update the name if necessary, this has to be before the members check
            # because they might not have loaded members (or it might have none)
            $cf->name( $filt->{name} )
                if $filt->{name} && $filt->{name} ne $cf->name;

            # skip the filter if it hasn't actually been loaded
            next unless defined $filt->{members};

            # get data object for use later
            my $data = $cf->data;

            # fix up the member list
            foreach my $uid ( keys %{ $filt->{members} } ) {
                my $member = $filt->{members}->{$uid};

                # don't need this, we can look it up
                delete $member->{user};

                # tags are given to us as a hashref, we need to flatten to an array
                $member->{tags} = [ keys %{ $member->{tags} || {} } ];

                # these may or may not be present, nuke them if they're default
                delete $member->{postertype}
                    if $member->{postertype} && $member->{postertype} eq 'any';
                delete $member->{adultcontent}
                    if $member->{adultcontent} && $member->{adultcontent} eq 'any';
                delete $member->{tagmode}
                    if $member->{tagmode} && $member->{tagmode} eq 'any_of';

                # now save this in the actual filter
                $data->{$uid} = $member;
            }

            # see whether we deleted any members from the filter
            foreach my $uid ( keys %{ $data } ) {
                # delete userid from $data if it is not also in $filt->{members}
                delete $data->{$uid} unless exists $filt->{members}->{$uid};
            }

            # save public and sortorder preferences
            $cf->_getset( 'sortorder', $filt->{sortorder} + 0 ) unless $filt->{sortorder} == $cf->{sortorder};
            $cf->_getset( 'public', $filt->{public} ? 1 : 0 ) unless $filt->{public} == $cf->{public};

            # save the filter, very important...
            $cf->_save;
        }

        $ret{ok} = 1;
    } elsif ( $mode eq "view_filter" ) {
        # called to get reading page url
        return DW::RPC->alert( 'No name provided.' )
            unless $get->{name} =~ /\S/;

        $ret{url} = $u->journal_base . "/read/" . $get->{name};
    }

    return DW::RPC->out( %ret );
}

sub extacct_auth_handler {
    my $r = DW::Request->get;
    my $get = $r->get_args;

    my $u = LJ::get_remote();
    return DW::RPC->err( LJ::Lang::ml( 'error.extacct_auth.nouser' ) )
        unless $u;

    # get the account
    my $acctid = LJ::ehtml( $get->{acctid} );
    my $account = DW::External::Account->get_external_account( $u, $acctid );
    return DW::RPC->err( LJ::Lang::ml( 'error.extacct_auth.nosuchaccount',
                            {
                                acctid => $acctid,
                                username => $u->username
                            }
                        ) ) unless $account;

    # make sure this account supports challenge/response authentication
    return DW::RPC->err( LJ::Lang::ml( 'error.extacct_auth.nochallenge',
                            {
                                account => LJ::ehtml( $account->displayname )
                            }
                        ) ) unless $account->supports_challenge;

    # get the auth challenge
    my $challenge = $account->challenge;
    return DW::RPC->err( LJ::Lang::ml( 'error.extacct_auth.authfailed',
                            {
                                account => LJ::ehtml( $account->displayname )
                            }
                        ) ) unless $challenge;

    return DW::RPC->out( challenge => $challenge, success => 1 );
}

sub general_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;

    # make sure we have a user of some sort
    my $remote = LJ::get_remote();
    my $u = LJ::load_user( $args->{user} ) || $remote
        or return DW::RPC->alert( 'Unable to load user for call.' );

    # in theory, they're passing a mode in the args-> arguments
    my $mode = $args->{mode}
        or return DW::RPC->alert( 'No mode passed.' );

    my %ret;

    # gets the list of people that this account subscribes to
    if ( $mode eq 'list_subscriptions' ) {
        $ret{subs} = $u->watch_list;

        my $uobjs = LJ::load_userids( keys %{ $ret{subs} } );
        foreach my $userid ( keys %$uobjs ) {
            $ret{subs}->{$userid}->{username} = $uobjs->{$userid}->user;
            $ret{subs}->{$userid}->{journaltype} = $uobjs->{$userid}->journaltype;
        }

    # get the list of someone's tags
    } elsif ( $mode eq 'list_tags' ) {
        $ret{tags} = LJ::Tags::get_usertags( $u, { remote => $remote } );
        foreach my $val ( values %{ $ret{tags} } ) {
            delete $val->{security_level};
            delete $val->{security};
            delete $val->{display};
        }

    # get the list of members of an access filter
    } elsif ( $mode eq 'list_filter_members' ) {
        my $filterid = $args->{filterid} + 0;
        $ret{filter_members}->{filterusers} = $u->trust_group_members(id=>$filterid);
        $ret{filter_members}->{filtername} = $u->trust_groups(id=>$filterid);
        my $uobjs = LJ::load_userids( keys %{ $ret{filter_members}->{filterusers} } );
        foreach my $userid (keys %$uobjs) {
            next unless $uobjs->{$userid};
            $ret{filter_members}->{filterusers}->{$userid}->{fancy_username} = $uobjs->{$userid}->ljuser_display;
        }

    # problems
    } else {
        return DW::RPC->alert( 'Unknown mode.' );

    }

    return DW::RPC->out( %ret );
}

sub addcomment_handler {
    my $remote = LJ::get_remote();
    my $r = DW::Request->get;
    my $post = $r->post_args;

    return DW::RPC->err( LJ::Lang::ml( 'error.invalidform' ) )
        if $r->did_post && ! LJ::check_form_auth( $post->{lj_form_auth} );

    # build the comment
    my $req = {
        ver      => 1,

        username => $remote->username,
        journal  => $post->{journal},
        ditemid  => $post->{itemid},
        parent   => $post->{parenttalkid},

        body     => $post->{body},
        subject  => $post->{subject},
        prop_picture_keyword => $post->{prop_picture_keyword},

        useragent => "rpc-addcomment",
    };

    # post!
    my $post_error;
    LJ::Protocol::do_request( "addcomment", $req, \$post_error, { noauth => 1, nocheckcap => 1 } );
    return DW::RPC->err( LJ::Protocol::error_message( $post_error ) ) if $post_error;

    # now get the comment count
    my $entry;
    my $uid = LJ::get_userid( $post->{journal} );
    $entry = LJ::Entry->new( $uid, ditemid => $post->{itemid} ) if $uid;
    $entry = undef unless $entry && $entry->valid;

    my $count;
    $count = $entry->reply_count( force_lookup => 1 ) if $entry;

    return DW::RPC->out( message => LJ::Lang::ml( 'comment.rpc.posted' ), count => $count );
}

1;
