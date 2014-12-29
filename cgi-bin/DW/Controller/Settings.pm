#!/usr/bin/perl
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.

package DW::Controller::Settings;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

=head1 NAME

DW::Controller::Settings - Controller for settings/settings-related pages

=cut

DW::Routing->register_string( "/accountstatus", \&account_status_handler, app => 1 );
DW::Routing->register_string( "/changepassword", \&changepassword_handler, app => 1, prefer_ssl => 1 );


sub account_status_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1, authas => { show_all => 1 } );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $remote = $rv->{remote};
    my $u = $rv->{u};
    my $get = $r->get_args;

    my $ml_scope = "/settings/accountstatus.tt";
    my @statusvis_options = $u->is_suspended
                                ? ( 'S' => LJ::Lang::ml( "$ml_scope.journalstatus.select.suspended" ) )
                                : ( 'V' => LJ::Lang::ml( "$ml_scope.journalstatus.select.activated" ),
                                    'D' => LJ::Lang::ml( "$ml_scope.journalstatus.select.deleted" ),
                                );
    my %statusvis_map = @statusvis_options;

    my $errors = DW::FormErrors->new;

    # TODO: this feels like a misuse of DW::FormErrors. Make a new class?
    my $messages = DW::FormErrors->new;
    my $warnings = DW::FormErrors->new;

    my $post;
    if ( $r->did_post && LJ::check_referer( '/accountstatus' ) ) {
        $post = $r->post_args;
        my $new_statusvis  = $post->{statusvis};

        # are they suspended?
        $errors->add( "", ".error.nochange.suspend" )
            if $u->is_suspended;

        # are they expunged?
        $errors->add( "", '.error.nochange.expunged' )
            if $u->is_expunged;

        # invalid statusvis
        $errors->add( "", '.error.invalid' )
            unless $new_statusvis eq 'D' || $new_statusvis eq 'V';

        my $did_change = $u->statusvis ne $new_statusvis;
        # no need to change?
        $messages->add( "", $u->is_community ? '.message.nochange.comm' : '.message.nochange', { statusvis => $statusvis_map{$new_statusvis} } )
            unless $did_change;

        if ( ! $errors->exist && $did_change  ) {
            my $res = 0;

            my $ip = $r->get_remote_ip;

            my @date = localtime( time );
            my $date = sprintf( "%02d:%02d %02d/%02d/%04d", @date[2,1], $date[3], $date[4]+1, $date[5]+1900 );

            if ( $new_statusvis eq 'D' ) {

                $res = $u->set_deleted;

                $u->set_prop( delete_reason => $post->{reason} || "" );

                if( $res ) {
                    # sending ESN status was changed
                    LJ::Event::SecurityAttributeChanged->new($u, {
                        action   => 'account_deleted',
                        ip       => $ip,
                        datetime => $date,
                    })->fire;
                }
            } elsif ( $new_statusvis eq 'V' ) {
                ## Restore previous statusvis of journal. It may be different
                ## from 'V', it may be read-only, or locked, or whatever.
                my @previous_status = grep { $_ ne 'D' } $u->get_previous_statusvis;
                my $new_status = $previous_status[0] || 'V';
                my $method = {
                    V => 'set_visible',
                    L => 'set_locked',
                    M => 'set_memorial',
                    O => 'set_readonly',
                    R => 'set_renamed',
                }->{$new_status};
                $errors->add_string( "", "Can't set status '" . LJ::ehtml( $new_status ) . "'" ) unless $method;

                unless ( $errors->exist ) {
                    $res = $u->$method;

                    $u->set_prop( delete_reason => "" );

                    if( $res ) {
                        LJ::Event::SecurityAttributeChanged->new($u ,  {
                            action   => 'account_activated',
                            ip       => $ip,
                            datetime => $date,
                        })->fire;

                        $did_change = 1;
                    }
                }
            }

            # error updating?
            $errors->add( "", ".error.db" ) unless $res;

            unless ( $errors->exist ) {
                $messages->add( "", $u->is_community ? '.message.success.comm' : '.message.success', { statusvis => $statusvis_map{$new_statusvis} } );

                if ( $new_statusvis eq 'D' ) {
                    $messages->add( "", $u->is_community ? ".message.deleted.comm" : ".message.deleted2", { sitenameshort => $LJ::SITENAMESHORT } );

                    # are they leaving any community admin-less?
                    if ( $u->is_person ) {
                        my $cids = LJ::load_rel_target( $remote, "A" );
                        my @warn_comm_ids;

                        if ( $cids ) {
                            # verify there are visible maintainers for each community
                            foreach my $cid ( @$cids ) {
                                push @warn_comm_ids, $cid
                                    unless
                                        grep { $_->is_visible }
                                        values %{ LJ::load_userids(
                                                      @{ LJ::load_rel_user( $cid, 'A' ) }
                                                  ) };
                            }

                            # and if not, warn them about it
                            if ( @warn_comm_ids ) {
                                my $commlist = '<ul>';
                                $commlist .= '<li>' . $_->ljuser_display . '</li>'
                                    foreach values %{ LJ::load_userids( @warn_comm_ids ) };
                                $commlist .= '</ul>';

                                $warnings->add( "", '.message.noothermaintainer', {
                                    commlist => $commlist,
                                    manage_url => LJ::create_url( "/communities/list" ),
                                    pagetitle => LJ::Lang::ml( '/communities/list.tt.title' ),
                                } );
                            }
                        }

                    }
                }
            }
        }
    }

    my $vars = {
        form_url => LJ::create_url( undef, keep_args => [ 'authas' ] ),
        extra_delete_text => LJ::Hooks::run_hook( "accountstatus_delete_text", $u ),
        statusvis_options => \@statusvis_options,

        u => $u,
        delete_reason => $u->prop( 'delete_reason' ),

        errors => $errors,
        messages => $messages,
        warnings => $warnings,
        formdata => $post,

        authas_form => $rv->{authas_form},
    };
    return DW::Template->render_template( 'settings/accountstatus.tt', $vars );
}

