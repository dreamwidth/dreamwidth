#!/usr/bin/perl
#
# DW::Controller::OpenID
#
# This controller is for OpenID related pages.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::OpenID;

use strict;
use warnings;
use DW::Routing;
use DW::Controller;
use DW::Template;

DW::Routing->register_string( '/openid/claim', \&openid_claim_handler, app => 1 );
DW::Routing->register_string( '/openid/claimed', \&openid_claimed_handler, app => 1 );
DW::Routing->register_string( '/openid/claim_confirm', \&openid_claim_confirm_handler, app => 1 );

sub openid_claim_handler {
    my $opts = shift;
    my $r = DW::Request->get;
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $err = sub {
        my @errors = map { $_ =~ /^\./ ? LJ::Lang::ml( "/openid/claim.tt$_" ) : $_ } @_;
        return DW::Template->render_template( 'openid/claim.tt', { error_list => \@errors } );
    };

    return $err->( '.error.no_openid' )
        unless LJ::OpenID::consumer_enabled();

    my $u = $rv->{remote};
    my @claims = $u->get_openid_claims;
    return DW::Template->render_template( 'openid/claim.tt', { claims => \@claims } )
        unless $r->did_post;

    # at this point, the user did a POST, so we want to try to perform an OpenID
    # login on the given URL.
    my $args = $r->post_args;
    my $url = LJ::trim( $args->{openid_url} );
    return $err->( '.error.required' ) unless $url;
    return $err->( '.error.invalidchars' ) if $url =~ /[\<\>\s]/;

    my $csr = LJ::OpenID::consumer();
    my $tried_local_ref = LJ::OpenID::blocked_hosts( $csr );

    my $claimed_id = eval { $csr->claimed_identity($url); };
    return $err->( $@ ) if $@;

    unless ( $claimed_id ) {
        return $err->( LJ::Lang::ml( '/openid/claim.tt.error.cantuseownsite', { sitename => $LJ::SITENAMESHORT } ) )
            if $$tried_local_ref;
        return $err->( $csr->err );
    }

    my $check_url = $claimed_id->check_url(
        return_to => "$LJ::SITEROOT/openid/claimed",
        trust_root => "$LJ::SITEROOT/",
        delayed_return => 1,
    );
    return $r->redirect( $check_url );
}

sub openid_claimed_handler {
    my $opts = shift;
    my $r = DW::Request->get;
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $err = sub {
        my @errors = map { $_ =~ /^\./ ? LJ::Lang::ml( "/openid/claim.tt$_" ) : $_ } @_;
        return DW::Template->render_template( 'openid/claim.tt', { error_list => \@errors } );
    };

    return $err->( '.error.no_openid' )
        unless LJ::OpenID::consumer_enabled();

    # attempt to verify the user
    my $u = $rv->{remote};
    my $args = $r->get_args;
    return $r->redirect( "$LJ::SITEROOT/openid/claim" )
        unless exists $args->{'openid.mode'};

    my $csr = LJ::OpenID::consumer( $args->as_hashref );
    return $r->redirect( "$LJ::SITEROOT/openid/claim" )
        if $csr->user_cancel;

    my $setup = $csr->user_setup_url;
    return $r->redirect( $setup ) if $setup;

    my $return_to = "$LJ::SITEROOT/openid/claimed";
    return $r->redirect( "$LJ::SITEROOT/openid/claim" )
        if $args->{'openid.return_to'} && $args->{'openid.return_to'} !~ /^\Q$return_to\E/;

    my $vident = eval { $csr->verified_identity; };
    return $err->( $@ ) if $@;
    return $err->( $csr->err ) unless $vident;

    my $url = $vident->url;
    return $err->( '.error.invalidchars' ) if $url =~ /[\<\>\s]/;

    my $ou = LJ::User::load_identity_user( 'O', $url, $vident );
    return $err->( '.error.failed_vivification' ) unless $ou;
    return $err->( LJ::Lang::ml( '/openid/claim.tt.error.account_deleted',
                                 { sitename => $LJ::SITENAMESHORT,
                                   aopts1 => '/openid',
                                   aopts2 => '/accountstatus',
                                 }
                               )
                 ) if $ou->is_deleted;

    # generate the authaction
    my $aa = LJ::register_authaction( $u->id, 'claimopenid', $ou->id )
        or return $err->( 'Internal error generating authaction.' );
    my $confirm_url = "$LJ::SITEROOT/openid/claim_confirm?auth=$aa->{aaid}.$aa->{authcode}";

    # great, let's send them an email to confirm
    my $email = LJ::Lang::ml( '/openid/claim.tt.email', {
        sitename      => $LJ::SITENAME,
        sitenameshort => $LJ::SITENAMESHORT,
        remote        => $u->display_name,
        openid        => $ou->display_name,
        confirm_url   => $confirm_url,
    } );
    LJ::send_mail( {
        to      => $u->email_raw,
        from    => $LJ::ADMIN_EMAIL,
        subject => LJ::Lang::ml( '/openid/claim.tt.email.subject', { sitename => $LJ::SITENAME } ),
        body    => $email,
        delay   => 1800,
    } );

    # now give them the conf page
    return DW::Template->render_template( 'openid/claim_sent.tt' );
}

sub openid_claim_confirm_handler {
    my $opts = shift;
    my $r = DW::Request->get;
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $err = sub {
        my @errors = map { $_ =~ /^\./ ? LJ::Lang::ml( "/openid/claim_confirm.tt$_" ) : $_ } @_;
        return DW::Template->render_template( 'openid/claim_confirm.tt', { error_list => \@errors } );
    };

    my $u = $rv->{remote};
    my @claims = $u->get_openid_claims;
    my $args = $r->get_args;

    # verify that the link they followed is good
    my ( $aaid, $authcode );
    ( $aaid, $authcode ) = ( $1, $2 )
        if $args->{auth} =~ /^(\d+)\.(\w+)$/;
    my $aa = LJ::is_valid_authaction( $aaid, $authcode );
    return $err->( '.error.invalid_auth' )
        unless $aa && ref $aa eq 'HASH' && $aa->{used} eq 'N' && $aa->{action} eq 'claimopenid';
    return $err->( '.error.wrong_account' )
        if $aa->{userid} != $u->id;

    # now make sure nobody has since claimed that account
    my $ou = LJ::load_userid( $aa->{arg1}+0 );
    return $err->( '.error.invalid_account' )
        unless $ou && $ou->is_identity;

    if ( my $cbu = $ou->claimed_by ) {
        return $err->( '.error.already_claimed_self' )
            if $cbu->equals( $u );
        return $err->( '.error.already_claimed_other' );
    }

    return $err->( LJ::Lang::ml( '/openid/claim.tt.error.account_deleted',
                                 { sitename => $LJ::SITENAMESHORT,
                                   aopts1 => '/openid',
                                   aopts2 => '/accountstatus',
                                 }
                               )
                 ) if $ou->is_deleted;

    # now start the claim process
    $u->claim_identity( $ou );

    return DW::Template->render_template( 'openid/claim_confirm.tt' );
}

1;
