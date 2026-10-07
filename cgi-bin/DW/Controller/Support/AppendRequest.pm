#!/usr/bin/perl
#
# DW::Controller::Support::AppendRequest
#
# POST target behind the support reply form (/support/see_request) and the
# reopen form on /support/act. Appends a user-facing and/or internal response to
# a request and performs the requested staff actions (touch/untouch, change
# category, approve a screened response, change the summary, or bounce to email
# and close), then shows a confirmation with navigation links.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Support::AppendRequest;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::Support;

DW::Routing->register_string( '/support/append_request', \&append_handler, app => 1 );

sub append_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r     = $rv->{r};
    my $scope = '/support/append_request.tt';

    # %FORM mirrors BML's merged GET+POST hash (POST wins).
    my %FORM = ( %{ $r->get_args }, %{ $r->post_args } );

    my $status = "";

    my $spid = ( $FORM{spid} || 0 ) + 0;
    my $sp   = LJ::Support::load_request($spid);

    return error_ml("$scope.unknown.request") unless $sp;
    return error_ml("$scope.closed.text") if $sp->{state} eq "closed";

    my $remote = $rv->{remote};
    LJ::Support::init_remote($remote);

    return needlogin()
        unless LJ::Support::can_append( $sp, $remote, $FORM{auth} ) || $remote;

    my $scat   = $sp->{_cat};
    my $catkey = $scat->{catkey};

    return error_ml("$scope.invalid.noid") unless $FORM{spid};
    return error_ml('bml.requirepost') unless $r->did_post;

    $FORM{summary} = LJ::trim( $FORM{summary} );
    return error_ml("$scope.invalid.nosummary")
        if $FORM{changesum} && !$FORM{summary};

    # links to show on the confirmation page
    my $auth_arg = $FORM{auth} ? "&amp;auth=$FORM{auth}" : "";
    $rv->{successlinks} = LJ::Lang::ml(
        "$scope.successlinks2",
        {
            number => $sp->{spid},
            aopts1 => "href='$LJ::SITEROOT/support/see_request?id=$sp->{spid}$auth_arg'",
            aopts2 => "href='$LJ::SITEROOT/support/help'",
            aopts3 => "href='$LJ::SITEROOT/support/help?cat=$scat->{catkey}'",
            aopts8 => "href='$LJ::SITEROOT/support/help?cat=$scat->{catkey}&amp;state=green'",
            aopts4 => "href='$LJ::SITEROOT/support/see_request?id=$sp->{spid}&amp;find=prev'",
            aopts5 => "href='$LJ::SITEROOT/support/see_request?id=$sp->{spid}&amp;find=next'",
            aopts6 => "href='$LJ::SITEROOT/support/see_request?id=$sp->{spid}&amp;find=cprev'",
            aopts7 => "href='$LJ::SITEROOT/support/see_request?id=$sp->{spid}&amp;find=cnext'",
        }
    );

    my $faqid = ( $FORM{faqid} || 0 ) + 0;

    my %answer_types = LJ::Support::get_answer_types( $sp, $remote, $FORM{auth} );

    # we need at least one action type, and any given one must be allowed
    my $userfacing_action_type = $FORM{replytype};
    my $internal_action_type   = $FORM{internaltype};
    return error_ml("$scope.invalid.type")
        if !$userfacing_action_type && !$internal_action_type
        || $userfacing_action_type  && !defined $answer_types{$userfacing_action_type}
        || $internal_action_type    && !defined $answer_types{$internal_action_type};

    # the staff actions below all require an internal response and the matching priv
    return error_ml("$scope.internal.approve")
        if $FORM{approveans}
        && ( $internal_action_type ne "internal" || !LJ::Support::can_help( $sp, $remote ) );

    return error_ml("$scope.internal.changecat")
        if $FORM{changecat}
        && ( $internal_action_type ne "internal"
        || !LJ::Support::can_perform_actions( $sp, $remote ) );

    return error_ml("$scope.internal.touch")
        if ( $FORM{touch} || $FORM{untouch} )
        && ( $internal_action_type ne "internal"
        || !LJ::Support::can_perform_actions( $sp, $remote ) );

    return error_ml("$scope.internal.changesum")
        if $FORM{changesum}
        && ( $internal_action_type ne "internal"
        || !LJ::Support::can_change_summary( $sp, $remote ) );

    # there has to be some text or some action to take
    return error_ml("$scope.invalid.blank")
        if $FORM{reply} !~ /\S/
        && $FORM{internal} !~ /\S/
        && !$FORM{approveans}
        && !$FORM{changecat}
        && !$FORM{changesum}
        && !$FORM{touch}
        && !$FORM{untouch}
        && !$FORM{bounce_email};

    # load + validate the response being approved
    my ( $res, $splid );
    if ( $FORM{approveans} ) {
        $splid = $FORM{approveans} + 0;
        $res   = LJ::Support::load_response($splid);

        return error_ml("$scope.invalid.noanswer")
            if $res->{spid} == $spid && $res->{type} ne "screened";

        return DW::Template->render_template( 'error.tt',
            { message => 'Invalid type to approve screened response as.' } )
            if $FORM{approveas} ne 'answer' && $FORM{approveas} ne 'comment';
    }

    # load + validate the destination category for a move
    my ( $newcat, $cats );
    if ( $FORM{changecat} ) {
        $newcat = $FORM{changecat} + 0;
        $cats   = LJ::Support::load_cats($newcat);
        return error_ml("$scope.invalid.notcat") unless $cats->{$newcat};
    }

    my $dbh = LJ::get_db_writer();

    if ( $FORM{touch} ) {
        $dbh->do(
            "UPDATE support SET state='open', timetouched=UNIX_TIMESTAMP(), timeclosed=0,"
                . " timemodified=UNIX_TIMESTAMP() WHERE spid=?",
            undef, $spid
        );
        $status .= "(Inserting request into queue)\n\n";
    }
    if ( $FORM{untouch} ) {
        $dbh->do(
            "UPDATE support SET timelasthelp=UNIX_TIMESTAMP(),"
                . " timemodified=UNIX_TIMESTAMP() WHERE spid=?",
            undef, $spid
        );
        $status .= "(Removing request from queue)\n\n";
    }

    # bounce the request to one or more email addresses and close it
    if ( $internal_action_type eq 'bounce' ) {
        return error_ml("$scope.bounce.noemail") unless $FORM{bounce_email};
        return error_ml("$scope.bounce.notauth") unless LJ::Support::can_bounce( $sp, $remote );

        my @form_emails = split /\s*,\s*/, $FORM{bounce_email};
        return error_ml("$scope.bounce.toomany") if @form_emails > 5;

        my @emails;    # error-checked, good emails
        foreach my $email (@form_emails) {

            # allow a username in place of an address
            unless ( $email =~ /\@/ ) {
                my $eu = LJ::load_user($email);
                $email = $eu->email_raw if $eu;
            }

            my @email_errors;
            LJ::check_email( $email, \@email_errors, \%FORM );
            if (@email_errors) {
                @email_errors = map { "<strong>$email:</strong> $_" } @email_errors;
                return DW::Template->render_template( 'error.tt', { message => \@email_errors } );
            }

            push @emails, $email;
        }

        LJ::Support::append_request(
            $sp,
            {
                body => "(Bouncing mail to '"
                    . join( ', ', @emails )
                    . "' and closing)\n\n"
                    . $FORM{body},
                posterid => $remote,
                type     => 'internal',
                uniq     => $r->note('uniq'),
                remote   => $remote,
            }
        );

        my $message =
            $dbh->selectrow_array(
            "SELECT message FROM supportlog WHERE spid=? ORDER BY splid LIMIT 1",
            undef, $sp->{spid} );

        LJ::send_mail(
            {
                to       => join( ", ", @emails ),
                from     => $sp->{reqemail},
                fromname => $sp->{reqname},
                headers  => { 'X-Bounced-By' => $remote->{user} },
                subject  => "$sp->{subject} (support request #$sp->{spid})",
                body     => "$message\n\n$LJ::SITEROOT/support/see_request?id=$sp->{spid}",
            }
        );

        $dbh->do(
            "UPDATE support SET state='closed', timeclosed=UNIX_TIMESTAMP(),"
                . " timemodified=UNIX_TIMESTAMP() WHERE spid=?",
            undef, $sp->{spid}
        );

        $rv->{state}       = 'bounced';
        $rv->{addresslist} = "<strong>" . join( ', ', @emails ) . "</strong>";
        return DW::Template->render_template( 'support/append_request.tt', $rv );
    }

    # a poster replying reopens their own request
    $dbh->do(
        "UPDATE support SET state='open', timetouched=UNIX_TIMESTAMP(), timeclosed=0,"
            . " timemodified=UNIX_TIMESTAMP() WHERE spid=?",
        undef, $spid
    ) if LJ::Support::is_poster( $sp, $remote, $FORM{auth} );

    if ( $FORM{changecat} ) {
        $dbh->do( "UPDATE support SET spcatid=? WHERE spid=?", undef, $newcat, $spid );
        $status .= "Changing from $catkey => $cats->{$newcat}->{catkey}\n\n";
        $sp->{spcatid} = $newcat;    # so the IC e-mail goes to the right place
        LJ::Hooks::run_hook(
            "support_changecat_extra_actions",
            spid   => $spid,
            catkey => $cats->{$newcat}->{catkey}
        );
    }

    if ( $FORM{approveans} ) {
        $dbh->do( "UPDATE supportlog SET type=? WHERE splid=?", undef, $FORM{approveas}, $splid );
        $status .= "(Approving $FORM{approveas} #$splid)\n\n";
        LJ::Support::mail_response_to_user( $sp, $splid );
    }

    if ( $FORM{changesum} ) {
        ( my $summary = $FORM{summary} ) =~ s/[\n\r]//g;
        $dbh->do( "UPDATE support SET subject=? WHERE spid=?", undef, $summary, $spid );
        $status .= "Changing subject from \"$sp->{subject}\" to \"$summary\".\n\n";
    }

    # the user-facing response
    if ( $FORM{reply} ) {
        $splid = LJ::Support::append_request(
            $sp,
            {
                body   => $FORM{reply},
                type   => $userfacing_action_type,
                faqid  => $faqid,
                uniq   => $r->note('uniq'),
                remote => $remote,
            }
        );

        LJ::Support::mail_response_to_user( $sp, $splid )
            unless LJ::Support::is_poster( $sp, $remote, $FORM{auth} );
    }

    # then any internal status changes
    if ( $status || $FORM{internal} ) {
        $splid = LJ::Support::append_request(
            $sp,
            {
                body   => $status . $FORM{internal},
                type   => $internal_action_type,
                uniq   => $r->note('uniq'),
                remote => $remote,
            }
        );

        LJ::Support::mail_response_to_user( $sp, $splid )
            unless LJ::Support::is_poster( $sp, $remote, $FORM{auth} );
    }

    $rv->{state} = 'logged';
    return DW::Template->render_template( 'support/append_request.tt', $rv );
}

1;
