# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

package LJ::Widget::CreateAccount;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use LJ::CreatePage;
use DW::Captcha;

sub need_res { qw( stc/widgets/createaccount.css js/widgets/createaccount.js js/browserdetect.js ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $post = $opts{post};
    my $get = $opts{get};
    my $from_post = $opts{from_post};
    my $errors = $from_post->{errors};

    my $code = LJ::trim( $get->{code} );
    my $from = LJ::trim( $get->{from} );

    my $error_msg = sub {
        my ( $key, $pre, $post ) = @_;
        my $msg = $errors->{$key};
        return unless $msg;
        return "$pre $msg $post";
    };

    my $ret;

    $ret .= $class->start_form(%{$opts{form_attr}});

    my $tip_birthdate = LJ::ejs($class->ml('widget.createaccount.tip.birthdate2'));
    my $tip_email = LJ::ejs($class->ml('widget.createaccount.tip.email'));
    my $tip_password = LJ::ejs($class->ml('widget.createaccount.tip.password'));
    my $tip_username = LJ::ejs($class->ml('widget.createaccount.tip.username'));

    $ret .= "<script type='text/javascript'>\n";
    $ret .= "CreateAccount.birthdate = \"$tip_birthdate\"\n";
    $ret .= "CreateAccount.email = \"$tip_email\"\n";
    $ret .= "CreateAccount.password = \"$tip_password\"\n";
    $ret .= "CreateAccount.username = \"$tip_username\"\n";
    $ret .= "</script>\n";

    # Errors container, listed in a TOC for screen-reader convenience
    # Don't even build if there are no errors in the page
    # IMPORTANT: The placement of this list in the HTML is necessary for
    # screen readers to announce it correctly after form submission. If you want to
    # move it, use CSS.
    if ( keys %$errors ) {
        $ret .= "<div tabindex=1 id='error-list' class='error-list' role='alert'>";
        $ret .= "<h2 class='nav' id='errorlist_label'>"
                .  LJ::ejs($class->ml('widget.createaccount.error.list'))
                .  "</h2>";
        $ret .= "<ol role='alert' labelledby='errorlist_label'>";

        # Print out all of the error messages that exist.
        # Do this manually as opposed to in a for loop in order to guarantee the order
        # matches the layout of the page
        $ret .= $error_msg->('username', '<li class="formitemFlag" role="alert">', '</li>');
        $ret .= $error_msg->('email', '<li class="formitemFlag" role="alert">', '</li>');
        $ret .= $error_msg->('password', '<li class="formitemFlag" role="alert">', '</li>');
        $ret .= $error_msg->('confirmpass', '<li class="formitemFlag" role="alert">', '</li>');
        $ret .= $error_msg->('bday', '<li class="formitemFlag" role="alert">', '</li>');
        $ret .= $error_msg->('captcha', '<li class="formitemFlag" role="alert">', '</li>');
        $ret .= $error_msg->('tos', '<li class="formitemFlag" role="alert">', '</li>');
            
        $ret .= "</ol>";
        $ret .= "</div> <!-- error-list -->\n";
    }

    # FIXME: this table should be converted to fieldsets and css layout
    # instead of tables for maximum accessibility. Eventually.

    $ret .= "<div class='relative-container'>\n";
    $ret .= "<div id='tips_box_arrow'></div>";
    $ret .= "<div id='tips_box'></div>";
    $ret .= "<table class='create-form' cellspacing='0' cellpadding='3'>\n";

    ### username

    # Highlight the field if the user needs to fix errors
    my $label_username = $errors->{'username'} ? "errors-present" : "errors-absent"; 
      
    $ret .= "<tr><td class='$label_username'>"
            .  $class->ml('widget.createaccount.field.username')
            .  "</td>\n<td>";
    
    # maxlength 26, so if people don't notice that they hit the limit,
    # we give them a warning. (some people don't notice/proofread)
    $ret .= $class->html_text(
        name => 'user',
        id => 'create_user',
        size => 20,
        maxlength => 26,
        raw => 'tabindex=1 style="<?loginboxstyle?>" aria-required="true"',
        value => $post->{user} || $get->{user},
    );

    # If JavaScript is available, check to see if the username is available
    # before submitting the form. Make sure that responses are returned as
    # ARIA live region for screen reader compatibility.
    $ret .= LJ::img( 'create_check', '', { 'id' => 'username_check', 
                                           'aria-live' => 'polite' } );
    $ret .= "<span id='username_error'><br /><span id='username_error_inner' class='formitemFlag' role='alert'></span></span>";

    $ret .= "</td></tr>\n";

    ### email

    # Highlight the field if the user needs to fix errors
    my $label_email = $errors->{'email'} ? "errors-present" : "errors-absent"; 
      
    $ret .= "<tr><td class='$label_email'>"
            .  $class->ml('widget.createaccount.field.email')
            .  "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'email',
        id => 'create_email',
        size => 28,
        maxlength => 50,
        raw => 'tabindex=1 aria-required="true"',
        value => $post->{email},
    );
    $ret .= "</td></tr>\n";

    ### password

    # Highlight the field if the user needs to fix errors
    my $label_password = $errors->{'password'} ? "errors-present" : "errors-absent"; 
      
    my $pass_value = $errors->{password} ? "" : $post->{password1};

    $ret .= "<tr><td class='$label_password'>"
            .  $class->ml('widget.createaccount.field.password')
            .  "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'password1',
        id => 'create_password1',
        size => 28,
        maxlength => 31,
        type => "password",
        raw => 'tabindex=1 aria-required="true"',
        value => $pass_value,
    );
    $ret .= "</td></tr>\n";

    ### confirm password

    # Highlight the field if the user needs to fix errors
    my $label_confirmpass = $errors->{'confirmpass'} ? "errors-present" : "errors-absent"; 
      
    $ret .= "<tr><td class='$label_confirmpass'>"
            . $class->ml('widget.createaccount.field.confirmpassword')
            . "</td>\n<td>";
    $ret .= $class->html_text(
        name => 'password2',
        id => 'create_password2',
        size => 28,
        maxlength => 31,
        type => "password",
        raw => 'tabindex=1 aria-required="true"',
        value => $pass_value,
    );
    $ret .= "</td></tr>\n";

    ### birthdate

    # Highlight the field if the user needs to fix errors
    my $label_bday = $errors->{'bday'} ? "errors-present" : "errors-absent"; 
      

    $ret .= "<tr>"
            .  "<td class='$label_bday'><label for='create_bday_mm'>"
            .  $class->ml('widget.createaccount.field.birthdate')
            .  "</label></td>\n<td>";
    $ret .= $class->html_datetime(
        name => 'bday',
        id => 'create_bday',
        raw => 'aria-required="true" tabindex=1',
        notime => 1,
        default => sprintf("%04d-%02d-%02d", $post->{bday_yyyy}, $post->{bday_mm}, $post->{bday_dd}),
    );
      
    $ret .= "</td></tr>\n";

    ### captcha

    # Highlight the field if the user needs to fix errors
    # NOTE: Because captcha is not currently in use on
    # dreamwidth.org, and because its accessibility is negligible
    # at best, WAI-ARIA code is not wrapped around the
    # captcha functionality.
    my $label_captcha = $errors->{'captcha'} ? "errors-present" : "errors-absent"; 

    my $captcha = DW::Captcha->new( 'create', %{$post || {}} );
    if ( $captcha->enabled ) {
        $ret .= "<tr valign='top'><td class='$label_captcha'>"
                .  $class->ml('widget.createaccount.field.captcha2')
                .  "</td>\n<td>";
        $ret .= $captcha->print;
        $ret .= "</td></tr>\n";
    }

    ### TOS

    # Highlight the field if the user needs to fix errors
    my $label_tos = $errors->{'tos'} ? "errors-present" : "errors-absent"; 
      
    # site news
    $ret .= "<tr valign='top'><td class='field-name'>&nbsp;</td>\n<td>";
    $ret .= $class->html_check(
        name => 'news',
        id => 'create_news',
        value => '1',
        raw => 'tabindex=1',
        selected => LJ::did_post() ? $post->{news} : 1,
        label => $class->ml('widget.createaccount.field.news', { sitename => $LJ::SITENAMESHORT }),
    );
    $ret .= "</td></tr>\n";

    # TOS
    $ret .= "<tr valign='top'><td class='$label_tos'>&nbsp;</td>\n<td>";
    $ret .= $class->html_check(
        name => 'tos',
        id => 'create_tos',
        value => '1',
        raw => 'tabindex=1',
        selected => LJ::did_post() ? $post->{tos} : 0,
    );
    $ret .= " <label for='create_tos' class='text'>";
    $ret .= $class->ml( 'widget.createaccount.field.tos', {
        sitename => $LJ::SITENAMESHORT,
        aopts1 => "href='$LJ::SITEROOT/legal/tos' target='_new'",
        aopts2 => "href='$LJ::SITEROOT/legal/privacy' target='_new'",
    } );
    $ret .= "</label>";
    $ret .= "</td></tr>\n";

    if ( $LJ::USE_ACCT_CODES && !DW::InviteCodes->is_promo_code( code => $code ) ) {
        my $item = DW::InviteCodes->paid_status( code => $code );
        if ( $item ) {
            $ret .= "<tr valign='top'><td class='field-name'>&nbsp;</td>\n<td>";
            if ( $item->permanent ) {
                $ret .= $class->ml( 'widget.createaccount.field.paidaccount.permanent', { type => "<strong>" . $item->class_name . "</strong>" } );
            } else {
                $ret .= $class->ml( 'widget.createaccount.field.paidaccount', { type => "<strong>" . $item->class_name . "</strong>", nummonths => $item->months } );
            }
            $ret .= "</td></tr>";
        }
    }

    ### submit button
    $ret .= "<tr valign='top'><td class='field-name'>&nbsp;</td>\n<td>";
    $ret .= $class->html_submit( 
        submit => $class->ml('widget.createaccount.btn'), 
        { class => "create-button",
          raw => 'tabindex=1', 
        },
    ) . "\n";
    $ret .= "</td></tr>\n";
    $ret .= "</table>\n";
    $ret .= "</div> <!-- relative-container -->\n";

    $ret .= $class->html_hidden( from => $from ) if $from;
    $ret .= $class->html_hidden( code => $code ) if $LJ::USE_ACCT_CODES;

    $ret .= $class->end_form;

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my %from_post;
    my $remote = LJ::get_remote();

    $post->{user} = LJ::trim($post->{user});
    my $user = LJ::canonical_username($post->{user});
    my $email = LJ::trim(lc $post->{email});

    # set up global things that can be used to modify the user later
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

    # validate code
    my $code = LJ::trim( $post->{code} );
    if ( $LJ::USE_ACCT_CODES ) {
        my $u = LJ::load_user( $post->{user} );
        my $userid = $u ? $u->id : 0;
        if ( DW::InviteCodes->check_code( code => $code, userid => $userid ) ) {
            $from_post{code_valid} = 1;

            # and if this is a community promo code, set the inviter
            if ( my $pc = DW::InviteCodes->get_promo_code_info( code => $code ) ) {
                if ( $pc->{suggest_journalid} ) {
                    my $invu = LJ::load_userid( $pc->{suggest_journalid} );
                    $post->{from} = $invu->user if $invu;
                }
            }

        } else {
            my $r = DW::Request->get;
            my $args = $r->query_string;
            my $querysep = $args ? "?" : "";
            my $uri = "$LJ::SITEROOT/create" . $querysep . $args;
            return BML::redirect( $uri );
        }
    }

    $post->{password1} = LJ::trim($post->{password1});
    $post->{password2} = LJ::trim($post->{password2});

    if ( !$post->{password1} ) {
        $from_post{errors}->{password} = $class->ml( 'widget.createaccount.error.password.blank' );
    } elsif ( $post->{password1} ne $post->{password2} ) {
        $from_post{errors}->{confirmpass} = $class->ml( 'widget.createaccount.error.password.nomatch' );
    } else {
        my $checkpass = LJ::CreatePage->verify_password( password => $post->{password1}, username => $user, email => $email );
        $from_post{errors}->{password} = $class->ml( 'widget.createaccount.error.password.bad' ) . " $checkpass"
            if $checkpass;
    }

    # age checking to determine how old they are
    my $uniq;
    my $is_underage = 0;

    $uniq = DW::Request->get->note('uniq');
    if ($uniq) {
        my $timeof = $dbh->selectrow_array('SELECT timeof FROM underage WHERE uniq = ?', undef, $uniq);
        $is_underage = 1 if $timeof && $timeof > 0;
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
    } else {
        $from_post{errors}->{bday} = $class->ml('widget.createaccount.error.birthdate.invalid');
    }

    # note this unique cookie as underage (if we have a unique cookie)
    if ($is_underage && $uniq) {
        $dbh->do("REPLACE INTO underage (uniq, timeof) VALUES (?, UNIX_TIMESTAMP())", undef, $uniq);
    }

    if ( $is_underage ) {
        $from_post{errors}->{bday} = 
            $class->ml('widget.createaccount.error.birthdate.underage');
    }

    ### end age check

    # check the email address
    my @email_errors;
    LJ::check_email($email, \@email_errors);
    if ($LJ::USER_EMAIL and $email =~ /\@\Q$LJ::USER_DOMAIN\E$/i) {
        push @email_errors, $class->ml('widget.createaccount.error.email.lj_domain', { domain => $LJ::USER_DOMAIN });
    }
    $from_post{errors}->{email} = join(", ", @email_errors) if @email_errors;

    # check the captcha answer if it's turned on
    my $captcha = DW::Captcha->new( 'create',  %{$post || {}} );
    my $captcha_error;
    $from_post{errors}->{captcha} = $captcha_error
        unless $captcha->validate( err_ref => \$captcha_error );

    # check TOS agreement
    $from_post{errors}->{tos} = $class->ml( 'widget.createaccount.error.tos' ) unless $post->{tos};

    # create user and send email as long as the user didn't double-click submit
    # (or they tried to re-create a purged account)
    unless ( $second_submit || keys %{$from_post{errors}} ) {
        my $bdate = sprintf("%04d-%02d-%02d", $post->{bday_yyyy}, $post->{bday_mm}, $post->{bday_dd});

        my $nu = LJ::User->create_personal(
            user => $user,
            bdate => $bdate,
            email => $email,
            password => $post->{password1},
            get_news => $post->{news} ? 1 : 0,
            inviter => $post->{from},
            extra_props => $opts{extra_props},
            status_history => $opts{status_history},
            code => $code,
        );
        return $class->ml('widget.createaccount.error.cannotcreate') unless $nu;

        # send welcome mail... unless they're underage
        my $aa = LJ::register_authaction($nu->id, "validateemail", $email);

        my $body = LJ::Lang::ml('email.newacct5.body', {
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
            subject => LJ::Lang::ml('email.newacct.subject', { sitename => $LJ::SITENAME }),
            body => $body,
        });

        $nu->make_login_session;

        # we're all done; mark the invite code as used
        if ( $LJ::USE_ACCT_CODES && $code ) {
            if ( DW::InviteCodes->is_promo_code( code => $code ) ) {
                DW::InviteCodes->use_promo_code( code => $code );
            } else {
                my $invitecode = DW::InviteCodes->new( code => $code );
                $invitecode->use_code( user => $nu );
            }
        }

        my $stop_output;
        $body = undef;
        my $redirect = $opts{ret};
        LJ::Hooks::run_hook('underage_redirect', {
            u => $nu,
            redirect => \$redirect,
            ret => \$body,
            stop_output => \$stop_output,
        });
        return BML::redirect($redirect) if $redirect;
        return $body if $stop_output;

        $redirect = LJ::Hooks::run_hook('rewrite_redirect_after_create', $nu);
        return BML::redirect($redirect) if $redirect;

        return BML::redirect( "$LJ::SITEROOT/create/setup" );
    }

    return %from_post;
}

1;
