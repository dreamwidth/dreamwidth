package DW::Controller::Talk;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Formats;
use Carp;

DW::Routing->register_string( '/talkpost_do', \&talkpost_do_handler, app => 1 );

# I think this canon isn't written down anywhere else, so HWAET: I sing a record
# of every damn form field that comes through in reply form POSTs. -NF
#
# Form names:
# - qrform
#     The quick-reply form, built by the LJ::create_qr_div function, in
#     LJ/Web.pm.
# - postform
#     The talkform, built by the LJ::Talk::talkform function.
# - There used to also be a previewform, but it was a menace and I killed it.
#
# Actual comment content (which gets saved to the DB):
# - subject
# - body
# - prop_picture_keyword
#     The user icon for this comment.
# - prop_opt_preformatted
#     The "don't autoformat" checkbox, which switches a comment from casual HTML
#     to raw HTML. Deprecated in favor of prop_editor and named formats. No
#     longer included in the forms, but can potentially come in via Protocol.
# - prop_editor
#     The markup format the comment's body text uses. See DW::Formats for more info.
# - prop_admin_post
#     Whether this comment is from a community admin (and should thus be displayed
#     specially).
# - subjecticon
#     The "subject icon" for this comment, chosen from a hardcoded list of ~32.
#     Only available in talkform.
# - editreason
#     An explanation for the edit; only present if editing.
#
# Sort of like comment content, but not quite:
# - unscreen_parent
#     Whether to unscreen the screened comment they're replying to. Only available
#     if this is a journal where the commenter can do that, and only shown in the
#     talkform. I think this is meant as a convenience for the no-javascript case,
#     because otherwise the AJAX unscreen button is faster and more intuitive.
#
# Identity stuff:
# - usertype
#     The type of user submitting the comment. In the quick-reply, this is locked
#     to `cookieuser`. In the talkform, it's a group of radio buttons so you can
#     switch user/go anon, and the value will be one of the following:
#         - anonymous
#         - openid
#         - openid_cookie
#         - cookieuser
#         - user
#     All of the identity fields mostly get consumed by the Talk controller, but
#     they can also influence the initial state of the talkform if it gets
#     regenerated partway through a comment submission (when previewing or when
#     there's an error that needs fixing). These fields are documented more fully
#     down in authenticate_user_and_mutate_form.
# - oidurl
# - oiddo_login
# - cookieuser
# - userpost
# - password
# - do_login
#
# Hidden fields that determine what the comment is replying to:
# - journal
#     The journal name for the entry they're replying to.
# - itemid
#     The ditemid (obfuscated display ID) of the entry they're replying to.
#     See comments in the implementation of LJ::Talk::talkform for more info about
#     the different ID formats.
# - parenttalkid
#     The jtalkid (raw ID) of the comment they're replying to. If they're replying
#     directly to the entry, this is 0.
# - replyto
#     An exact duplicate of parenttalkid;
#     LJ::Talk::Post::prepare_and_validate_comment will fall back to this if
#     parenttalkid isn't present, which should never be the case. Nothing else
#     uses this, but jquery.quickreply.js confirms that it's present before
#     allowing you to continue. LJ::Comment->create omits replyto in the mock form
#     it sends to prep/validate.
# - editid
#     The dtalkid (obfuscated display ID) of the existing comment to be edited. If
#     posting a new comment, this is 0.
#
# Consistency checks and metadata:
# - lj_form_auth
#     Form auth for logged-in users. I don't fully understand how this works yet,
#     but plenty of others around here do, so go ask them.
# - chrp1
#     A time-expiring server-provided token used to make spam posts inconvenient.
# - captcha_type (and other captcha fields)
#     Which captcha implementation to use, if a captcha is deemed necessary;
#     absent if not. Captchas can bring in additional form fields. These get
#     consumed by the captcha implementations, which get invoked down near the
#     bottom of LJ::Talk::Post::prepare_and_validate_comment.
# - qr
#     Hardcoded to 1 in the quick-reply form; absent in talkform. As far as I can
#     tell, nothing ever consumes this. Maybe was for some ancient server log
#     metrics?
#
# Things that affect the return link after replying:
# - viewing_thread
#     The filtered thread view (`?thread=12345`) they were in when they hit the
#     "reply" link, and which they should be returned to once they finish posting.
#     Consumed by Talk controller to build the return link.
# - style/format/s2id/fallback
#     The "viewing style" options (`?style=light`) that were in effect when they
#     hit the "reply" link, which should be re-instated once they finish
#     posting. You get one hidden input for each of these that was present,
#     although usually there's only one and the effects of mixing them seem
#     obscure. See LJ::viewing_style_opts (in Web.pm) for more info.
#
# Enablers for quick-reply's "more options" button:
# - dtid
#     The dtalkid (obfuscated display ID) of the comment they're replying to (in
#     other words, the display version of `parenttalkid`). Only used by the
#     quick-reply JS for building the "more options" URL. Nothing on the backend
#     ever consumes this.
# - basepath
#     The path to the journal entry they're replying to, with any viewing style
#     options included. The quick-reply JS uses this for building the "more
#     options" URL. Nothing on the backend ever consumes this.
#
# Submit buttons and their friends:
# - submitpost
#     The post button. Nothing on the backend listens for this by name; it's just
#     the button that does a "vanilla" form submission.
# - submitpreview
#     The actual signal to the backend that we need to build a preview for this
#     comment instead of posting it. Has indirect behavior sometimes because we
#     disable the post buttons with JS to prevent double-submits, and browsers
#     don't send disabled inputs. In the quick-reply, this is a hidden input whose
#     value gets set to 1 if they click `submitpview`. In the talkform, this is
#     the name of the preview button, so it gets sent normally if JS is disabled,
#     but see also `previewplaceholder`.
# - submitpview
#     The "preview" submit button in the quick-reply form. Nothing on the backend
#     listens for this by name; it just sets the value of the hidden
#     `submitpreview` input.
# - previewplaceholder
#     A hidden input in the talkform whose value is 1. If JS is enabled, we change
#     its name to `submitpreview` when they click the preview button, so the
#     signal to preview will reach the backend despite the submit buttons being
#     disabled.
# - submitmoreopts
#     The "more options" button in the quick-reply. Changes the action of the form
#     to point to the ReplyPage instead of to talkpost_do (so they can continue
#     with a partially-filled talkform), then submits. Nothing on the backend
#     listens for this by name.

