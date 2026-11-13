# t/plack-console-form-auth.t
#
# Recover console input after rejected form authentication without executing it.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::Entities qw(decode_entities);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::Console::Command::Print;
use DW::Auth::Challenge;

# Exercise real sessions and form checks, without development impersonation.
local $LJ::IS_DEV_SERVER = 0;
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $user       = temp_user();
my $other      = temp_user();
my $executions = 0;
my $execute    = \&LJ::Console::Command::Print::execute;

sub form_token {
    my ($response) = @_;
    for my $form ( $response->content =~ m{(<form\b[^>]*>.*?</form>)}sg ) {
        next unless $form =~ /<textarea\b[^>]*name=['"]commands['"]/;
        return ( $form =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/ )[0];
    }
    return undef;
}

sub commands_value {
    my ($response) = @_;
    my ($value) =
        $response->content =~ m{<textarea\b[^>]*name=['"]commands['"][^>]*>(.*?)</textarea>}s;
    return defined $value ? decode_entities($value) : undef;
}

with_fake_memcache {
    no warnings 'redefine';
    local *LJ::Console::Command::Print::execute = sub {
        $executions++;
        return $execute->(@_);
    };

    test_psgi $app, sub {
        my $cb     = shift;
        my $cookie = sub {
            my ($u) = @_;
            my $session = LJ::Session->create( $u, exptype => 'short', nolog => 1 )
                or die 'Unable to create console test session';
            return
                  'ljmastersession='
                . $session->master_cookie_string
                . '; ljloggedin='
                . $session->loggedin_cookie_string;
        };
        my $auth           = $cookie->($user);
        my $other_auth     = $cookie->($other);
        my $second_session = $cookie->($user);
        my $url            = 'http://localhost/admin/console/index';
        my $get            = sub { return $cb->( GET $url, Cookie => $_[0] ); };
        my $post           = sub {
            my ( $cookie, $token, $commands ) = @_;
            return $cb->(
                POST $url,
                Cookie  => $cookie,
                Content => [ lj_form_auth => $token, commands => $commands ]
            );
        };

        my $initial = $get->($auth);
        is( $initial->code,           200, 'authenticated console renders' );
        is( commands_value($initial), '',  'initial command input is empty' );
        my $valid = form_token($initial);
        ok( $valid, 'console supplies a signed form token' );
        my $expired =
            DW::Auth::Challenge->generate( -1, DW::Auth::Challenge->get_attributes($valid) );
        my $bad_signature = $valid;
        substr( $bad_signature, -1, 1 ) = substr( $valid, -1, 1 ) eq '0' ? '1' : '0';
        my $other_token = form_token( $get->($other_auth) );
        my $forged_user = $other_token;
        my $attributes  = DW::Auth::Challenge->get_attributes($forged_user);
        my @attributes  = split /-/, $attributes;
        $attributes[1] = $user->id;
        substr( $forged_user, index( $forged_user, $attributes ), length($attributes) ) = join '-',
            @attributes;
        my @rejected = (
            [ 'missing',           '' ],
            [ 'invalid signature', $bad_signature ],
            [ 'different user',    $other_token ],
            [ 'forged user ID',    $forged_user ],
        );
        my $commands = qq{print "</textarea><script>CONSOLE_MARKER</script> & text"\nprint second};

        for my $case (@rejected) {
            my ( $name, $token ) = @$case;
            subtest $name => sub {
                my $before   = $executions;
                my $response = $post->( $auth, $token, $commands );
                is( $executions,               $before, 'untrusted commands never execute' );
                is( commands_value($response), undef,   'untrusted input is not refilled' );
                is( form_token($response), undef,
                    'untrusted POST does not receive a console form' );
                unlike(
                    $response->content,
                    qr/CONSOLE_MARKER|Your commands were not run/,
                    'untrusted POST keeps the generic invalid-form error'
                );
            };
        }

        my $old_session_token = form_token( $get->($second_session) );
        my @recoverable       = (
            [ 'expired',           $expired ],
            [ 'different session', $old_session_token ],
            [
                'expired old session',
                DW::Auth::Challenge->generate(
                    -1, DW::Auth::Challenge->get_attributes($old_session_token)
                )
            ],
        );
        for my $case (@recoverable) {
            my ( $name, $token ) = @$case;
            subtest $name => sub {
                my $before   = $executions;
                my $response = $post->( $auth, $token, $commands );
                is( $response->code, 200,     'rejection redisplays the console form' );
                is( $executions,     $before, 'rejected commands never execute' );
                is( commands_value($response),
                    $commands, 'all submitted command text is recovered' );
                like(
                    $response->content,
                    qr/Your commands were not run/,
                    'rejection explains no execution'
                );
                like(
                    $response->content,
                    qr/class="alert-box alert" role="alert"/,
                    'recovery explanation uses the Foundation alert styling'
                );
                unlike( $response->content, qr/<script>CONSOLE_MARKER/,
                    'submitted markup stays text' );
                my $fresh = form_token($response);
                ok( $fresh, 'a replacement token is present' );
                isnt( $fresh, $token, 'replacement token differs from rejected token' );
                my $resubmit = $post->( $auth, $fresh, 'print CONSOLE_RESUBMITTED' );
                is( $resubmit->code, 200,         'explicit resubmission succeeds' );
                is( $executions,     $before + 1, 'explicit valid resubmission executes once' );
                like(
                    $resubmit->content,
                    qr/<span[^>]*>CONSOLE_RESUBMITTED<\/span>/,
                    'the real console command returns its result'
                );
                is( commands_value($resubmit),
                    '', 'success clears input to avoid accidental repetition' );
            };
        }

        my $fresh  = form_token( $get->($auth) );
        my $denied = $post->( $auth, $fresh, 'find_user_cluster ' . $other->user );
        like(
            $denied->content,
            qr/You are not authorized to run this command/,
            'valid form authentication does not grant command privileges'
        );
        my $before    = $executions;
        my $anonymous = $post->( '', form_token( $get->($auth) ), 'print CONSOLE_ANONYMOUS' );
        is( $executions, $before, 'anonymous requests cannot execute a console command' );
        unlike(
            $anonymous->content,
            qr/<textarea[^>]*name=['"]commands/,
            'anonymous requests do not receive a console form'
        );
    };
};

done_testing;
