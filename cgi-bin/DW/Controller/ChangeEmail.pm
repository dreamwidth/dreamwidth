#!/usr/bin/perl
#
# DW::Controller::Changeemail
#
# This controller is for the Change Email page.
#
# Authors:
#      hotlevel4 <hotlevel4@hotmail.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Changeemail;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/changeemail', \&changeemail_handler, app => 1 );

sub changeemail_handler {
    my ( $ok, $rv ) = controller( authas => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $post   = $r->post_args;
    my $u      = $rv->{u};
    my $remote = $rv->{remote};

    my $vars;
    $vars->{u}      = $u;
    $vars->{remote} = $remote;

    return error_ml('/changeemail.tt.error.suspended') if $u->is_suspended;

    $vars->{getextra} = ( $u ne $remote ) ? ( "?authas=" . $u->user ) : '';

    my $is_identity_no_email = $u->is_identity && !$u->email_raw;
    $vars->{noemail} = 1 if $is_identity_no_email;

    $vars->{is_identity}  = 1 if $u->is_identity;
    $vars->{is_community} = 1 if $u->is_community;

    # Warn if logged in and not validated
    $vars->{notvalidated} = 1
        if ( $u && !$r->did_post && $u->{'status'} ne 'A' && !$is_identity_no_email );

    $vars->{old_email} = $is_identity_no_email ? '' : $u->email_raw;

    $vars->{authas_html} = $rv->{authas_html};

    if ( $r->did_post && ( $post->{email} || $post->{password} ) ) {
        my $password = $post->{password};
        my $email    = LJ::trim( $post->{email} );

        my @errors = ();

        LJ::check_email( $post->{email}, \@errors, $post, \( $vars->{email_checkbox} ) );

        my $blocked = 0;

        if ( $LJ::BLOCKED_PASSWORD_EMAIL && $post->{email} =~ /$LJ::BLOCKED_PASSWORD_EMAIL/ ) {
            $blocked = 1;
            push @errors, LJ::Lang::ml('/changeemail.tt.error.invalidemail');
        }

        if ( $LJ::USER_EMAIL and $post->{email} =~ /\@\Q$LJ::USER_DOMAIN\E$/i ) {
            push @errors,
                LJ::Lang::ml(
                "/changeemail.tt.error.lj_domain2",
                {
                    'user'   => $remote->{'user'},
                    'domain' => $LJ::USER_DOMAIN,
                    'aopts'  => "href='$LJ::SITEROOT/manage/profile/'"
                }
                );
        }

        if ( $post->{email} =~ /\s/ ) {
            push @errors, LJ::Lang::ml('/changeemail.tt.error.nospace');
        }

        if ( !$remote->is_identity && ( !defined $password || $password ne $remote->password ) ) {
            push @errors, LJ::Lang::ml('/changeemail.tt.error.invalidpassword');
        }

        $vars->{error_list} = \@errors if @errors;

        ## make note of changed email
        my $is_identity_no_email = $u->is_identity && !$u->email_raw;
        my $old_email            = $is_identity_no_email ? "none" : $u->email_raw;

        my $loginfo = "old: $old_email, new: $post->{email}";
        $loginfo .= ", ip: " . $r->get_remote_ip if $LJ::LOG_CHANGEEMAIL_IP;
        $loginfo .= ", blocked: " . $blocked;
        $loginfo .= ", success: " . ( ( scalar @errors ) ? 'false' : 'true' );

        LJ::statushistory_add( $u, $remote, 'email_changed', $loginfo );

        unless ( scalar @errors ) {
            $u->infohistory_add( 'email', $old_email, $u->{status} );

            $u->log_event( 'email_change', { remote => $remote, new => $post->{email} } );

            LJ::Hooks::run_hook(
                'post_email_change',
                {
                    user     => $u,
                    newemail => $post->{email},
                }
            );

            my $tochange = { email => $post->{email} };
            $tochange->{status} = 'T' if $u->{status} eq 'A';

            $u->update_self($tochange);

            # send letter to old email address
            my @date = localtime(time);
            LJ::send_mail(
                {
                    'to'       => $old_email,
                    'from'     => $LJ::ADMIN_EMAIL,
                    'fromname' => $LJ::SITENAME,
                    'charset'  => 'utf-8',
                    'subject'  => LJ::Lang::ml('/changeemail.tt.newemail_old.subject'),
                    'body'     => LJ::Lang::ml(
                        '/changeemail.tt.newemail_old.body2',
                        {
                            username          => $u->display_username,
                            ip                => $r->get_remote_ip,
                            old_email         => $old_email,
                            new_email         => $post->{email},
                            email_change_link => $LJ::SITEROOT . '/changeemail',
                            email_manage_link => $LJ::SITEROOT . '/tools/emailmanage',
                            sitename          => $LJ::SITENAME,
                            sitelink          => $LJ::SITEROOT,
                            datetime          => sprintf(
                                "%02d:%02d %02d/%02d/%04d",
                                @date[ 2, 1 ],
                                $date[3],
                                $date[4] + 1,
                                $date[5] + 1900
                            ),
                        }
                    ),
                }
            ) unless $is_identity_no_email;

            # send validation mail
            my $aa = LJ::register_authaction( $u->{'userid'}, "validateemail", $post->{email} );
            if ($is_identity_no_email) {
                LJ::send_mail(
                    {
                        'to'       => $post->{email},
                        'from'     => $LJ::ADMIN_EMAIL,
                        'fromname' => $LJ::SITENAME,
                        'charset'  => 'utf-8',
                        'subject'  => LJ::Lang::ml('/changeemail.tt.newemail.subject.openid'),
                        'body'     => LJ::Lang::ml(
                            '/changeemail.tt.newemail.body.openid',
                            {
                                username => $u->display_username,
                                sitename => $LJ::SITENAME,
                                sitelink => $LJ::SITEROOT,
                                conflink => "$LJ::SITEROOT/confirm/$aa->{'aaid'}.$aa->{'authcode'}"
                            }
                        ),
                    }
                );
            }
            else {
                LJ::send_mail(
                    {
                        'to'       => $post->{email},
                        'from'     => $LJ::ADMIN_EMAIL,
                        'fromname' => $LJ::SITENAME,
                        'charset'  => 'utf-8',
                        'subject'  => LJ::Lang::ml('/changeemail.tt.newemail.subject'),
                        'body'     => LJ::Lang::ml(
                            '/changeemail.tt.newemail.body3',
                            {
                                username => $u->display_username,
                                email    => $u->email_raw,
                                sitename => $LJ::SITENAME,
                                sitelink => $LJ::SITEROOT,
                                conflink => "$LJ::SITEROOT/confirm/$aa->{'aaid'}.$aa->{'authcode'}"
                            }
                        ),
                    }
                );
            }
            $vars->{success} = 1;
        }
    }
    return DW::Template->render_template( 'changeemail.tt', $vars );
}

1;
