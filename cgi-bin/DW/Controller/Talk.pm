package DW::Controller::Talk;

use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;

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

    my @errors;
    my $skip_form_auth = 0;

    my $editid = $POST->{editid};

    # OpenID support
    # openid is a bit of hackery but we'll check to make sure they're
    # coming back from the identity server and then recreate their
    # POST hash as if they never left.  Watch and see
    if (($GET->{'openid.mode'} eq 'id_res' || $GET->{'openid.mode'} eq 'cancel') && $GET->{'jid'} && $GET->{'pendcid'}) {
        my $csr = LJ::OpenID::consumer($GET->mixed);

        if ($GET->{'openid.mode'} eq 'id_res') { # Verify their identity

            unless ( LJ::check_referer('/talkpost_do', $GET->{'openid.return_to'}) ) {
                return error_ml( '/openid/login.bml.error.invalidparameter',
                                               { item => "return_to" } );
            }

            my $errmsg;
            my $uo = LJ::User::load_from_consumer( $csr, \$errmsg );
            return error_ml( $errmsg ) unless $uo;

            $remote = $uo;
            $skip_form_auth = 1;  # wouldn't have form auth at this point
        }

        # Restore their data to reset state where they were
        my $pendcid = $GET->{'pendcid'} + 0;

        my $journalu = LJ::load_userid($GET->{'jid'});
        return error_ml("Unable to load user or get database handle") unless $journalu && $journalu->writer;

        my $pending = $journalu->selectrow_array("SELECT data FROM pendcomments WHERE jid=? AND pendcid=?",
                                                 undef, $journalu->{'userid'}, $pendcid);

        return error_ml("Unable to load pending comment, maybe you took too long") unless $pending;

        my $penddata = eval { Storable::thaw($pending) };

        $POST = $penddata;

        push @errors, "You chose to cancel your identity verification"
            if $csr->user_cancel;
    } elsif ( ! LJ::did_post() ) {
        return error_ml('/talkpost_do.tt.error.badrequest');
    }


    # as an exception, we do NOT call LJ::text_in() to check for bad
    # input, since it may be not in UTF-8 in replies coming from mail
    # clients. We call it later.

    my $journalu = LJ::load_user($POST->{journal});
    return error_ml('Unknown journal.  Please go back and try again.') unless $journalu;

    # libs for userpicselect
    LJ::Talk::init_iconbrowser_js()
        if $remote && $remote->can_use_userpic_select;


    # show this error along with the regenerated comment form down below
    push @errors, LJ::Lang::ml('error.invalidform') if $remote && ! ( $skip_form_auth || LJ::check_form_auth($POST->{lj_form_auth} ) );

    ## preview
    # ignore errors for previewing
    if ($POST->{'submitpreview'} || ($POST->{'qr'} && $POST->{'do_spellcheck'})) {
        my $cookie_auth;
        $cookie_auth = 1 if $POST->{usertype} eq "cookieuser";

        my $entry = LJ::Entry->new( $journalu, ditemid => $POST->{itemid} + 0 );
        my $talkurl = $entry->url;

        $title = '.title.preview';
        return LJ::Talk::Post::make_preview($talkurl, $cookie_auth, $POST);
    }

    ## init.  this handles all the error-checking, as well.
    my $need_captcha = 0;
    my $init = LJ::Talk::Post::init($POST, $remote, \$need_captcha, \@errors);
    # Report errors in a friendly manner by regenerating the field.
    # Required for challenge/response login, since we also need to regenerate an auth token.
    # We repopulate what we can via hidden fields - however the objects (journalu & parpost) must be recreated here.
    unless ( $init ) {
        my ($sth, $parpost);
        my $dbcr = LJ::get_cluster_def_reader($journalu);
        return error_ml('No database connection present.  Please go back and try again.') unless $dbcr;

        $sth = $dbcr->prepare("SELECT posterid, state FROM talk2 ".
                              "WHERE journalid=? AND jtalkid=?");
        $sth->execute($journalu->{userid}, $POST->{itemid}+0);
        $parpost = $sth->fetchrow_hashref;

        $title = '.title.error' unless $need_captcha;

        $POST->{edit} = $POST->{editid}; # talkform expects the editid to be in "edit"
        my $talkform = LJ::Talk::talkform({ 'remote'      => $remote,
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

    if (defined $init->{check_url}) {
        return $r->redirect($init->{check_url});
    }

    my ( $talkurl, $entryu, $parent, $comment, $item );

    $talkurl = $init->{talkurl};
    $entryu   = $init->{entryu};
    $journalu = $init->{journalu};
    $parent   = $init->{parent};
    $comment  = $init->{comment};
    $item     = $init->{item};

    my $unscreen_parent = $POST->{unscreen_parent} ? 1 : 0;

    # check max comments only if posting a new comment (not when editing)
    unless ($editid) {
        return error_ml('.error.maxcomments')
            if LJ::Talk::Post::over_maxcomments($journalu, $item->{'jitemid'});
    }

    # no replying to frozen comments
    return error_ml('/talkpost.bml.error.noreply_frozen')
        if $parent->{state} eq 'F';

    # no replying to suspended entries, even by entry poster
    my $entry = LJ::Entry->new($journalu, jitemid => $item->{jitemid});
    return error_ml('/talkpost.bml.error.noreply_suspended')
        if $entry && $entry->is_suspended;

    # no replying to entries/comments in an entry where the remote user or journal are read-only
    return error_ml('/talkpost.bml.error.noreply_readonly_remote')
        if $remote && $remote->is_readonly;
    return error_ml('/talkpost.bml.error.noreply_readonly_journal')
        if $journalu && $journalu->is_readonly;

    # is the current user banned by the author of the original post?
    return error_ml( '.error.banned.entryowner' )
        if defined $remote && $entryu->has_banned( $remote );

    # Don't allow user A to reply to a comment by user B if user B has banned user A.
    # We check whether $remote is defined because it won't be if we aren't logged in.
    # We check if $parentu is defined because it won't be if the parent is an anonymous comment.
    if ( defined $remote ) {
        my $parentu = LJ::load_userid( $parent->{posterid} );
        return error_ml('.error.banned.reply')
            if defined $parentu && $parentu->has_banned( $remote );
    }

    ## insertion or editing
    my $wasscreened = ($parent->{state} eq 'S');
    my $err;
    if ($editid) {
        unless (LJ::Talk::Post::edit_comment($entryu, $journalu, $comment, $parent, $item, \$err)) {
            return error_ml($err);
        }
    } else {
        unless ( LJ::Talk::Post::post_comment( $entryu, $journalu, $comment, $parent, $item, \$err, $unscreen_parent ) ) {
            return error_ml($err);
        }
    }

    # Yeah, we're done.
    my $dtalkid = $comment->{talkid}*256 + $item->{anum};

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
        if (!($wasscreened and $parent->{state} ne 'S') && !$init->{didlogin}) {
            LJ::set_lastcomment($journalu->{'userid'}, $remote, $dtalkid);
            return $r->redirect($commentlink);
        }

        $mlcode = '.success.message2';
    } else {
        # otherwise, it's a screened comment.
        my $commentu = $init ? $init->{comment}->{u} : undef;
        if ( $journalu && $journalu->is_community ) {
            if ( $POST->{'usertype'} eq 'anonymous' ) {
                $mlcode = '.success.screened.comm.anon3';
            } elsif ( $commentu && $commentu->can_manage( $journalu ) ) {
                $mlcode = '.success.screened.comm.owncomm4';
            } else {
                $mlcode = '.success.screened.comm3';
            }
        } else {  # not a community
            if ( $POST->{'usertype'} eq 'anonymous' ) {
                $mlcode = '.success.screened.user.anon3';
            } elsif ( $commentu && $commentu->equals( $journalu ) ) {
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
    $vars->{unscreened} = $wasscreened and $parent->{state} ne 'S';
    $vars->{didlogin} = $init->{didlogin};

    return DW::Template->render_template( 'talkpost_do.tt', $vars );
}


1;
