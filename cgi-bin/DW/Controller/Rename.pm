#!/usr/bin/perl
#
# DW::Controller::Rename
#
# This controller is for renames
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Rename;

use strict;
use warnings;
use DW::Controller;
use DW::Routing;
use DW::Template;

use DW::RenameToken;
use DW::Shop;

# be lax in accepting what goes in the URL in case of typos or mis-copy/paste
# we validate the token inside and return an appropriate message (instead of 404)
# ideally, should be: /rename, or /rename/(20 character token)
DW::Routing->register_regex( qr!^/rename(?:/([A-Z0-9]*))?$!i, \&rename_handler, app => 1 );

sub rename_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = LJ::get_remote();

    return error_ml( 'rename.error.invalidaccounttype' ) unless $remote->is_personal;

    my $vars = {};

    my $given_token = $_[0]->subpatterns->[0];
    my $token = DW::RenameToken->new( token => $given_token );
    my $post_args = DW::Request->get->post_args || {};
    my $get_args = DW::Request->get->get_args || {};

    $get_args->{type} ||= "P";
    $get_args->{type} = "P" unless $get_args->{type} =~ m/^(P|C)$/;

    if ( $r->method eq "POST" ) {

        # this is kind of ugly. Basically, it's a rendered template if it's a success, and a list of errors if it failed
        my ( $post_ok, $rv ) = handle_post( $token, $post_args );
        return $rv if $post_ok;

        $vars->{error_list} = $rv;
    }

    $vars->{invalidtoken} = $given_token
        if $given_token && ! $token;

    my $rename_to_errors = [];
    if ( $get_args->{checkuser} ) {
        $vars->{checkusername} = {
            user => $get_args->{checkuser},
            status => $remote->can_rename_to( $get_args->{checkuser}, errref => $rename_to_errors ) ? "available" : "unavailable",
            errors => $rename_to_errors
        };
    }

    if ( $token ) {
        if ( $token->applied ) {
            $vars->{usedtoken} = $token->token;
        } else {
            $vars->{token} = $token;

            # not using the regular authas logic because we want to exclude the current username
            my $authas =  LJ::make_authas_select( $remote,
                {   selectonly => 1,
                    type => $get_args->{type},
                    authas => $post_args->{authas} || $get_args->{authas},
                } );

            $authas .= $remote->user if $get_args->{type} eq "P";

            my @rel_types = $get_args->{type} eq "P"
                ? qw( trusted_by watched_by trusted watched communities )
                : ();

            # initialize the form based on previous posts (in case of error) or with some default values
            $vars->{form} = {
                authas      => $authas,
                journaltype => $get_args->{type},
                journalurl  => $get_args->{type} eq "P" ? $remote->journal_base : LJ::journal_base( "communityname", "community" ),
                pageurl     => "/rename/" . $token->token,
                token       => $token->token,
                to          => $post_args->{touser} || $get_args->{to} || "",
                redirect    => $post_args->{redirect} || "disconnect",
                rel_types   => \@rel_types,
                rel_options => %$post_args ? { map { $_ => 1 } $post_args->get( "rel_options" ) }
                                            : { map { $_ => 1 } @rel_types },
                others      => %$post_args ? { map { $_ => 1 } $post_args->get( "others" ) }
                                            : { email => 0 },
            };

        }
    }

    if ( ! $token || ( $token && $token->applied ) ) {
        # grab a list of tokens they can use in case they didn't provide a usable token
        # assume we always have a remote because our controller is registered as requiring a remote (default behavior)
        $vars->{unused_tokens} = DW::RenameToken->by_owner_unused( userid => $remote->userid );
    }

    return DW::Template->render_template( 'rename.tt', $vars );
}

sub handle_post {
    my ( $token, $post_args ) = @_;

    return ( 0, [ LJ::Lang::ml( '/rename.tt.error.invalidform' ) ] ) unless LJ::check_form_auth( $post_args->{lj_form_auth} );

    my $errref = [];

    # the journal we are going to rename; yourself or (eventually) a community you maintain
    my $journal = LJ::get_authas_user( $post_args->{authas} );
    push @$errref, LJ::Lang::ml( '/rename.tt.error.nojournal' ) unless $journal;

    my $fromusername = $journal ? $journal->user : "";

    my $tousername = $post_args->{touser};
    my $redirect_journal = $post_args->{redirect} && $post_args->{redirect} eq "disconnect" ? 0 : 1;
    push @$errref, LJ::Lang::ml( '/rename.tt.error.noredirectopt' ) unless $post_args->{redirect};

    # since you can't recover deleted relationships, but you can delete the relationships later if something was missed
    # negate the form submission so we're explicitly stating which rels we want to delete, rather than deleting everything not listed
    my %keep_rel = map { $_ => 1 } $post_args->get( "rel_options" );
    my %del_rel = map { +"del_$_" => ! $keep_rel{$_} } qw( trusted_by watched_by trusted watched communities );

    my %other_opts = map { $_ => 1 } $post_args->get( "others" );
    if ( $other_opts{email} ) {
        if ( $post_args->{redirect} ne "forward" ) {
            push @$errref, LJ::Lang::ml( '/rename.tt.error.emailnotforward', { emaildomain => "\@$LJ::USER_DOMAIN" } );
            $other_opts{email} = 0;
        } 

        unless ( $LJ::USER_EMAIL && $journal->can_have_email_alias ) {
            push @$errref, LJ::Lang::ml( '/rename.tt.error.emailnoalias' );
            $other_opts{email} = 0;
        }
    }

    # try the rename and see if there are any errors
    $journal->rename( $tousername, user => LJ::get_remote(), token => $token, redirect => $redirect_journal, redirect_email => $other_opts{email}, %del_rel, errref => $errref );

    return ( 1, success_ml( "/rename.tt.success", { from => $fromusername, to => $journal->user } ) ) unless @$errref;

    # return the list of errors, because we want to print out other things as well...
    return ( 0, $errref );
}
1;
