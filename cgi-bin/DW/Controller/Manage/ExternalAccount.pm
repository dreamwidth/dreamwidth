#!/usr/bin/perl
#
# DW::Controller::Manage::ExternalAccount
#
# Lets a user add or edit an external account for crossposting. The list of
# configured accounts (and the delete action) lives on the "Other Sites" tab
# of /manage/settings/, which links here.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Manage::ExternalAccount;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

use DW::External::Account;
use DW::External::Site;
use DW::External::XPostProtocol;

DW::Routing->register_string(
    '/manage/externalaccount', \&externalaccount_handler,
    app      => 1,
    no_cache => 1
);

my $ml_scope = '/manage/externalaccount.tt';

sub externalaccount_handler {
    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $u    = $rv->{remote};
    my $get  = $r->get_args;
    my $post = $r->post_args;

    LJ::need_res( { group => "foundation" }, "js/pages/manage/externalaccount.js" );

    my $errors = DW::FormErrors->new;

    if ( $r->did_post ) {
        my $acctid =
            $post->{acctid}
            ? edit_external_account( $u, $post, $errors )
            : create_external_account( $u, $post, $errors );
        if ($acctid) {
            my $arg = $post->{acctid} ? "update" : "create";
            return $r->redirect(
                LJ::create_url(
                    "/manage/settings/", args => { cat => "othersites", $arg => $acctid }
                )
            );
        }
    }

    # editing an existing account if a valid acctid was passed
    my $editacct;
    if ( my $acctid = $get->{acctid} || $post->{acctid} ) {
        $editacct = DW::External::Account->get_external_account( $u, $acctid );
    }

    # the sites available in the site dropdown, for new accounts
    my @sites;
    unless ($editacct) {
        @sites =
            map {
            { siteid => $_->{siteid}, sitename => $_->{sitename}, protocolid => $_->servicetype }
            }

            # LJRossia is temporarily broken, so remove from list
            grep { $_->{sitename} ne 'LJRossia' }
            sort { $a->{sitename} cmp $b->{sitename} } DW::External::Site->get_xpost_sites;
    }

    # per-protocol option sections; only the section for the currently
    # selected protocol is shown (js/pages/manage/externalaccount.js)
    my %protocols = DW::External::XPostProtocol->get_all_protocols;
    my @protocol_sections;
    foreach my $protocol_id ( sort keys %protocols ) {
        my $protocol = $protocols{$protocol_id};
        my @options =
            grep { $_->{type} eq 'select' }
            $protocol->protocol_options( $editacct, $r->did_post ? $post : undef );
        push @protocol_sections,
            { id => $protocol_id, protocolid => $protocol->protocolid, options => \@options }
            if @options;
    }

    # the registry key for the account's protocol ('lj'), which names the
    # protocol option section; distinct from protocolid ('LJ-XMLRPC')
    my $edit_protocol;
    if ($editacct) {
        my $protocol = $editacct->protocol;
        ($edit_protocol) = grep { $protocols{$_} == $protocol } keys %protocols;
    }

    my $did_post = $r->did_post;
    $rv->{editacct}          = $editacct;
    $rv->{edit_protocol}     = $edit_protocol;
    $rv->{sites}             = \@sites;
    $rv->{servicetype_items} = [ map { ( $_, $_ ) } sort keys %protocols ];
    $rv->{protocol_sections} = \@protocol_sections;
    $rv->{site_selected}     = $did_post ? $post->{site} : 2;
    $rv->{xpostbydefault_sel} =
        $did_post ? $post->{xpostbydefault} : $editacct ? $editacct->xpostbydefault : 0;
    $rv->{recordlink_sel} = $did_post ? $post->{recordlink} : $editacct ? $editacct->recordlink : 0;
    $rv->{savepassword_sel} =
          $did_post ? $post->{savepassword}
        : $editacct ? $editacct->password ne ""
        :             1;
    $rv->{formdata} = $post;
    $rv->{errors}   = $errors;

    return DW::Template->render_template( 'manage/externalaccount.tt', $rv );
}

