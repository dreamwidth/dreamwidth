#!/usr/bin/perl
#
# DW::Controller::OpenID
#
# This controller is for OpenID related pages.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2011-2020 by Dreamwidth Studios, LLC.
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

use LJ::OpenID;

DW::Routing->register_string( '/openid/index',   \&openid_index_handler,   app => 1 );
DW::Routing->register_string( '/openid/options', \&openid_options_handler, app => 1 );

# for responding to OpenID authentication requests
DW::Routing->register_string(
    '/openid/server', \&openid_server_handler,
    app      => 1,
    no_cache => 1
);

# for claiming imported comments
DW::Routing->register_string( '/openid/claim',         \&openid_claim_handler,         app => 1 );
DW::Routing->register_string( '/openid/claimed',       \&openid_claimed_handler,       app => 1 );
DW::Routing->register_string( '/openid/claim_confirm', \&openid_claim_confirm_handler, app => 1 );

# for handling site logins
DW::Routing->register_string(
    '/openid/login', \&openid_login_handler,
    app      => 1,
    no_cache => 1
);

sub openid_index_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $vars =
        { continue_to => $r->get_args->{returnto} || $r->header_in("Referer") };

    return DW::Template->render_template( 'openid/index.tt', $vars );
}

sub openid_options_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{remote};

    my $dbh     = LJ::get_db_writer();
    my $trusted = {};

    my $load_trusted = sub {
        $trusted = $dbh->selectall_hashref(
            q{
            SELECT ye.endpoint_id as 'endid', ye.url
            FROM openid_endpoint ye, openid_trust yt
            WHERE yt.endpoint_id=ye.endpoint_id
            AND yt.userid=? }, 'endid', undef, $u->userid
        );
    };

    $load_trusted->();

    # check for deletions
    if ( $r->did_post ) {
        foreach my $endid ( keys %$trusted ) {
            next unless $r->post_args->{"delete:$endid"};
            $dbh->do( "DELETE FROM openid_trust WHERE userid=? AND endpoint_id=?",
                undef, $u->userid, $endid );
        }

        $load_trusted->();
    }

    # construct row data
    my @rows;
    my $url_sort = sub { $trusted->{$a}->{url} cmp $trusted->{$b}->{url} };
    foreach my $endid ( sort $url_sort keys %$trusted ) {
        push @rows, [ "delete:$endid", $trusted->{$endid}->{url} ];
    }

    $rv->{rows} = \@rows;

    return DW::Template->render_template( 'openid/options.tt', $rv );
}

