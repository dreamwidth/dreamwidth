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

use DW::EmailPost;
use File::Temp ();
use LJ::Support;
use LJ::Sysban;
use MIME::Parser;
use Net::SMTP;
use DW::Stats;

# Process a raw email message. Returns 1 on success (or deliberate drop),
# 0 on transient failure (caller should retry).
#
# Arguments:
#   $raw_email - scalar containing the raw email bytes
#
sub process {
    my ( $class, $raw_email, $path, %opts ) = @_;
    $path ||= 'legacy';

    # %opts may carry SES receipt verdicts (dmarc_verdict, dmarc_policy) used to
    # gate forwarding. Absent on the legacy path; gating is fail-open without them.

    DW::Stats::increment( 'dw.incoming_email.received', 1, ["path:$path"] );

    unless ( defined $raw_email && length $raw_email ) {
        $class->_outcome( 'empty', $path, 'none', 'warn' );
        return 1;
    }

    my $tmpdir = File::Temp::tempdir( CLEANUP => 1 );
    die "No tempdir made?" unless -d $tmpdir && -w $tmpdir;

    my $parser = MIME::Parser->new;
    $parser->output_dir($tmpdir);

    my $entity = eval { $parser->parse_data($raw_email) };
    if ($@) {
        $class->_outcome( 'parse_fail', $path, 'none', 'error', error => $@ );
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
                $class->_outcome( 'hook_retry', $path, 'none', 'warn', msg => $errmsg );
                return 0;    # transient failure
            }
            if ($errmsg) {
                $class->_outcome( 'hook_error', $path, 'none', 'error', msg => $errmsg );
                return 1;
            }
            $class->_outcome( 'hook_drop', $path, 'none', 'info' );
            return 1;
        }
    }

    # Post-by-email (or comment-by-email; both flow through get_handler)
    my $email_post = DW::EmailPost->get_handler($entity);
    if ($email_post) {
        my $kind = ref($email_post) =~ /Comment/ ? 'comment' : 'post';

        my ( $ok, $status_msg ) = $email_post->process;
        if ($ok) {
            $class->_outcome( 'post_success', $path, $kind, 'info' );
            return 1;
        }

        if ( $email_post->dequeue ) {
            $class->_outcome( 'post_rejected', $path, $kind, 'info', msg => $status_msg );
            return 1;
        }
        else {
            $class->_outcome( 'post_retry', $path, $kind, 'warn', msg => $status_msg );
            return 0;    # transient failure
        }
    }

    # Blackhole addresses (e.g. dw_null) — bounce/null sink. Drop silently
    # before forwarding/support routing so they don't masquerade as failures.
    if ( $class->_is_blackhole($head) ) {
        $class->_outcome( 'dropped', $path, 'none', 'info', reason => 'blackhole' );
        return 1;
    }

    # Try email alias forwarding before support routing
    if ( $class->_try_alias_forward( $entity, $raw_email, $path, %opts ) ) {
        return 1;
    }

    # Support request routing
    return $class->_route_to_support( $head, $entity, $subject, $path );
}

# Return true if any To/Cc recipient is a configured blackhole/null address
# (the SES-path equivalent of postfix's "dw_null: /dev/null" alias).
sub _is_blackhole {
    my ( $class, $head ) = @_;

    # Local-parts (on our domain) whose mail should be silently discarded.
    # Override via @LJ::EMAIL_BLACKHOLE_LOCALPARTS; defaults to dw_null.
    my @localparts =
        @LJ::EMAIL_BLACKHOLE_LOCALPARTS ? @LJ::EMAIL_BLACKHOLE_LOCALPARTS : ('dw_null');
    my %blackhole = map { lc($_) => 1 } @localparts;

    foreach
        my $a ( Mail::Address->parse( $head->get('To') ), Mail::Address->parse( $head->get('Cc') ) )
    {
        my $address = lc $a->address;
        next unless $address =~ /^(.+)\@\Q$LJ::USER_DOMAIN\E$/;
        return 1 if $blackhole{$1};
    }

    return 0;
}

