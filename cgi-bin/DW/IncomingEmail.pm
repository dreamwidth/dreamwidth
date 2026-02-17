#!/usr/bin/perl
#
# DW::IncomingEmail
#
# Shared processing logic for incoming email. Handles post-by-email,
# support request routing, and email alias forwarding. Spam/virus
# filtering is handled upstream by SES.
#
# Extracted from DW::Task::IncomingEmail so that both the legacy
# DW::TaskQueue worker and the new SES-based worker can share the
# same processing pipeline.
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

package DW::IncomingEmail;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Digest::SHA qw(sha256_hex);
use DW::EmailPost;
use DW::Task::SendEmail;
use DW::TaskQueue;
use File::Temp ();
use LJ::Support;
use LJ::Sysban;
use MIME::Parser;

# Process a raw email message. Returns 1 on success (or deliberate drop),
# 0 on transient failure (caller should retry).
#
# Arguments:
#   $raw_email - scalar containing the raw email bytes
#
sub process {
    my ( $class, $raw_email ) = @_;

    unless ( defined $raw_email && length $raw_email ) {
        $log->error("Empty email data, dropping");
        return 1;
    }

    my $tmpdir = File::Temp::tempdir( CLEANUP => 1 );
    die "No tempdir made?" unless -d $tmpdir && -w $tmpdir;

    my $parser = MIME::Parser->new;
    $parser->output_dir($tmpdir);

    my $entity = eval { $parser->parse_data($raw_email) };
    if ($@) {
        $log->error("Can't parse MIME: $@");
        return 1;
    }

    my $head = $entity->head;
    $head->unfold;

    # Normalize alternate incoming domains to the primary domain
    # so all downstream routing (aliases, support) works unchanged.
    if ( @LJ::INCOMING_EMAIL_DOMAINS && $LJ::DOMAIN ) {
        for my $hdr ( 'To', 'Cc' ) {
            my $val = $head->get($hdr) or next;
            my $changed;
            for my $alt (@LJ::INCOMING_EMAIL_DOMAINS) {
                $changed = 1 if $val =~ s/\@\Q$alt\E/\@$LJ::DOMAIN/gi;
            }
            $head->replace( $hdr, $val ) if $changed;
        }
    }

    my $subject = $head->get('Subject') // '';
    chomp $subject;
    $subject = LJ::trim($subject);

    # See if a hook is registered to handle this message
    if ( LJ::Hooks::are_hooks("incoming_email_handler") ) {
        my $errmsg = "";
        my $retry  = 0;

        my $rv = LJ::Hooks::run_hook(
            "incoming_email_handler",
            entity => $entity,
            errmsg => \$errmsg,
            retry  => \$retry
        );

        if ($rv) {
            if ($retry) {
                $log->warn("Hook requested retry: $errmsg");
                return 0;    # transient failure
            }
            if ($errmsg) {
                $log->error("Hook error: $errmsg");
                return 1;
            }
            return 1;
        }
    }

    # Post-by-email
    my $email_post = DW::EmailPost->get_handler($entity);
    if ($email_post) {
        my ( $ok, $status_msg ) = $email_post->process;
        return 1 if $ok;

        if ( $email_post->dequeue ) {
            $log->error("EmailPost dequeued: $status_msg");
            return 1;
        }
        else {
            $log->warn("EmailPost retry: $status_msg");
            return 0;    # transient failure
        }
    }

    # Try email alias forwarding before support routing
    if ( $class->_try_alias_forward($entity) ) {
        return 1;
    }

    # Support request routing
    return $class->_route_to_support( $head, $entity, $subject );
}

