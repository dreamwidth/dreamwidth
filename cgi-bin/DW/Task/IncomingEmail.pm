#!/usr/bin/perl
#
# DW::Task::IncomingEmail
#
# SQS worker for processing incoming email (post-by-email, support requests).
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

package DW::Task::IncomingEmail;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::BlobStore;
use DW::EmailPost;
use File::Path ();
use File::Temp ();
use LJ::Support;
use LJ::Sysban;
use MIME::Parser;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $arg = $self->args->[0];

    my $tmpdiro = DW::Task::IncomingEmail::TempDirObj->new;
    my $tmpdir  = $tmpdiro->dir;

    my $parser = MIME::Parser->new;
    $parser->output_dir($tmpdir);

    my $entity;
    if ( $arg =~ /^ie:.+$/ ) {
        my $email = DW::BlobStore->retrieve( temp => $arg );
        unless ($email) {
            $log->error("Can't retrieve from BlobStore: $arg");
            return DW::Task::COMPLETED;
        }
        $entity = eval { $parser->parse_data($$email) };
    }
    else {
        $entity = eval { $parser->parse_data($arg) };
    }
    if ($@) {
        $log->error("Can't parse MIME: $@");
        return DW::Task::COMPLETED;
    }

    my $head = $entity->head;
    $head->unfold;

    my $subject = $head->get('Subject');
    chomp $subject;
    $subject = LJ::trim($subject);

    # simple/effective spam/bounce/virus checks:
    if ( $head->get("Return-Path") =~ /^\s*<>\s*$/ ) {
        $log->info("Dequeued: Bounce");
        return DW::Task::COMPLETED;
    }
    if ( subject_is_bogus($subject) ) {
        $log->info("Dequeued: Spam (bogus subject)");
        return DW::Task::COMPLETED;
    }
    if ( virus_check($entity) ) {
        $log->info("Dequeued: Virus found");
        return DW::Task::COMPLETED;
    }
    if ( $subject && $subject =~ /^\[SPAM: \d+\.?\d*\]/ ) {
        $log->info("Dequeued: Spam");
        return DW::Task::COMPLETED;
    }

    # see if a hook is registered to handle this message
    if ( LJ::Hooks::are_hooks("incoming_email_handler") ) {

        my $errmsg = "";
        my $retry  = 0;

        # incoming_email_handler hook will return a true value
        # if it chose to handle this incoming email
        my $rv = LJ::Hooks::run_hook(
            "incoming_email_handler",
            entity => $entity,
            errmsg => \$errmsg,
            retry  => \$retry
        );

        # success is signaled by a true $rv
        if ($rv) {

            # temporary retry case
            if ($retry) {
                $log->warn("Hook requested retry: $errmsg");
                return DW::Task::FAILED;
            }

            # total failure case
            if ($errmsg) {
                $log->error("Hook error: $errmsg");
                return DW::Task::COMPLETED;
            }

            return DW::Task::COMPLETED;
        }

        # hook didn't want to handle this email...
    }

    # see if it's a post-by-email
    my $email_post = DW::EmailPost->get_handler($entity);
    if ($email_post) {
        my ( $ok, $status_msg ) = $email_post->process;

        # on success: $status_msg eq 'Post success"
        # on failure: $status_msg is something else
        #             -- then we check $email_post->dequeue
        return DW::Task::COMPLETED if $ok;

        # failure. do we retry?
        if ( $email_post->dequeue ) {
            $log->error("EmailPost dequeued: $status_msg");
            return DW::Task::COMPLETED;
        }
        else {
            $log->warn("EmailPost retry: $status_msg");
            return DW::Task::FAILED;
        }
    }

    # stop more spam, based on body text checks
    my $tent = DW::EmailPost->get_entity($entity);
    $tent ||= DW::EmailPost->get_entity( $entity, 'html' );
    unless ($tent) {
        $log->error("Can't find text or html entity");
        return DW::Task::COMPLETED;
    }
    my $body = $tent->bodyhandle->as_string;
    $body = LJ::trim($body);

    ### spam
    if (   $body =~ /I send you this file in order to have your advice/i
        || $body =~ /^Content-Type: application\/octet-stream/i
        || $body =~ /^(Please see|See) the attached file for details\.?$/i
        || $body =~ /^I apologize for this automatic reply to your email/i )
    {
        $log->info("Dequeued: Spam (body check)");
        return DW::Task::COMPLETED;
    }

    # From this point on we know it's a support request of some type,
    my $email2cat = LJ::Support::load_email_to_cat_map();

    my $to;
    my $toarg;
    foreach
        my $a ( Mail::Address->parse( $head->get('To') ), Mail::Address->parse( $head->get('Cc') ) )
    {
        my $address = $a->address;
        my $arg;
        if ( $address =~ /^(.+)\+(.*)\@(.+)$/ ) {
            ( $address, $arg ) = ( lc "$1\@$3", $2 );
        }
        if ( defined $LJ::ALIAS_TO_SUPPORTCAT{$address} ) {
            $address = $LJ::ALIAS_TO_SUPPORTCAT{$address};
        }
        if ( defined $email2cat->{$address} ) {
            $to    = $address;
            $toarg = $arg;
        }
    }

    unless ($to) {
        $log->error("Not deliverable to support system (no match To:)");
        return DW::Task::COMPLETED;
    }

    my $adf = ( Mail::Address->parse( $head->get('From') ) )[0];
    unless ($adf) {
        $log->error("Bogus From: header");
        return DW::Task::COMPLETED;
    }

    my $name = $adf->name;
    my $from = $adf->address;
    $subject ||= "(No Subject)";

    # is this a reply to another post?
    if ( $toarg =~ /^(\d+)z(.+)$/ ) {
        my $spid     = $1;
        my $miniauth = $2;
        my $sp       = LJ::Support::load_request($spid);

        LJ::Support::mini_auth($sp) eq $miniauth
            or die "Invalid authentication?";

        if ( LJ::sysban_check( 'support_email', $from ) ) {
            my $msg = "Support request blocked based on email.";
            LJ::Sysban::block( 0, $msg, { 'email' => $from } );
            $log->info("Dequeued: $msg");
            return DW::Task::COMPLETED;
        }

        # make sure it's not locked
        if ( LJ::Support::is_locked($sp) ) {
            $log->info("Request is locked, can't append comment.");
            return DW::Task::COMPLETED;
        }

        # valid.  need to strip out stuff now with authcodes:
        $body =~ s!https?://.+/support/act\S+![snipped]!g;
        $body =~ s!\+(\d)+z\w{1,10}\@!\@!g;
        $body =~ s!&auth=\S+!!g;

        ## try to get rid of reply stuff.
        # Outlook Express:
        $body =~ s!(\S+.*?)-{4,10} Original Message -{4,10}.+!$1!s;

        # Pine/Netscape
        $body =~ s!(\S+.*?)\bOn [^\n]+ wrote:\n.+!$1!s;

        # append the comment, re-open the request if necessary
        my $splid = LJ::Support::append_request(
            $sp,
            {
                'type' => 'comment',
                'body' => $body,
            }
        );
        unless ($splid) {
            $log->error("Error appending request?");
            return DW::Task::COMPLETED;
        }

        LJ::Support::add_email_address( $sp, $from );

        LJ::Support::touch_request($spid);

        return DW::Task::COMPLETED;
    }

    # Now see if we want to ignore this particular email and bounce it back with
    # the contents from a file.  Check $LJ::DENY_REQUEST_FROM_EMAIL first.  Note
    # that this will only bounce initial emails; if a user replies to an email
    # from a request that's open, it'll be accepted above.
    my ( $content_file, $content );
    if ( %LJ::DENY_REQUEST_FROM_EMAIL && $LJ::DENY_REQUEST_FROM_EMAIL{$to} ) {
        $content_file = $LJ::DENY_REQUEST_FROM_EMAIL{$to};
        $content      = LJ::load_include($content_file);
    }
    if ( $content_file && $content ) {

        # construct mail to send to user
        my $email = <<EMAIL_END;
$content

Your original message:

$body
EMAIL_END

        # send the message
        LJ::send_mail(
            {
                'to'      => $from,
                'from'    => $LJ::BOGUS_EMAIL,
                'subject' => "Your Email to $to",
                'body'    => $email,
                'wrap'    => 1,
            }
        );

        # all done
        return DW::Task::COMPLETED;
    }

    # make a new post.
    my @errors;

    # convert email body to utf-8
    my $content_type = $head->get('Content-type:');
    if ( $content_type =~ /\bcharset=[\'\"]?(\S+?)[\'\"]?[\s\;]/i ) {
        my $charset = $1;
        if (   defined $charset
            && $charset !~ /^UTF-?8$/i
            && Unicode::MapUTF8::utf8_supported_charset($charset) )
        {
            $body = Unicode::MapUTF8::to_utf8( { -string => $body, -charset => $charset } );
        }
    }

    my $spid = LJ::Support::file_request(
        \@errors,
        {
            'spcatid'  => $email2cat->{$to}->{'spcatid'},
            'subject'  => $subject,
            'reqtype'  => 'email',
            'reqname'  => $name,
            'reqemail' => $from,
            'body'     => $body,
        }
    );

    if (@errors) {
        $log->error("Support errors: @errors");
        return DW::Task::COMPLETED;
    }

    return DW::Task::COMPLETED;
}

