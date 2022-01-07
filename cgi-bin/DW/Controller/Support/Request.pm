#!/usr/bin/perl
#
# DW::Controller::Support::Request
#
# This controller is for the Support Request submission page.
#
# Authors:
#      Ruth Hatch <ruth.s.hatch@gmail.com>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This is based on code originally implemented on LiveJournal.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Support::Request;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/support/see_request', \&see_request_handler, app => 1 );

sub see_request_handler {
    my $r = DW::Request->get;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $scope = '/support/see_request.tt';
    my $dbr   = LJ::get_db_reader();

    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $vars   = {};

    my $spid  = $GET->{'id'} ? $GET->{'id'} + 0 : 0;
    my $sp    = LJ::Support::load_request($spid);
    my $props = LJ::Support::load_props($spid);
    my $cats  = LJ::Support::load_cats();
    LJ::Support::init_remote($remote);
    $vars->{remote} = $remote;
    $vars->{sp}     = $sp;
    $vars->{spid}   = $spid;
    $vars->{uniq}   = $props->{'uniq'};

    if ( $GET->{'find'} ) {
        my $find = $GET->{'find'};
        my $op   = '<';
        my $sort = 'DESC';
        if ( $find eq 'next' || $find eq 'cnext' || $find eq 'first' ) {
            $op   = '>';
            $sort = 'ASC';
        }
        my $spcatand = '';
        if ( $sp && ( $find eq 'cnext' || $find eq 'cprev' ) ) {
            my $spcatid = $sp->{_cat}->{'spcatid'} + 0;
            $spcatand = "AND spcatid=$spcatid";
        }
        else {
            my @filter_cats = LJ::Support::filter_cats( $remote, $cats );
            return error_ml("$scope.error.text1") unless @filter_cats;
            my $cats_in = join( ",", map { $_->{'spcatid'} } @filter_cats );
            $spcatand = "AND spcatid IN ($cats_in)";
        }
        my $clause = "";
        $clause = "AND spid$op$spid" unless ( $find eq 'first' || $find eq 'last' );
        my ($foundspid) =
            $dbr->selectrow_array( "SELECT spid FROM support WHERE state='open' "
                . "$spcatand $clause ORDER BY spid $sort LIMIT 1" );

        if ($foundspid) {
            return $r->redirect("see_request?id=$foundspid");
        }
        else {
            my $extra = $find eq "cnext" || $find eq "cprev" ? "_cat" : "";
            my $text =
                $find eq 'next' || $find eq 'cnext'
                ? LJ::Lang::ml( "$scope.error.nonext" . $extra )
                : LJ::Lang::ml( "$scope.error.noprev" . $extra );
            my $goback =
                $sp
                ? LJ::Lang::ml( "$scope.goback.text",
                { request_link => "href='see_request?id=$spid'", spid => $spid } )
                : '';
            return DW::Template->render_template( 'error.tt', { message => "$text$goback" } );
        }

        $vars->{find} = 1;
    }

    return error_ml("$scope.unknownumber") unless $sp;

    my $sth;
    my $user;
    my $user_url;
    my $auth = $GET->{'auth'};

    my $email = $sp->{'reqemail'};

    # Get remote username and journal URL, or example user's username and journal URL
    if ($remote) {
        $user     = $remote->user;
        $user_url = $remote->journal_base;
    }
    else {
        my $exampleu = LJ::load_user($LJ::EXAMPLE_USER_ACCOUNT);
        $user =
              $exampleu
            ? $exampleu->user
            : "<b>[Unknown or undefined example username]</b>";
        $user_url =
              $exampleu
            ? $exampleu->journal_base
            : "<b>[Unknown or undefined example username]</b>";
    }

    my $u;
    my $clusterdown = 0;
    if ( $sp->{'reqtype'} eq "user" && $sp->{'requserid'} ) {
        $u = LJ::load_userid( $sp->{'requserid'} );
        unless ($u) {
            warn "Error: user '$sp->{requserid}' not found in request #$spid";
            return DW::Template->render_template( 'error.tt', { message => "Unknown user" } );
        }

        # now do a check for a down cluster?
        $clusterdown = 1 unless LJ::get_cluster_reader($u);

        $email = $u->email_raw if $u->email_raw;
        $u->preload_props( "stylesys", "s2_style", "schemepref" )
            unless $clusterdown;
        $vars->{u}           = $u;
        $vars->{clusterdown} = $clusterdown;
    }

    my $winner;    # who closed it?
    if ( $sp->{'state'} eq "closed" ) {
        $sth = $dbr->prepare( "SELECT u.user, sp.points FROM useridmap u, supportpoints sp "
                . "WHERE u.userid=sp.userid AND sp.spid=?" );
        $sth->execute($spid);
        $winner = $sth->fetchrow_hashref;
    }

    # get all replies
    my @replies;
    $sth = $dbr->prepare(
"SELECT splid, timelogged, UNIX_TIMESTAMP()-timelogged AS 'age', type, faqid, userid, message "
            . "FROM supportlog WHERE spid=? ORDER BY timelogged" );
    $sth->execute($spid);
    while ( my $le = $sth->fetchrow_hashref ) {
        push @replies, $le;
    }

    # load category this request is in
    $vars->{problemarea} = $sp->{_cat}->{'catname'};
    $vars->{catkey}      = $sp->{_cat}->{'catkey'};

    unless ( LJ::Support::can_read( $sp, $remote, $auth ) ) {
        return error_ml("$scope.nothaveprivilege");
    }

    # helper variables for commonly called methods
    my $can_close = LJ::Support::can_close( $sp, $remote, $auth ) ? 1 : 0;
    my $can_reopen = LJ::Support::can_reopen( $sp, $remote, $auth ) ? 1 : 0;
    my $helper_mode = LJ::Support::can_help( $sp, $remote ) ? 1 : 0;
    my $stock_mode = LJ::Support::can_see_stocks( $sp, $remote ) ? 1 : 0;
    my $is_poster = LJ::Support::is_poster( $sp, $remote, $auth ) ? 1 : 0;

    $vars->{can_close}   = $can_close;
    $vars->{can_reopen}  = $can_reopen;
    $vars->{helper_mode} = $helper_mode;
    $vars->{stock_mode}  = $stock_mode;
    $vars->{is_poster}   = $is_poster;

    # fix up the subject if needed
    eval {
        if ( $sp->{'subject'} =~ /^=\?(utf-8)?/i ) {
            my @subj_data;
            require MIME::Words;
            @subj_data = MIME::Words::decode_mimewords( $sp->{'subject'} );
            if ( scalar(@subj_data) ) {
                if ( !$1 ) {
                    $sp->{'subject'} = Unicode::MapUTF8::to_utf8(
                        { -string => $subj_data[0][0], -charset => $subj_data[0][1] } );
                }
                else {
                    $sp->{'subject'} = $subj_data[0][0];
                }
            }
        }
    };

    if ( $u->{'defaultpicid'} && !$u->is_suspended ) {
        my $userpic_obj = $u->userpic;
        my $user_img    = '';
        $user_img .= "<a href='" . $u->allpics_base . "'>";
        $user_img .= $userpic_obj->imgtag;
        $user_img .= "</a>";
        $vars->{user_img} = $user_img;
    }

    my $display_name;

    # show requester name + email
    {
        my $visemail = $email;
        $visemail =~ s/^.+\@/********\@/;

        my $ename = $sp->{'reqtype'} eq 'user' ? LJ::ljuser($u) : LJ::ehtml( $sp->{reqname} );

        # we show links to the history page if the user is a helper since
        # helpers can always find this information anyway just by taking
        # more steps.  Show email history link if they have finduser and
        # thus once again could get this information anyway.
        my $has_sh = $remote && $remote->has_priv('supporthelp');
        my $has_fu = $remote && $remote->has_priv('finduser');
        my $has_vs = $remote && $remote->has_priv('supportviewscreened');

        my %show_history = (
            user  => $has_sh,
            email => ( $has_fu || ( $has_sh && !$sp->{_cat}->{public_read} ) ),
        );

        if ( $show_history{user} || $show_history{email} ) {
            $display_name =
                $sp->{reqtype} eq 'user' && $show_history{user}
                ? "$ename <a href=\"history?user=$u->{user}\">" . LJ::ehtml( $u->{name} ) . "</a>"
                : "$ename";

            my $email_string = $has_vs || $has_sh ? " ($visemail)" : "";
            $email_string = " (<a href=\"history?email=" . LJ::eurl($email) . "\">$email</a>)"
                if $show_history{email};
            $display_name .= $email_string;
        }
        else {
            # default view
            $display_name = $ename;
            $display_name .= " ($visemail)" if $has_vs || $has_sh;
        }
    }
    $vars->{display_name} = $display_name;
    $vars->{accounttype}  = LJ::Capabilities::name_caps( $u->{caps} )
        || "<i>" . LJ::Lang::ml("$scope.unknown") . "</i>";

    my $ustyle = '';
    if ( $u->{'stylesys'} == 2 ) {
        $ustyle .= "(S2) ";
        if ( $u->{'s2_style'} ) {
            my $s2style = LJ::S2::load_style( $u->{'s2_style'} );
            my $pub     = LJ::S2::get_public_layers();              # cached
            foreach my $lay ( sort { $a cmp $b } keys %{ $s2style->{'layer'} } ) {
                my $lid = $s2style->{'layer'}->{$lay};
                unless ($lid) {
                    next if $lay eq 'i18n';     # do we even support style langcodes?
                    next if $lay eq 'i18nc';    # do we even support style langcodes?
                    $ustyle .= "$lay: none, ";
                    next;
                }
                $ustyle .= "$lay: <a href='$LJ::SITEROOT/customize/advanced/layerbrowse?id=$lid'>";
                $ustyle .= ( defined $pub->{$lid} ? 'public' : 'custom' ) . "</a>, ";
            }
        }
        else {
            $ustyle .= LJ::Lang::ml("$scope.none");
        }
    }
    else {
        $ustyle .= "(User on S1; why?) ";
    }
    $ustyle =~ s/,\s*$//;
    $vars->{ustyle} = $ustyle;

    # if the user has siteadmin:users or siteadmin:* show them link to resend validation email?
    my $extraval = sub {
        return '' unless $remote && $remote->has_priv( 'siteadmin', 'users' );
        return
            " (<a href='$LJ::SITEROOT/register?foruser=$u->{user}'>"
            . LJ::Lang::ml("$scope.resend.validation.email") . "</a>)";
    };

    my $email_status;

    if ( $u->{'status'} eq "A" ) {
        $email_status = "<b>" . LJ::Lang::ml("$scope.yes") . "</b>";
    }
    if ( $u->{'status'} eq "N" ) {
        $email_status = "<b>" . LJ::Lang::ml("$scope.no") . "</b>" . $extraval->();
    }
    if ( $u->{'status'} eq "T" ) {
        $email_status = LJ::Lang::ml("$scope.transitioning") . $extraval->();
    }

    $vars->{email_status} = $email_status;

    $vars->{cluster_info} = LJ::DB::get_cluster_description( $u->{clusterid} ) if $u->{clusterid};

    if ( LJ::isu($u) && $u->is_personal ) {

        # only personal accounts can upload images
        my $media_usage = DW::Media->get_usage_for_user($u);
        my $media_quota = DW::Media->get_quota_for_user($u);
        my $megabytes   = sprintf( "%0.3f MB", $media_usage / 1024 / 1024 );
        my $percentage =
            ( $media_quota != 0 )
            ? sprintf( "%0.1f%%", $media_usage / $media_quota * 100 )
            : LJ::Lang::ml("$scope.noquota");

        $vars->{media_usage} = "$megabytes ($percentage)";
    }
    $vars->{view_history} = $remote && $remote->has_priv('historyview');
    $vars->{view_userlog} = $remote && $remote->has_priv( 'canview', 'userlog' );

    if ( %LJ::BETA_FEATURES
        && LJ::Support::has_any_support_priv($remote) )
    {

        $vars->{show_beta} = 1;
        $vars->{betafeatures} =
            LJ::isu($u)
            ? join( ", ", $u->prop( LJ::BetaFeatures->prop_name ) ) // ''
            : '';
    }

    $vars->{show_cat_links} = LJ::Support::can_read_cat( $sp->{_cat}, $remote );

    $vars->{timecreate} = LJ::time_to_http( $sp->{timecreate} );
    $vars->{age}        = LJ::diff_ago_text( $sp->{timecreate} );

    my $state = $sp->{'state'};
    if ( $state eq "open" ) {

        # check if it's still open or needing help or what
        if ( $sp->{'timelasthelp'} > ( $sp->{'timetouched'} + 5 ) ) {

            # open, answered
            $state = LJ::Lang::ml("$scope.answered");
        }
        elsif ( $sp->{'timelasthelp'} && $sp->{'timetouched'} > $sp->{'timelasthelp'} + 5 ) {

            # open, still needs help
            $state = LJ::Lang::ml("$scope.answered.need.help");
        }
        else {
            # default
            $state =
                "<b><span style='color: #ff0000;'>" . LJ::Lang::ml("$scope.open") . "</span></b>";
        }
    }
    if ( $state eq "closed" && $winner && LJ::Support::can_see_helper( $sp, $remote ) ) {
        my $s     = $winner->{'points'} > 1 ? "s" : "";
        my $wuser = $winner->{'user'};
        $state .= " (<b>$winner->{'points'}</b> point$s to ";
        $state .= LJ::ljuser( $wuser, { 'full' => 1 } ) . ")";
    }
    if ( $can_close || $can_reopen ) {
        if ( $sp->{'state'} eq "open" && $can_close ) {
            $state .=
                  ", <a href='act?close;$sp->{'spid'};$sp->{'authcode'}'><b>"
                . LJ::Lang::ml("$scope.close.without.credit")
                . "</b></a>";
        }
        elsif ( $sp->{state} eq 'closed' ) {
            my $permastatus = LJ::Support::is_locked($sp);
            $state .=
                $sp->{'state'} eq "closed" && !$permastatus
                ? ", <a href='act?touch;$sp->{'spid'};$sp->{'authcode'}'><b>"
                . LJ::Lang::ml("$scope.reopen.this.request")
                . "</b></a>"
                : "";
            if ( LJ::Support::can_lock( $sp, $remote ) ) {
                $state .=
                    $permastatus
                    ? ", <a href='act?unlock;$sp->{spid};$sp->{authcode}'><b>"
                    . LJ::Lang::ml("$scope.unlock.request")
                    . "</b></a>"
                    : ", <a href='act?lock;$sp->{spid};$sp->{authcode}'><b>"
                    . LJ::Lang::ml("$scope.lock.request")
                    . "</b></a>";
            }
        }
    }
    $vars->{state} = $state;

    $vars->{private_req} = ( !$sp->{_cat}->{public_read} && $is_poster ) ? 1 : 0;

    my @screened;
    my @cleaned_replies;
    my $curlang = LJ::Lang::get_effective_lang();

    ### reply loop
    foreach my $le (@replies) {
        my $reply        = {};
        my $up           = LJ::load_userid( $le->{userid} );
        my $remote_is_up = $remote && $remote->equals($up);

        next
            if $le->{type} eq "internal"
            && !( LJ::Support::can_read_internal( $sp, $remote ) || $remote_is_up );
        next
            if $le->{type} eq "screened"
            && !( LJ::Support::can_read_screened( $sp, $remote ) || $remote_is_up );
        next if $le->{type} eq "screened" && $up && !$up->is_visible;

        push @screened, $le if $le->{type} eq "screened";

        my $message = $le->{message};
        my %url;
        my $urlN = 0;

        $message = LJ::trim( LJ::ehtml($message) );
        $message =~ s/\n( +)/"\n" . "&nbsp;&nbsp;" x length($1) /eg;
        $message = LJ::html_newlines($message);
        $message = LJ::auto_linkify($message);

        # special case: original request
        if ( $le->{'type'} eq "req" ) {

            # insert support diagnostics from props
            if ( $props->{useragent} ) {
                $message .= sprintf(
                    "<hr><strong>%s</strong> %s",
                    LJ::Lang::ml("$scope.diagnostics"),
                    LJ::ehtml( $props->{useragent} )
                );
            }

            $reply->{msg}  = $message;
            $reply->{orig} = 1;
            push @cleaned_replies, $reply;
            next;
        }

        $reply->{msg}  = $message;
        $reply->{id}   = $le->{splid};
        $reply->{type} = $le->{type};

        # reply header
        my $header = "";
        $reply->{show_helper} = LJ::Support::can_see_helper( $sp, $remote );
        if ( $up && $reply->{show_helper} ) {
            my $picid = $up->get_picid_from_keyword('_support') || $up->{defaultpicid};
            my $icon  = $picid ? LJ::Userpic->new( $up, $picid ) : undef;
            $reply->{poster} = $up;
            $reply->{icon}   = $icon;
        }

        my $what = '.answer';
        if    ( $le->{'type'} eq "internal" ) { $what = '.internal.comment'; }
        elsif ( $le->{'type'} eq "comment" )  { $what = ".comment"; }
        elsif ( $le->{'type'} eq "screened" ) { $what = '.screened.response'; }
        $reply->{type_title} = $what;

        $reply->{timehelped} = LJ::time_to_http( $le->{'timelogged'} );
        $reply->{age}        = LJ::ago_text( $le->{'age'} );

        if ( $can_close && $sp->{'state'} eq "open" && $le->{'type'} eq "answer" ) {
            $reply->{show_close} = 1;
        }
        if ( $helper_mode && $le->{type} eq "screened" ) {
            $reply->{show_approve} = 1;
        }

        my $bordercolor = "default";
        if ( $le->{'type'} eq "internal" ) { $bordercolor = "internal"; }
        if ( $le->{'type'} eq "answer" )   { $bordercolor = "answer"; }
        if ( $le->{'type'} eq "screened" ) { $bordercolor = "screened"; }
        $reply->{bordercolor} = $bordercolor;

        if ( $le->{faqid} ) {
            $reply->{faqid} = $le->{faqid};

            my $faq = LJ::Faq->load( $le->{faqid}, lang => $curlang );
            $faq->render_in_place;
            $reply->{faq} = $faq;
        }
        push @cleaned_replies, $reply;
    }
    $vars->{replies} = \@cleaned_replies;

    my @ans_type = LJ::Support::get_answer_types( $sp, $remote, $auth );
    my %ans_type = @ans_type;
    $vars->{can_append} = LJ::Support::can_append( $sp, $remote, $auth );
    $vars->{show_note}  = !LJ::Support::can_read_internal( $sp, $remote )
        && ( $ans_type{'answer'} || $ans_type{'screened'} );

    # FAQ reference
    my @faqlist;
    if ( $ans_type{'answer'} || $ans_type{'screened'} ) {
        my %faqcat;
        my %faqq;

        # FIXME: must refactor that somewhere
        my $deflang = BML::get_language_default();
        my $mll     = LJ::Lang::get_lang($curlang);
        my $mld     = LJ::Lang::get_dom("faq");
        my $altlang = $deflang ne $curlang;
        $altlang = 0 unless $mld and $mll;
        if ($altlang) {
            my $sql = qq{SELECT fc.faqcat, t.text as faqcatname, fc.catorder
                         FROM faqcat fc, ml_text t, ml_latest l, ml_items i
                         WHERE t.dmid=$mld->{'dmid'} AND l.dmid=$mld->{'dmid'}
                             AND i.dmid=$mld->{'dmid'} AND l.lnid=$mll->{'lnid'}
                             AND l.itid=i.itid
                             AND i.itcode=CONCAT('cat.', fc.faqcat)
                             AND l.txtid=t.txtid AND fc.faqcat<>'int-abuse'};
            $sth = $dbr->prepare($sql);
        }
        else {
            $sth = $dbr->prepare(
                "SELECT faqcat, faqcatname, catorder FROM faqcat WHERE faqcat<>'int-abuse'");
        }
        $sth->execute;
        while ( $_ = $sth->fetchrow_hashref ) {
            $faqcat{ $_->{'faqcat'} } = $_;
        }

        foreach my $f ( LJ::Faq->load_all( lang => $curlang ) ) {
            $f->render_in_place( { user => $user, url => $user_url } );
            push @{ $faqq{ $f->faqcat } ||= [] }, $f;
        }

        @faqlist = ( '0', "(don't reference FAQ)" );
        foreach my $faqcat (
            sort { $faqcat{$a}->{'catorder'} <=> $faqcat{$b}->{'catorder'} }
            keys %faqcat
            )
        {
            push @faqlist, ( '0', "[ $faqcat{$faqcat}->{'faqcatname'} ]" );
            foreach my $faq ( sort { $a->sortorder <=> $b->sortorder } @{ $faqq{$faqcat} || [] } ) {
                my $q = $faq->question_raw;
                next unless $q;
                $q = "... $q";
                $q =~ s/^\s+//;
                $q =~ s/\s+$//;
                $q =~ s/\n/ /g;
                $q = substr( $q, 0, 75 ) . "..." if length($q) > 75;
                push @faqlist, ( $faq->faqid, $q );
            }
        }
        $vars->{faqlist} = \@faqlist;
    }

    # Prefill an e-mail validation reminder, if needed.
    if (   ( $u->{status} eq "N" || $u->{status} eq "T" )
        && !$u->is_identity
        && !$is_poster )
    {
        my $reminder = LJ::load_include('validationreminder');
        $vars->{reminder} = "\n\n$reminder" if $reminder;
    }

    # add in canned answers if there are any for this category and the user can use them
    my $stocks_html = "";
    if ( $stock_mode && !$is_poster ) {

        # if one category's stock answers exactly matches another's
        my $stock_spcatid =
            $LJ::SUPPORT_STOCKS_OVERRIDE{ $sp->{_cat}->{catkey} } || $sp->{_cat}->{spcatid};
        my $rows = $dbr->selectall_arrayref(
            'SELECT subject, body FROM support_answers WHERE spcatid = ? ORDER BY subject',
            undef, $stock_spcatid );

        if ( $rows && @$rows ) {
            $stocks_html .= "<script type='text/javascript'>\n";
            $stocks_html .= "var canned = new Array();\n";
            my $i = 0;
            foreach my $row (@$rows) {
                $stocks_html .= "canned[$i] = '" . LJ::ejs( $row->[1] ) . "';\n";
                $i++;
            }
            $stocks_html .= "</script>\n";

            $stocks_html .=
"<label for='canned'><a href='$LJ::SITEROOT/support/stock_answers?spcatid=$stock_spcatid'>Stock Answers</a>:</label><select id='canned'>\n";
            $stocks_html .=
                  "<option value='-1' selected>( "
                . LJ::Lang::ml("$scope.select.canned.to.insert")
                . " )</option>\n";
            $i = 0;
            foreach my $row (@$rows) {
                $stocks_html .= "<option value='$i'>" . LJ::ehtml( $row->[0] ) . "</option>\n";
                $i++;
            }
            $stocks_html .= "</select>\n";
        }
    }
    $vars->{stock_answers} = $stocks_html;

    my $can_move_touch = LJ::Support::can_perform_actions( $sp, $remote ) && !$is_poster;
    $vars->{can_move_touch} = $can_move_touch;
    $vars->{catlist}        = [
        ( '', $sp->{'_cat'}->{'catname'} ),

        map { $_->{'spcatid'}, "---> $_->{'catname'}" } LJ::Support::sorted_cats($cats)
    ];
    $vars->{screenedlist} = [
        ( '', '' ),

        map { $_->{'splid'}, "\#$_->{'splid'} (" . LJ::get_username( $_->{'userid'} ) . ")" }
            @screened
    ];

    $vars->{userfacing_actions_list} =
        [ map { $ans_type{$_} ? ( $_ => $ans_type{$_} ) : () } qw(screened answer comment) ];
    $vars->{internal_actions_list} =
        [ map { $ans_type{$_} ? ( $_ => $ans_type{$_} ) : () } qw(internal bounce) ];
    $vars->{approve_actions_list} = [ "answer" => "as answer", "comment" => "as comment" ];
    $vars->{can}                  = {
        do_internal_actions => LJ::Support::can_make_internal( $sp, $remote ) && !$is_poster,

        use_stock_answers => 1,                        #$stock_mode && ! $is_poster && $stocks_html,
        approve_answers   => @screened && $helper_mode,

        change_category   => $can_move_touch,
        put_in_queue      => $can_move_touch && $sp->{timelasthelp} > ( $sp->{timetouched} + 5 ),
        take_out_of_queue => $can_move_touch && $sp->{timelasthelp} <= ( $sp->{timetouched} + 5 ),

        change_summary => LJ::Support::can_change_summary( $sp, $remote ),
    };

    return DW::Template->render_template( 'support/see_request.tt', $vars );

}

1;