# Check if the recipient matches an email alias and forward if so.
# Returns 1 if forwarded, 0 if no alias match.
sub _try_alias_forward {
    my ( $class, $entity ) = @_;

    return 0 unless $LJ::USER_EMAIL;

    my $dbr = LJ::get_db_reader()
        or return 0;

    my $head = $entity->head;

    # Check all To/Cc addresses against email_aliases
    foreach
        my $a ( Mail::Address->parse( $head->get('To') ), Mail::Address->parse( $head->get('Cc') ) )
    {
        my $address = lc $a->address;

        # Only check addresses on our domain
        next unless $address =~ /^(.+)\@\Q$LJ::USER_DOMAIN\E$/;
        my $local_part = $1;

        # Normalize dashes to underscores (matches Postfix query behavior)
        $local_part =~ s/-/_/g;
        my $alias = "$local_part\@$LJ::USER_DOMAIN";

        my $rcpt = $dbr->selectrow_array( "SELECT rcpt FROM email_aliases WHERE alias = ?",
            undef, $alias );
        next unless $rcpt;

        # Forward to each recipient
        my @rcpts = grep { $_ } map { LJ::trim($_) } split( /,/, $rcpt );
        unless (@rcpts) {
            $log->warn("Alias $alias has empty rcpt, dropping");
            return 1;
        }

        my $from_addr     = ( Mail::Address->parse( $head->get('From') ) )[0];
        my $original_from = $from_addr ? $from_addr->address : 'unknown';
        $log->info("Forwarding alias from=$original_from alias=$alias rcpt=$rcpt");

        # Rewrite the From header so DKIM/SPF/DMARC align with
        # dreamwidth.org. Use a per-sender hash so mail clients
        # group messages from the same original sender together.
        my $hash     = substr( sha256_hex( lc $original_from ), 0, 12 );
        my $new_from = "noreply-$hash\@$LJ::DOMAIN";

        ( my $safe_from = $original_from ) =~ s/["\\\r\n]//g;
        $head->replace( 'From',     "\"$safe_from via Dreamwidth\" <$new_from>" );
        $head->replace( 'Reply-To', $original_from )
            unless $head->get('Reply-To');

        # Forward via the SendEmail task queue with a dreamwidth.org
        # envelope sender so SES accepts it.
        DW::TaskQueue->dispatch(
            DW::Task::SendEmail->new(
                {
                    env_from => $new_from,
                    rcpts    => \@rcpts,
                    data     => $entity->as_string,
                }
            )
        );

        return 1;
    }

    return 0;
}

# Route email to the support system
sub _route_to_support {
    my ( $class, $head, $entity, $subject ) = @_;

    # Extract body text from MIME entity
    my $tent = DW::EmailPost->get_entity($entity);
    $tent ||= DW::EmailPost->get_entity( $entity, 'html' );
    unless ($tent) {
        $log->error("Can't find text or html entity");
        return 1;
    }
    my $body = $tent->bodyhandle->as_string;
    $body = LJ::trim($body);

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
        return 1;
    }

    my $adf = ( Mail::Address->parse( $head->get('From') ) )[0];
    unless ($adf) {
        $log->error("Bogus From: header");
        return 1;
    }

    my $name = $adf->name;
    my $from = $adf->address;
    $subject ||= "(No Subject)";

    # Is this a reply to another post?
    if ( $toarg =~ /^(\d+)z(.+)$/ ) {
        my $spid     = $1;
        my $miniauth = $2;
        my $sp       = LJ::Support::load_request($spid);

        unless ( LJ::Support::mini_auth($sp) eq $miniauth ) {
            $log->error("Invalid mini_auth for support request $spid, dropping");
            return 1;
        }

        if ( LJ::sysban_check( 'support_email', $from ) ) {
            my $msg = "Support request blocked based on email.";
            LJ::Sysban::block( 0, $msg, { 'email' => $from } );
            $log->info("Dequeued: $msg");
            return 1;
        }

        if ( LJ::Support::is_locked($sp) ) {
            $log->info("Request is locked, can't append comment.");
            return 1;
        }

        # Strip authcodes from body
        $body =~ s!https?://.+/support/act\S+![snipped]!g;
        $body =~ s!\+(\d)+z\w{1,10}\@!\@!g;
        $body =~ s!&auth=\S+!!g;

        # Strip reply quoting
        $body =~ s!(\S+.*?)-{4,10} Original Message -{4,10}.+!$1!s;
        $body =~ s!(\S+.*?)\bOn [^\n]+ wrote:\n.+!$1!s;

        my $splid = LJ::Support::append_request(
            $sp,
            {
                'type' => 'comment',
                'body' => $body,
            }
        );
        unless ($splid) {
            $log->error("Error appending request?");
            return 1;
        }

        LJ::Support::add_email_address( $sp, $from );
        LJ::Support::touch_request($spid);

        return 1;
    }

    # Deny list check
    my ( $content_file, $content );
    if ( %LJ::DENY_REQUEST_FROM_EMAIL && $LJ::DENY_REQUEST_FROM_EMAIL{$to} ) {
        $content_file = $LJ::DENY_REQUEST_FROM_EMAIL{$to};
        $content      = LJ::load_include($content_file);
    }
    if ( $content_file && $content ) {
        my $email = <<EMAIL_END;
$content

Your original message:

$body
EMAIL_END

        LJ::send_mail(
            {
                'to'      => $from,
                'from'    => $LJ::BOGUS_EMAIL,
                'subject' => "Your Email to $to",
                'body'    => $email,
                'wrap'    => 1,
            }
        );

        return 1;
    }

    # File new support request
    my @errors;

    # Convert email body to UTF-8
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
        return 1;
    }

    return 1;
}

1;
