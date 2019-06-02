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
#      Janine Smith <janine@netrophic.com>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009-2017 by Dreamwidth Studios, LLC.

package DW::Controller::Create;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use LJ::Widget::Location;

=head1 NAME

DW::Controller::Create - Account creation flow

=cut

my %urls = (
    create  => '/create',
    setup   => '/create/setup',
    upgrade => '/create/upgrade',
    next    => '/create/next',
);

DW::Routing->register_string( $urls{create},  \&create_handler,  app => 1 );
DW::Routing->register_string( $urls{setup},   \&setup_handler,   app => 1 );
DW::Routing->register_string( $urls{upgrade}, \&upgrade_handler, app => 1 );
DW::Routing->register_string( $urls{next},    \&next_handler,    app => 1 );

sub create_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r   = $rv->{r};
    my $get = $r->get_args;
    my $post;

    my $code_valid = $LJ::USE_ACCT_CODES ? 0 : 1;
    my $code;

    # start out saying we're okay; we'll modify this if we're actually checking codes later
    my $rate_ok = 1;

    my $errors = DW::FormErrors->new;
    my $email_checkbox;
    if ( $r->did_post ) {
        $post = $r->post_args;

        $post->{user} = LJ::trim( $post->{user} );
        my $user  = LJ::canonical_username( $post->{user} );
        my $email = LJ::trim( lc $post->{email} );

        # reject this email?
        if ( LJ::sysban_check( email => $email ) ) {
            LJ::Sysban::block(
                0,
                "Create user blocked based on email",
                {
                    new_user => $user,
                    email    => $email,
                    name     => $user,
                }
            );
            return $r->HTTP_SERVICE_UNAVAILABLE;
        }

        # is username valid?
        my $second_submit = 0;
        my $error         = LJ::CreatePage->verify_username(
            $post->{user},
            post              => $post,
            second_submit_ref => \$second_submit
        );
        $errors->add_string( "user", $error ) if $error;

        # validate code
        my $code = LJ::trim( $post->{code} );
        if ($LJ::USE_ACCT_CODES) {
            my $u      = LJ::load_user( $post->{user} );
            my $userid = $u ? $u->id : 0;
            if ( DW::InviteCodes->check_code( code => $code, userid => $userid ) ) {
                $code_valid = 1;

                # and if this is a community promo code, set the inviter
                if ( my $pc = DW::InviteCodes::Promo->load( code => $code ) ) {
                    my $invu = $pc->suggest_journal;
                    $post->{from} = $invu->user if $invu;
                }
            }
            else {
                return $r->redirect( LJ::create_url( undef, keep_args => [qw( user from code )] ) );
            }
        }

        # check passwords
        $post->{password1} = LJ::trim( $post->{password1} );
        $post->{password2} = LJ::trim( $post->{password2} );

        if ( !$post->{password1} ) {
            $errors->add( 'password1', 'widget.createaccount.error.password.blank' );
        }
        elsif ( $post->{password1} ne $post->{password2} ) {
            $errors->add( 'password2', 'widget.createaccount.error.password.nomatch' );
        }
        else {
            my $checkpass = LJ::CreatePage->verify_password(
                password => $post->{password1},
                username => $user,
                email    => $email
            );
            $errors->add(
                'password1',
                'widget.createaccount.error.password.bad2',
                { reason => $checkpass }
            ) if $checkpass;
        }

        # age check
        my $dbh = LJ::get_db_writer();

        my $uniq;
        my $is_underage = 0;

        $uniq = $r->note('uniq');
        if ($uniq) {
            my $timeof =
                $dbh->selectrow_array( 'SELECT timeof FROM underage WHERE uniq = ?', undef, $uniq );
            $is_underage = 1 if $timeof && $timeof > 0;
        }

        my ( $year, $mon, $day ) =
            ( $post->{bday_yyyy} + 0, $post->{bday_mm} + 0, $post->{bday_dd} + 0 );
        if ( $year < 100 && $year > 0 ) {
            $post->{bday_yyyy} += 1900;
            $year += 1900;
        }

        my $nyear = ( gmtime() )[5] + 1900;

        # require dates in the 1900s (or beyond)
        if ( $year && $mon && $day && $year >= 1900 && $year < $nyear ) {
            my $age = LJ::calc_age( $year, $mon, $day );
            $is_underage = 1 if $age < 13;
        }
        else {
            $errors->add( 'birthdate', 'widget.createaccount.error.birthdate.invalid2' );
        }

        # note this unique cookie as underage (if we have a unique cookie)
        if ( $is_underage && $uniq ) {
            $dbh->do( "REPLACE INTO underage (uniq, timeof) VALUES (?, UNIX_TIMESTAMP())",
                undef, $uniq );
        }

        $errors->add( 'birthdate', 'widget.createaccount.error.birthdate.underage' )
            if $is_underage;

        # check the email address
        my @email_errors;
        LJ::check_email( $email, \@email_errors, $post, \$email_checkbox );
        $errors->add_string( 'email', $_ ) foreach @email_errors;
        $errors->add(
            'email',
            'widget.createaccount.error.email.lj_domain',
            { domain => $LJ::USER_DOMAIN }
        ) if $LJ::USER_EMAIL and $email =~ /\@\Q$LJ::USER_DOMAIN\E$/i;

        # check the captcha answer if it's turned on
        my $captcha = DW::Captcha->new( 'create', %{ $post || {} } );
        my $captcha_error;
        $errors->add_string( 'captcha', $captcha_error )
            unless $captcha->validate( err_ref => \$captcha_error );

        # check TOS agreement
        $errors->add( 'tos', 'widget.createaccount.error.tos' ) unless $post->{tos};

        # create user and send email as long as the user didn't double-click submit
        # (or they tried to re-create a purged account)
        my $nu;
        unless ( $second_submit || $errors->exist ) {
            my $bdate =
                sprintf( "%04d-%02d-%02d", $post->{bday_yyyy}, $post->{bday_mm}, $post->{bday_dd} );
            $nu = LJ::User->create_personal(
                user     => $user,
                bdate    => $bdate,
                email    => $email,
                password => $post->{password1},
                get_news => $post->{news} ? 1 : 0,
                inviter  => $post->{from},
                code     => DW::InviteCodes->check_code( code => $code ) ? $code : undef,
            );
            $errors->add( '', 'widget.createaccount.error.cannotcreate' ) unless $nu;
        }

        # now go on and do post-create stuff
        if ($nu) {

            # send welcome mail
            my $aa = LJ::register_authaction( $nu->id, "validateemail", $email );

            my $body = LJ::Lang::ml(
                'email.newacct6.body',
                {
                    sitename           => $LJ::SITENAME,
                    regurl             => "$LJ::SITEROOT/confirm/$aa->{'aaid'}.$aa->{'authcode'}",
                    journal_base       => $nu->journal_base,
                    username           => $nu->user,
                    siteroot           => $LJ::SITEROOT,
                    sitenameshort      => $LJ::SITENAMESHORT,
                    lostinfourl        => "$LJ::SITEROOT/lostinfo",
                    editprofileurl     => "$LJ::SITEROOT/manage/profile/",
                    searchinterestsurl => "$LJ::SITEROOT/interests",
                    editiconsurl       => "$LJ::SITEROOT/manage/icons",
                    customizeurl       => "$LJ::SITEROOT/customize/",
                    postentryurl       => "$LJ::SITEROOT/update",
                    setsecreturl       => "$LJ::SITEROOT/set_secret",
                    supporturl         => "$LJ::SITEROOT/support/submit",
                }
            );

            LJ::send_mail(
                {
                    to       => $email,
                    from     => $LJ::BOGUS_EMAIL,
                    fromname => $LJ::SITENAME,
                    charset  => 'utf-8',
                    subject =>
                        LJ::Lang::ml( 'email.newacct.subject', { sitename => $LJ::SITENAME } ),
                    body => $body,
                }
            );

            # we're all done
            $nu->make_login_session;

            if ($code) {

                # unconditionally mark the invite code as used
                if ($LJ::USE_ACCT_CODES) {
                    if ( my $pc = DW::InviteCodes::Promo->load( code => $code ) ) {
                        $pc->use_code;
                    }
                    else {
                        my $invitecode = DW::InviteCodes->new( code => $code );
                        $invitecode->use_code( user => $nu );
                    }

                    # user is now paid, let's assume that this came from the invite code
                    # so mark the invite code as used
                }
                elsif ( DW::Pay::get_current_account_status($nu) ) {
                    my $invitecode = DW::InviteCodes->new( code => $code );
                    $invitecode->use_code( user => $nu );
                }
            }

            # go on to the next step
            my $stop_output;
            my $stop_body;
            my $redirect;
            LJ::Hooks::run_hook(
                'underage_redirect',
                {
                    u           => $nu,
                    redirect    => \$redirect,
                    ret         => \$stop_body,
                    stop_output => \$stop_output,
                }
            );
            return $r->redirect($redirect) if $redirect;
            return $stop_body if $stop_output;

            $redirect = LJ::Hooks::run_hook( 'rewrite_redirect_after_create', $nu );
            return $r->redirect($redirect) if $redirect;

            return $r->redirect( LJ::create_url( $urls{setup} ) );
        }
    }
    else {
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
        steps_to_show => [ steps_to_show( $step, code => $code ) ],
        step          => $step,

        form_url => LJ::create_url( undef, keep_args => [qw( user from code )] ),

        code => LJ::trim( $get->{code} ),
        from => LJ::trim( $get->{from} ),

        formdata       => $post,
        errors         => $errors,
        email_checkbox => $email_checkbox,

        username_maxlength => $LJ::USERNAME_MAXLENGTH,
    };

    if ( $code_valid && $rate_ok ) {
        $vars->{months} = [ map { $_, LJ::Lang::month_long_ml($_) } ( 1 .. 12 ) ];
        $vars->{days}   = [ map { $_, $_ } ( 1 .. 31 ) ];

        $vars->{formdata} ||= { user => $get->{user}, };

        LJ::set_active_resource_group("foundation");
        my $captcha = DW::Captcha->new( 'create', %{ $post || {} } );
        $vars->{captcha} = $captcha->print if $captcha->enabled;

        if ($LJ::USE_ACCT_CODES) {
            if ( my $pc = DW::InviteCodes::Promo->load( code => $code ) ) {
                if ( $pc->paid_class ) {
                    $vars->{code_paid_time} = {
                        type   => $pc->paid_class_name,
                        months => $pc->paid_months,
                    };
                }
            }
            else {
                my $item = DW::InviteCodes->paid_status( code => $code );
                if ($item) {
                    $vars->{code_paid_time} = {
                        type      => $item->class_name,
                        months    => $item->months,
                        permanent => $item->permanent,
                    };
                }
            }
        }

        return DW::Template->render_template( 'create/account.tt', $vars );
    }
    else {
        # we can still use invite codes to create new paid accounts
        # so display this in case they hit the rate limit, even without USE_ACCT_CODES
        $errors->add( 'code', 'widget.createaccountentercode.error.toofast' ) unless $rate_ok;

# also check for the presence of a code (if we reach this point with a code, code should be invalid...)
        $errors->add( 'code', 'widget.createaccountentercode.error.invalidcode' )
            if $code && !$code_valid;

        $vars->{payments_enabled} = LJ::is_enabled('payments');
        $vars->{logged_out}       = $rv->{remote} ? 0 : 1;

        $vars->{formdata} ||= {
            code => $vars->{code},
            from => $vars->{from},
        };

        return DW::Template->render_template( 'create/code.tt', $vars );
    }
}

