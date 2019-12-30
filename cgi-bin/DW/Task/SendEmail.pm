#!/usr/bin/perl
#
# DW::Task::SendEmail
#
# Worker to send emails.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::SendEmail;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Carp qw/ croak /;
use Digest::MD5 qw/ md5_hex /;
use Net::SMTPS;

use base 'DW::Task';

my $smtp;
my $last_email    = 0;
my $email_counter = 0;

sub work {
    my ( $self, $handle ) = @_;

    my $failed = sub {
        $log->error( sprintf(@_) );
        return DW::Task::FAILED;
    };

    # Refresh the SMTP client if we don't have one or we haven't sent an email in
    # more than 10 seconds
    if ( ( $email_counter++ % 30 == 0 ) || ( time() - $last_email > 10 ) || !defined $smtp ) {
        $smtp = Net::SMTPS->new(
            $LJ::EMAIL_VIA_SES{hostname},
            doSSL   => 'starttls',
            Port    => 587,
            Timeout => 60,
        );
        return $failed->(
            "Temporary failure connecting to $LJ::EMAIL_VIA_SES{hostname}, will retry.")
            unless $smtp;

        $smtp->auth( $LJ::EMAIL_VIA_SES{username}, $LJ::EMAIL_VIA_SES{password} )
            or
            return $failed->("Couldn't authenticate to $LJ::EMAIL_VIA_SES{hostname}, will retry.");
    }
    $last_email = time();

    my $args     = $self->args->[0];
    my $env_from = $args->{env_from};    # Envelope From
    my $rcpts    = $args->{rcpts};       # arrayref of recipients
    my $body     = $args->{data};

    # Drop any recipient domains that we don't support/aren't allowed
    foreach my $rcpt ( @$rcpts ) {
        my ( $domain ) = ( $1 )
            if $rcpt =~ /@(.+?)$/;
        unless ( $domain ) {
            $log->error( 'Invalid email address: ', $rcpt );
            DW::Stats::increment( 'dw.email.sent', 1, [ 'status:invalid', 'via:ses' ] );
            return DW::Task::COMPLETED;
        }

        if ( exists $LJ::DISALLOW_EMAIL_DOMAIN{$domain} ) {
            $log->info( 'Disallowing email to: ', $rcpt );
            DW::Stats::increment( 'dw.email.sent', 1, [ 'status:disallowed', 'via:ses' ] );
            return DW::Task::COMPLETED;
        }
    }

    $log->debug( 'Sending email to: ', join( ', ', @$rcpts ) );

    # remove bcc
    $body =~ s/^(.+?\r?\n\r?\n)//s;
    my $headers = $1;
    $headers =~ s/^bcc:.+\r?\n//mig;

    # unless they specified a message ID, let's prepend our own:
    unless ( $headers =~ m!^message-id:.+!mi ) {
        my ($this_domain) = $env_from =~ /\@(.+)/;
        my $hstr = substr( md5_hex($handle), 0, 12 );
        $headers = "Message-ID: <dw-$hstr\@$this_domain>\r\n" . $headers;
    }

    my $details = sub {
        return eval { $smtp->code . " " . $smtp->message; }
    };

    my $not_ok = sub {
        my $cmd = $_[0];
        return $failed->(
            'Permanent failure during %s phase to [%s]: %s',
            $cmd, join( ', ', @$rcpts ),
            $details->()
        ) if $smtp->status == 5;
        return $failed->(
            'Error during %s phase to [%s]: %s',
            $cmd, join( ', ', @$rcpts ),
            $details->()
        );
    };

    return $not_ok->("MAIL") unless $smtp->mail($env_from);

    my $got_an_okay = 0;
    foreach my $rcpt (@$rcpts) {
        if ( $smtp->to($rcpt) ) {
            $got_an_okay = 1;
            next;
        }
        next if $smtp->status == 5;

        return $failed->( 'Error during TO phase to [%s]: %s', join( ', ', @$rcpts ),
            $details->() );
    }

    unless ($got_an_okay) {
        return $failed->( 'Permanent failure TO [%s]: %s', join( ', ', @$rcpts ), $details->() );
    }

    return $not_ok->("DATA")     unless $smtp->data;
    return $not_ok->("DATASEND") unless $smtp->datasend( $headers . $body );
    return $not_ok->("DATAEND")  unless $smtp->dataend;

    $log->debug('Email sent successfully.');
    DW::Stats::increment( 'dw.email.sent', 1, [ "status:completed", "via:ses" ] );

    return DW::Task::COMPLETED;
}

1;
