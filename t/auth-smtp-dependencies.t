# t/auth-smtp-dependencies.t
#
# Verify SMTP authentication dependencies and the mechanisms used by SES.
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
use Authen::SASL;
use IO::Socket::INET;
use MIME::Base64 qw( encode_base64 decode_base64 );
use Net::SMTP;
use POSIX qw( _exit );

my $username = 'smtp-test@example.invalid';
my $password = 'smtp-test-password';

sub serve_auth {
    my ( $listener, $mechanism ) = @_;
    local $SIG{ALRM} = sub { die "SMTP fixture timed out\n"; };
    local $SIG{PIPE} = 'IGNORE';
    alarm 15;
    my $client = $listener->accept or die "SMTP accept: $!";
    $client->autoflush(1);
    print $client "220 localhost test SMTP\r\n";
    my $hello = <$client> // die "No SMTP greeting";
    die "Expected EHLO" unless $hello =~ /^EHLO /;
    print $client "250-localhost\r\n250 AUTH $mechanism\r\n";

    my $auth = <$client> // die "No AUTH command";
    $auth =~ s/\r?\n$//;
    my ( $received_user, $received_password );
    if ( $mechanism eq 'PLAIN' ) {
        die "Expected AUTH PLAIN" unless $auth =~ /^AUTH PLAIN(?: (\S+))?$/;
        my $response = $1;
        unless ( defined $response ) {
            print $client "334 \r\n";
            $response = <$client> // die "No PLAIN response";
        }
        ( undef, $received_user, $received_password ) = split /\0/, decode_base64($response), -1;
    }
    else {
        die "Expected AUTH LOGIN" unless $auth =~ /^AUTH LOGIN(?: (\S+))?$/;
        my $response = $1;
        unless ( defined $response ) {
            print $client '334 ' . encode_base64( 'Username:', '' ) . "\r\n";
            $response = <$client> // die "No LOGIN username";
        }
        $received_user = decode_base64($response);
        print $client '334 ' . encode_base64( 'Password:', '' ) . "\r\n";
        $received_password = decode_base64( scalar <$client> // die "No LOGIN password" );
    }
    die "Credentials did not survive $mechanism authentication"
        unless $received_user eq $username && $received_password eq $password;
    print $client "235 Authentication successful\r\n";

    my $quit = <$client> // die "No QUIT command";
    die "Expected QUIT" unless $quit =~ /^QUIT\r?\n$/;
    print $client "221 Bye\r\n";
    close $client;
    close $listener;
    alarm 0;
}

for my $mechanism ( 'PLAIN', 'LOGIN' ) {
    subtest $mechanism => sub {
        my $listener = IO::Socket::INET->new(
            LocalAddr => '127.0.0.1',
            LocalPort => 0,
            Listen    => 1,
            ReuseAddr => 1,
        ) or BAIL_OUT("Cannot start loopback SMTP fixture: $!");
        my $port = $listener->sockport;
        my $pid  = fork();
        BAIL_OUT("Cannot fork SMTP fixture: $!") unless defined $pid;
        unless ($pid) {
            my $ok = eval { serve_auth( $listener, $mechanism ); 1 };
            warn $@ unless $ok;
            _exit( $ok ? 0 : 1 );
        }
        close $listener;

        # This is the same Net::SMTP auth API the mail worker uses. Only the
        # loopback fixture sees these synthetic credentials; no mail is sent.
        my $smtp = Net::SMTP->new( Host => '127.0.0.1', Port => $port, Timeout => 5 );
        ok( $smtp, 'Connected to the loopback SMTP fixture' );
        if ($smtp) {
            ok( $smtp->auth( $username, $password ),
                'Authenticated using the advertised mechanism' );
            ok( $smtp->quit, 'Closed the SMTP connection' );
        }
        else {
            fail('Authentication could not run');
            fail('QUIT could not run');
            kill 'TERM', $pid;
        }
        waitpid( $pid, 0 );
        is( $?, 0, 'Fixture verified the decoded credentials and protocol' );
    };
}

done_testing();