sub talkpost_do_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, anonymous => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $title  = '.success.title';

    my $vars;

    # Like error_ml but for when we don't control the error string.
    my $err_raw = sub {
        return DW::Template->render_template( 'error.tt', { message => $_[0] } );
    };

    # For errors that aren't immediately fatal, collect them as we go and let
    # the user fix them all at once.
    my @errors;

    # If this is a GET (not POST), see if they're coming back from an OpenID
    # identity server. If so, restore the POST hash we saved before they left.
    if (   ( $GET->{'openid.mode'} eq 'id_res' || $GET->{'openid.mode'} eq 'cancel' )
        && $GET->{jid}
        && $GET->{pendcid} )
    {
        my $csr = LJ::OpenID::consumer( $GET->mixed );

        if ( $GET->{'openid.mode'} eq 'id_res' ) {    # Verify their identity

            unless ( LJ::check_referer( '/talkpost_do', $GET->{'openid.return_to'} ) ) {
                return error_ml( '/openid/login.tt.error.invalidparameter',
                    { item => "return_to" } );
            }

            my $errmsg;
            my $uo = LJ::User::load_from_consumer( $csr, \$errmsg );
            return $err_raw->($errmsg) unless $uo;

            # Change who we think we are. NB: don't use set_remote to ACTUALLY
            # change the remote, or you'll cause a glitch in the matrix. We just
            # want to use this OpenID user below to check auth, etc.
            $remote = $uo;
        }

        # Restore their data to reset state where they were
        my $pendcid = $GET->{pendcid} + 0;

        my $journalu = LJ::load_userid( $GET->{jid} );
        return error_ml("/talkpost_do.tt.error.openid.nodb") unless $journalu && $journalu->writer;

        my $pending =
            $journalu->selectrow_array( "SELECT data FROM pendcomments WHERE jid=? AND pendcid=?",
            undef, $journalu->{userid}, $pendcid );

        return error_ml("/talkpost_do.tt.error.openid.nopending") unless $pending;

        my $penddata = eval { Storable::thaw($pending) };

        $POST = $penddata;

        # Not fatal, maybe just decided to be someone else for this comment:
        push @errors, "You chose to cancel your identity verification"
            if $csr->user_cancel;
    }
    elsif ( !LJ::did_post() ) {

        # If it's a GET and you're NOT coming back from the OpenID dance, wyd
        return error_ml('/talkpost_do.tt.error.badrequest');
    }

    # We don't call LJ::text_in() here; instead, we call it during
    # LJ::Talk::Post::prepare_and_validate_comment.
    # Old talkpost_do.bml comments said they did this because of non-UTF-8 in
    # "replies coming from mail clients," but nobody in 2020 knew what that
    # meant. (Maybe they just wanted to call it only once, so they put it in a
    # spot where it would also hit replies that come through LJ::Protocol
    # instead of talkpost_do? But you'd think encoding checks should be the
    # concern of the request handler, whether it's Protocol or a controller.)
    # Anyway... the point is it gets called eventually. -NF

    my $journalu = LJ::load_user( $POST->{journal} );
    return error_ml('/talkpost_do.tt.error.nojournal') unless $journalu;

    # This launches some garbage into the void of the Apache "notes" system, and
    # it's impossible to know for sure what ends up reading it as an implicit
    # argument. Obviously everyone hates this. It dates back to the old
    # talkpost_do.bml we inherited from LJ. NF's best guess is that S2.pm
    # expects this, but it might also be irrelevant. Who knows.
    $r->note( 'journalid', $journalu->userid ) if $r;

    unless ( $POST->{itemid} ) {
        return error_ml('talk.error.noentry');
    }
    my $entry   = LJ::Entry->new( $journalu, ditemid => $POST->{itemid} + 0 );
    my $talkurl = $entry->url;

    # validate the challenge/response value (anti-spammer)
    my ( $chrp_ok, $chrp_err ) = LJ::Talk::validate_chrp1( $POST->{'chrp1'} );
    unless ($chrp_ok) {
        if ( $LJ::DEBUG{'talkspam'} ) {
            my $ip    = LJ::get_remote_ip();
            my $ruser = $remote ? $remote->{user} : "[nonuser]";
            carp("talkhash error: from $ruser \@ $ip - $chrp_err - $talkurl\n");
        }
        if ($LJ::REQUIRE_TALKHASH) {
            push @errors,
"Sorry, form expired.  Press back, copy text, reload form, paste into new form, and re-submit."
                if $chrp_err eq "too_old";
            push @errors, "Missing parameters";
        }
    }

    ## Sort out who's posting for real.
    my ( $commenter, $didlogin );
    my ( $authok, $auth ) = authenticate_user_and_mutate_form( $POST, $remote, $journalu );
    if ($authok) {
        if ( $auth->{check_url} ) {

            # openid thing. Round and round we go.
            return $r->redirect( $auth->{check_url} );
        }
        else {
            $commenter = $auth->{user};
            $didlogin  = $auth->{didlogin};
        }
    }
    else {
        push @errors, $auth;
    }

    # Now that we've given them a chance to log in, set a resource group.
    # FIXME: You're supposed to set this in the template, so if someone ever
    # rewrites DW::Captcha::TextCAPTCHA to stop snooping around in
    # $LJ::ACTIVE_RES_GROUP, definitely do that. In the meantime, this needs to
    # happen before LJ::Talk::talkform gets called or things might break. -NF
    my $real_remote = LJ::get_remote();
    if ( LJ::BetaFeatures->user_in_beta( $real_remote => "s2foundation" ) ) {
        LJ::set_active_resource_group("foundation");
    }
    else {
        LJ::set_active_resource_group("jquery");
    }

    ## Prepare the comment (or wipe out on the permissions/consistency checks)
    my $need_captcha = 0;
    my $comment =
        LJ::Talk::Post::prepare_and_validate_comment( $POST, $commenter, $entry, \$need_captcha,
        \@errors );

    # If there's anything in @errors at the end of prepare_and_validate_comment,
    # it returns undef instead of a $comment, even if it wasn't the one to
    # add those errors. So all the "non-fatal" errors we've been logging above
    # become suddenly fatal right... about... NOW.

    # At this point, there's three main paths:
    # 1. Stop and show the requested preview (and report errors inline)
    # 2. Stop and ask user to fix errors
    # 3. Continue and post the comment for real.

    # 1. We're previewing!
    # For most errors, we preview anyway; they can fix it while they edit
    # their text. But we DO need to know who they think they are, so let the
    # error path handle auth failures.
    if ( $authok && $POST->{submitpreview} ) {

        # yer a reply page, Harry. (keep consistent behavior by loading same
        # JS/CSS as journal pages.)
        LJ::Talk::init_s2journal_js(
            iconbrowser => 1,
            siteskin    => 1,
            noqr        => 1
        );

        # Plus we're displaying entry/comment content, so the legacy site skins
        # need CSS for that.
        LJ::need_res( { group => 'jquery' }, 'stc/siteviews/layout.css', 'stc/entrypage.css', );

        # If validation failed, just use what we have on hand to build the preview.
        # Might theoretically have borked non-UTF-8, shrug.
        unless ($comment) {
            $comment = {
                u      => $commenter,
                entry  => $entry,
                parent => {
                    talkid => $POST->{replyto} || $POST->{parenttalkid},
                },
                subject         => $POST->{subject},
                body            => $POST->{body},
                subjecticon     => $POST->{subjecticon} eq 'none' ? '' : $POST->{subjecticon},
                preformat       => $POST->{'prop_opt_preformatted'},
                admin_post      => $POST->{'prop_admin_post'},
                picture_keyword => $POST->{'prop_picture_keyword'},
                editor          => $POST->{'prop_editor'},
            };
        }

        my $talkform = LJ::Talk::talkform(
            {
                journalu   => $journalu,
                parpost    => $comment->{parent},
                replyto    => $comment->{parent}->{talkid},
                ditemid    => $comment->{entry}->ditemid,
                do_captcha => $need_captcha,
                errors     => @errors ? \@errors : undef,
                form       => $POST,
            }
        );

        $vars->{title}   = '.title.preview';
        $vars->{preview} = 1;
        $vars->{comment} = preview_comment_args($comment);
        $vars->{parent}  = preview_parent_args($comment);
        $vars->{html}    = $talkform;
        return DW::Template->render_template( 'talkpost_do.tt', $vars );
    }

    # 2. Validation failed!
    # Don't continue; report errors, ask for help, and regenerate the
    # form. We repopulate what we can via hidden fields, but the objects
    # (journalu & parpost) must be recreated here.
    unless ($comment) {
        my ( $sth, $parpost );
        my $dbcr = LJ::get_cluster_def_reader($journalu);
        return error_ml('/talkpost_do.tt.error.nodb') unless $dbcr;

        $sth = $dbcr->prepare(
            "SELECT posterid, state FROM talk2 " . "WHERE journalid=? AND jtalkid=?" );
        $sth->execute( $journalu->{userid}, $POST->{itemid} + 0 );
        $parpost = $sth->fetchrow_hashref;

        # yer a reply page, Harry. (keep consistent behavior by loading same
        # JS/CSS as journal pages.)
        LJ::Talk::init_s2journal_js(
            iconbrowser => 1,
            siteskin    => 1,
            noqr        => 1
        );

        my $talkform = LJ::Talk::talkform(
            {
                journalu   => $journalu,
                parpost    => $parpost,
                replyto    => $POST->{replyto} || $POST->{parenttalkid},
                ditemid    => $POST->{itemid},
                do_captcha => $need_captcha,
                errors     => \@errors,
                form       => $POST,
            }
        );
        $vars->{title} = '.title.error';
        $vars->{html}  = $talkform;
        return DW::Template->render_template( 'talkpost_do.tt', $vars );
    }

    # 3. It's go time!!
    # We might show a page at the end anyway (for example, if the user logged
    # in), but the most common path is to silently redirect back to the thread
    # after posting.

    my $parent = $comment->{parent};

    my $unscreen_parent = $POST->{unscreen_parent} ? 1 : 0;

    # ACTUALLY POST IT
    my $editid      = $POST->{editid};
    my $wasscreened = ( $parent->{state} eq 'S' );
    my $talkid;

    if ($editid) {
        my ( $postok, $talkid_or_err ) = LJ::Talk::Post::edit_comment($comment);
        unless ($postok) {
            return $err_raw->($talkid_or_err);
        }
        $talkid = $talkid_or_err;
    }
    else {
        my ( $postok, $talkid_or_err ) = LJ::Talk::Post::post_comment( $comment, $unscreen_parent );
        unless ($postok) {
            return $err_raw->($talkid_or_err);
        }
        $talkid = $talkid_or_err;
    }

    # Yeah, we're done.
    my $dtalkid = $talkid * 256 + $entry->{anum};

    # Figure out whether we should offer to update their default formatting.
    my $editor_new;
    if (   $real_remote
        && DW::Formats::is_active( $comment->{editor} )
        && $comment->{editor} ne $real_remote->comment_editor )
    {
        $editor_new = $comment->{editor};
    }

    # Allow style=mine, etc for QR redirects
    my $style_args = LJ::viewing_style_args(%$POST);

