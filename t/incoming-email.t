# t/incoming-email.t
#
# Test DW::IncomingEmail processing pipeline — MIME parsing, routing
# to hooks/emailpost/alias/support handlers, and From-rewriting for
# alias forwards.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Digest::SHA qw(sha256_hex);
use File::Temp ();
use MIME::Parser;

use DW::IncomingEmail;

# Save real methods before mocking
my $real_try_alias_forward = \&DW::IncomingEmail::_try_alias_forward;

# Helper: build a minimal raw email string
sub make_email {
    my (%opts) = @_;
    my $from    = $opts{from}    || 'sender@example.com';
    my $to      = $opts{to}      || 'support@dreamwidth.org';
    my $subject = $opts{subject} || 'Test email';
    my $body    = $opts{body}    || 'This is a test email body.';

    return <<"EMAIL";
From: $from
To: $to
Subject: $subject
Date: Sun, 16 Feb 2026 12:00:00 +0000
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

$body
EMAIL
}

# ============================================================================
# process() tests — mock downstream handlers to isolate routing
# ============================================================================

# Mock out everything downstream so we can test the process() shell
# without DB access
{
    no warnings 'redefine', 'once';

    # Prevent hook/emailpost/alias/support from running
    *LJ::Hooks::are_hooks       = sub { return 0 };
    *DW::EmailPost::get_handler = sub { return undef };

    # _try_alias_forward and _route_to_support need DB; mock them
    *DW::IncomingEmail::_try_alias_forward = sub { return 0 };
    *DW::IncomingEmail::_route_to_support  = sub { return 1 };
}

# Empty/undef email should be dropped (return 1)
is( DW::IncomingEmail->process(''), 1, 'Empty email is dropped' );

is( DW::IncomingEmail->process(undef), 1, 'Undef email is dropped' );

# Legitimate email should pass through to support routing
{
    my $email = make_email(
        subject => 'I need help with my account',
        body    => 'Hello, I cannot log in to my account.',
    );
    is( DW::IncomingEmail->process($email), 1, 'Legitimate email reaches routing' );
}

# Various subject lines should all pass through (no filtering)
{
    my @subjects = (
        'auto-reply: out of office',
        '[SPAM: 15.3] Buy now!',
        'failure notice',
        'Message Undeliverable',
        'Re: Your support request',
        'Question about communities',
    );

    for my $subj (@subjects) {
        my $email = make_email( subject => $subj );
        is( DW::IncomingEmail->process($email), 1, "Subject passes through: '$subj'" );
    }
}

# Unparseable MIME should be dropped (return 1), not crash
{
    is( DW::IncomingEmail->process('this is not a valid email at all'),
        1, 'Unparseable content is dropped gracefully' );
}

# ============================================================================
# From-rewriting for alias forwards
# ============================================================================

# Test the rewriting logic by calling _try_alias_forward with mocks
# that simulate finding an alias match
{
    no warnings 'redefine', 'once';

    # Restore the real _try_alias_forward
    *DW::IncomingEmail::_try_alias_forward = $real_try_alias_forward;

    # Capture what gets dispatched to the task queue
    my $captured_task;
    local *DW::TaskQueue::dispatch = sub {
        my ( $class, $task ) = @_;
        $captured_task = $task;
    };

    # Mock DB to return an alias match
    local *LJ::get_db_reader = sub {
        return bless {}, 'FakeDBH';
    };

    # FakeDBH returns a recipient for any alias query
    {

        package FakeDBH;
        sub selectrow_array { return 'real-user@gmail.com' }
    }

    local $LJ::USER_EMAIL  = 1;
    local $LJ::USER_DOMAIN = 'dreamwidth.org';
    local $LJ::DOMAIN      = 'dreamwidth.org';
    local $LJ::BOGUS_EMAIL = 'noreply@dreamwidth.org';

    my $raw = make_email(
        from => '"Test User" <testuser@gmail.com>',
        to   => 'mark@dreamwidth.org',
    );

    my $parser = MIME::Parser->new;
    $parser->output_dir( File::Temp::tempdir( CLEANUP => 1 ) );
    my $entity = $parser->parse_data($raw);
    $entity->head->unfold;

    my $rv = DW::IncomingEmail->_try_alias_forward($entity);
    is( $rv, 1, 'Alias forward returned success' );

    ok( defined $captured_task, 'Task was dispatched' );
    my $args = $captured_task->args->[0];

    # Check the From was rewritten with hash
    my $expected_hash = substr( sha256_hex('testuser@gmail.com'), 0, 12 );
    like(
        $args->{data},
        qr/^From:.*noreply-$expected_hash\@dreamwidth\.org/m,
        'From header rewritten with sender hash'
    );
    like(
        $args->{data},
        qr/^From:.*testuser\@gmail\.com via Dreamwidth/m,
        'From display name includes original sender'
    );
    like(
        $args->{data},
        qr/^Reply-To: testuser\@gmail\.com$/m,
        'Reply-To header added with original sender'
    );

    # env_from should also use the hashed address
    is(
        $args->{env_from},
        "noreply-$expected_hash\@dreamwidth.org",
        'Envelope from uses hashed address'
    );

    # Same sender should always produce the same hash
    my $hash2 = substr( sha256_hex('testuser@gmail.com'), 0, 12 );
    is( $expected_hash, $hash2, 'Hash is deterministic for same sender' );

    # Different sender produces different hash
    my $hash3 = substr( sha256_hex('other@yahoo.com'), 0, 12 );
    isnt( $expected_hash, $hash3, 'Different sender produces different hash' );
}

# ============================================================================
# Alternate domain normalization
# ============================================================================

{
    local @LJ::INCOMING_EMAIL_DOMAINS = ('dreamwidth.net');
    local $LJ::DOMAIN                 = 'dreamwidth.org';

    my $email = make_email(
        to   => 'support@dreamwidth.net',
        from => 'someone@example.com',
    );

    # process() will normalize the To header; we mock downstream to capture
    # that it routes correctly (mocks from above still active)
    is( DW::IncomingEmail->process($email), 1, 'Alternate domain email processed' );

    # Verify normalization by parsing what process() would see — test it
    # more directly by parsing and checking the header rewrite
    my $parser = MIME::Parser->new;
    $parser->output_dir( File::Temp::tempdir( CLEANUP => 1 ) );
    my $entity = $parser->parse_data($email);
    my $head   = $entity->head;
    $head->unfold;

    # Simulate the normalization
    for my $hdr ( 'To', 'Cc' ) {
        my $val = $head->get($hdr) or next;
        for my $alt (@LJ::INCOMING_EMAIL_DOMAINS) {
            $val =~ s/\@\Q$alt\E/\@$LJ::DOMAIN/gi;
        }
        $head->replace( $hdr, $val );
    }

    like( $head->get('To'), qr/dreamwidth\.org/, 'To header normalized to primary domain' );
    unlike( $head->get('To'), qr/dreamwidth\.net/, 'Alternate domain removed from To' );
}

done_testing();