sub setup_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $u      = LJ::get_effective_remote();
    my $post;

    return $r->redirect( LJ::create_url("/") ) unless $remote->is_personal;

    my @location_props = qw/ country state city /;
    my $errors         = DW::FormErrors->new;
    if ( $r->did_post ) {
        $post = $r->post_args;

        # name
        $errors->add( 'name', '/manage/profile/index.bml.error.noname' )
            unless LJ::trim( $post->{name} ) || defined $post->{name_absent};

        $errors->add( 'name', '/manage/profile/index.bml.error.name.toolong' )
            if length $post->{name} > 80;

        $post->{name} =~ s/[\n\r]//g;
        $post->{name} = LJ::text_trim( $post->{name}, LJ::BMAX_NAME, LJ::CMAX_NAME );

        # gender
        $post->{gender} = 'U' unless $post->{gender} =~ m/^[UMFO]$/;

        # location
        my $state_from_dropdown = LJ::Lang::ml('states.head.defined');
        $post->{stateother} = "" if $post->{stateother} eq $state_from_dropdown;

        my %countries;
        DW::Countries->load( \%countries );

        my $regions_cfg = LJ::Widget::Location->country_regions_cfg( $post->{country} );
        if ( $regions_cfg && $post->{stateother} ) {
            $errors->add( 'statedrop', 'widget.location.error.locale.country_ne_state' );
        }
        elsif ( !$regions_cfg && $post->{statedrop} ) {
            $errors->add( 'stateother', 'widget.location.error.locale.state_ne_country' );
        }

        if ( $post->{country} && !defined $countries{ $post->{country} } ) {
            $errors->add( 'country', 'widget.location.error.locale.invalid_country' );
        }

        # check if specified country has states
        if ($regions_cfg) {

            # if it is - use region select dropbox
            $post->{state} = $post->{statedrop};

            # mind save_region_code also
            unless ( $regions_cfg->{save_region_code} ) {

                # save region name instead of code
                my $regions_arrayref = LJ::Widget::Location->region_options($regions_cfg);
                my %regions_as_hash  = @$regions_arrayref;
                $post->{state} = $regions_as_hash{ $post->{state} };
            }
        }
        else {
            # use state input box
            $post->{state} = $post->{stateother};
        }

        # interests
        my @interests_strings = (
            $post->{interests_music},   $post->{interests_moviestv}, $post->{interests_books},
            $post->{interests_hobbies}, $post->{interests_other},
        );
        my @ints = LJ::interest_string_to_list( join ", ", @interests_strings );

        # count interests
        my $intcount     = scalar @ints;
        my $maxinterests = $u->count_max_interests;

        $errors->add( 'interests', 'error.interest.excessive2',
            { intcount => $intcount, maxinterests => $maxinterests } )
            if $intcount > $maxinterests;

        # clean interests, and make sure they're valid
        my @interrors;
        my @valid_ints = LJ::validate_interest_list( \@interrors, @ints );
        if ( @interrors > 0 ) {
            for my $err (@interrors) {
                $errors->add(
                    'interests',
                    $err->[0],
                    {
                        words     => $err->[1]{words},
                        words_max => $err->[1]{words_max},
                        'int'     => $err->[1]{int},
                        bytes     => $err->[1]{bytes},
                        bytes_max => $err->[1]{bytes_max},
                        chars     => $err->[1]{chars},
                        chars_max => $err->[1]{chars_max},
                    }
                );
            }
        }

        # bio
        $errors->add( 'bio', '/manage/profile/index.bml.error.bio.toolong' )
            if length $post->{bio} >= LJ::BMAX_BIO;
        LJ::EmbedModule->parse_module_embed( $u, \$post->{bio} );

        # inviter / communities
        ## trust
        if ( $post->{inviter_trust} ) {
            my $trust_u = LJ::load_userid( $post->{inviter_trust} );
            $u->add_edge( $trust_u, trust => {} )
                if LJ::isu($trust_u) && !$u->trusts($trust_u);
        }

        if ( $post->{inviter_watch} ) {
            my $watch_u = LJ::load_userid( $post->{inviter_watch} );
            $u->add_edge( $watch_u, watch => {} )
                if LJ::isu($watch_u) && !$u->watches($watch_u);
        }

        my @comm_ids = $post->get_all('inviter_join');
        foreach my $comm_id (@comm_ids) {
            my $join_u = LJ::load_userid($comm_id);

            if ( LJ::isu($join_u) && !$u->member_of($join_u) ) {

                # try to join the community
                # if it fails and the community's moderated, send a join request and watch it
                unless ( $u->join_community( $join_u, 1 ) ) {
                    if ( $join_u->is_moderated_membership ) {
                        $join_u->comm_join_request($u);
                        $u->add_edge( $join_u, watch => {} );
                    }
                }
            }
        }

        unless ( $errors->exist ) {

            # name
            $u->update_self( { name => $post->{name} } );

            # gender
            $u->set_prop( 'gender', $post->{gender} );

            # location
            $u->set_prop( $_, $post->{$_} ) foreach @location_props;

            # interests
            $u->set_interests( \@valid_ints );

            # bio
            $u->set_bio( $post->{bio}, $post->{bio_absent} );

            $u->invalidate_directory_record;

            # now go to the next page
            return $r->redirect( LJ::create_url( $urls{upgrade} ) )
                if LJ::is_enabled('payments') && !$remote->is_paid;

            return $r->redirect( LJ::create_url( $urls{next} ) );
        }

    }

    my @current_interests;
    foreach ( sort keys %{ $u->interests } ) {
        push @current_interests, $_ if LJ::text_in($_);
    }

    # location
    $u->preload_props(@location_props);

    my $inviter;
    my $inviter_u = $u->who_invited;
    my %inviter_form_defaults;
    if ($inviter_u) {
        my %comms =
              $inviter_u->is_individual
            ? $inviter_u->relevant_communities
            : ( $inviter_u->id => { u => $inviter_u, istatus => 'normal' } );

        my @comms = map { id => $_, %{ $comms{$_} } },
            sort { $comms{$a}->{u}->display_username cmp $comms{$b}->{u}->display_username }
            keys %comms;

        $inviter = {
            user           => $inviter_u->user,
            id             => $inviter_u->id,
            ljuser_display => $inviter_u->ljuser_display,

            # if inviter was a community, then it came from a promo code
            from_promo => $inviter_u->is_individual ? 0 : 1,

            comms => \@comms,

            can_add_watch => $u->can_watch($inviter_u),
            can_add_trust => $u->can_trust($inviter_u),
        };

        %inviter_form_defaults = (
            inviter_watch => $inviter_u->id,
            inviter_trust => $inviter_u->id,

            inviter_join => $inviter_u->is_community ? $inviter_u->id : undef,
        );
    }

    my $step = 2;
    my $vars = {
        steps_to_show => [ steps_to_show($step) ],
        step          => $step,

        inviter => $inviter,

        form_url    => LJ::create_url(),
        gender_list => [
            F => LJ::Lang::ml('/manage/profile/index.bml.gender.female'),
            M => LJ::Lang::ml('/manage/profile/index.bml.gender.male'),
            O => LJ::Lang::ml('/manage/profile/index.bml.gender.other'),
            U => LJ::Lang::ml('/manage/profile/index.bml.gender.unspecified'),
        ],
        interests => \@current_interests,

        country_list => LJ::Widget::Location->country_options,
        state_list   => undef,                                   # set later
        countries_with_regions => join( " ", LJ::Widget::Location->countries_with_regions ) || "",

        is_utf8 => {
            name => LJ::text_in( $u->name_orig ),
            bio  => LJ::text_in( $u->bio ),
        },

        formdata => $post || {
            name   => $u->name_orig      || "",
            gender => $u->prop('gender') || 'U',
            interests_other => join( ", ", @current_interests ) || "",
            bio => $u->bio || "",

            country    => $u->prop('country') || "",
            statedrop  => $u->prop('state')   || "",
            stateother => $u->prop('state')   || "",
            city       => $u->prop('city')    || "",

            %inviter_form_defaults,
        },
        errors => $errors,
    };

    # clean bio and expand for editing
    my $bio = \$vars->{formdata}->{bio};
    LJ::EmbedModule->parse_module_embed( $u, $bio, edit => 1 );
    LJ::text_out( $bio, "force" );

    # populate specified country with state information (if any)
    # first check if specified country has regions
    my $regions_cfg = LJ::Widget::Location->country_regions_cfg( $vars->{formdata}->{country} );

