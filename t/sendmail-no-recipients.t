# t/sendmail-no-recipients.t
#
# Test empty-recipient handling, diagnostics, and caller guards for mail sending.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
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
use Test::MockObject;
use Log::Log4perl;
use Log::Log4perl::Appender::TestBuffer;
use MIME::Lite;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user with_fake_memcache );
use DW::Task::SendEmail;
use DW::Task::SupportNotify;
use LJ::Event::AddedToCircle;
use LJ::NotificationMethod::Email;
use LJ::Sendmail;
use LJ::Support;

my $log_config = q{
log4perl.rootLogger=OFF, Capture
log4perl.logger.LJ=WARN
log4perl.logger.LJ.NotificationMethod.Email=WARN
log4perl.logger.DW.Task.SendEmail=WARN
log4perl.appender.Capture=Log::Log4perl::Appender::TestBuffer
log4perl.appender.Capture.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Capture.layout.ConversionPattern=%p %c %m%n
};
Log::Log4perl::init( \$log_config );
my $logs = Log::Log4perl::Appender::TestBuffer->by_name('Capture');

my @dispatched;
my @stats;

{
    no warnings qw( redefine once );
    local *DW::TaskQueue::dispatch = sub {
        my ( $class, @tasks ) = @_;
        push @dispatched, @tasks;
        return 1;
    };
    local *DW::Stats::increment = sub {
        push @stats, [@_];
        return 1;
    };

    subtest 'LJ::send_mail rejects empty recipients with safe diagnostics' => sub {
        @dispatched = ();
        @stats      = ();
        $logs->buffer('');

        my $line = __LINE__ + 1;
        my $rv   = LJ::send_mail(
            {
                to         => '',
                from       => 'private-sender@example.invalid',
                subject    => 'SECRET_SUBJECT_TOKEN_1659',
                body       => 'SECRET_BODY_PASSWORD_1659',
                logger_mdc => {
                    userid    => 4242,
                    evt_class => 'LJ::Event::SecurityAttributeChanged',
                },
            }
        );

        is( $rv,                0, 'Returns 0 when no recipients are present' );
        is( scalar @dispatched, 0, 'Does not dispatch a SendEmail task' );

        my $buf = $logs->buffer;
        like(
            $buf,
            qr/WARN LJ .*caller=main\/\Q$line\E.*input=hashref.*from=1 to=0 cc=0 bcc=0/,
            'Logs caller location and header presence flags'
        );
        like(
            $buf,
            qr/evt_class=LJ::Event::SecurityAttributeChanged/,
            'Includes safe logger_mdc context'
        );
        unlike( $buf, qr/SECRET_SUBJECT_TOKEN_1659/,        'Does not log subject' );
        unlike( $buf, qr/SECRET_BODY_PASSWORD_1659/,        'Does not log body' );
        unlike( $buf, qr/private-sender\@example\.invalid/, 'Does not log sender address' );

        my @no_rcpt_stats = grep { $_->[0] eq 'dw.mail.send.no_recipients' } @stats;
        is( scalar @no_rcpt_stats, 1, 'Records no-recipients stat' );
    };

    subtest 'LJ::send_mail handles undef to with toname cleanly' => sub {
        @dispatched = ();
        $logs->buffer('');

        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_ };

        my $rv = LJ::send_mail(
            {
                to      => undef,
                toname  => 'Sensitive Display Name',
                from    => 'noreply@example.invalid',
                subject => 'SECRET_SUBJECT_TONAME',
                body    => 'SECRET_BODY_TONAME',
            }
        );

        is( $rv,                0, 'Returns 0 for undef to with toname' );
        is( scalar @dispatched, 0, 'Does not dispatch a SendEmail task' );
        is_deeply( \@warnings, [], 'Emits no Perl uninitialized warnings' );

        my $buf = $logs->buffer;
        like( $buf, qr/WARN LJ .*to=0 cc=0 bcc=0/, 'Logs diagnostic warning' );
        unlike( $buf, qr/Sensitive Display Name/, 'Does not log toname' );
        unlike( $buf, qr/SECRET_BODY_TONAME/,     'Does not log body' );
    };

    subtest 'LJ::send_mail rejects MIME::Lite with no recipients' => sub {
        @dispatched = ();
        $logs->buffer('');

        my $mime = MIME::Lite->new(
            From    => 'noreply@example.invalid',
            Subject => 'SECRET_MIME_SUBJECT',
            Data    => 'SECRET_MIME_BODY',
        );

        my $rv = LJ::send_mail($mime);
        is( $rv,                0, 'Returns 0 for MIME::Lite with no recipients' );
        is( scalar @dispatched, 0, 'Does not dispatch a SendEmail task' );

        my $buf = $logs->buffer;
        like( $buf, qr/WARN LJ .*input=MIME::Lite.*to=0 cc=0 bcc=0/, 'Logs MIME::Lite input' );
        unlike( $buf, qr/SECRET_MIME_SUBJECT/, 'Does not log MIME::Lite subject' );
        unlike( $buf, qr/SECRET_MIME_BODY/,    'Does not log MIME::Lite body' );
    };

    subtest 'LJ::send_mail allows BCC-only and normal messages' => sub {
        @dispatched = ();
        $logs->buffer('');

        my $rv_bcc = LJ::send_mail(
            {
                bcc     => 'bcc-recipient@example.invalid',
                from    => 'noreply@example.invalid',
                subject => 'BCC test',
                body    => 'Body',
            }
        );
        is( $rv_bcc, 1, 'Returns 1 for BCC-only mail' );

        my $rv_to = LJ::send_mail(
            {
                to      => 'to-recipient@example.invalid',
                from    => 'noreply@example.invalid',
                subject => 'To test',
                body    => 'Body',
            }
        );
        is( $rv_to,             1, 'Returns 1 for standard To mail' );
        is( scalar @dispatched, 2, 'Dispatches both valid tasks' );
        is_deeply( $dispatched[0]->args->[0]->{rcpts}, ['bcc-recipient@example.invalid'] );
        is_deeply( $dispatched[1]->args->[0]->{rcpts}, ['to-recipient@example.invalid'] );
        is( $logs->buffer, '', 'Emits no warning for valid recipients' );
    };

    subtest 'LJ::send_formatted_mail attributes real caller on empty to' => sub {
        @dispatched = ();
        $logs->buffer('');

        my $line = __LINE__ + 1;
        my $rv   = LJ::send_formatted_mail(
            to      => '',
            from    => 'noreply@example.invalid',
            subject => 'SECRET_FORMATTED_SUBJECT',
            body    => 'SECRET_FORMATTED_BODY',
        );

        is( $rv,                0, 'Returns 0 when send_formatted_mail has no recipient' );
        is( scalar @dispatched, 0, 'Does not dispatch a SendEmail task' );

        my $buf = $logs->buffer;
        like(
            $buf,
            qr/WARN LJ .*caller=main\/\Q$line\E/,
            'Attributes warning to send_formatted_mail caller rather than LJ::Sendmail'
        );
        unlike( $buf, qr/SECRET_FORMATTED_BODY/, 'Does not log formatted body' );
    };
}