# Check if the recipient matches an email alias and forward if so.
# Returns 1 if forwarded, 0 if no alias match.
sub _try_alias_forward {
    my ( $class, $entity, $raw_email, $path, %opts ) = @_;
    $path ||= 'legacy';

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

        # DMARC gate: refuse to forward (and thus re-sign as dreamwidth.org) mail
        # that the sender's OWN domain published a reject policy for and that
        # failed DMARC. This honors the sender domain's stated policy and avoids
        # lending our reputation to forged/spam mail. Fail-open: only drops on an
        # explicit reject+fail; PASS, p=none/quarantine, or missing verdicts
        # (e.g. the legacy path) all forward as normal.
        if ( lc( $opts{dmarc_policy} // '' ) eq 'reject'
            && uc( $opts{dmarc_verdict} // '' ) eq 'FAIL' )
        {
            $class->_outcome(
                'forward_dropped', $path, 'forward', 'warn',
                alias  => $alias,
                reason => 'dmarc_reject'
            );
            return 1;
        }

        # Forward to each recipient
        my @rcpts = grep { $_ } map { LJ::trim($_) } split( /,/, $rcpt );
        unless (@rcpts) {
            $class->_outcome(
                'forward_dropped', $path, 'forward', 'warn',
                alias  => $alias,
                reason => 'empty_rcpt'
            );
            return 1;
        }

        # Envelope sender: preserve the original return-path (classic forwarding,
        # so bounces go back to the original sender). Fall back to the From
        # address, then to $LJ::BOGUS_EMAIL if neither is present.
        my $env_from =
            ${ ( Mail::Address->parse( $head->get('Return-Path') ) )[0] || [] }[1];
        unless ($env_from) {
            my $from_addr = ( Mail::Address->parse( $head->get('From') ) )[0];
            $env_from = $from_addr ? $from_addr->address : $LJ::BOGUS_EMAIL;
        }

        # Relay the ORIGINAL raw bytes, unmodified, through the outbound relay.
        # Do NOT use $entity->as_string here: re-serializing the MIME entity can
        # alter bytes and break the sender's DKIM signature, which is the whole
        # point of relaying (DKIM survives, DMARC passes on DKIM alignment).
        unless ( $class->_relay_raw( $raw_email, $env_from, \@rcpts ) ) {
            $class->_outcome(
                'forward_retry', $path, 'forward', 'warn',
                alias => $alias,
                from  => $env_from
            );
            return 0;    # transient relay failure -> allow SQS retry
        }

        $class->_outcome(
            'forward_sent', $path, 'forward', 'info',
            alias => $alias,
            from  => $env_from,
            rcpt  => $rcpt
        );

        return 1;
    }

    return 0;
}

# Relay a raw message, unmodified, to the outbound relay host
# ($LJ::FORWARD_RELAY_HOST, e.g. va-mail01). Sending the original bytes verbatim
# preserves the sender's DKIM signature so the forwarded mail passes DMARC on
# DKIM alignment (SPF will fail, which is expected and harmless for forwards).
#
#   $raw_bytes - the original raw email, exactly as received (NOT re-serialized)
#   $env_from  - envelope sender (MAIL FROM)
#   $rcpts     - arrayref of recipient addresses
#
# Returns 1 on success, 0 on transient failure (caller should allow retry).
sub _relay_raw {
    my ( $class, $raw_bytes, $env_from, $rcpts ) = @_;

    my $host = $LJ::FORWARD_RELAY_HOST;
    unless ($host) {
        $log->error("Cannot relay forward: \$LJ::FORWARD_RELAY_HOST is not set");
        return 0;
    }

    my $smtp = Net::SMTP->new( $host, Port => 25, Timeout => 60 );
    unless ($smtp) {
        $log->warn("Forward relay: failed to connect to $host, will retry");
        return 0;
    }

    my $ok = eval {
        $smtp->mail($env_from)      or die "MAIL FROM rejected\n";
        $smtp->to(@$rcpts)          or die "RCPT TO rejected\n";
        $smtp->data                 or die "DATA rejected\n";
        $smtp->datasend($raw_bytes) or die "DATASEND failed\n";
        $smtp->dataend              or die "DATAEND rejected\n";
        1;
    };
    my $err  = $@;
    my $code = eval { $smtp->code } // 0;
    $smtp->quit;

    return 1 if $ok;

    # 5xx = permanent (e.g. message too large). Log and treat as handled so we
    # don't retry forever. 4xx / connection issues = transient, allow retry.
    if ( $code >= 500 && $code < 600 ) {
        $log->error(
            "Forward relay permanent failure ($code) to " . join( ',', @$rcpts ) . ": $err" );
        return 1;
    }

    $log->warn( "Forward relay transient failure ($code) to "
            . join( ',', @$rcpts )
            . ": $err, will retry" );
    return 0;
}

# Route email to the support system
sub _route_to_support {
    my ( $class, $head, $entity, $subject, $path ) = @_;
    $path ||= 'legacy';

    # Extract body text from MIME entity
    my $tent = DW::EmailPost->get_entity($entity);
    $tent ||= DW::EmailPost->get_entity( $entity, 'html' );
    unless ($tent) {
        $class->_outcome( 'support_rejected', $path, 'support', 'info', reason => 'no_entity' );
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
        $class->_outcome( 'support_rejected', $path, 'support', 'info', reason => 'no_match' );
        return 1;
    }

    my $adf = ( Mail::Address->parse( $head->get('From') ) )[0];
    unless ($adf) {
        $class->_outcome( 'support_rejected', $path, 'support', 'error', reason => 'bogus_from' );
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
            $class->_outcome(
                'support_rejected', $path, 'support', 'error',
                reason => 'bad_miniauth',
                spid   => $spid
            );
            return 1;
        }

        if ( LJ::sysban_check( 'support_email', $from ) ) {
            my $msg = "Support request blocked based on email.";
            LJ::Sysban::block( 0, $msg, { 'email' => $from } );
            $class->_outcome( 'support_rejected', $path, 'support', 'info', reason => 'sysban' );
            return 1;
        }

        if ( LJ::Support::is_locked($sp) ) {
            $class->_outcome( 'support_rejected', $path, 'support', 'info', reason => 'locked' );
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
            $class->_outcome( 'support_rejected', $path, 'support', 'error',
                reason => 'append_failed' );
            return 1;
        }

        LJ::Support::add_email_address( $sp, $from );
        LJ::Support::touch_request($spid);

        $class->_outcome(
            'support_routed', $path, 'support', 'info',
            spid => $spid,
            mode => 'append'
        );
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

        $class->_outcome( 'support_rejected', $path, 'support', 'info', reason => 'deny_list' );
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
        $class->_outcome( 'support_rejected', $path, 'support', 'error', reason => 'file_errors' );
        return 1;
    }

    $class->_outcome( 'support_routed', $path, 'support', 'info', spid => $spid, mode => 'new' );
    return 1;
}

# Emit one metric + one structured log line for a terminal outcome.
#   $result - bounded enum string (see metric contract)
#   $path   - 'legacy' | 'ses'
#   $kind   - 'post' | 'comment' | 'forward' | 'support' | 'none'
#   $level  - log4perl level: 'info' | 'warn' | 'error'
#   %fields - extra key=value detail for the log ONLY (never tags)
sub _outcome {
    my ( $class, $result, $path, $kind, $level, %fields ) = @_;

    DW::Stats::increment( 'dw.incoming_email.processed', 1,
        [ "result:$result", "path:$path", "kind:$kind" ] );

    my $detail = join ' ', map { "$_=" . ( defined $fields{$_} ? $fields{$_} : '' ) }
        sort keys %fields;
    my $line = "email_outcome result=$result path=$path kind=$kind" . ( $detail ? " $detail" : '' );

    $log->error($line) if $level eq 'error';
    $log->warn($line)  if $level eq 'warn';
    $log->info($line)  if $level eq 'info';
    return;
}

1;
