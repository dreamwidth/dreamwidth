#!/usr/bin/perl
#
# DW::Controller::Manage::EmailPost
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
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#

package DW::Controller::Manage::EmailPost;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

use DW::API::Key;
use LJ::Emailpost::Web;

DW::Routing->register_string( "/manage/emailpost", \&emailpost_handler, app => 1 );

sub emailpost_handler {
    my $ml_scope = "/manage/emailpost.tt";
    return error_ml("$ml_scope.error.sitenotconfigured") unless $LJ::EMAIL_POST_DOMAIN;

    my ( $ok, $rv ) = controller( anonymous => 0, form_auth => 1 );
    return $rv unless $ok;

    my $u = $rv->{u};
    return DW::Template->render_template( 'error.tt', { message => $LJ::MSG_READONLY_USER } )
        if $u->is_readonly;

    return error_ml("$ml_scope.error.acct") unless $u->can_emailpost;

    my @emailpost_props = qw/
        emailpost_pin emailpost_allowfrom
        emailpost_userpic emailpost_security
        emailpost_comments
        /;
    $u->preload_props(@emailpost_props);
    $rv->{u} = $u;

    my $r         = $rv->{r};
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;

    my ( $mode, $type ) = ( $form_args->{mode}, $form_args->{type} );

    if ( $mode && $mode eq 'help' ) {
        $rv->{type}      = $type;
        $rv->{format_to} = sub { sprintf "%s@%s", $_[0], $LJ::EMAIL_POST_DOMAIN };

        if ( my @addr = split /\s*,\s*/, ( $u->{emailpost_allowfrom} || '' ) ) {
            my $email = $addr[0];
            $email =~ s/\(\w\)$//;
            $rv->{example} = $email;
        }

        return DW::Template->render_template( 'manage/emailpost_help.tt', $rv );
    }

    # this was 2, but it's 4 on mobile settings - should be consistent
    $rv->{addr_max} = 4;

    $rv->{addrlist} = LJ::Emailpost::Web::get_allowed_senders($u);
    $rv->{apikeys}  = DW::API::Key->get_keys_for_user($u);

    if ( $r->did_post ) {
        my $success_links = [
            {
                text => LJ::Lang::ml("$ml_scope.success.back"),
                url  => '/manage/emailpost'
            },
            {
                text => LJ::Lang::ml("$ml_scope.success.info"),
                url  => '/manage/emailpost?mode=help'
            },
            {
                text => LJ::Lang::ml("$ml_scope.success.settings"),
                url  => '/manage/settings/?cat=mobile'
            },
        ];

        my $errors = DW::FormErrors->new;

        if ( $form_args->{save} ) {
            my $pin = $form_args->{pin};
            $pin =~ s/\s+//g if defined $pin;

            $errors->add( 'pin', "$ml_scope.error.invalidpin", { num => 4 } )
                if $pin && $pin !~ /^([a-z0-9]){4,20}$/i;

            $errors->add( 'pin', "$ml_scope.error.invalidpinuser" )
                if $pin && $pin eq $u->user;

            # Check email, add flags if needed.
            my %allowed;
            my @send_helpmessage;

            foreach my $count ( 0 .. $rv->{addr_max} ) {
                my $a = $form_args->{"addresses_$count"} or next;
                $a =~ s/\s+//g;
                next unless $a;
                next if length $a > 80;
                $a = lc $a;

                my @email_errors;
                LJ::check_email( $a, \@email_errors, { force_spelling => 1 } );

                $errors->add(
                    "addresses_$count",
                    "$ml_scope.error.invalidemail",
                    { email => LJ::ehtml($a), error => $email_errors[0] }
                ) if @email_errors;

                $allowed{$a} = {};
                $allowed{$a}->{get_errors} = 1 if $form_args->{"check_$count"};
                push @send_helpmessage, $a if $form_args->{"help_$count"};
            }

            if ( $errors->exist ) {
                $rv->{errors}   = $errors;
                $rv->{formdata} = $r->post_args;
                return DW::Template->render_template( 'manage/emailpost.tt', $rv );
            }

            $u->set_prop( "emailpost_pin", $pin );
            foreach my $prop (@emailpost_props) {
                next if $prop =~ /emailpost_(allowfrom|pin)/;
                next if ( $u->{$prop} // '' ) eq ( $form_args->{$prop} // '' );

                if ( $form_args->{$prop} && $form_args->{$prop} ne 'default' ) {
                    $u->set_prop( $prop, $form_args->{$prop} );
                }
                else {
                    $u->set_prop( $prop, undef );
                }
            }

            LJ::Emailpost::Web::set_allowed_senders( $u, \%allowed );
            email_helpmessage( $u, $_ ) foreach @send_helpmessage;

            return success_ml( "$ml_scope.success.message", undef, $success_links );
        }

        my $info_box = sub {
            my ( $bool, $succ, $err ) = @_;
            my @sp_args = $bool ? ( 'highlight', $succ ) : ( 'error', $err );
            return sprintf "<div class='%s-box'>%s</div>", @sp_args;
        };

        $rv->{info_box} = '';

        # if we just reset the token, add a header but show the original page still
        if ( $form_args->{'action:token'} ) {
            $rv->{info_box} = $info_box->(
                $u->generate_emailpost_auth,
                LJ::Lang::ml("$ml_scope.reply.status.success"),
                LJ::Lang::ml("$ml_scope.reply.status.error"),
            );
        }

        if ( $form_args->{'action:apikey'} ) {
            $rv->{info_box} = $info_box->(
                DW::API::Key->new_for_user($u),
                LJ::Lang::ml("$ml_scope.api.status.success"),
                LJ::Lang::ml("$ml_scope.api.status.error"),
            );
        }

        if ( $form_args->{'action:delete'} ) {
            for ( my $api_idx = 0 ; $api_idx < @{ $rv->{apikeys} } ; $api_idx++ ) {
                my $deleted = $form_args->{"delete_${api_idx}"} or next;
                $deleted =~ s/\s+//g;
                next unless $deleted;
                my $key = DW::API::Key->get_key($deleted);
                next unless defined $key;

                $rv->{info_box} .= $info_box->(
                    $key->delete($u),
                    LJ::Lang::ml( "$ml_scope.api.delete.success", { key => $key->{keyhash} } ),
                    LJ::Lang::ml( "$ml_scope.api.delete.error",   { key => $key->{keyhash} } ),
                );
            }
        }

        # regenerate list to reflect key changes
        $rv->{apikeys} = DW::API::Key->get_keys_for_user($u);
    }

    return DW::Template->render_template( 'manage/emailpost.tt', $rv );
}

sub email_helpmessage {
    my ( $u, $address ) = @_;
    return unless $u && $address;
    my $user = LJ::isu($u) ? $u->user : $u;    # allow object or string

    my $format_to = sub { sprintf "%s@%s", $_[0], $LJ::EMAIL_POST_DOMAIN };

    LJ::send_mail(
        {
            to       => $address,
            from     => $LJ::BOGUS_EMAIL,
            fromname => $LJ::SITENAME,
            subject  => LJ::Lang::ml(
                'setting.emailposting.helpmessage.subject',
                { sitenameshort => $LJ::SITENAMESHORT }
            ),
            body => LJ::Lang::ml(
                'setting.emailposting.helpmessage.body',
                {
                    email => $format_to->("$user+PIN"),
                    comm  => $format_to->("$user.communityname"),
                    url   => "$LJ::SITEROOT/manage/emailpost"
                }
            ),
        }
    );
}

1;
