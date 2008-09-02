package LJ::Widget::CreateAccount;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::CreatePage Captcha::reCAPTCHA );

sub need_res { qw( stc/widgets/createaccount.css js/widgets/createaccount.js js/browserdetect.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $post = $opts{post};
    my $get = $opts{get};
    my $from_post = $opts{from_post};
    my $errors = $from_post->{errors};

    my $error_msg = sub {
        my $key = shift;
        my $pre = shift;
        my $post = shift;
        my $msg = $errors->{$key};
        return unless $msg;
        return "$pre $msg $post";
    };

    my $ret;

    $ret .= "<div class='rounded-box'><div class='rounded-box-tr'><div class='rounded-box-bl'><div class='rounded-box-br'>";
    $ret .= "<div class='rounded-box'><div class='rounded-box-tr'><div class='rounded-box-bl'><div class='rounded-box-br'>";

    $ret .= "<div class='rounded-box-content'>";
    $ret .= $class->start_form;

    my $tip_birthdate = LJ::ejs($class->ml('widget.createaccount.tip.birthdate'));
    my $tip_email = LJ::ejs($class->ml('widget.createaccount.tip.email'));
    my $tip_password = LJ::ejs($class->ml('widget.createaccount.tip.password'));
    my $tip_username = LJ::ejs($class->ml('widget.createaccount.tip.username'));

    # tip module
    $ret .= "<script language='javascript'>\n";
    $ret .= "CreateAccount.birthdate = \"$tip_birthdate\"\n";
    $ret .= "CreateAccount.email = \"$tip_email\"\n";
    $ret .= "CreateAccount.password = \"$tip_password\"\n";
    $ret .= "CreateAccount.username = \"$tip_username\"\n";
    $ret .= "</script>\n";
    $ret .= "<div id='tips_box_arrow'></div>";
    $ret .= "<div id='tips_box'></div>";

    $ret .= "<table class='create-form' cellspacing='0' cellpadding='3'>\n";

    ### username
    $ret .= "<tr><td class='field-name'>" . $class->ml('widget.createaccount.field.username') . "</td>\n<td>";
    # maxlength 16, so if people don't notice that they hit the limit,
    # we give them a warning. (some people don't notice/proofread)
    $ret .= $class->html_text(
        name => 'user',
        id => 'create_user',
        size => 15,
        maxlength => 16,
        raw => 'style="<?loginboxstyle?>"',
        value => $post->{user} || $get->{user},
    );
    $ret .= " <img id='username_check' src='$LJ::IMGPREFIX/create/check.png' alt='" . $class->ml('widget.createaccount.field.username.available') . "' title='" . $class->ml('widget.createaccount.field.username.available') . "' />";
    $ret .= $error_msg->('username', '<span id="username_error_main"><br /><span class="formitemFlag">', '</span></span>');
    $ret .= "<span id='username_error'><br /><span id='username_error_inner' class='formitemFlag'></span></span>";
    $ret .= "</td></tr>\n";

    ### email
    $ret .= "<tr><td class='field-name'>" . $class->ml('widget.createaccount.field.email') . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'email',
        id => 'create_email',
        size => 28,
        maxlength => 50,
        value => $post->{email},
    );
    $ret .= $error_msg->('email', '<br /><span class="formitemFlag">', '</span>');
    $ret .= "</td></tr>\n";

    ### password
    my $pass_value = $errors->{password} ? "" : $post->{password1};
    $ret .= "<tr><td class='field-name'>" . $class->ml('widget.createaccount.field.password') . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'password1',
        id => 'create_password1',
        size => 28,
        maxlength => 31,
        type => "password",
        value => $pass_value,
    );
    $ret .= $error_msg->('password', '<br /><span class="formitemFlag">', '</span>');
    $ret .= "</td></tr>\n";

    ### confirm password
    $ret .= "<tr><td class='field-name'>" . $class->ml('widget.createaccount.field.confirmpassword') . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'password2',
        id => 'create_password2',
        size => 28,
        maxlength => 31,
        type => "password",
        value => $pass_value,
    );
    $ret .= $error_msg->('confirmpass', '<br /><span class="formitemFlag">', '</span>');
    $ret .= "</td></tr>\n";

    ### birthdate
    if ($LJ::COPPA_CHECK) {
        $ret .= "<tr><td class='field-name'>" . $class->ml('widget.createaccount.field.birthdate') . "</td>\n<td>";
        $ret .= $class->html_datetime(
            name => 'bday',
            id => 'create_bday',
            notime => 1,
            default => sprintf("%04d-%02d-%02d", $post->{bday_yyyy}, $post->{bday_mm}, $post->{bday_dd}),
        );
        $ret .= $error_msg->('bday', '<br /><span class="formitemFlag">', '</span>');
        $ret .= "</td></tr>\n";
    }

    ### captcha
    if ($LJ::HUMAN_CHECK{create}) {
        if (LJ::is_enabled("recaptcha")) {
            $ret .= "<tr valign='top'><td class='field-name'>" . $class->ml('widget.createaccount.field.captcha') . "</td>\n<td>";

            my $c = Captcha::reCAPTCHA->new;
            $ret .= $c->get_options_setter({ theme => 'white' });
            $ret .= $c->get_html( LJ::conf_test($LJ::RECAPTCHA{public_key}), '', 1 );
        } else {
            # flag to indicate they've submitted with 'audio' as the answer to the captcha challenge
            my $wants_audio = $from_post->{wants_audio} || 0;

            # captcha id
            my $capid = $from_post->{capid};
            my $anum = $from_post->{anum};

            my ($captcha_chal, $captcha_sess);

            my $answer = $post->{answer};
            undef $answer if $errors->{captcha} || $wants_audio;
            $captcha_chal = $post->{captcha_chal};
            undef $captcha_chal if $errors->{captcha};

            $captcha_chal = $captcha_chal || LJ::challenge_generate(900);
            $captcha_sess = LJ::get_challenge_attributes($captcha_chal);

            $ret .= "<tr valign='top'><td class='field-name'>" . $class->ml('widget.createaccount.field.captcha') . "</td>\n<td>";

            if ($wants_audio || $post->{audio_chal}) { # audio
                my $url = $capid && $anum ? # previously entered correctly
                    "$LJ::SITEROOT/captcha/audio.bml?capid=$capid&amp;anum=$anum" :
                    "$LJ::SITEROOT/captcha/audio.bml?chal=$captcha_chal";

                $ret .= "<a href='$url'>" . $class->ml('widget.createaccount.field.captcha.play') . "</a>";
                $ret .= $class->html_hidden( audio_chal => 1 );
                $ret .= "<p class='field-desc'>" . $class->ml('widget.createaccount.field.captcha.hear') . "</p>";
            } else { # visual
                my $url = $capid && $anum ? # previously entered correctly
                    "$LJ::SITEROOT/captcha/image.bml?capid=$capid&amp;anum=$anum" :
                    "$LJ::SITEROOT/captcha/image.bml?chal=$captcha_chal";

                $ret .= "<img src='$url' width='175' height='35' />";
                $ret .= "<p class='field-desc'>" . $class->ml('widget.createaccount.field.captcha.visual') . "</p>";
            }

            $ret .= $class->html_text(
                name => 'answer',
                id => 'create_answer',
                size => 28,
                value => $answer,
            );
            $ret .= $class->html_hidden( captcha_chal => $captcha_chal );
        }

        $ret .= $error_msg->('captcha', '<br /><span class="formitemFlag">', '</span>');
        $ret .= "</td></tr>\n";
    }

    ### site news
    $ret .= "<tr valign='top'><td>&nbsp;</td>\n<td>";
    $ret .= $class->html_check(
        name => 'news',
        id => 'create_news',
        value => '1',
        selected => LJ::did_post() ? $post->{news} : 1,
        label => $class->ml('widget.createaccount.field.news', { sitename => $LJ::SITENAMESHORT }),
    );
    $ret .= "</td></tr>\n";

    ### TOS
    if ($LJ::TOS_CHECK) {
        $ret .= "<tr valign='top'><td>&nbsp;</td>\n<td>";
        $ret .= "<p class='tos-blurb'>" . $class->ml('widget.createaccount.field.tos', {
                sitename => $LJ::SITENAMESHORT,
                aopts1 => "href='$LJ::SITEROOT/legal/tos.bml'",
                aopts2 => "href='$LJ::SITEROOT/legal/privacy.bml'",
        }) . "</p>";
        $ret .= "</td></tr>\n";
    }

    ### submit button
    $ret .= "<tr valign='top'><td>&nbsp;</td>\n<td>";
    $ret .= $class->html_submit( submit => $class->ml('widget.createaccount.btn'), { class => "create-button" }) . "\n";
    $ret .= "</td></tr>\n";

    $ret .= "</table>\n";

    $ret .= $class->end_form;
    $ret .= "</div>";

    $ret .= "</div></div></div></div>";
    $ret .= "</div></div></div></div>";

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $get = $opts{get};
    my %from_post;
    my $remote = LJ::get_remote();

    # flag to indicate they've submitted with 'audio' as the answer to the captcha
    my $wants_audio = $from_post{wants_audio} = 0;

    # captcha id
    my ($capid, $anum);

    # if they've given 'audio' as the answer to the captcha
    if ($LJ::HUMAN_CHECK{create} && !LJ::is_enabled("recaptcha") && lc $post->{answer} eq 'audio') {
        $wants_audio = $from_post{wants_audio} = 1;
    }

    $post->{user} = LJ::trim($post->{user});
    my $user = LJ::canonical_username($post->{user});
    my $email = LJ::trim(lc $post->{email});

    # set up global things that can be used to modify the user later
    my $is_underage = 0; # turn on if the user should be marked as underage
    my $ofage = 0;       # turn on to note that the user is over 13 in actuality
                         # (but is_underage might be on which just means
                         # that their account is being marked as underage
                         # even if they're old [unique cookie check])

    # reject this email?
    return LJ::sysban_block(0, "Create user blocked based on email", {
        new_user => $user,
        email => $email,
        name => $user,
    }) if LJ::sysban_check('email', $email);

    my $dbh = LJ::get_db_writer();

    my $second_submit = 0;
    my $error = LJ::CreatePage->verify_username($post->{user}, post => $post, second_submit_ref => \$second_submit );
    $from_post{errors}->{username} = $error if $error;

    $post->{password1} = LJ::trim($post->{password1});
    $post->{password2} = LJ::trim($post->{password2});

    if ($post->{password1} ne $post->{password2}) {
        $from_post{errors}->{confirmpass} = $class->ml('widget.createaccount.error.password.nomatch');
    } else {
        my $checkpass = LJ::run_hook("bad_password", {
            user => $user,
            email => $email,
            password => $post->{password1},
        });

        if ($checkpass) {
            $from_post{errors}->{password} = $class->ml('widget.createaccount.error.password.bad') . " $checkpass";
        }
    }
    if (!$post->{password1}) {
        $from_post{errors}->{password} = $class->ml('widget.createaccount.error.password.blank');
    } elsif (length $post->{password1} > 30) {
        $from_post{errors}->{password} = LJ::Lang::ml('password.max30');
    }

    unless (LJ::is_ascii($post->{password1})) {
        $from_post{errors}->{password} = $class->ml('widget.createaccount.error.password.asciionly');
    }

    ### start COPPA_CHECK
    # age checking to determine how old they are
    if ($LJ::COPPA_CHECK) {
        my $uniq;
        if ($LJ::UNIQ_COOKIES) {
            $uniq = BML::get_request()->notes('uniq');
            if ($uniq) {
                my $timeof = $dbh->selectrow_array('SELECT timeof FROM underage WHERE uniq = ?', undef, $uniq);
                $is_underage = 1 if $timeof && $timeof > 0;
            }
        }

        my ($year, $mon, $day) = ( $post->{bday_yyyy}+0, $post->{bday_mm}+0, $post->{bday_dd}+0 );
        if ($year < 100 && $year > 0) {
            $post->{bday_yyyy} += 1900;
            $year += 1900;
        }

        my $nyear = (gmtime())[5] + 1900;

        # require dates in the 1900s (or beyond)
        if ($year && $mon && $day && $year >= 1900 && $year < $nyear) {
            my $age = LJ::calc_age($year, $mon, $day);
            $is_underage = 1 if $age < 13;
            $ofage = 1 if $age >= 13;
        } else {
            $from_post{errors}->{bday} = $class->ml('widget.createaccount.error.birthdate.invalid');
        }

        # note this unique cookie as underage (if we have a unique cookie)
        if ($is_underage && $uniq) {
            $dbh->do("REPLACE INTO underage (uniq, timeof) VALUES (?, UNIX_TIMESTAMP())", undef, $uniq);
        }
    }
    ### end COPPA_CHECK

    # check the email address
    my @email_errors;
    LJ::check_email($email, \@email_errors);
    if ($LJ::USER_EMAIL and $email =~ /\@\Q$LJ::USER_DOMAIN\E$/i) {
        push @email_errors, $class->ml('widget.createaccount.error.email.lj_domain', { domain => $LJ::USER_DOMAIN });
    }
    $from_post{errors}->{email} = join(", ", @email_errors) if @email_errors;

    # check the captcha answer if it's turned on
    if ($LJ::HUMAN_CHECK{create}) {
        if (LJ::is_enabled("recaptcha")) {
            if ($post->{recaptcha_response_field}) {
                my $c = Captcha::reCAPTCHA->new;
                my $result = $c->check_answer(
                    LJ::conf_test($LJ::RECAPTCHA{private_key}), $ENV{'REMOTE_ADDR'},
                    $post->{'recaptcha_challenge_field'}, $post->{'recaptcha_response_field'}
                );

               $from_post{errors}->{captcha} = $class->ml('widget.createaccount.error.captcha.invalid') unless $result->{'is_valid'} eq '1';
            } else {
                $from_post{errors}->{captcha} = $class->ml('widget.createaccount.error.captcha.invalid');
            }
        } elsif (!$wants_audio) {
            ($capid, $anum) = LJ::Captcha::session_check_code($post->{captcha_chal}, $post->{answer});
            $from_post{errors}->{captcha} = $class->ml('widget.createaccount.error.captcha.invalid') unless $capid && $anum;
            $from_post{capid} = $capid;
            $from_post{anum} = $anum;
        }
    }

    # create user and send email as long as the user didn't double-click submit
    # (or they tried to re-create a purged account)
    unless ($second_submit || keys %{$from_post{errors}} || (!LJ::is_enabled("recaptcha") && $wants_audio)) {
        my $bdate = sprintf("%04d-%02d-%02d", $post->{bday_yyyy}, $post->{bday_mm}, $post->{bday_dd});

        my $nu = LJ::User->create_personal(
            user => $user,
            bdate => $bdate,
            email => $email,
            password => $post->{password1},
            get_ljnews => $post->{news},
            inviter => $get->{from},
            underage => $is_underage,
            ofage => $ofage,
        );
        return $class->ml('widget.createaccount.error.cannotcreate') unless $nu;

        if ($LJ::HUMAN_CHECK{create} && !LJ::is_enabled("recaptcha")) {
            # mark the captcha for deletion
            LJ::Captcha::expire($capid, $anum, $nu->id);
        }

        # send welcome mail... unless they're underage
        unless ($is_underage) {
            my $aa = LJ::register_authaction($nu->id, "validateemail", $email);

            my $body = LJ::Lang::ml('email.newacct4.body', {
                sitename => $LJ::SITENAME,
                regurl => "$LJ::SITEROOT/confirm/$aa->{'aaid'}.$aa->{'authcode'}",
                journal_base => $nu->journal_base,
                username => $nu->user,
                siteroot => $LJ::SITEROOT,
                sitenameshort => $LJ::SITENAMESHORT,
                lostinfourl => "$LJ::SITEROOT/lostinfo.bml",
                editprofileurl => "$LJ::SITEROOT/manage/profile/",
                searchinterestsurl => "$LJ::SITEROOT/interests.bml",
                editpicsurl => "$LJ::SITEROOT/editpics.bml",
                customizeurl => "$LJ::SITEROOT/customize/style.bml",
                postentryurl => "$LJ::SITEROOT/update.bml",
            });

            LJ::send_mail({
                to => $email,
                from => $LJ::ADMIN_EMAIL,
                fromname => $LJ::SITENAME,
                charset => 'utf-8',
                subject => LJ::Lang::ml('email.newacct.subject', { sitename => $LJ::SITENAME }),
                body => $body,
            });
        }

        if ($LJ::TOS_CHECK) {
            my $err = "";
            $nu->tosagree_set(\$err)
                or return LJ::bad_input($err);
        }

        $nu->make_login_session;

        # Default new accounts to Plus level
        $nu->add_to_class('plus');
        $nu->set_prop("create_accttype", "plus");

        my $stop_output;
        my $body;
        my $redirect = undef;
        LJ::run_hook('underage_redirect', {
            u => $nu,
            redirect => \$redirect,
            ret => \$body,
            stop_output => \$stop_output,
        });

        return BML::redirect($redirect) if $redirect;
        return $body if $stop_output;

        $redirect = LJ::run_hook('rewrite_redirect_after_create', $nu);
        return BML::redirect($redirect) if $redirect;

        my $url = LJ::ab_testing_value() == 0 ? "step2a.bml" : "step2b.bml";
        return BML::redirect("$LJ::SITEROOT/create/$url$opts{getextra}");
    }

    return %from_post;
}

1;
