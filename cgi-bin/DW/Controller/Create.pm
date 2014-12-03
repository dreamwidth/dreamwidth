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

package DW::Controller::Create;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

=head1 NAME

DW::Controller::Create - Account creation flow

=cut

DW::Routing->register_string( "/create", \&create_handler, app => 1, prefer_ssl => 1 );

DW::Routing->register_redirect( "/create/", "/create", app => 1 );

sub create_handler {
    my ( $opts ) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $get = $r->get_args;
    my $post;

    my $code_valid = $LJ::USE_ACCT_CODES ? 0 : 1;
    my $code;

    # start out saying we're okay; we'll modify this if we're actually checking codes later
    my $rate_ok = 1;

    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        $post = $r->post_args;

        $post->{user} = LJ::trim( $post->{user} );
        my $user = LJ::canonical_username( $post->{user} );
        my $email = LJ::trim( lc $post->{email} );


        # reject this email?
        if ( LJ::sysban_check( email => $email ) ) {
            LJ::Sysban::block( 0, "Create user blocked based on email", {
                new_user => $user,
                email => $email,
                name => $user,
            } ) ;
            return $r->HTTP_SERVICE_UNAVAILABLE;
        }

        # is username valid?
        my $second_submit = 0;
        my $error = LJ::CreatePage->verify_username( $post->{user}, post => $post, second_submit_ref => \$second_submit );
        $errors->add_string( "user", $error ) if $error;


        # validate code
        my $code = LJ::trim( $post->{code} );
        if ( $LJ::USE_ACCT_CODES ) {
            my $u = LJ::load_user( $post->{user} );
            my $userid = $u ? $u->id : 0;
            if ( DW::InviteCodes->check_code( code => $code, userid => $userid ) ) {
                $code_valid = 1;

                # and if this is a community promo code, set the inviter
                if ( my $pc = DW::InviteCodes::Promo->load( code => $code ) ) {
                    my $invu = $pc->suggest_journal;
                    $post->{from} = $invu->user if $invu;
                }
            } else {
                return $r->redirect( LJ::create_url( undef, keep_args => [ qw( user from code )] ) );
            }
        }


        # check passwords
        $post->{password1} = LJ::trim( $post->{password1} );
        $post->{password2} = LJ::trim( $post->{password2} );

        if ( !$post->{password1} ) {
            $errors->add( 'password1', 'widget.createaccount.error.password.blank' );
        } elsif ( $post->{password1} ne $post->{password2} ) {
            $errors->add( 'password2', 'widget.createaccount.error.password.nomatch' );
        } else {
            my $checkpass = LJ::CreatePage->verify_password( password => $post->{password1}, username => $user, email => $email );
            $errors->add( 'password1', 'widget.createaccount.error.password.bad2', { reason => $checkpass } )
                if $checkpass;
        }


        # age check
        my $dbh = LJ::get_db_writer();

        my $uniq;
        my $is_underage = 0;

        $uniq = $r->note('uniq');
        if ( $uniq ) {
            my $timeof = $dbh->selectrow_array( 'SELECT timeof FROM underage WHERE uniq = ?', undef, $uniq );
            $is_underage = 1 if $timeof && $timeof > 0;
        }

        my ( $year, $mon, $day ) = ( $post->{bday_yyyy}+0, $post->{bday_mm}+0, $post->{bday_dd}+0 );
        if ($year < 100 && $year > 0) {
            $post->{bday_yyyy} += 1900;
            $year += 1900;
        }

        my $nyear = (gmtime())[5] + 1900;

        # require dates in the 1900s (or beyond)
        if ( $year && $mon && $day && $year >= 1900 && $year < $nyear ) {
            my $age = LJ::calc_age( $year, $mon, $day );
            $is_underage = 1 if $age < 13;
        } else {
            $errors->add( 'birthdate', 'widget.createaccount.error.birthdate.invalid' );
        }

        # note this unique cookie as underage (if we have a unique cookie)
        if ( $is_underage && $uniq ) {
            $dbh->do( "REPLACE INTO underage (uniq, timeof) VALUES (?, UNIX_TIMESTAMP())", undef, $uniq );
        }

        $errors->add( 'birthdate', 'widget.createaccount.error.birthdate.underage' )
            if $is_underage;


        # check the email address
        my @email_errors;
        LJ::check_email( $email, \@email_errors );
        $errors->add_string( 'email', $_ ) foreach @email_errors;
        $errors->add( 'email', 'widget.createaccount.error.email.lj_domain', { domain => $LJ::USER_DOMAIN } )
            if $LJ::USER_EMAIL and $email =~ /\@\Q$LJ::USER_DOMAIN\E$/i;


        # check the captcha answer if it's turned on
        my $captcha = DW::Captcha->new( 'create',  %{$post || {} } );
        my $captcha_error;
        $errors->add_string( 'captcha', $captcha_error )
            unless $captcha->validate( err_ref => \$captcha_error );


        # check TOS agreement
        $errors->add( 'tos', 'widget.createaccount.error.tos' ) unless $post->{tos};

        # create user and send email as long as the user didn't double-click submit
        # (or they tried to re-create a purged account)
        my $nu;
        unless ( $second_submit || $errors->exist ) {
            my $bdate = sprintf( "%04d-%02d-%02d", $post->{bday_yyyy}, $post->{bday_mm}, $post->{bday_dd} );
            $nu = LJ::User->create_personal(
                user => $user,
                bdate => $bdate,
                email => $email,
                password => $post->{password1},
                get_news => $post->{news} ? 1 : 0,
                inviter => $post->{from},
                code => DW::InviteCodes->check_code( code => $code ) ? $code : undef,
            );
            $errors->add( '', 'widget.createaccount.error.cannotcreate' ) unless $nu;
        }

        # now go on and do post-create stuff
        if ( $nu ) {
            # send welcome mail
            my $aa = LJ::register_authaction( $nu->id, "validateemail", $email );

            my $body = LJ::Lang::ml( 'email.newacct5.body', {
                sitename => $LJ::SITENAME,
                regurl => "$LJ::SITEROOT/confirm/$aa->{'aaid'}.$aa->{'authcode'}",
                journal_base => $nu->journal_base,
                username => $nu->user,
                siteroot => $LJ::SITEROOT,
                sitenameshort => $LJ::SITENAMESHORT,
                lostinfourl => "$LJ::SITEROOT/lostinfo",
                editprofileurl => "$LJ::SITEROOT/manage/profile/",
                searchinterestsurl => "$LJ::SITEROOT/interests",
                editiconsurl => "$LJ::SITEROOT/editicons",
                customizeurl => "$LJ::SITEROOT/customize/",
                postentryurl => "$LJ::SITEROOT/update",
                setsecreturl => "$LJ::SITEROOT/set_secret",
            });

            LJ::send_mail({
                to => $email,
                from => $LJ::ADMIN_EMAIL,
                fromname => $LJ::SITENAME,
                charset => 'utf-8',
                subject => LJ::Lang::ml( 'email.newacct.subject', { sitename => $LJ::SITENAME } ),
                body => $body,
            });

            # we're all done
            $nu->make_login_session;

            if ( $code ) {
                # unconditionally mark the invite code as used
                if ( $LJ::USE_ACCT_CODES ) {
                    if ( my $pc = DW::InviteCodes::Promo->load( code => $code ) ) {
                        $pc->use_code;
                    } else {
                        my $invitecode = DW::InviteCodes->new( code => $code );
                        $invitecode->use_code( user => $nu );
                    }

                # user is now paid, let's assume that this came from the invite code
                # so mark the invite code as used
                } elsif ( DW::Pay::get_current_account_status( $nu ) ) {
                    my $invitecode = DW::InviteCodes->new( code => $code );
                    $invitecode->use_code( user => $nu );
                }
            }


            # go on to the next step
            my $stop_output;
            my $stop_body;
            my $redirect;
            LJ::Hooks::run_hook( 'underage_redirect', {
                u => $nu,
                redirect => \$redirect,
                ret => \$stop_body,
                stop_output => \$stop_output,
            });
            return $r->redirect( $redirect ) if $redirect;
            return $stop_body if $stop_output;

            $redirect = LJ::Hooks::run_hook( 'rewrite_redirect_after_create', $nu );
            return $r->redirect( $redirect ) if $redirect;

            return $r->redirect( LJ::create_url( '/create/setup' ) );
        }
    } else {
        # we always need the code, because it might contain paid time
        $code = LJ::trim( $get->{code} );

        # and we always do rate limiting if we have a code
        $rate_ok = DW::InviteCodes->check_rate if $code;

        # but we don't always need to block the registration on the validity of the code
        # (if we have an invalid code, but we do don't require codes to open an account, just fail silently)
        $code_valid = DW::InviteCodes->check_code( code => $code )
            if $LJ::USE_ACCT_CODES;
    }

    my $step = 1;
    my $vars = {
        steps_to_show   => [ steps_to_show( $code, $step ) ],
        step            => $step,

        form_url        => LJ::create_url( undef, keep_args => [ qw( user from code ) ] ),

        code            => LJ::trim( $get->{code} ),
        from            => LJ::trim( $get->{from} ),

        formdata        => $post,
        errors          => $errors,
    };

    if ( $code_valid && $rate_ok ) {
        $vars->{months} = [ map { $_, LJ::Lang::month_long_ml( $_ ) } ( 1..12 ) ];
        $vars->{days} = [ map { $_, $_ } ( 1..31 ) ];

        $vars->{formdata} ||= {
            user => $get->{user},
        };

        LJ::set_active_resource_group( "foundation" );
        my $captcha = DW::Captcha->new( 'create', %{$post || {}} );
        $vars->{captcha} = $captcha->print if $captcha->enabled;

        if ( $LJ::USE_ACCT_CODES ) {
            if ( my $pc = DW::InviteCodes::Promo->load( code => $code ) ) {
                if ( $pc->paid_class ) {
                    $vars->{code_paid_time} = {
                        type    => $pc->paid_class_name,
                        months  => $pc->paid_months,
                    };
                }
            } else {
                my $item = DW::InviteCodes->paid_status( code => $code );
                if ( $item ) {
                    $vars->{code_paid_time} = {
                        type     => $item->class_name,
                        months   => $item->months,
                        permanent => $item->permanent,
                    };
                }
            }
        }

        return DW::Template->render_template( 'create/account.tt', $vars );
    } else {
        # we can still use invite codes to create new paid accounts
        # so display this in case they hit the rate limit, even without USE_ACCT_CODES
        $errors->add( 'code', 'widget.createaccountentercode.error.toofast' ) unless $rate_ok;

        # also check for the presence of a code (if we reach this point with a code, code should be invalid...)
        $errors->add( 'code', 'widget.createaccountentercode.error.invalidcode' ) if $code && ! $code_valid;

        $vars->{formdata} ||= {
            code => $vars->{code},
            from => $vars->{from},
        };

        return DW::Template->render_template( 'create/code.tt', $vars );
    }
}

sub steps_to_show {
    my ( $code, $given_step ) = @_;
    my $u = LJ::get_effective_remote();

    return ! LJ::is_enabled( 'payments' )
            || ( $LJ::USE_ACCT_CODES && $given_step == 1 && !DW::InviteCodes::Promo->is_promo_code( code => $code ) && DW::InviteCodes->paid_status( code => $code ) )
            || ( $given_step > 1 && $u && $u->is_paid )
        ? ( 1, 2, 4 )
        : ( 1..4 );
}

1;