# returns true on found virus
sub virus_check {
    my $entity = shift;
    return unless $entity;

    my @exe = DW::EmailPost->get_entity( $entity, 'all' );
    return unless scalar @exe;

    # If an attachment's encoding begins with one of these strings,
    # we want to completely drop the message.
    # (Other 'clean' attachments are silently ignored, and the
    # message is allowed.)
    my @virus_sigs = qw(
        TVqQAAMAA TVpQAAIAA TVpAALQAc TVpyAXkAX TVrmAU4AA
        TVrhARwAk TVoFAQUAA TVoAAAQAA TVoIARMAA TVouARsAA
        TVrQAT8AA UEsDBBQAA UEsDBAoAAA
        R0lGODlhaAA7APcAAP///+rp6puSp6GZrDUjUUc6Zn53mFJMdbGvvVtXh2xre8bF1x8cU4yLprOy
    );

    # get the length of the longest virus signature
    my $maxlength =
        length( ( sort { length $b <=> length $a } @virus_sigs )[0] );
    $maxlength = 1024 if $maxlength >= 1024;    # capped at 1k

    foreach my $part (@exe) {
        my $contents = $part->stringify_body;
        $contents = substr $contents, 0, $maxlength;

        foreach (@virus_sigs) {
            return 1 if index( $contents, $_ ) == 0;
        }
    }

    return;
}

