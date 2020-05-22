package DW::Controller::Talk;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use Carp;

DW::Routing->register_string( '/talkpost_do', \&talkpost_do_handler, app => 1 );

sub talkpost_do_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, anonymous => 1);
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $POST   = $r->post_args;
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $title  = '.success.title';

    my $vars;

    # Hack to make sure resource group is set to SOMETHING (in case lj::talk
    # returns way too early and we don't pass through the template at all)
    LJ::set_active_resource_group( "jquery" );

    # With most kinds of commenting errors, the user can recover by fixing their
    # form inputs. There also might be several of these errors at once. So
    # unless it's something immediately fatal, just push errors onto @errors
    # instead of returning, and we'll bundle them up at the end.
    my @errors;
    my $skip_form_auth = 0;

    my $editid = $POST->{editid};

    # If this is a GET instead of a POST, check whether we're in the second pass
    # of the OpenID auth flow, where they come back from the identity server. If
    # so, we recreate their POST hash as if they never left.
    if (($GET->{'openid.mode'} eq 'id_res' || $GET->{'openid.mode'} eq 'cancel') && $GET->{jid} && $GET->{pendcid}) {
        my $csr = LJ::OpenID::consumer($GET->mixed);

        if ($GET->{'openid.mode'} eq 'id_res') { # Verify their identity

            unless ( LJ::check_referer('/talkpost_do', $GET->{'openid.return_to'}) ) {
                return error_ml( '/openid/login.bml.error.invalidparameter',
                                               { item => "return_to" } );
            }

            my $errmsg;
            my $uo = LJ::User::load_from_consumer( $csr, \$errmsg );
            return error_ml( $errmsg ) unless $uo;

            # Change who we think we are. NB: don't use set_remote to ACTUALLY
            # change the remote, or you'll cause a glitch in the matrix. We just
            # want to use this OpenID user below to check auth, etc.
            $remote = $uo;
            $skip_form_auth = 1;  # wouldn't have form auth at this point
        }

        # Restore their data to reset state where they were
        my $pendcid = $GET->{pendcid} + 0;

        my $journalu = LJ::load_userid($GET->{jid});
        return error_ml("Unable to load user or get database handle") unless $journalu && $journalu->writer;

        my $pending = $journalu->selectrow_array("SELECT data FROM pendcomments WHERE jid=? AND pendcid=?",
                                                 undef, $journalu->{userid}, $pendcid);

        return error_ml("Unable to load pending comment, maybe you took too long") unless $pending;

        my $penddata = eval { Storable::thaw($pending) };

        $POST = $penddata;

        # Not fatal, maybe just decided to be someone else for this comment:
        push @errors, "You chose to cancel your identity verification"
            if $csr->user_cancel;
    } elsif ( ! LJ::did_post() ) {
        # If it's a GET and you're NOT coming back from the OpenID dance, wyd
        return error_ml('/talkpost_do.tt.error.badrequest');
    }


    # as an exception, we do NOT call LJ::text_in() to check for bad
    # input, since it may be not in UTF-8 in replies coming from mail
    # clients. We call it later.


    my $journalu = LJ::load_user($POST->{journal});
    return error_ml('Unknown journal.  Please go back and try again.') unless $journalu; # hmm, is error_ml right? -NF
    $r->note( 'journalid', $journalu->userid ) if $r; # What the heck? -NF Oh, looks like maybe this gets looked up by S2.pm under some conditions.

    my $entry = LJ::Entry->new( $journalu, ditemid => $POST->{itemid} + 0 );
    unless ($entry) {
        push @errors, 'talk.error.noentry';
    }
    my $talkurl = $entry->url;

    # libs for userpicselect
    LJ::Talk::init_iconbrowser_js()
        if $remote && $remote->can_use_userpic_select;


    # validate form auth (maybe)
    push @errors, LJ::Lang::ml('error.invalidform') if $remote && ! ( $skip_form_auth || LJ::check_form_auth($POST->{lj_form_auth} ) );

    # validate the challenge/response value (anti-spammer)
    my ($chrp_ok, $chrp_err) = LJ::Talk::validate_chrp1($POST->{'chrp1'});
    unless ($chrp_ok) {
        if ( $LJ::DEBUG{'talkspam'} ) {
            my $ip = LJ::get_remote_ip();
            my $ruser = $remote ? $remote->{user} : "[nonuser]";
            carp( "talkhash error: from $ruser \@ $ip - $chrp_err - $talkurl\n" );
        }
        if ($LJ::REQUIRE_TALKHASH) {
            push @errors, "Sorry, form expired.  Press back, copy text, reload form, paste into new form, and re-submit." if $chrp_err eq "too_old";
            push @errors, "Missing parameters";
        }
    }

    ## preview
    # ignore errors for previewing
    if ($POST->{'submitpreview'} || ($POST->{'qr'} && $POST->{'do_spellcheck'})) {
        my $cookie_auth;
        $cookie_auth = 1 if $POST->{usertype} eq "cookieuser";

        $vars->{title} = '.title.preview';
        $vars->{html} = LJ::Talk::Post::make_preview($talkurl, $cookie_auth, $POST);
        return DW::Template->render_template( 'talkpost_do.tt', $vars );
    }

    ## Sort out who's posting for real.
    my $didlogin = 0;
    my $commenter_or_redirect = authenticate_user_and_mutate_form($POST, $remote, $journalu, \@errors, \$didlogin);
    if (defined $commenter_or_redirect && ! $commenter_or_redirect->isa('LJ::User')) {
        # openid thing. Round and round we go.
        return $r->redirect($commenter_or_redirect);
    }
    my $commenter = $commenter_or_redirect;

    ## Prepare the comment (or trip on our shoelaces during the permissions/consistency checks)
    my $need_captcha = 0;
    my $comment = LJ::Talk::Post::prepare_and_validate_comment($POST, $commenter, $entry, \$need_captcha, \@errors);

    # Report errors in a friendly manner by regenerating the field.
    # We repopulate what we can via hidden fields - however the objects (journalu & parpost) must be recreated here.
    unless ( $comment ) {
        my ($sth, $parpost);
        my $dbcr = LJ::get_cluster_def_reader($journalu);
        return error_ml('No database connection present.  Please go back and try again.') unless $dbcr;

        $sth = $dbcr->prepare("SELECT posterid, state FROM talk2 ".
                              "WHERE journalid=? AND jtalkid=?");
        $sth->execute($journalu->{userid}, $POST->{itemid}+0);
        $parpost = $sth->fetchrow_hashref;

        $title = '.title.error' unless $need_captcha;

        my $talkform = LJ::Talk::talkform({ 'remote'      => $commenter,
                                    'journalu'    => $journalu,
                                    'parpost'     => $parpost,
                                    'replyto'     => $POST->{replyto} || $POST->{parenttalkid},
                                    'ditemid'     => $POST->{itemid},
                                    'do_captcha'  => $need_captcha,
                                    'errors'      => \@errors,
                                    'form'        => $POST });
        $vars->{title} = $title;
        $vars->{html} = $talkform;
        return DW::Template->render_template( 'talkpost_do.tt', $vars );
    }

    my ( $entryu, $parent );

    $entryu   = $entry->poster;
    $parent   = $comment->{parent};

    my $unscreen_parent = $POST->{unscreen_parent} ? 1 : 0;

    ## insertion or editing
    my $wasscreened = ($parent->{state} eq 'S');
    my $err;
    if ($editid) {
        unless (LJ::Talk::Post::edit_comment($entryu, $journalu, $comment, $parent, $entry, \$err)) {
            return error_ml($err);
        }
    } else {
        unless ( LJ::Talk::Post::post_comment( $entryu, $journalu, $comment, $parent, $entry, \$err, $unscreen_parent ) ) {
            return error_ml($err);
        }
    }

    # Yeah, we're done.
    my $dtalkid = $comment->{talkid}*256 + $entry->{anum};

    # Allow style=mine, etc for QR redirects
    my $style_args = LJ::viewing_style_args( %$POST );

    # FIXME: potentially can be replaced with some form of additional logic when we have multiple account linkage
    my $posted = $comment->{state} eq 'A' ? "posted=1" : "";

    my $cthread = $POST->{'viewing_thread'} ? "thread=$POST->{viewing_thread}" : "view=$dtalkid";
    my $commentlink = LJ::Talk::talkargs( $talkurl, $cthread, $style_args, $posted ) . LJ::Talk::comment_anchor( $dtalkid );

    my $mlcode;
    if ($comment->{state} eq 'A') {
        # Redirect the user back to their post as long as it didn't unscreen its parent,
        # is screened itself, or they logged in
        if (!($wasscreened && ($parent->{state} ne 'S')) && !$didlogin) {
            LJ::set_lastcomment($journalu->{'userid'}, $remote, $dtalkid);
            return $r->redirect($commentlink);
        }

        $mlcode = '.success.message2';
    } else {
        # otherwise, it's a screened comment.
        if ( $journalu && $journalu->is_community ) {
            if ( $POST->{'usertype'} eq 'anonymous' ) {
                $mlcode = '.success.screened.comm.anon3';
            } elsif ( $commenter && $commenter->can_manage( $journalu ) ) {
                $mlcode = '.success.screened.comm.owncomm4';
            } else {
                $mlcode = '.success.screened.comm3';
            }
        } else {  # not a community
            if ( $POST->{'usertype'} eq 'anonymous' ) {
                $mlcode = '.success.screened.user.anon3';
            } elsif ( $commenter && $commenter->equals( $journalu ) ) {
                $mlcode = '.success.screened.user.ownjournal3';
            } else {
                $mlcode = '.success.screened.user3';
            }
        }
    }
    $vars->{mlcode} = $mlcode;
    $vars->{commentlink} = $commentlink;
    $vars->{title} = $title;

    # did this comment unscreen its parent?
    $vars->{unscreened} = $wasscreened && ($parent->{state} ne 'S');
    $vars->{didlogin} = $didlogin;

    return DW::Template->render_template( 'talkpost_do.tt', $vars );
}