# FIXME: potentially can be replaced with some form of additional logic when we have multiple account linkage
    my $posted = $comment->{state} eq 'A' ? "posted=1" : "";

    my $cthread = $POST->{'viewing_thread'} ? "thread=$POST->{viewing_thread}" : "view=$dtalkid";
    my $commentlink = LJ::Talk::talkargs( $talkurl, $cthread, $style_args, $posted )
        . LJ::Talk::comment_anchor($dtalkid);

    my $mlcode;
    if ( $comment->{state} eq 'A' ) {

        # Redirect straight to the post as long as:
        # - it isn't screened
        # - it didn't unscreen its parent
        # - its formatting type didn't change
        # - it didn't log the user in as a side-effect
        if ( !( $wasscreened && ( $parent->{state} ne 'S' ) ) && !$didlogin && !$editor_new ) {
            LJ::set_lastcomment( $journalu->id, $commenter, $dtalkid );
            return $r->redirect($commentlink);
        }

        $mlcode = '.success.message2';
    }
    else {
        # otherwise, it's a screened comment.
        if ( $journalu && $journalu->is_community ) {
            if ( $POST->{usertype} eq 'anonymous' ) {
                $mlcode = '.success.screened.comm.anon3';
            }
            elsif ( $commenter && $commenter->can_manage($journalu) ) {
                $mlcode = '.success.screened.comm.owncomm4';
            }
            else {
                $mlcode = '.success.screened.comm3';
            }
        }
        else {    # not a community
            if ( $POST->{usertype} eq 'anonymous' ) {
                $mlcode = '.success.screened.user.anon3';
            }
            elsif ( $commenter && $commenter->equals($journalu) ) {
                $mlcode = '.success.screened.user.ownjournal3';
            }
            else {
                $mlcode = '.success.screened.user3';
            }
        }
    }
    $vars->{title} = $title;

    my @notices = ( LJ::Lang::ml( "/talkpost_do.tt$mlcode", { aopts => "href='$commentlink'" } ) );
    push @notices,
        DW::Template->template_string(
        'default_editor_form.tt',
        {
            type      => 'comment',
            format    => $DW::Formats::formats{$editor_new},
            exit_text => "Return to comment",
            exit_url  => $commentlink,
        }
        ) if $editor_new;
    push @notices, LJ::Lang::ml('/talkpost_do.tt.success.unscreened')
        if $wasscreened && ( $parent->{state} ne 'S' );
    push @notices, LJ::Lang::ml('/talkpost_do.tt.success.loggedin') if $didlogin;
    $vars->{html} = join( "\n", map { "<p>$_</p>" } @notices );

    return DW::Template->render_template( 'talkpost_do.tt', $vars );
}

