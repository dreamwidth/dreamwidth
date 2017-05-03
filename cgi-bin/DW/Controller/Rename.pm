#!/usr/bin/perl
#
# DW::Controller::Rename
#
# This controller is for renames
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010-2018 by Dreamwidth Studios, LLC.
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
use DW::FormErrors;

use DW::RenameToken;
use DW::Shop;

DW::Routing->register_string( "/rename/swap", \&swap_handler, app => 1 );

# token is now passed as a get argument
DW::Routing->register_string( "/rename/index", \&rename_handler, app => 1 );

DW::Routing->register_string( "/admin/rename/index", \&rename_admin_handler, app => 1 );
DW::Routing->register_string( "/admin/rename/edit", \&rename_admin_edit_handler, app => 1 );

DW::Routing->register_string( "/admin/rename/new", \&siteadmin_rename_handler, app => 1 );

DW::Controller::Admin->register_admin_page( '/',
    path => '/admin/rename/',
    ml_scope => '/admin/rename.tt',
    privs => [ 'siteadmin:rename', 'payments' ]
);

sub rename_handler {
    my ( $opts ) = @_;

    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = LJ::get_remote();

    return error_ml( 'rename.error.invalidaccounttype' ) unless $remote->is_personal;

    my $vars = {};

    my $post_args = DW::Request->get->post_args;
    my $get_args = DW::Request->get->get_args;
    my $given_token = $get_args->{giventoken};
    my $token = DW::RenameToken->new( token => $given_token );

    $get_args->{type} ||= "P";
    $get_args->{type} = "P" unless $get_args->{type} =~ m/^(P|C)$/;

    if ( $r->method eq "POST" ) {

        # this is kind of ugly. $post_ok is a hashref of template args
        # if it's a success, and false if it failed
        my $errors = DW::FormErrors->new;
        my $post_ok = handle_post( $token, $post_args, errors => $errors );
        return success_ml( "/rename.tt.success", $post_ok ) if $post_ok;

        $vars->{errors} = $errors;
    }

    $vars->{invalidtoken} = $given_token
        if $given_token && ! $token;

    my $rename_to_errors = DW::FormErrors->new;
    if ( $get_args->{checkuser} ) {
        $vars->{checkusername} = {
            user => $get_args->{checkuser},
            status => $remote->can_rename_to( $get_args->{checkuser}, errors => $rename_to_errors ) ? "available" : "unavailable",
            errors => $rename_to_errors
        };
    }

    if ( $token ) {
        if ( $token->applied || $token->revoked ) {
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
                journalname => $get_args->{type} eq "P" ? $remote->user : "communityname",
                journalurl  => $get_args->{type} eq "P" ? $remote->journal_base : LJ::journal_base( "communityname", vhost => "community" ),
                pageurl     => "/rename?giventoken=" . $token->token,
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

    if ( ! $token || ( $token && $token->applied ) || ( $token && $token->revoked ) ) {
        # grab a list of tokens they can use in case they didn't provide a usable token
        # assume we always have a remote because our controller is registered as requiring a remote (default behavior)
        $vars->{unused_tokens} = DW::RenameToken->by_owner_unused( userid => $remote->userid );
    }

    return DW::Template->render_template( 'rename.tt', $vars );
}

sub handle_post {
    my ( $token, $post_args, %opts ) = @_;

    my $errors = $opts{errors} || DW::FormErrors->new;

    unless ( LJ::check_form_auth( $post_args->{lj_form_auth} ) ) {
        $errors->add( '', '/rename.tt.error.invalidform' );
        return 0;
    }

    # the journal we are going to rename: yourself or a community you maintain
    my $journal = LJ::get_authas_user( $post_args->{authas} );
    $errors->add( 'authas', '/rename.tt.error.nojournal' ) unless $journal;

    my $fromusername = $journal ? $journal->user : "";

    my $tousername = $post_args->{touser};
    my $redirect_journal = $post_args->{redirect} && $post_args->{redirect} eq "disconnect" ? 0 : 1;
    $errors->add( 'redirect', '/rename.tt.error.noredirectopt' ) unless $post_args->{redirect};

    # since you can't recover deleted relationships, but you can delete the relationships later if something was missed
    # negate the form submission so we're explicitly stating which rels we want to delete, rather than deleting everything not listed
    my %keep_rel = map { $_ => 1 } $post_args->get_all( "rel_options" );
    my %del_rel = map { +"del_$_" => ! $keep_rel{$_} } qw( trusted_by watched_by trusted watched communities );

    my %other_opts = map { $_ => 1 } $post_args->get_all( "others" );
    if ( $other_opts{email} ) {
        if ( $post_args->{redirect} ne "forward" ) {
            $errors->add( 'redirect', '/rename.tt.error.emailnotforward', { emaildomain => "\@$LJ::USER_DOMAIN" } );
            $other_opts{email} = 0;
        }

        unless ( $journal->can_have_email_alias ) {
            $errors->add( 'others_email', '/rename.tt.error.emailnoalias' );
            $other_opts{email} = 0;
        }
    }

    # try the rename and see if there are any errors
    $journal->rename( $tousername, user => LJ::get_remote(), token => $token, redirect => $redirect_journal, redirect_email => $other_opts{email}, %del_rel, errors => $errors );

    return { from => $fromusername, to => $journal->user } unless $errors->exist;

    # the list of errors should be present in the caller
    return 0;
}


sub swap_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    return error_ml( 'rename.error.invalidaccounttype' ) unless $remote->is_personal;

    my $vars = {};

    my $post_args = DW::Request->get->post_args;

    if ( $r->method eq "POST" ) {
        # this is kind of ugly. $post_ok is a hashref of template args
        # if it's a success, and false if it failed
        my $errors = DW::FormErrors->new;
        my $post_ok = handle_swap_post( $post_args, user => $remote, errors => $errors );
        return success_ml( "/rename/swap.tt.success", $post_ok ) if $post_ok;

        $vars->{errors} = $errors;
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

    my $errors = $opts{errors} || DW::FormErrors->new;
    $errors->add( '', '/rename.tt.error.invalidform' ) unless LJ::check_form_auth( $post_args->{lj_form_auth} );

    my $journal = LJ::get_authas_user( $post_args->{authas} );
    $errors->add( 'authas', '/rename/swap.tt.error.nojournal' ) unless $journal;

    my $swapjournal = LJ::load_user( $post_args->{swapjournal} );
    $errors->add( 'swapjournal', '/rename/swap.tt.error.invalidswapjournal' ) unless $swapjournal;

    my $remote = $opts{user};
    my $get_unused_tokens = sub { @{DW::RenameToken->by_owner_unused( userid => $_[0]->id ) || []} };

    my @check_users = ( $journal, $swapjournal );
    unshift @check_users, $remote if $remote;

    my @unused_tokens = grep { defined } map { $get_unused_tokens->( $_ ) } @check_users;

    $errors->add( '', '/rename/swap.tt.numtokens.toofew',
                      { aopts => "href='/shop/renames?for=self'" } )
        unless @unused_tokens > 1;

    return 0 if $errors->exist;


    ( $journal, $swapjournal ) = ( $swapjournal, $journal )
        if $journal->is_community && $swapjournal->is_personal;

    # let's do this
    my $swap_errors = $opts{errors} || DW::FormErrors->new;
    $journal->swap_usernames( $swapjournal, user => $opts{user}, tokens => \@unused_tokens, errors => $swap_errors );

    return { journal => $journal->ljuser_display,
             swapjournal => $swapjournal->ljuser_display } unless $errors->exist;

    # the list of errors should be present in the caller
    return 0;
}

sub rename_admin_handler {
    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:rename', 'payments' ] );
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
    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:rename', 'payments' ] );
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
        my $errors = DW::FormErrors->new;
        my $post_ok = handle_admin_post( $token, $post_args,
                    journal     => $u,
                    from_user    => $token->fromuser,
                    to_user      => $token->touser,
                    errors      => $errors,
        );
        return DW::Template->render_template( 'success.tt',
            { message => "Successfully changed settings." } ) if $post_ok;

        $vars->{errors} = $errors;
    }

    return DW::Template->render_template( "admin/rename_edit.tt", $vars );
}

sub handle_admin_post {
    my ( $token, $post_args, %opts ) = @_;

    my $errors = $opts{errors} || DW::FormErrors->new;

    unless ( LJ::check_form_auth( $post_args->{lj_form_auth} ) ) {
        $errors->add( '', '/rename.tt.error.invalidform' );
        return 0;
    }

    my %rename_opts = ( user => LJ::get_remote(), from => $opts{from_user}, to => $opts{to_user} );

    if ( $post_args->{override_redirect} ) {
        if ( LJ::isu( $opts{journal} ) && $opts{from_user} && $opts{to_user} ) {
            my $redirect_journal = $post_args->{redirect} && $post_args->{redirect} eq "disconnect" ? 0 : 1;
            $rename_opts{break_redirect}->{username} = ! $redirect_journal;
        } else {
            $errors->add_string( '', "Cannot do redirect; invalid journal, or no username provided to rename from/to." );
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
                $errors->add( 'redirect', '/rename.tt.error.emailnotforward', { emaildomain => "\@$LJ::USER_DOMAIN" } );
                $other_opts{email} = 0;
            }

            unless ( $opts{journal}->can_have_email_alias ) {
                $errors->add( 'others_email', '/rename.tt.error.emailnoalias' );
                $other_opts{email} = 0;
            }
        }

        $rename_opts{break_redirect}->{email} = ! $other_opts{email};
    }

    $opts{journal}->apply_rename_opts( %rename_opts );

    return $errors->exist ? 0 : 1;
}


