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
use DW::Controller::Admin;

use DW::RenameToken;
use DW::Shop;

DW::Routing->register_string( "/rename/swap", \&swap_handler, app => 1 );

# be lax in accepting what goes in the URL in case of typos or mis-copy/paste
# we validate the token inside and return an appropriate message (instead of 404)
# ideally, should be: /rename, or /rename/(20 character token)
DW::Routing->register_regex( qr!^/rename(?:/([A-Z0-9]*))?$!i, \&rename_handler, app => 1 );

DW::Routing->register_string( "/admin/rename/index", \&rename_admin_handler, app => 1 );
DW::Routing->register_string( "/admin/rename/edit", \&rename_admin_edit_handler, app => 1 );

DW::Routing->register_string( "/admin/rename/new", \&siteadmin_rename_handler, app => 1 );

DW::Controller::Admin->register_admin_page( '/',
    path => '/admin/rename/',
    ml_scope => '/admin/rename.tt',
    privs => [ 'siteadmin:rename' ]
);

sub rename_handler {
    my ( $opts, $given_token ) = @_;

    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = LJ::get_remote();

    return error_ml( 'rename.error.invalidaccounttype' ) unless $remote->is_personal;

    my $vars = {};

    my $token = DW::RenameToken->new( token => $given_token );
    my $post_args = DW::Request->get->post_args;
    my $get_args = DW::Request->get->get_args;

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

            $vars->{rel_types} = \@rel_types;

            # initialize the form based on previous posts (in case of error) or with some default values
            $vars->{formdata} = {
                authas      => $authas,
                journaltype => $get_args->{type},
                journalurl  => $get_args->{type} eq "P" ? $remote->journal_base : LJ::journal_base( "communityname", "community" ),
                pageurl     => "/rename/" . $token->token,
                token       => $token->token,
                touser      => $post_args->{touser} || $get_args->{to} || "",
                redirect    => $post_args->{redirect} || "disconnect",
                rel_options => %$post_args ? { map { $_ => 1 } $post_args->get_all( "rel_options" ) }
                                            : { map { $_ => 1 } @rel_types },
                others      => %$post_args ? { map { $_ => 1 } $post_args->get_all( "others" ) }
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
    my ( $token, $post_args, %opts ) = @_;

    return ( 0, [ LJ::Lang::ml( '/rename.tt.error.invalidform' ) ] ) unless LJ::check_form_auth( $post_args->{lj_form_auth} );

    my $errref = [];

    # the journal we are going to rename: yourself or a community you maintain
    my $journal = LJ::get_authas_user( $post_args->{authas} );
    push @$errref, LJ::Lang::ml( '/rename.tt.error.nojournal' ) unless $journal;

    my $fromusername = $journal ? $journal->user : "";

    my $tousername = $post_args->{touser};
    my $redirect_journal = $post_args->{redirect} && $post_args->{redirect} eq "disconnect" ? 0 : 1;
    push @$errref, LJ::Lang::ml( '/rename.tt.error.noredirectopt' ) unless $post_args->{redirect};

    # since you can't recover deleted relationships, but you can delete the relationships later if something was missed
    # negate the form submission so we're explicitly stating which rels we want to delete, rather than deleting everything not listed
    my %keep_rel = map { $_ => 1 } $post_args->get_all( "rel_options" );
    my %del_rel = map { +"del_$_" => ! $keep_rel{$_} } qw( trusted_by watched_by trusted watched communities );

    my %other_opts = map { $_ => 1 } $post_args->get_all( "others" );
    if ( $other_opts{email} ) {
        if ( $post_args->{redirect} ne "forward" ) {
            push @$errref, LJ::Lang::ml( '/rename.tt.error.emailnotforward', { emaildomain => "\@$LJ::USER_DOMAIN" } );
            $other_opts{email} = 0;
        } 

        unless ( $journal->can_have_email_alias ) {
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


sub swap_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    return error_ml( 'rename.error.invalidaccounttype' ) unless $remote->is_personal;

    my $vars = {};

    my $post_args = DW::Request->get->post_args;

    my @unused_tokens = @{DW::RenameToken->by_owner_unused( userid => $remote->userid ) || []};
    $vars->{numtokens} = scalar @unused_tokens;

    if ( $r->method eq "POST" ) {
        # this is kind of ugly. Basically, it's a rendered template if it's a success, and a list of errors if it failed
        my ( $post_ok, $rv ) = handle_swap_post( $post_args, tokens => \@unused_tokens, user => $remote );
        return $rv if $post_ok;

        $vars->{error_list} = $rv;
    }

    my $authas =  LJ::make_authas_select( $remote,
        {   selectonly => 1,
            authas => $post_args->{authas},
        } );

    $vars->{authas} = $authas;
    $vars->{formdata} = $post_args;

    return DW::Template->render_template( 'rename/swap.tt', $vars );
}

sub handle_swap_post {
    my ( $post_args, %opts ) = @_;

    my @errors = ();
    push @errors, LJ::Lang::ml( '/rename.tt.error.invalidform' ) unless LJ::check_form_auth( $post_args->{lj_form_auth} );

    my $journal = LJ::get_authas_user( $post_args->{authas} );
    push @errors, LJ::Lang::ml( '/rename/swap.tt.error.nojournal' ) unless $journal;

    my $swapjournal = LJ::load_user( $post_args->{swapjournal} );
    push @errors, LJ::Lang::ml( '/rename/swap.tt.error.invalidswapjournal' ) unless $swapjournal;

    return ( 0, \@errors ) if @errors;


    ( $journal, $swapjournal ) = ( $swapjournal, $journal )
        if $journal->is_community && $swapjournal->is_personal;

    # let's do this
    my $errref = [];
    $journal->swap_usernames( $swapjournal, user => $opts{user}, tokens => $opts{tokens}, errref => $errref );

    return ( 1, success_ml( "/rename/swap.tt.success", {
            journal => $journal->ljuser_display,
            swapjournal => $swapjournal->ljuser_display,
    } ) ) unless @$errref;

    # return the list of errors, because we want to print out other things as well...
    return ( 0, $errref );
}

sub rename_admin_handler {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:rename" ] );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $post_args = $r->post_args;
    my $get_args = $r->get_args;

    # just get the username, and not a user object, because username may no longer be valid for a user
    my $user = $post_args->{user} || $get_args->{user};

    my @renames;
    if ( $user ) {
        my @rename_tokens = sort { $a->rendate <=> $b->rendate }
            @{ DW::RenameToken->by_username( user => $user ) || [] };
        foreach my $token ( @rename_tokens ) {
            push @renames, {
                token   => $token->token,
                from    => $token->fromuser,
                to      => $token->touser,

                # FIXME: these should probably just be in DW::RenameToken instead
                owner   => LJ::load_userid( $token->ownerid ),
                target  => LJ::load_userid( $token->renuserid ),
                date    => LJ::mysql_time( $token->rendate ),
            }
        }
    }

    my $vars = {
        %$rv,

        # lookup a list of renames involving a username
        user => $user,
        renames => $user ? \@renames : undef,
    };

    return DW::Template->render_template( "admin/rename.tt", $vars );
}

sub rename_admin_edit_handler {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:rename" ] );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $post_args = $r->post_args;
    my $get_args = $r->get_args;

    my $token = DW::RenameToken->new( token => $get_args->{token} );

    my $u = LJ::load_userid( $token->renuserid );
    my @rel_types = qw( trusted_by watched_by trusted watched communities );
    my $form = {
        from    => $token->fromuser,
        to      => $token->touser,
        byuser  => LJ::load_userid( $token->ownerid ),
        user    => $u,
        journaltype => $u ? $u->journaltype : "P",
    };

    # load up the old values
    my $token_details = $token->details;
    if ( $token_details ) {
        $form->{redirect} = $token_details->{redirect}->{username} ? "forward" : "disconnect";
        $form->{rel_options} = { map { $_ => ! $token_details->{del}->{$_} } @rel_types };
        $form->{others}->{email} = $token_details->{redirect}->{email};
    }

    my $vars = {
        %$rv,
        formdata => $form,
        rel_types => \@rel_types,
        token => $token,
        nodetails => $token_details ? 0: 1,
    };

    if ( $r->did_post ) {
        my ( $post_ok, $rv ) = handle_admin_post( $token, $post_args,
                    journal     => $u,
                    from_user    => $token->fromuser,
                    to_user      => $token->touser,
        );
        return $rv if $post_ok;

        $vars->{error_list} = $rv;
    }

    return DW::Template->render_template( "admin/rename_edit.tt", $vars );
}

sub handle_admin_post {
    my ( $token, $post_args, %opts ) = @_;

    return ( 0, [ LJ::Lang::ml( '/rename.tt.error.invalidform' ) ] ) unless LJ::check_form_auth( $post_args->{lj_form_auth} );

    my $errref = [];
    my %rename_opts = ( user => LJ::get_remote(), from => $opts{from_user}, to => $opts{to_user} );

    if ( $post_args->{override_redirect} ) {
        if ( LJ::isu( $opts{journal} ) && $opts{from_user} && $opts{to_user} ) {
            my $redirect_journal = $post_args->{redirect} && $post_args->{redirect} eq "disconnect" ? 0 : 1;
            $rename_opts{break_redirect}->{username} = ! $redirect_journal;
        } else {
            push @$errref, "Cannot do redirect; invalid journal, or no username provided to rename from/to.";
        }
    }


    if( $post_args->{override_relationships} ) {
        # since you can't recover deleted relationships, but you can delete the relationships later if something was missed
        # negate the form submission so we're explicitly stating which rels we want to delete, rather than deleting everything not listed
        my %keep_rel = map { $_ => 1 } $post_args->get_all( "rel_options" );
        my %del_rel = map { +"del_$_" => ! $keep_rel{$_} } qw( trusted_by watched_by trusted watched communities );

        $rename_opts{del} = \%del_rel;
    }


    if( $post_args->{override_others} ) {
        my %other_opts = map { $_ => 1 } $post_args->get_all( "others" );

        # force email to false if we can't support forwarding for this user
        if ( $other_opts{email} ) {
            if ( $post_args->{redirect} ne "forward" ) {
                push @$errref, LJ::Lang::ml( '/rename.tt.error.emailnotforward', { emaildomain => "\@$LJ::USER_DOMAIN" } );
                $other_opts{email} = 0;
            }

            unless ( $opts{journal}->can_have_email_alias ) {
                push @$errref, LJ::Lang::ml( '/rename.tt.error.emailnoalias' );
                $other_opts{email} = 0;
            }
        }

        $rename_opts{break_redirect}->{email} = ! $other_opts{email};
    }

    $opts{journal}->apply_rename_opts( %rename_opts );

    return ( 1, DW::Template->render_template(
        'success.tt', { message => "Successfully changed settings." }
    ) ) unless @$errref;

    # return the list of errors, because we want to print out other things as well...
    return ( 0, $errref );
}


sub siteadmin_rename_handler {
    my ( $ok, $rv ) = controller( privcheck => [ "siteadmin:rename" ] );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $post_args = DW::Request->get->post_args;

    my $vars = {};

    if ( $r->method eq "POST" ) {
        my ( $post_ok, $rv ) = handle_siteadmin_rename_post( $post_args );
        return $rv if $post_ok;
    
        $vars->{error_list} = $rv;
    }

    return DW::Template->render_template( "admin/rename_new.tt", $vars );
}


sub handle_siteadmin_rename_post {
    my ( $post_args ) = @_;

    return ( 0, [ LJ::Lang::ml( '/rename.tt.error.invalidform' ) ] )
        unless LJ::check_form_auth( $post_args->{lj_form_auth} );

    my $errref = [];

    my $from_user = LJ::load_user( $post_args->{user} );
    my $to_user = $post_args->{touser};

    push @$errref, LJ::Lang::ml( '/rename.tt.error.nojournal' ) unless $from_user;

    $from_user->rename( $to_user,
        token => DW::RenameToken->create_token( systemtoken => 1 ),
        user => LJ::get_remote(),
        force => 1,
        errref => $errref,
    );

    return ( 1, DW::Template->render_template(
        'success.tt', { message => "Successfully changed settings." }
    ) ) unless @$errref;

    return ( 0, $errref );
}
1;