# hashref of all regions for the specified country; it is initialized and used only if $regions_cfg is defined, i.e. the country has regions (states)
    $vars->{state_list} = LJ::Widget::Location->region_options($regions_cfg) if $regions_cfg;

    return DW::Template->render_template( 'create/setup.tt', $vars );
}

sub upgrade_handler {
    my ( $ok, $rv ) = controller( form_auth => 0 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    return $r->redirect( LJ::create_url( $urls{next} ) )
        unless LJ::is_enabled('payments') && $remote->is_personal && !$remote->is_paid;

    return $r->redirect( LJ::create_url("/shop/account?for=self") )
        if $r->did_post;

    my $step = 3;
    my $vars = {
        steps_to_show => [ steps_to_show($step) ],
        step          => $step,

        upgrade_url => LJ::create_url(),
        next_url    => LJ::create_url( $urls{next} ),

        help_url => $LJ::HELPURL{paidaccountinfo},
    };

    return DW::Template->render_template( 'create/upgrade.tt', $vars );
}

sub next_handler {
    my $step = 4;
    return DW::Template->render_template(
        'create/next.tt',
        {
            steps_to_show => [ steps_to_show($step) ],
            step          => $step,
        }
    );
}

sub steps_to_show {
    my ( $given_step, %opts ) = @_;
    my $u    = LJ::get_effective_remote();
    my $code = $opts{code};

    return !LJ::is_enabled('payments')
        || ( $LJ::USE_ACCT_CODES
        && $given_step == 1
        && !DW::InviteCodes::Promo->is_promo_code( code => $code )
        && DW::InviteCodes->paid_status( code => $code ) )
        || ( $given_step > 1 && $u && $u->is_paid )
        ? ( 1, 2, 4 )
        : ( 1 .. 4 );
}

1;