# Handles user auth for the talkform's "from" fields.
# Args:
# - $form: a hashref representing the POSTed comment form. We might mutate its
# usertype, userpost, cookieuser, and oidurl fields, in order to canonicalize
# some values or help the comment form react to a change in the global login
# state.
# - $remote: the current logged-in LJ::User, or undef, OR the just-now
# authenticated OpenID user (which is why we can't just get_remote from within).
# - $journalu: LJ::User who owns the journal the comment was submitted to. Need
# this for storing pending comments in first pass through openid auth, and also
# we use it to switch off between variant error messages.
# Returns: (1, result) on success, (0, error) on failure. result is one of:
# - {user => $u, didlogin => $bool} ($u is undef for anons)
# - {check_url => $url} (openid redirect)
sub authenticate_user_and_mutate_form {
    my ( $form, $remote, $journalu ) = @_;

    my $didlogin = 0;

    my $err = sub {
        my $error = shift;
        return ( 0, $error );
    };
    my $mlerr = sub {
        return $err->( LJ::Lang::ml(@_) );
    };
    my $incoherent = sub {
        return $mlerr->("/talkpost_do.tt.error.confused_identity");
    };
    my $got_user = sub {
        my $user = shift;
        return ( 1, { user => $user, didlogin => $didlogin } );
    };

    # The "usertype" field must be one of the following. (Each value might have
    # some associated fields it expects, which are shown as nested lists.)
    # - anonymous
    #   - (nothing)
    # - openid
    #   - oidurl
    #   - oiddo_login
    # - openid_cookie
    #   - (nothing) (in talkform), OR:
    #   - cookieuser (= ext_1234) (in quickreply)
    # - cookieuser (currently logged in user)
    #   - cookieuser (= username) (yes, "cookieuser" is the field's name)
    # - user (non-logged-in user, w/ name/password provided)
    #   - userpost (the username provided in the form)
    #   - password
    #   - do_login

    # CHECKLIST:
    # 1. Check for incoherent combinations of fields. (Most can only happen with
    # JS disabled. I'm told there were once cases where it could post as the
    # wrong user, possibly without auth; who knows. But regardless, conflicting
    # info means the user's intention was not clear and they must clarify.)
    # 2. Validate the specified user type's credentials.
    # 3. If validated, return the relevant user object.
    # 4. OpenID is weird.
    # NOTA BENE: This long "if" statement is tedious and stupid, and I'm well
    # aware there's several cleverer and more exciting ways to write it. But
    # don't. KEEP IT STUPID. KEEP IT SAFE. </gandalf voice> -NF, 2020
    if ( $form->{usertype} eq 'anonymous' ) {
        if ( $form->{oidurl} || $form->{userpost} ) {
            return $incoherent->();
        }
        return $got_user->(undef);    # Well! that was easy.
    }
    elsif ( $form->{usertype} eq 'cookieuser' ) {
        if ( $form->{oidurl} ) {
            return $incoherent->();
        }

        # If they selected "current user" and then typed in their own username,
        # well, that's "wrong" but their intention was perfectly clear. But if
        # they typed in a DIFFERENT username, get outta here.
        if ( $form->{userpost} && ( $form->{userpost} ne $form->{cookieuser} ) ) {
            return $incoherent->();
        }

        # OK! Check if that's the logged-in user.
        if ( $remote && ( $remote->user eq $form->{cookieuser} ) ) {
            return $got_user->($remote);    # Cool.
        }
        else {
            return $mlerr->("/talkpost_do.tt.error.lostcookie");
        }
    }
    elsif ( $form->{usertype} eq 'user' ) {
        if ( $form->{oidurl} ) {
            return $incoherent->();
        }

        # No username?
        if ( !$form->{userpost} ) {
            my $iscomm = $journalu->is_community ? '.comm' : '';
            my $noanon = $journalu->prop('opt_whocanreply') eq 'all' ? '' : '.noanon';
            return $mlerr->(
                "/talkpost_do.tt.error.nousername$noanon$iscomm",
                { sitename => $LJ::SITENAMESHORT }
            );
        }

        my $exptype;    # set to long if ! after username
        my $ipfixed;    # set to remote ip if < after username

        # Parse inline login options.
        # MUTATE FORM: remove trailing garbage from username.
        if ( $form->{userpost} =~ s/([!<]{1,2})$// ) {
            $exptype = 'long' if index( $1, "!" ) >= 0;
            $ipfixed = LJ::get_remote_ip() if index( $1, "<" ) >= 0;
        }

        my $up = LJ::load_user( $form->{userpost} );

        # Now for all the things that can go wrong:
        if ( !$up ) {
            return $mlerr->(
                "/talkpost_do.tt.error.badusername2",
                {
                    sitename => $LJ::SITENAMESHORT,
                    aopts    => "href='$LJ::SITEROOT/lostinfo'"
                }
            );
        }

        if ( $up->is_identity ) {
            return $err->( "To comment as an OpenID user, you must choose the "
                    . "OpenID option and authenticate with your identity provider; "
                    . "it's not possible to log in using an OpenID account's "
                    . "internal 'ext_12345' username." );
        }

        if ( $up->is_community || $up->is_syndicated ) {
            return $mlerr->("/talkpost_do.tt.error.postshared");
        }

        # authenticate on username/password
        my $ok = LJ::auth_okay( $up, $form->{password} );

        unless ($ok) {

            # Don't pre-populate the fix-up form with a password we already know is wrong.
            $form->{password} = '';
            return $mlerr->(
                "/talkpost_do.tt.error.badpassword2",
                { aopts => "href='$LJ::SITEROOT/lostinfo'" }
            );
        }

        # GREAT, they're in!

        # if the user chooses to log in, do so
        if ( $form->{do_login} ) {
            $didlogin = $up->make_login_session( $exptype, $ipfixed );

            # MUTATE FORM: change the usertype, so if they need to fix an
            # unrelated error and are already logged in, the form uses the
            # "currently logged-in user" option.
            $form->{usertype}   = 'cookieuser';
            $form->{cookieuser} = $up->user;
        }

        return $got_user->($up);
    }
    elsif ( $form->{usertype} eq 'openid' || $form->{usertype} eq 'openid_cookie' ) {
        if ( $form->{userpost} ) {
            return $incoherent->();
        }

        # Okay: This one's weird, but mostly just because the code order is
        # backwards from how things happen irl, WHICH IS:
        # - Person supplies OpenID URL.
        # - We store the form to the database, bail out, and tell the caller to
        # redirect to an authentication server URL. (The URL also tells the auth
        # server where to redirect to once IT'S done.)
        # - Auth server sends them back to /talkpost_do, but as a GET request
        # instead of a POST.
        # - Controller restores their frozen POST data from last time and calls
        # this function again, passing the newly authenticated user as $remote.
        # (This is why we're not using LJ::get_remote in this function, btw.)
        # - Since $remote is set, we let them through.

        # If $remote looks good, they're in.
        if ( $remote && defined $remote->openid_identity ) {

            # Go ahead and log in, if requested.
            if ( $form->{oiddo_login} ) {

                # Those extra form vars got stored last time, see below.
                $didlogin = $remote->make_login_session( $form->{exptype}, $form->{ipfixed} );

                # MUTATE FORM: change the usertype if they logged in, so
                # things look more consistent if they hit an unrelated error
                $form->{usertype} = 'openid_cookie';
            }

            return $got_user->($remote);    # welcome back
        }
        else {

            # If this is your first time at Tautology Club... you've never been
            # here before.

            return $err->("No OpenID identity URL entered") unless $form->{oidurl};

            my $csr     = LJ::OpenID::consumer();
            my $exptype = 'short';
            my $ipfixed = 0;

            # parse inline login opts
            # MUTATE FORM: remove trailing garbage from oidurl
            if ( $form->{oidurl} =~ s/([!<]{1,2})$// ) {
                $exptype = 'long' if index( $1, "!" ) >= 0;
                $ipfixed = LJ::get_remote_ip() if index( $1, "<" ) >= 0;
            }

            my $tried_local_ref = LJ::OpenID::blocked_hosts($csr);

            my $claimed_id = $csr->claimed_identity( $form->{oidurl} );

            unless ($claimed_id) {
                return $err->(
                    "You can't use a $LJ::SITENAMESHORT OpenID account on $LJ::SITENAME &mdash; "
                        . "just <a href='/login'>go login</a> with your actual $LJ::SITENAMESHORT account."
                ) if $$tried_local_ref;
                return $err->( "No claimed id: " . $csr->err );
            }

            # Store their cleaned up identity url (vs. what they actually typed.)
            # MUTATE FORM: canonicalize oidurl
            $form->{oidurl} = $claimed_id->claimed_url();

            # Store the entry
            my $pendcid = LJ::alloc_user_counter( $journalu, "C" );

            return $err->("Unable to allocate pending id") unless $pendcid;

            # persist login options in the form data, since we removed them from
            # the oidurl
            # MUTATE FORM: add junk that never appears in a real comment form.
            $form->{exptype} = $exptype;
            $form->{ipfixed} = $ipfixed;

            my $penddata = Storable::freeze($form);

            return $err->("Unable to get database handle to store pending comment")
                unless $journalu->writer;

            my $journalid = $journalu->id;

            $journalu->do(
"INSERT INTO pendcomments (jid, pendcid, data, datesubmit) VALUES (?, ?, ?, UNIX_TIMESTAMP())",
                undef, $journalid, $pendcid, $penddata
            );

            return $err->( $journalu->errstr ) if $journalu->err;

            my $check_url = $claimed_id->check_url(
                return_to      => "$LJ::SITEROOT/talkpost_do?jid=$journalid&pendcid=$pendcid",
                trust_root     => "$LJ::SITEROOT",
                delayed_return => 1,
            );

            # Caller must redirect to this URL.
            return ( 1, { check_url => $check_url } );
        }
    }
    else {
        return $err->("Reply form was submitted without any user information.");
    }
}