sub siteadmin_rename_handler {
    my ( $ok, $rv ) = controller( privcheck => [ 'siteadmin:rename', 'payments' ] );
    return $rv unless $ok;

    my $r = DW::Request->get;
    my $post_args = DW::Request->get->post_args;

    my $vars = {};

    if ( $r->method eq "POST" ) {
        my $errors = DW::FormErrors->new;
        my $post_ok = handle_siteadmin_rename_post( $post_args, errors => $errors );
        return DW::Template->render_template( 'success.tt',
            { message => "Successfully changed settings." } ) if $post_ok;

        $vars->{errors} = $errors;

        # also prefill form with previously submitted data
        $vars->{prev_user}   = $post_args->{user};
        $vars->{prev_touser} = $post_args->{touser};
    }

    return DW::Template->render_template( "admin/rename_new.tt", $vars );
}


sub handle_siteadmin_rename_post {
    my ( $post_args, %opts ) = @_;

    my $errors = $opts{errors} || DW::FormErrors->new;

    unless ( LJ::check_form_auth( $post_args->{lj_form_auth} ) ) {
        $errors->add( '', '/rename.tt.error.invalidform' );
        return 0;
    }

    my $from_user = LJ::load_user( $post_args->{user} );
    my $to_user = $post_args->{touser};

    $errors->add( 'user', '/rename.tt.error.nojournal' ) unless $from_user;

    $from_user->rename( $to_user,
        token => DW::RenameToken->create_token( systemtoken => 1 ),
        user => LJ::get_remote(),
        force => 1,
        errors => $errors,
        form_from => 'user',
    ) if defined $from_user;

    return $errors->exist ? 0 : 1;
}
1;
