# t/task-send-email-recipients.t
#
# Test recipient filtering before the mail worker submits an SMTP envelope.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( with_fake_memcache );
use DW::Task::SendEmail;

local %LJ::SMTP_SERVER           = ( hostname          => 'smtp-fixture.invalid', plaintext => 1 );
local %LJ::DISALLOW_EMAIL_DOMAIN = ( 'blocked.invalid' => 1 );

my ( @mail, @recipients, @messages );
my $smtp = Test::MockObject->new;
$smtp->mock( mail => sub { push @mail,       $_[1]; return 1; } );
$smtp->mock( to   => sub { push @recipients, $_[1]; return 1; } );
$smtp->mock( data => sub { return 1; } );
$smtp->mock( datasend => sub { push @messages, $_[1]; return 1; } );
$smtp->mock( dataend  => sub { return 1; } );

{
    no warnings qw( redefine once );
    local *Net::SMTP::new = sub { return $smtp; };

    my @cases = (
        [ 'empty list',        [],                            [] ],
        [ 'empty address',     [''],                          [] ],
        [ 'malformed address', ['not-an-address'],            [] ],
        [ 'blocked domain',    ['recipient@blocked.invalid'], [] ],
        [ 'valid address',     ['recipient@example.invalid'], ['recipient@example.invalid'] ],
        [
            'invalid before valid',
            [ '', 'recipient@example.invalid' ],
            ['recipient@example.invalid']
        ],
        [
            'invalid after valid',
            [ 'recipient@example.invalid', '' ],
            ['recipient@example.invalid']
        ],
        [
            'blocked before valid',
            [ 'a@blocked.invalid', 'recipient@example.invalid' ],
            ['recipient@example.invalid']
        ],
        [
            'blocked after valid',
            [ 'recipient@example.invalid', 'a@blocked.invalid' ],
            ['recipient@example.invalid']
        ],
        [
            'duplicate valid addresses',
            [ 'recipient@example.invalid', 'recipient@example.invalid' ],
            ['recipient@example.invalid']
        ],
    );

    for my $case (@cases) {
        my ( $name, $input, $expected ) = @$case;
        subtest $name => sub {
            with_fake_memcache {
                my $task = DW::Task::SendEmail->new(
                    {
                        env_from   => 'sender@example.invalid',
                        rcpts      => $input,
                        data       => "Subject: Recipient filtering\r\n\r\nFixture body",
                        logger_mdc => { recipient_fixture => 'active' },
                    }
                );
                my $check = sub {
                    my ($wanted) = @_;
                    @mail = @recipients = @messages = ();
                    my $result = eval { $task->work('recipient-fixture'); };
                    is( $@, '', 'Filtering does not throw' );
                    is( $result, DW::Task::COMPLETED, 'Task completes without a retry' );
                    is_deeply(
                        [ sort @recipients ],
                        [ sort @$wanted ],
                        'Only allowed recipients reach SMTP'
                    );
                    is(
                        scalar @mail,
                        @$wanted ? 1 : 0,
                        'No envelope is submitted without recipients'
                    );
                    is(
                        scalar @messages,
                        @$wanted ? 1 : 0,
                        'Message is submitted only when needed'
                    );
                    is( Log::Log4perl::MDC->get('recipient_fixture'),
                        undef, 'Logger context is cleared' );
                };
                $check->($expected);

                # A delivered message must still be suppressed on redelivery.
                $check->( [] ) if @$expected;
            };
        };
    }
}

done_testing();