# Returns hashref for template.
sub preview_comment_args {
    my ($comment) = @_;

    my $cleansubject = $comment->{subject};
    LJ::CleanHTML::clean_subject( \$cleansubject );

    my $cleanbody = $comment->{body};
    LJ::CleanHTML::clean_comment(
        \$cleanbody,
        {
            anon_comment => LJ::Talk::treat_as_anon( $comment->{u}, $comment->{entry}->journal ),
            preformatted => $comment->{preformat},
            admin_post   => $comment->{admin_post},
            editor       => $comment->{editor},
        }
    );

    my $poster = "(Anonymous)";
    my $icon   = '';
    if ( $comment->{u} ) {
        $poster = $comment->{u}->ljuser_display;

        my $userpic = LJ::Userpic->new_from_keyword( $comment->{u}, $comment->{picture_keyword} );
        if ($userpic) {
            $icon =
                  '<a href="'
                . $comment->{u}->allpics_base . '">'
                . $userpic->imgtag( keyword => $comment->{prop_picture_keyword} ) . '</a>';
        }
    }

    my $preview = {
        poster      => $poster,
        subjecticon => LJ::Talk::print_subjecticon_by_id( $comment->{subjecticon} ),
        body        => $cleanbody,
        subject     => $cleansubject,
        icon        => $icon,
        admin_post  => $comment->{admin_post},
    };

    return $preview;
}

