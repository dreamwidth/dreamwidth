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
use LJ::JSON;

DW::Routing->register_rpc( "extacct_auth", \&extacct_auth_handler, format => 'json' );
DW::Routing->register_rpc( "general", \&general_handler, format => 'json' );

sub extacct_auth_handler {
    my $r = DW::Request->get;
    my $get = $r->get_args;

    my $u = LJ::get_remote();
    return DW::RPC->err( LJ::Lang::ml( '/tools/endpoints/extacct_auth.bml.error.nouser' ) )
        unless $u;

    # get the account
    my $acctid = LJ::ehtml( $get->{acctid} );
    my $account = DW::External::Account->get_external_account( $u, $acctid );
    return DW::RPC->err( LJ::Lang::ml( '/tools/endpoints/extacct_auth.bml.error.nosuchaccount',
                            {
                                acctid => $acctid,
                                username => $u->username
                            }
                        ) ) unless $account;

    # make sure this account supports challenge/response authentication
    return DW::RPC->err( LJ::Lang::ml( '/tools/endpoints/extacct_auth.bml.error.nochallenge',
                            {
                                account => LJ::ehtml( $account->displayname )
                            }
                        ) ) unless $account->supports_challenge;

    # get the auth challenge
    my $challenge = $account->challenge;
    return DW::RPC->err( LJ::Lang::ml( '/tools/endpoints/extacct_auth.bml.error.authfailed',
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
    my $u = LJ::load_user( $args->{user} || $remote->user )
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

1;
