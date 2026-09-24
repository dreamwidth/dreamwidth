#!/usr/bin/perl
# Proves LJ::Protocol.pm:563's LJ::Lang::set_request_context(lang => 'en',
# getter => undef) call in sendmessage forces English and discards any
# getter already on the request, not just the language.
#
# Message sending between two disposable temp users is not a moderation
# action (no report/ban/sysban call is on this path): the chosen failure --
# LJ::Message::can_send's error.message.individual, from sending to a
# community, which is neither a person nor an identity account -- returns
# before LJ::Message::send is ever called (LJ::Message.pm's can_send returns
# false at its very first check, so the caller's "push @msg, $msg if
# $msg->can_send(...)" never adds it to the send list), so nothing gets
# persisted or delivered. Grepped LJ::Protocol::sendmessage,
# LJ::Protocol::authenticate, and LJ::Message::new/can_send for
# sysban/report/ban/moderation calls before choosing this path: none found.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use LJ::Test qw(temp_user temp_comm);

sub request {
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        }
    );
}

subtest
    'sendmessage forces both the language AND the getter, and it persists after sendmessage returns'
    => sub {
    my @calls;
    request();
    LJ::Lang::set_request_context(
        lang   => 'ru',
        getter => sub {
            push @calls, [ $_[0], $_[1] ];
            return "$_[0]:$_[1]";
        },
    );

    is( LJ::Lang::ml('error.message.individual'),
        'ru:error.message.individual',
        'before sendmessage: the request language (ru) and custom getter are both active' );
    @calls = ();    # isolate calls made during/after sendmessage from this sanity check

    my $sender = temp_user();
    $sender->update_self( { status => 'A' } );
    my $comm = temp_comm();

    my $real_english = LJ::Lang::get_text( 'en', 'error.message.individual',
        undef, { ljuser => $comm->ljuser_display } );

    my $err = '';
    my $res = LJ::Protocol::sendmessage(
        {
            username => $sender->user,
            to       => $comm->user,
            subject  => 'test subject',
            body     => 'test body',
        },
        \$err,
        { noauth => 1, u => $sender }
    );
    is( $res, undef, 'sendmessage fails as expected (community cannot receive a private message)' );

    # LJ::Protocol.pm:563 forces LJ::Lang::set_request_context(lang => 'en',
    # getter => undef) directly -- explicitly overwriting the existing getter
    # key, not just the language. LJ::Lang::ml()'s own fallback
    # ($context->{getter} || \&LJ::Lang::get_text) then uses the real native
    # getter. So the failure text is genuine, properly-translated English --
    # not the ru language, and not routed through the custom recorder getter
    # installed above -- proving the call clobbers both, not only the
    # language.
    is( $err, "203:$real_english",
'the failure error carries genuine English text, not ru and not the custom recorder\'s format'
    ) or diag("err was: $err");
    is( scalar(@calls), 0,
'the custom getter installed before sendmessage never fires for this lookup -- it was overwritten'
    );
    is( LJ::Lang::request_context()->{getter},
        undef, 'the request getter is explicitly undef after sendmessage' );

    is(
        LJ::Lang::ml('error.message.individual'),
        LJ::Lang::get_text( 'en', 'error.message.individual' ),
'after sendmessage returns, the request is still on English with the real getter -- neither ru nor the custom recorder was restored'
    );
    };

subtest 'forcing English with no active request is a safe no-op' => sub {
    DW::Request->reset;
    ok( !LJ::Lang::request_context(), 'no request context exists before the call' );
    ok( eval { LJ::Lang::set_request_context( lang => 'en', getter => undef ); 1 },
        'set_request_context does not die with no active request' )
        or diag("died: $@");
    ok( !LJ::Lang::request_context(),
        'no request context is created: set_request_context early-returns without a DW::Request' );
    is( LJ::Lang::get_effective_lang(),
        $LJ::DEFAULT_LANG,
        'LJ::Lang::ml falls back to the configured default language with no request to force' );
};

done_testing;