# Returns hashref for template.
sub preview_parent_args {
    my ($comment) = @_;

    my $userpic_tag = sub {
        my $item    = shift;
        my $icon    = '';
        my $userpic = $item->userpic;
        if ($userpic) {
            $icon = $userpic->imgtag( keyword => $item->userpic_kw );
        }
        return $icon;
    };

    my $entry = $comment->{entry};

    if ( $comment->{parent}->{talkid} ) {

        # Replying to comment
        my $parentitem =
            LJ::Comment->new( $entry->journal, jtalkid => $comment->{parent}->{talkid} );

        my $poster      = 'Anonymous';
        my $poster_name = '';
        my $in_journal  = $entry->journal->ljuser_display;

        if ( $parentitem->poster ) {
            $poster      = $parentitem->poster->ljuser_display;
            $poster_name = $parentitem->poster->name_html;

            if ( $parentitem->poster->user eq $entry->journal->user ) {
                $in_journal = '';
            }
        }

        return {
            type        => 'comment',
            body        => $parentitem->body_html,
            subject     => $parentitem->subject_html,
            poster      => $poster,
            poster_name => $poster_name,
            in_journal  => $in_journal,
            admin_post  => $parentitem->prop('admin_post'),
            icon        => $userpic_tag->($parentitem),
            time        => $parentitem->{datepost},
            url         => $parentitem->url,
            entry_url   => $entry->url,
        };
    }
    else {
        # Replying to entry

        my $in_journal =
            $entry->poster->user eq $entry->journal->user ? '' : $entry->journal->ljuser_display;

        return {
            type        => 'entry',
            body        => $entry->event_html,
            subject     => $entry->subject_html,
            poster      => $entry->poster->ljuser_display,
            poster_name => $entry->poster->name_html,
            in_journal  => $in_journal,
            icon        => $userpic_tag->($entry),
            time        => $entry->eventtime_mysql,
            url         => $entry->url,
            entry_url   => $entry->url,
        };
    }
}

1;