sub changepassword_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $get = $r->get_args;
    my $post;

    my $remote = $rv->{remote};

    my ( $aa, $authu );
    my $ml_scope = "/settings/changepassword.tt";
    if ( my $auth = $get->{auth} ) {
        my $lostinfo_url = LJ::create_url( "/lostinfo" );

        return error_ml( "$ml_scope.error.invalidarg" )
            unless $auth =~ /^(\d+)\.(.+)$/;

        $aa = LJ::is_valid_authaction( $1, $2 );
        return error_ml( "$ml_scope.error.invalidarg" )
            unless $aa;

        return error_ml( "$ml_scope.error.actionalreadyperformed", { url => $lostinfo_url } )
            if $aa->{used} eq 'Y';

        return $r->redirect( $lostinfo_url )
             unless $aa->{action} eq 'reset_password';

         # confirmed the identity...
         $authu = LJ::load_userid( $aa->{userid} );

         # verify the email can still receive passwords
         return error_ml( "$ml_scope.error.emailchanged", { url => $lostinfo_url } )
             unless $authu->can_receive_password( $aa->{arg1} );
    }
    return error_ml( "$ml_scope.error.identity" ) if $remote && $remote->is_identity;

    my $errors = DW::FormErrors->new;
    if ( $r->did_post && $r->post_args->{mode} eq 'submit' ) {
        $post = $r->post_args;

        my $user = $authu ? $authu->user : LJ::canonical_username( $post->{user} );
        my $password = $post->{password};
        my $newpass1 = LJ::trim( $post->{newpass1} );
        my $newpass2 = LJ::trim( $post->{newpass2} );

        my $u = LJ::load_user( $user );
        $errors->add( "user", ".error.invaliduser" ) unless $u;
        $errors->add( "user", ".error.identity" ) if $u && $u->is_identity;
        $errors->add( "user", ".error.changetestaccount" ) if grep { $user eq $_ } @LJ::TESTACCTS;

        unless ( $errors->exist ) {
            if ( LJ::login_ip_banned( $u ) ) {
                $errors->add( "user", "error.ipbanned" );
            } elsif ( ! $authu && ( $u->password eq "" || $u->password ne $password ) ) {
                $errors->add( "password", ".error.badoldpassword" );
                LJ::handle_bad_login( $u );
            }
        }

        if ( ! $newpass1 ) {
            $errors->add( "newpass1", ".error.blankpassword" );
        } elsif ( $newpass1 ne $newpass2 ) {
            $errors->add( "newpass2", ".error.badnewpassword" );
        } else {
            my $checkpass = LJ::CreatePage->verify_password( password => $newpass1, u => $u );
            $errors->add( "newpass1", ".error.badcheck", { error => $checkpass } )
                if $checkpass;
        }

        # don't allow changes if email address is not validated, unless they
        # have a bad password or got the reset email
        $errors->add( "newpass1", ".error.notvalidated" )
            if $u->{status} ne 'A' && ! $u->prop( 'badpassword' ) && ! $authu;

        # now let's change the password
        unless ( $errors->exist ) {
            ## make note of changed password
            my $dbh = LJ::get_db_writer();
            my $oldval = Digest::MD5::md5_hex( $u->password . "change" );
            $u->infohistory_add( 'password', $oldval );

            $u->log_event('password_change', { remote => $remote } );

            $u->update_self( { password => $post->{newpass1} } );

            # if we used an authcode, we'll need to expire it now
            LJ::mark_authaction_used( $aa ) if $authu;

            # If we forced them to change their password, mark them as now being good
            $u->set_prop( 'badpassword', 0 ) if LJ::is_enabled( 'force_pass_change' );

            # Kill all sessions, forcing user to relogin
            $u->kill_all_sessions;

            LJ::send_mail( {
                'to' => $u->email_raw,
                'from' => $LJ::ADMIN_EMAIL,
                'fromname' => $LJ::SITENAME,
                'charset' => 'utf-8',
                'subject' => LJ::Lang::ml( "$ml_scope.email.subject" ),
                'body' => LJ::Lang::ml( "$ml_scope.email.body2",
                                  { sitename => $LJ::SITENAME,
                                    siteroot => $LJ::SITEROOT,
                                    username => $u->{user},
                                  } ),
            } );

            my $success_ml = $remote ? "settings/changepassword.tt.withremote" : "settings/changepassword.tt";
            return DW::Controller->render_success( $success_ml,  {
                    url => LJ::create_url( "/login" ),
                } );

            LJ::Hooks::run_hooks( "post_changepassword", {
                "u" => $u,
                "newpassword" => $post->{newpass1},
                "oldpassword" => $u->password,
            } );

            LJ::Hooks::run_hook( 'user_login', $u );
        }
    }

    my $vars = {
        bad_password        => $remote && $remote->prop( 'badpassword' ),
        needs_validation    => ! $authu && $remote && ! $remote->prop( 'badpassword' ) && ! $r->did_post && $remote->{status} ne 'A',

        authu   => $authu,
        remote  => $remote,

        formdata => $post || { user => $remote ? $remote->user : "" },
        errors   => $errors,
    };
    return DW::Template->render_template( 'settings/changepassword.tt', $vars );
}
1;