sub openid_server_handler {
    my $r   = DW::Request->get;
    my $get = $r->get_args;

    my $trust_root = $get->{'openid.trust_root'} // '';
    my $return_to  = $get->{'openid.return_to'}  // '';

    ## Non-OpenID-compliant section: rewrite LiveJournal's trust_root to
    ## https so that it will match their return_to URL and pass validation.
    $get->{'openid.trust_root'} = 'https://www.livejournal.com/'
        if ( $trust_root eq 'http://www.livejournal.com/'
        && $return_to =~ m|^https://www\.livejournal\.com/| );

    my $nos = LJ::OpenID::server( $get, $r->post_args );
    my ( $type, $data ) = $nos->handle_page( redirect_for_setup => 1 );

    return $r->redirect($data) if $type eq "redirect";

    $r->content_type($type) if $type;
    $r->print($data);
    return $r->OK;
}

sub openid_claim_handler {
    my $opts = shift;
    my $r    = DW::Request->get;
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $err = sub {
        my @errors = map { $_ =~ /^\./ ? LJ::Lang::ml("/openid/claim.tt$_") : $_ } @_;
        return DW::Template->render_template( 'openid/claim.tt', { error_list => \@errors } );
    };

    my $u      = $rv->{remote};
    my @claims = $u->get_openid_claims;
    return DW::Template->render_template( 'openid/claim.tt', { claims => \@claims } )
        unless $r->did_post;

    # at this point, the user did a POST, so we want to try to perform an OpenID
    # login on the given URL.
    my $args = $r->post_args;
    my $url  = LJ::trim( $args->{openid_url} );
    return $err->('.error.required') unless $url;
    return $err->('.error.invalidchars') if $url =~ /[\<\>\s]/;

    my $csr             = LJ::OpenID::consumer();
    my $tried_local_ref = LJ::OpenID::blocked_hosts($csr);

    my $claimed_id = eval { $csr->claimed_identity($url); };
    return $err->($@) if $@;

    unless ($claimed_id) {
        return $err->(
            LJ::Lang::ml(
                '/openid/claim.tt.error.cantuseownsite',
                { sitename => $LJ::SITENAMESHORT }
            )
        ) if $$tried_local_ref;
        return $err->( $csr->err );
    }

    my $check_url = $claimed_id->check_url(
        return_to      => "$LJ::SITEROOT/openid/claimed",
        trust_root     => "$LJ::SITEROOT/",
        delayed_return => 1,
    );
    return $r->redirect($check_url);
}

sub openid_claimed_handler {
    my $opts = shift;
    my $r    = DW::Request->get;
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $err = sub {
        my @errors = map { $_ =~ /^\./ ? LJ::Lang::ml("/openid/claim.tt$_") : $_ } @_;
        return DW::Template->render_template( 'openid/claim.tt', { error_list => \@errors } );
    };

    # attempt to verify the user
    my $u    = $rv->{remote};
    my $args = $r->get_args;
    return $r->redirect("$LJ::SITEROOT/openid/claim")
        unless exists $args->{'openid.mode'};

    my $csr = LJ::OpenID::consumer( $args->as_hashref );
    return $r->redirect("$LJ::SITEROOT/openid/claim")
        if $csr->user_cancel;

    my $setup = $csr->user_setup_url;
    return $r->redirect($setup) if $setup;

    my $return_to = "$LJ::SITEROOT/openid/claimed";
    return $r->redirect("$LJ::SITEROOT/openid/claim")
        if $args->{'openid.return_to'} && $args->{'openid.return_to'} !~ /^\Q$return_to\E/;

    my $vident = eval { $csr->verified_identity; };
    return $err->($@) if $@;
    return $err->( $csr->err ) unless $vident;

    my $url = $vident->url;
    return $err->('.error.invalidchars') if $url =~ /[\<\>\s]/;

    my $ou = LJ::User::load_identity_user( 'O', $url, $vident );
    return $err->('.error.failed_vivification') unless $ou;
    return $err->(
        LJ::Lang::ml(
            '/openid/claim.tt.error.account_deleted',
            {
                sitename => $LJ::SITENAMESHORT,
                aopts1   => '/openid',
                aopts2   => '/accountstatus',
            }
        )
    ) if $ou->is_deleted;

    # generate the authaction
    my $aa = LJ::register_authaction( $u->id, 'claimopenid', $ou->id )
        or return $err->('Internal error generating authaction.');
    my $confirm_url = "$LJ::SITEROOT/openid/claim_confirm?auth=$aa->{aaid}.$aa->{authcode}";

    # great, let's send them an email to confirm
    my $email = LJ::Lang::ml(
        '/openid/claim.tt.email',
        {
            sitename      => $LJ::SITENAME,
            sitenameshort => $LJ::SITENAMESHORT,
            remote        => $u->display_name,
            openid        => $ou->display_name,
            confirm_url   => $confirm_url,
        }
    );
    LJ::send_mail(
        {
            to   => $u->email_raw,
            from => $LJ::ADMIN_EMAIL,
            subject =>
                LJ::Lang::ml( '/openid/claim.tt.email.subject', { sitename => $LJ::SITENAME } ),
            body => $email,
        }
    );

    # now give them the conf page
    return DW::Template->render_template('openid/claim_sent.tt');
}

sub openid_claim_confirm_handler {
    my $opts = shift;
    my $r    = DW::Request->get;
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $err = sub {
        my @errors = map { $_ =~ /^\./ ? LJ::Lang::ml("/openid/claim_confirm.tt$_") : $_ } @_;
        return DW::Template->render_template( 'openid/claim_confirm.tt',
            { error_list => \@errors } );
    };

    my $u      = $rv->{remote};
    my @claims = $u->get_openid_claims;
    my $args   = $r->get_args;

    # verify that the link they followed is good
    my ( $aaid, $authcode );
    ( $aaid, $authcode ) = ( $1, $2 )
        if $args->{auth} =~ /^(\d+)\.(\w+)$/;
    my $aa = LJ::is_valid_authaction( $aaid, $authcode );
    return $err->('.error.invalid_auth')
        unless $aa && ref $aa eq 'HASH' && $aa->{used} eq 'N' && $aa->{action} eq 'claimopenid';
    return $err->('.error.wrong_account')
        if $aa->{userid} != $u->id;

    # now make sure nobody has since claimed that account
    my $ou = LJ::load_userid( $aa->{arg1} + 0 );
    return $err->('.error.invalid_account')
        unless $ou && $ou->is_identity;

    if ( my $cbu = $ou->claimed_by ) {
        return $err->('.error.already_claimed_self')
            if $cbu->equals($u);
        return $err->('.error.already_claimed_other');
    }

    return $err->(
        LJ::Lang::ml(
            '/openid/claim.tt.error.account_deleted',
            {
                sitename => $LJ::SITENAMESHORT,
                aopts1   => '/openid',
                aopts2   => '/accountstatus',
            }
        )
    ) if $ou->is_deleted;

    # now start the claim process
    $u->claim_identity($ou);

    return DW::Template->render_template('openid/claim_confirm.tt');
}

sub openid_login_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $remote = $rv->{remote};
    return error_ml( '/openid/login.tt.error.logout.content', { user => $remote->ljuser_display } )
        if $remote;

    my $r = $rv->{r};

    # yes, this looks at post_args without checking for did_post.
    # that's how the old page operated so I'm preserving that behavior.
    my $continue_to = $r->post_args->{'continue_to'};
    my $query_args  = $continue_to ? "?continue_to=" . LJ::eurl($continue_to) : "";
    my $return_to   = "$LJ::SITEROOT/openid/login" . $query_args;

    if ( $r->did_post ) {
        my $csr = LJ::OpenID::consumer();
        my $url = $r->post_args->{'openid_url'};

        return error_ml('/openid/login.tt.error.invalidcharacters') if $url =~ /[\<\>\s]/;

        my $tried_local_ref = LJ::OpenID::blocked_hosts($csr);

        my $claimed_id = eval { $csr->claimed_identity($url); };
        return error_ml( '/openid/login.tt.error.claimed_identity', { err => $@ } ) if $@;

        unless ($claimed_id) {
            return error_ml( '/openid/login.tt.error.cantuseownsite',
                { sitename => $LJ::SITENAMESHORT } )
                if $$tried_local_ref;
            return error_ml( '/openid/login.tt.error.loading_identity', { err => $csr->err } );
        }

        my $check_url = $claimed_id->check_url(
            return_to      => $return_to,
            trust_root     => "$LJ::SITEROOT/",
            delayed_return => 1,
        );
        return $r->redirect($check_url);
    }

    my $get_args = $r->get_args;
    if ( $get_args->{'openid.mode'} ) {

        my $csr = LJ::OpenID::consumer($get_args);
        return $r->redirect("$LJ::SITEROOT/openid/") if $csr->user_cancel;

        my $setup = $csr->user_setup_url;
        return $r->redirect($setup) if $setup;

        if (   $get_args->{'openid.return_to'}
            && $get_args->{'openid.return_to'} !~ /^\Q$return_to\E/ )
        {
            return error_ml( '/openid/login.tt.error.invalidparameter', { item => "return_to" } );
        }

        my $errmsg;
        my $u = LJ::User::load_from_consumer( $csr, \$errmsg );
        return error_ml( '/openid/login.tt.error.consumer_object', { err => $errmsg } )
            unless $u;

        my $sess_opts = { exptype => 'short', ipfixed => 0 };
        my $etime     = 0;

        # yes, we're looking at post args in a get request again.
        if ( $r->post_args->{'expire'} eq "never" ) {
            $etime = time() + 60 * 60 * 24 * 60;
            $sess_opts->{'exptype'} = "long";
        }

        $u->make_login_session( $sess_opts->{'exptype'}, $sess_opts->{'ipfixed'} );
        LJ::set_remote($u);

        my $redirect = "$LJ::SITEROOT/login";

        # handle the continue_to url, if it's a valid URL to redirect to.
        $continue_to = $get_args->{'continue_to'};
        if ($continue_to) {

            # some pages return a relative url
            if ( $continue_to =~ /^\// ) {
                $continue_to = $LJ::SITEROOT . $continue_to;
            }
            if ( DW::Controller::validate_redirect_url($continue_to) ) {

                # if the account is validated, then go ahead and redirect
                if ( $u->is_validated ) {
                    $redirect = $continue_to;
                }
                else {
                    $redirect .= "?continue_to=" . LJ::eurl($continue_to);
                }
            }
        }
        return $r->redirect($redirect);
    }

    # the old code displayed an empty page if we got this far. let's do better.
    return $r->redirect("$LJ::SITEROOT/login");
}

1;