# form handler.  does the actual new account creation.
# returns the new acctid on success, 0 on failure.
sub create_external_account {
    my ( $u, $post, $errors ) = @_;

    # check to see if we're already at max.
    my $max_accts = $u->count_max_xpost_accounts;
    my @accounts  = DW::External::Account->get_external_accounts($u);
    if ( scalar @accounts >= $max_accts ) {
        my $errmsg =
            ( $max_accts == 1 )
            ? "$ml_scope.error.maxacct.singular"
            : "$ml_scope.error.maxacct.plural";
        $errors->add( '', $errmsg, { max_accts => $max_accts } );
        return 0;
    }

    my %opts;
    my $ok = 1;

    # general properties, for all servers
    $opts{$_} = $post->{$_} for qw( password username xpostbydefault recordlink savepassword );

    # username is required
    unless ( $opts{username} ) {
        $errors->add( 'username', "$ml_scope.error.username.required" );
        $ok = 0;
    }

    my $extacct_info = { %{ $post->as_hashref } };

    # check if it's a default site or a custom site
    if ( $post->{site} ne -1 ) {

        # default site; just use the siteid
        $opts{siteid} = $post->{site};
    }
    else {
        # custom site
        $opts{$_} = $post->{$_} for qw( servicename servicetype serviceurl );

        # all three fields are required for custom sites
        foreach my $reqfield (qw( servicename servicetype serviceurl )) {
            unless ( $opts{$reqfield} ) {
                $errors->add( $reqfield, "$ml_scope.error.$reqfield.required" );
                $ok = 0;
            }
        }

        # validate the site.
        if ($ok) {
            my $protocol = DW::External::XPostProtocol->get_protocol( $opts{servicetype} );
            if ( !$protocol ) {
                $errors->add( 'servicetype', "$ml_scope.error.servicetype",
                    { servicetype => $opts{servicetype} } );
                $ok = 0;
            }
            else {
                my ( $valid, $serviceurl ) = $protocol->validate_server( $opts{serviceurl} );
                if ($valid) {

                    # update in case it's been canonicalized
                    $extacct_info->{serviceurl} = $opts{serviceurl} = $serviceurl;
                }
                else {
                    $errors->add( 'serviceurl', "$ml_scope.error.url",
                        { url => $opts{serviceurl} } );
                    $ok = 0;
                }
            }
        }
    }

    # verification of account info - only do this if $ok isn't already set
    # to 0, so we have username/password and valid site info
    if ($ok) {
        my $account_valid = account_isvalid( $u, $extacct_info );

        unless ( $account_valid eq '1' ) {
            $ok = 0;

            # specific error messages for the server errors we recognize;
            # otherwise show the one we get from the server
            if ( $account_valid eq "Invalid username" ) {
                $errors->add( 'username', "$ml_scope.error.username.invalid" );
            }
            elsif ( $account_valid eq "Invalid password" ) {
                $errors->add( 'password', "$ml_scope.error.password.invalid" );
            }
            elsif ( $account_valid eq
"Client error: Your IP address is temporarily banned for exceeding the login failure rate."
                )
            {
                $errors->add( '', "$ml_scope.error.ipban" );
            }
            else {
                $errors->add_string( '', $account_valid );
            }
        }
    }

    if ($ok) {

        # check the options, if any.
        my $protocol;
        if ( $opts{siteid} ) {
            my $site = DW::External::Site->get_site_by_id( $opts{siteid} );
            $protocol = DW::External::XPostProtocol->get_protocol( $site->servicetype );
        }
        else {
            $protocol = DW::External::XPostProtocol->get_protocol( $opts{servicetype} );
        }
        $opts{options} = parse_options( $protocol, $post );

        # if the user requested that we don't save their password, then
        # don't save their password.
        $opts{password} = "" unless $opts{savepassword};

        my $new_acct = DW::External::Account->create( $u, \%opts );
        return $new_acct->acctid if $new_acct;

        $errors->add( '', "$ml_scope.error.createfailed" );
    }

    return 0;
}

# check whether an account actually exists on the other service and whether
# the password is correct by sending a 'login' request
sub account_isvalid {
    my ( $u, $extacct ) = @_;

    # if the site was selected from the drop-down, we need to get the
    # corresponding values.  if it's user-entered, we can construct the site
    # from these values.  we only run this check if we have already
    # validated the external site.
    my ( $protocol_id, $proxyurl );
    if ( $extacct->{site} ne -1 ) {
        my $externalsite = DW::External::Site->get_site_by_id( $extacct->{site} );
        $proxyurl    = "https://" . $externalsite->{domain} . "/interface/xmlrpc";
        $protocol_id = $externalsite->servicetype;
    }
    else {
        $proxyurl    = $extacct->{serviceurl};
        $protocol_id = $extacct->{servicetype};
    }

    # need to encrypt password to send it
    my $protocol = DW::External::XPostProtocol->get_protocol($protocol_id);
    $extacct->{encrypted_password} = $protocol->encrypt_password( $extacct->{password} );

    # check to see whether we can log in with this data
    my $authresp =
        DW::External::XPostProtocol::LJXMLRPC->call_xmlrpc( $proxyurl, 'login', {}, $extacct );

    # if the validation was successful, return 1, if not the error message
    return $authresp->{success} ? 1 : $authresp->{error};
}

# form handler.  edits the given account.
# returns the acctid on success, 0 on failure.
sub edit_external_account {
    my ( $u, $post, $errors ) = @_;

    my $acct = DW::External::Account->get_external_account( $u, $post->{acctid} );
    return 0 unless $acct;

    if ( !$post->{savepassword} ) {

        # don't save the password. checkbox unchecked
        $acct->set_password("");
    }
    elsif ( $post->{password} && $post->{password} ne "" ) {

        # we have a password
        $acct->set_password( $post->{password} );
    }
    $acct->set_xpostbydefault( $post->{xpostbydefault} );
    $acct->set_recordlink( $post->{recordlink} );

    $acct->set_options( parse_options( $acct->protocol, $post ) );

    return $acct->acctid;
}

# returns the appropriate options from the post.
sub parse_options {
    my ( $protocol, $post ) = @_;

    my $options = {};
    foreach my $option ( $protocol->protocol_options ) {
        my $option_name = $option->{opts}->{name};
        my $value       = $post->{$option_name};
        $options->{$option_name} = $value if $value;
    }
    return $options;
}

1;
