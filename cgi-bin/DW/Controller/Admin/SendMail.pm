#!/usr/bin/perl
#
# DW::Controller::SendMail
#
# Admin page for sending emails from site accounts.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2012-2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Admin::SendMail;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::Controller::Admin;
use DW::FormErrors;

my @privs = qw(siteadmin:sendmail);

DW::Controller::Admin->register_admin_page( '/',
    path => 'sendmail/',
    ml_scope => '/admin/sendmail/index.tt',
    privs => \@privs,
);

DW::Routing->register_string( "/admin/sendmail/index", \&index_controller );
#add these later
#DW::Routing->register_string( "/admin/sendmail/lookup", \&lookup_controller );
#DW::Routing->register_string( "/admin/sendmail/forms", \&form_controller );

sub index_controller {
    my ( $ok, $rv ) = controller( privcheck => \@privs, form_auth => 1 );
    return $rv unless $ok;
    my $remote = $rv->{remote};

    my $scope = sub { return '/admin/sendmail/index.tt' . $_[0] };

    my $r = DW::Request->get;
    my $errors = DW::FormErrors->new;

    # form processing
    if ( $r->did_post ) {
        my $args = $r->post_args;

        my $account     = LJ::trim( $args->{account} );
        my $sendto      = LJ::trim( $args->{sendto}  );
        my $message     = LJ::trim( $args->{message} );
        my $subject     = LJ::trim( $args->{subject} );
        my $support_req = LJ::trim( $args->{request} );
        my $teamnotes   = LJ::trim( $args->{notes}   );
        my $reqsubj     = $args->{reqsubj} ? 1 : 0;

        if ( $account ) {
            $errors->add( "account", ".error.badacct" )
                unless exists $LJ::SENDMAIL_ACCOUNTS{$account};
        } else {
            $errors->add( "account", ".error.noacct" );
        }

        $errors->add( "subject", ".error.nosubj" )  unless $subject;
        $errors->add( "message", ".error.nomsg" )  unless $message;

        if ( $support_req ) {
            if ( $support_req =~ /^\d+$/ ) {
                $subject = "[\#$support_req] $subject" if $reqsubj;
            } else {
                $errors->add( "request", ".error.badreq" );
            }
        }

        my $u;

        if ( $sendto ) {
            if ( $sendto =~ /,/ ) { # multiple recipients
                $errors->add( "sendto", ".error.nomulti" );
            } else {
                # make sure we're sending to either a valid user or something
                # that looks reasonably like an email address.
                if ( $sendto !~ /^[^@]+@[^.]+\./ ) {
                    # doesn't look like an email address; do a username lookup
                    $u = LJ::load_user( $sendto );
                    $errors->add( "sendto", ".error.badrcpt" ) unless defined $u;
                    $sendto = $u->id;  # log userid instead of username
                }
            }
        } else { # no $sendto
            $errors->add( "sendto", ".error.norcpt" );
        }

        # at this point, we should have good form data; the form can still
        # have errors below, but they aren't the fault of the user input

        unless ( $errors->exist ) {
            # now that we have the data, send the message.
            # 1. insert data into siteadmin_email_history table
            my $msgid = LJ::alloc_global_counter('N');
            my $dbh = LJ::get_db_writer();
            $dbh->do( "INSERT INTO siteadmin_email_history (msgid, remoteid," .
                      " time_sent, account, sendto, subject, request, message, " .
                      " notes) VALUES (?,?,?,?,?,?,?,?,?)", undef,
                      $msgid, $remote->id, time, $account, $sendto, $subject,
                      $support_req, $message, $teamnotes )
                or return error_ml( $scope->( '.error.sendfailed' ) );
            # keeping this as error_ml; if we get a DB error things are FUBAR

            # 2. construct the message and send it to the user(s)
            # (this block adapted from bin/worker/paidstatus)
            my $msg = { from => "$account\@$LJ::DOMAIN",
                        fromname => $LJ::SITENAME,
                        subject => $subject,
                        body => $message,
                      };
            my $sent = 0;

            my $send = sub { LJ::send_mail( $msg ); $sent = 1; };

            if ( $u && $u->is_community ) {
                # send an email to every maintainer
                my $maintus = LJ::load_userids( $u->maintainer_userids );
                foreach my $maintu ( values %$maintus ) {
                    $msg->{to} = $maintu->email_raw;
                    $send->() if $msg->{to};
                }

            } else {
                $msg->{to} = $u ? $u->email_raw : $sendto;
                $send->() if $msg->{to};
            }

            # 3. update userlog and return success message
            if ( $sent ) {
                $remote->log_event( 'siteadmin_email', { account => $account,
                                                         msgid => $msgid } );
                return success_ml( $scope->( '.success.msgtext' ), undef,
                    [ { text => LJ::Lang::ml( $scope->( '.success.linktext.a' ) ),
                        url => '/admin/sendmail' } ] );
            } else {
                $errors->add( "sendto", ".error.nouseremail" );
            }
        }
    }
    # end form processing

    # Construct data for dropdown of available email addresses;
    # the user should have at least one of these for this page to be useful.
    # If the user somehow has sendmail priv but no relevant account priv,
    # we print an error in the template in that case.
    my @account_menu = ( "", LJ::Lang::ml( $scope->( '.select.account.choose' ) ) );

    foreach my $account ( sort keys %LJ::SENDMAIL_ACCOUNTS ) {
        my $priv = $LJ::SENDMAIL_ACCOUNTS{$account};
        push @account_menu, ( $account, "$account\@$LJ::DOMAIN" )
            if $remote->has_priv( $priv );
    }

    $rv->{has_menu}      = ( @account_menu > 2 );
    $rv->{account_menu}  = \@account_menu;

    $rv->{errors}        = $errors;
    $rv->{formdata}      = $r->post_args;

    return DW::Template->render_template( 'admin/sendmail/index.tt', $rv );
}


1;
