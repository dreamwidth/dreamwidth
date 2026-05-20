#!/usr/bin/perl
#
# DW::Task::SupportNotify
#
# SQS worker for sending support request notification emails.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::SupportNotify;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::Faq;
use LJ::Lang;
use LJ::Support;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $a = $self->args->[0];

    # load basic stuff common to both paths
    my $type      = $a->{type};
    my $spid      = $a->{spid} + 0;
    my $load_body = $type eq 'new' ? 1 : 0;
    my $sp = LJ::Support::load_request( $spid, $load_body, { force => 1 } );    # force from master

    # we're only going to be reading anyway, but these jobs
    # sometimes get processed faster than replication allows,
    # causing the message not to load from the reader
    my $dbr = LJ::get_db_writer();

    # now branch a bit to select the right user information
    my $level = $type eq 'new' ? "'new', 'all'" : "'all'";
    my $data  = $dbr->selectcol_arrayref(
        "SELECT userid FROM supportnotify WHERE spcatid=? AND level IN ($level)",
        undef, $sp->{_cat}{spcatid} );
    my $userids = LJ::load_userids(@$data);

    # prepare the email
    my $body;
    my @emails;

    if ( $type eq 'new' ) {
        my $show_name = $sp->{reqname};
        if ( $sp->{reqtype} eq 'user' ) {
            my $u = LJ::load_userid( $sp->{requserid} );
            $show_name = $u->display_name if $u;
        }

        $body = LJ::Lang::ml(
            "support.email.notif.new.body2",
            {
                sitename => $LJ::SITENAMESHORT,
                category => $sp->{_cat}{catname},
                subject  => $sp->{subject},
                username => LJ::trim($show_name),
                url      => "$LJ::SITEROOT/support/see_request?id=$spid",
                text     => $sp->{body}
            }
        );
        $body .= "\n\n" . "=" x 4 . "\n\n";
        $body .= LJ::Lang::ml(
            "support.email.notif.new.footer",
            {
                url     => "$LJ::SITEROOT/support/see_request?id=$spid",
                setting => "$LJ::SITEROOT/support/changenotify"
            }
        );

        foreach my $u ( values %$userids ) {
            next unless $u->should_receive_support_notifications( $sp->{_cat}{spcatid} );
            push @emails, $u->email_raw;
        }

    }
    elsif ( $type eq 'update' ) {

        # load the response we want to stuff in the email
        my ( $resp, $rtype, $posterid, $faqid ) =
            $dbr->selectrow_array(
            "SELECT message, type, userid, faqid FROM supportlog WHERE spid = ? AND splid = ?",
            undef, $sp->{spid}, $a->{splid} + 0 );

        # set up $show_name for this environment
        my $show_name;
        if ($posterid) {
            my $u = LJ::load_userid($posterid);
            $show_name = $u->display_name if $u;
        }

        $show_name ||= $sp->{reqname};

        # set up $response_type for this environment
        my $response_type = {
            req      => "New Request",        # not applicable here
            answer   => "Answer",
            comment  => "Comment",
            internal => "Internal Comment",
            screened => "Screened Answer",
        }->{$rtype};

        # build body
        $body = LJ::Lang::ml(
            "support.email.notif.update.body4",
            {
                sitename => $LJ::SITENAMESHORT,
                category => $sp->{_cat}{catname},
                subject  => $sp->{subject},
                username => LJ::trim($show_name),
                url      => "$LJ::SITEROOT/support/see_request?id=$spid",
                type     => $response_type
            }
        );
        if ($faqid) {

            # need to set up $lang
            my ( $lang, $u );
            $u    = LJ::load_userid($posterid) if $posterid;
            $lang = LJ::Support::prop( $spid, 'language' )
                if LJ::is_enabled('support_request_language');
            $lang ||= $LJ::DEFAULT_LANG;

            # now actually get the FAQ
            my $faq = LJ::Faq->load( $faqid, lang => $lang );
            if ($faq) {
                $faq->render_in_place;
                my $faqref = $faq->question_raw . " " . $faq->url_full;

                # now add it to the e-mail!
                $body .= "\n"
                    . LJ::Lang::ml(
                    "support.email.notif.update.body.faqref",
                    {
                        faqref => $faqref
                    }
                    );
                $body .= "\n";
            }
        }
        $body .= LJ::Lang::ml(
            "support.email.notif.update.body.text",
            {
                text => $resp
            }
        );
        $body .= "\n\n" . "=" x 4 . "\n\n";
        $body .= LJ::Lang::ml(
            "support.email.notif.update.footer",
            {
                url     => "$LJ::SITEROOT/support/see_request?id=$spid",
                setting => "$LJ::SITEROOT/support/changenotify"
            }
        );

        # now see who this should be sent to
        foreach my $u ( values %$userids ) {
            next unless $u->should_receive_support_notifications( $sp->{_cat}{spcatid} );
            next unless LJ::Support::can_read_response( $sp, $u, $rtype, $posterid );
            next if $posterid == $u->id && !$u->prop('opt_getselfsupport');
            push @emails, $u->email_raw;
        }
    }

    # send the email
    LJ::send_mail(
        {
            bcc      => join( ', ', @emails ),
            from     => $LJ::BOGUS_EMAIL,
            fromname => LJ::Lang::ml( "support.email.fromname", { sitename => $LJ::SITENAME } ),
            charset  => 'utf-8',
            subject  => (
                $type eq 'update'
                ? LJ::Lang::ml( "support.email.notif.update.subject", { number => $spid } )
                : LJ::Lang::ml( "support.email.subject",              { number => $spid } )
            ),
            body => $body,
            wrap => 1,
        }
    ) if @emails;

    return DW::Task::COMPLETED;
}

1;