# Handles user auth for the talkform's "from" fields.
# Args:
# - $form: a hashref representing the POSTed comment form. It might Go Through
# Some Changes during this function (mostly affecting those "from" fields).
# - $remote: the current logged-in LJ::User, or undef, OR the just-now authenticated OpenID
# user (which is why we can't just get_remote like normal).
# - $journalu: LJ::User who owns the journal the comment was submitted to. Need
# this for storing pending comments in first pass through openid auth, and also
# we use it to switch off between variant error messages.
# - $errret: an array ref to push errors onto. Actually, should probably
# refactor this to just return an error instead; we only ever push one error,
# since any error here is fatal.
# - $didlogin: an optional scalar ref to indicate whether we started a new login
# session. Only really used for an informational thing on an interstitial page
# after commenting, which doesn't appear 100% reliably.
# Returns one of:
# - user object (authenticated user)
# - undef (anon)
# - string with URL (openid first pass)
sub authenticate_user_and_mutate_form {
    my ( $form, $remote, $journalu, $errret, $didlogin ) = @_;

    my $err = sub {
        my $error = shift;
        push @$errret, $error;
        return undef;
    };
    my $mlerr = sub {
        return $err->( LJ::Lang::ml(@_) );
    };
    my $incoherent = sub {
        return $mlerr->("/talkpost_do.tt.error.confused_identity");
    };

    # just so we only have to check this once.
    unless (ref $didlogin eq 'SCALAR') {
        my $throwaway = 0;
        $didlogin = \$throwaway;
    }

    # User stuff!
    # usertype - One of the following, with the following extra fields
        # anonymous
            # nothing
        # openid
            # oidurl
            # oiddo_login
        # openid_cookie
            # nothing, OR:
            # cookieuser (= ext_1234) (QR)
        # cookieuser (currently logged in user)
            # cookieuser (= username)
        # user (non-logged-in user, w/ name/password provided in the form)
            # userpost - The username provided in the form
            # password

    # CHECKLIST:
    # 1. Check for incoherent combinations of fields. Most of these can only
    # happen if javascript is disabled. From what I've been told, there used to
    # be rare conditions where it would straight-up post as the wrong user; who
    # knows if that's somehow still true, but regardless, if we got conflicting
    # information, then the user's intention was not clear and we need to ask
    # them to clarify, because they might have meant it either way.
    # 2. Validate the specified user type's credentials.
    # 3. If validated, return the LJ::User object for that user.
    if ( $form->{usertype} eq 'anonymous' ) {
        if ($form->{oidurl} || $form->{userpost}) {
            return $incoherent->();
        }
        return undef; # Well! that was easy.
    } elsif ( $form->{usertype} eq 'cookieuser' ) {
        if ($form->{oidurl}) {
            return $incoherent->();
        }
        # If they selected "current user" and then typed in their own username,
        # well, that's "wrong" but their intention was perfectly clear. But if
        # they typed in a DIFFERENT username, get outta here.
        if ( $form->{userpost} && ($form->{userpost} ne $form->{cookieuser}) ) {
            return $incoherent->();
        }

        # OK! Check if that's the logged-in user.
        if ( $remote && ($remote->user eq $form->{cookieuser}) ) {
            return $remote; # Cool.
        } else {
            return $mlerr->("/talkpost_do.tt.error.lostcookie");
        }
    } elsif ( $form->{usertype} eq 'user' ) {
        if ($form->{oidurl}) {
            return $incoherent->();
        }
        # No username?
        if ( ! $form->{userpost} ) {
            my $iscomm = $journalu->is_community ? '.comm' : '';
            my $noanon = $journalu->prop('opt_whocanreply') eq 'all' ? '' : '.noanon';
            return $mlerr->( "/talkpost_do.tt.error.nousername$noanon$iscomm", { sitename => $LJ::SITENAMESHORT } );
        }

        my $exptype;    # set to long if ! after username
        my $ipfixed;    # set to remote  ip if < after username

        # Parse inline login options.
        # MUTATE FORM: remove trailing garbage from username.
        if ( $form->{userpost} =~ s/([!<]{1,2})$// ) {
            $exptype = 'long' if index( $1, "!" ) >= 0;
            $ipfixed = LJ::get_remote_ip() if index( $1, "<" ) >= 0;
        }

        my $up = LJ::load_user( $form->{userpost} );

        # Now for all the things that can go wrong:
        if ( ! $up ) {
            return $mlerr->(
                "/talkpost_do.tt.error.badusername2",
                {
                    sitename => $LJ::SITENAMESHORT,
                    aopts    => "href='$LJ::SITEROOT/lostinfo'"
                }
            );
        }

        if ( $up->is_identity ) {
            return $err->("To comment as an OpenID user, you must choose the "
                . "OpenID option and authenticate with your identity provider; "
                . "it's not possible to log in using an OpenID account's "
                . "internal 'ext_12345' username."
            );
        }

        if ( $up->is_community || $up->is_syndicated ) {
            return $mlerr->("/talkpost_do.tt.error.postshared");
        }

        # authenticate on username/password
        my $ok = LJ::auth_okay( $up, $form->{password} );

        return $mlerr->(
            "/talkpost_do.tt.error.badpassword2", { aopts => "href='$LJ::SITEROOT/lostinfo'" }
        ) unless $ok;

        # GREAT, they're in!

        # if the user chooses to log in, do so
        if ( $form->{do_login} ) {
            $$didlogin = $up->make_login_session( $exptype, $ipfixed );
            # MUTATE FORM: change the usertype if they logged in, so they don't
            # have to re-type their password if they hit an unrelated error
            # (captcha whiff, etc.) and are already logged in.
            $form->{usertype} = 'cookieuser';
            $form->{cookieuser} = $up->user;
        }

        return $up;
    } elsif ( $form->{usertype} eq 'openid' || $form->{usertype} eq 'openid_cookie' ) {
        # Okay: This one's weird.
        # - If they're already logged in, $remote is set and we just let them
        # through. We don't bother to compare against $form->{cookieuser} for a
        # "lost cookie" error, because it doesn't get set consistently;
        # quick-reply includes it, but talkform doesn't.
        # - If they're not logged in, the authentication happens in two passes.
        # - On the first pass, we store the current state of the form to the
        # database, bail out, and tell the caller to redirect to the
        # authentication server by returning a string with a URL. The caller is
        # responsible for actually doing the redirect!
        # - The authentication server then kicks the user back to /talkpost_do
        # as a GET request. The Talk controller looks up and reconstructs their
        # frozen form info, and calls THIS function (or the thing that calls it)
        # a second time, passing the user who just authenticated as $remote.
        # - On the second pass, our passed-in $remote HAS to be set to the
        # openid user, even if it's a one-off comment and not a login session.
        # (This is why we're not using LJ::get_remote in this function, btw.)
        # So, openid_cookie and the second pass of openid act the same way.
        # - If they put trailing garbage on their auth URL to configure their
        # login session, we stash it in the form before freezing it, since
        # that's the only convenient way to preserve it through to the second
        # pass (where we actually set the login session).

        # So, if $remote is set, then they were already authenticated before
        # they got here, and we let them in.
        if ( $remote && defined $remote->openid_identity ) {

            # Go ahead and log in, if requested.
            if ( $form->{oiddo_login} ) {
                $$didlogin = $remote->make_login_session( $form->{exptype}, $form->{ipfixed} );
                # MUTATE FORM: change the usertype if they logged in, so
                # things look more consistent if they hit an unrelated error
                # (captcha whiff, etc.) and are already logged in.
                $form->{usertype} = 'openid_cookie';
            }

            return $remote; # welcome home
        } else {

            # If this is your first time at Tautology Club... you've never been
            # here before.

            return $err->("No OpenID identity URL entered") unless $form->{'oidurl'};

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

            # Store their cleaned up identity url vs what they
            # actually typed in.
            # MUTATE FORM: clean up oidurl
            $form->{oidurl} = $claimed_id->claimed_url();

            # Store the entry
            my $pendcid = LJ::alloc_user_counter( $journalu, "C" );

            $err->("Unable to allocate pending id") unless $pendcid;

            # persist login options in the form data, since we removed them from
            # the oidurl
            # MUTATE FORM: add junk that never appears in a real comment form.
            $form->{exptype} = $exptype;
            $form->{ipfixed} = $ipfixed;

            my $penddata = Storable::freeze($form);

            return $err->("Unable to get database handle to store pending comment")
                unless $journalu->writer;

            $journalu->do(
"INSERT INTO pendcomments (jid, pendcid, data, datesubmit) VALUES (?, ?, ?, UNIX_TIMESTAMP())",
                undef, $journalu->{'userid'}, $pendcid, $penddata
            );

            # Don't redirect them if errors
            return $err->( $journalu->errstr ) if $journalu->err;

            my $check_url = $claimed_id->check_url(
                return_to => "$LJ::SITEROOT/talkpost_do?jid=$journalu->{'userid'}&pendcid=$pendcid",
                trust_root     => "$LJ::SITEROOT",
                delayed_return => 1,
            );

            # Returning a string instead of undef or an LJ::User! Caller must
            # eventually redirect to this URL.
            return $check_url;
        }
    }
}

1;