subtest 'DW::Task::SendEmail handles missing, empty, and undef rcpts safely' => sub {
    local %LJ::SMTP_SERVER = ( hostname => 'smtp-fixture.invalid', plaintext => 1 );

    my ( @mail, @recipients, @messages );
    my $smtp = Test::MockObject->new;
    $smtp->mock( mail => sub { push @mail,       $_[1]; return 1; } );
    $smtp->mock( to   => sub { push @recipients, $_[1]; return 1; } );
    $smtp->mock( data => sub { return 1; } );
    $smtp->mock( datasend => sub { push @messages, $_[1]; return 1; } );
    $smtp->mock( dataend  => sub { return 1; } );

    no warnings qw( redefine once );
    local *Net::SMTP::new = sub { return $smtp; };

    for my $case (
        [ 'empty arrayref', [], 'ARRAY' ],
        [ 'undef rcpts',  undef,      'undef' ],
        [ 'scalar rcpts', 'not-aref', 'scalar' ],
        )
    {
        my ( $name, $rcpts, $expected_type ) = @$case;
        with_fake_memcache {
            @mail = @recipients = @messages = ();
            $logs->buffer('');

            my $task = DW::Task::SendEmail->new(
                {
                    env_from   => 'sender-secret@example.invalid',
                    rcpts      => $rcpts,
                    data       => "Subject: WORKER_SECRET_SUBJ\r\n\r\nWORKER_SECRET_BODY",
                    logger_mdc => { worker_case => $name },
                }
            );

            my $result = eval { $task->work('empty-rcpts-fixture') };
            is( $@,                 '',                  "$name: does not throw" );
            is( $result,            DW::Task::COMPLETED, "$name: completes without retry" );
            is( scalar @mail,       0,                   "$name: does not send MAIL FROM" );
            is( scalar @recipients, 0,                   "$name: does not send RCPT TO" );
            is( scalar @messages,   0,                   "$name: does not send DATA" );
            is( Log::Log4perl::MDC->get('worker_case'), undef, "$name: clears MDC" );

            my $buf = $logs->buffer;
            like(
                $buf,
qr/WARN DW\.Task\.SendEmail .*rcpts_type=\Q$expected_type\E has_env_from=1 has_data=1/,
                "$name: logs safe diagnostic metadata"
            );
            unlike( $buf, qr/WORKER_SECRET_SUBJ/,              "$name: does not log subject" );
            unlike( $buf, qr/WORKER_SECRET_BODY/,              "$name: does not log body" );
            unlike( $buf, qr/sender-secret\@example\.invalid/, "$name: does not log env_from" );
        };
    }

    with_fake_memcache {
        @mail = @recipients = @messages = ();
        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_ };

        my $task = DW::Task::SendEmail->new(
            {
                env_from => 'sender@example.invalid',
                rcpts    => [ undef, 'ok@example.invalid' ],
                data     => "Subject: Mixed undef\r\n\r\nBody",
            }
        );

        my $result = eval { $task->work('undef-elem-fixture') };
        is( $@, '', 'undef element: does not throw' );
        is( $result, DW::Task::COMPLETED, 'undef element: completes' );
        is_deeply( \@recipients, ['ok@example.invalid'], 'undef element: delivers valid address' );
        is_deeply( \@warnings, [], 'undef element: emits no Perl warnings' );
    };
};