sub subject_is_bogus {
    my $subject = shift;

    # ignore spam/vacation/auto-reply messages
    return $subject =~ /auto.?(response|reply)/i
        || $subject =~
        /^(Undelive|Mail System Error - |ScanMail Message: |\+\s*SPAM|Norton AntiVirus)/i
        || $subject =~ /^(Mail Delivery Problem|Mail delivery failed)/i
        || $subject =~ /^failure notice$/i
        || $subject =~ /\[BOUNCED SPAM\]/i
        || $subject =~ /^Symantec AVF /i
        || $subject =~ /Attachment block message/i
        || $subject =~ /Use this patch immediately/i
        || $subject =~ /^YOUR PAYPAL\.COM ACCOUNT EXPIRES/i
        || $subject =~ /^don\'t be late! ([\w\-]{1,25})$/i
        || $subject =~ /^your account ([\w\-]{1,25})$/i
        || $subject =~ /Message Undeliverable/i;
}

# Helper class for temporary directory cleanup
package DW::Task::IncomingEmail::TempDirObj;

sub new {
    my ($class) = @_;
    my $tmpdir = File::Temp::tempdir();
    die "No tempdir made?" unless -d $tmpdir && -w $tmpdir;
    return bless { dir => $tmpdir, }, $class;
}

sub dir { $_[0]{dir} }

sub DESTROY {
    my $self = shift;
    File::Path::rmtree( $self->{dir} ) if -d $self->{dir};
}

1;