subtest 'LJ::NotificationMethod::Email skips users without an email address' => sub {
    my $u = temp_user();
    $u->set_email('');

    @dispatched = ();
    $logs->buffer('');

    no warnings qw( redefine once );
    local $LJ::_T_EMAIL_NOTIFICATION = undef;
    local *DW::TaskQueue::dispatch   = sub {
        push @dispatched, $_[1];
        return 1;
    };

    my $meth = LJ::NotificationMethod::Email->new($u);
    my $ev   = LJ::Event::AddedToCircle->new( $u, $u, 2 );

    my $rv = eval { $meth->notify($ev) };
    is( $@,                 '', 'Does not die when user has no email address' );
    is( $rv,                1,  'Returns success without retrying' );
    is( scalar @dispatched, 0,  'Does not enqueue empty-recipient email' );

    my $uid = $u->id;
    like(
        $logs->buffer,
qr/WARN LJ\.NotificationMethod\.Email .*userid=\Q$uid\E.*evt_class=LJ::Event::AddedToCircle/,
        'Logs safe userid and event class warning'
    );
};

subtest 'LJ::Support::all_email_addresses omits empty addresses' => sub {
    my $u = temp_user();
    $u->set_email('');

    my @user_emails = LJ::Support::all_email_addresses(
        {
            spid      => 0,
            reqtype   => 'user',
            requserid => $u->id,
            reqemail  => '',
        }
    );
    is_deeply( \@user_emails, [], 'Returns empty list for user without email' );

    my @missing_user_emails = eval {
        LJ::Support::all_email_addresses(
            {
                spid      => 0,
                reqtype   => 'user',
                requserid => 0,
                reqemail  => '',
            }
        );
    };
    is( $@, '', 'Does not crash when requserid does not resolve to a user' );
    is_deeply( \@missing_user_emails, [], 'Returns empty list for missing user without reqemail' );

    my @email_req = LJ::Support::all_email_addresses(
        {
            spid     => 0,
            reqtype  => 'email',
            reqemail => '',
        }
    );
    is_deeply( \@email_req, [], 'Returns empty list for email request with empty reqemail' );
};

subtest 'DW::Task::SupportNotify skips volunteers without an email address' => sub {
    my $u = temp_user();
    $u->set_email('');

    @dispatched = ();
    $logs->buffer('');

    my $real_dbr = LJ::get_db_writer();
    my $fake_dbr = Test::MockObject->new;
    $fake_dbr->mock( selectcol_arrayref => sub { return [ $u->id ] } );
    $fake_dbr->mock(
        selectrow_array => sub {
            shift;
            return $real_dbr->selectrow_array(@_);
        }
    );

    no warnings qw( redefine once );
    local *DW::TaskQueue::dispatch = sub { push @dispatched, $_[1]; return 1; };
    local *LJ::get_db_writer       = sub { return $fake_dbr };
    local *LJ::Support::load_request = sub {
        return {
            spid    => 999999,
            reqtype => 'email',
            reqname => 'Fixture Requester',
            subject => 'Support Fixture',
            body    => 'Fixture body',
            _cat    => { spcatid => 1, catname => 'General' },
        };
    };
    local *LJ::User::should_receive_support_notifications = sub { return 1 };

    my $task = DW::Task::SupportNotify->new( { spid => 999999, type => 'new' } );
    my $rv   = eval { $task->work('support-notify-fixture') };
    is( $@, '', 'SupportNotify does not throw' );
    is( $rv, DW::Task::COMPLETED, 'SupportNotify completes' );
    is( scalar @dispatched, 0,  'Does not dispatch mail when no volunteer has email' );
    is( $logs->buffer,      '', 'Skips before calling LJ::send_mail' );
};

done_testing();
