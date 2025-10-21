# t/captcha-textcaptcha.t
#
# Test DW::Captcha with text-based CAPTCHA.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 27;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Captcha;
use XML::Simple;
use LJ::Test;

my $fakeanswers_single = {
    question => 'The white bank is what colour?',
    answer   => ['d508fe45cecaf653904a0e774084bb5c'],
};

my $fakeanswers_multiple = {
    question => 'If I have twelve monkeys, how many monkeys do I have?',
    answer   => [
        "c20ad4d76fe97759aa27a0c99bff6710",    # 12
        "15f6f8dc036519d7fe15b39338f6e5db",    # twelve
    ],
};

my $fakeanswers_zeroes = {
    question => 'What is the third digit of 1304873111?',
    answer   => [
        "cfcd208495d565ef66e7dff9f98764da",    # 0
        "d02c4c4cde7ae76252540d116a40f23a",    # zero
    ],
};

# convenience method to generate and handle answers for the captcha
# to make multiple inputs to the test easier to understand
sub _run_test {
    local $Test::Builder::Level = $Test::Builder::Level + 2;

    my ( $content, $auth, $answer, $testmsg, $fail ) = @_;

    subtest "generating and testing captcha" => sub {

    # generate new captcha auth for each, because we can't reuse captcha on this form
    # note: we can reuse the form auth! might have a need to pull in alternate captcha for same form
        my $captcha = DW::Captcha::textCAPTCHA::Logic::form_data( $content, $auth );
        my $checked =
            DW::Captcha::textCAPTCHA::Logic::check_answer( _get_answers($captcha), $answer, $auth,
            $captcha->{chal} );

        $fail ? ok( !$checked, $testmsg ) : ok( $checked, $testmsg );
    }
}

sub _get_answers {
    my $captcha = $_[0];
    return [ split( ":", $captcha->{answers} ) ];
}

note("single answer");
{
    LJ::start_request();
    my $content = $fakeanswers_single;
    my $auth    = LJ::form_auth(1);
    my $captcha = DW::Captcha::textCAPTCHA::Logic::form_data( $content, $auth );

   # we want the question to be the same
   # but we know the answer will be different -- we don't know and don't care what it will be though
    is(
        $captcha->{question},
        $fakeanswers_single->{question},
        "got back the question for use in a form"
    );
    isnt(
        _get_answers($captcha)->[0],
        $fakeanswers_single->{answer},
        "got back an answer for use in a form (which does not look like what we put in)"
    );

    isnt( $captcha->{chal}, $auth, "Form auth and captcha auth are not the same" );

    my $test_captcha = sub {
        my ( $answer, $msg, %opts ) = @_;
        return _run_test( $content, $auth, $answer, $msg, $opts{fail} ? 1 : 0 );
    };

    # now validate user responses
    $test_captcha->( "blue", "completely incorrect", fail => 1 );
    $test_captcha->( "white",  "correct" );
    $test_captcha->( "WHITE",  "correct (caps)" );
    $test_captcha->( "white ", "correct (whitespace)" );

    LJ::start_request();
    $captcha = DW::Captcha::textCAPTCHA::Logic::form_data( $content, $auth );
    ok(
        !DW::Captcha::textCAPTCHA::Logic::check_answer(
            _get_answers($captcha), "white", LJ::form_auth(1), $captcha->{chal}
        ),
        "incorrect (auth; tried to submit captcha on a different form?)"
    );
}

note("multiple valid answers");
{
    LJ::start_request();
    my $content = $fakeanswers_multiple;
    my $auth    = LJ::form_auth(1);
    my $captcha = DW::Captcha::textCAPTCHA::Logic::form_data( $content, $auth );

    my %original_answers = map { $_ => 1 } @{ $fakeanswers_multiple->{answer} };
    is(
        $captcha->{question},
        $fakeanswers_multiple->{question},
        "got back the question for use in a form"
    );

    foreach ( @{ _get_answers($captcha) } ) {
        ok( !$original_answers{$_},
            "one ofs multiple answers for use in a form (which does not look like what we put in)"
        );
    }

    my $test_captcha = sub {
        my ( $answer, $msg, %opts ) = @_;
        return _run_test( $content, $auth, $answer, $msg, $opts{fail} ? 1 : 0 );
    };

    # now validate user responses
    $test_captcha->( "12",     "correct ('12' is one of the valid choices)" );
    $test_captcha->( "twelve", "correct ('twelve' is another of the valid choices)" );
    $test_captcha->( "a dozen", "incorrect ('a dozen' is not one of the valid choices)",
        fail => 1 );
};

note("make sure zero is a valid answer");
{
    LJ::start_request();
    my $content = $fakeanswers_zeroes;
    my $auth    = LJ::form_auth(1);
    my $captcha = DW::Captcha::textCAPTCHA::Logic::form_data( $content, $auth );

    my %original_answers = map { $_ => 1 } @{ $fakeanswers_zeroes->{answer} };
    is(
        $captcha->{question},
        $fakeanswers_zeroes->{question},
        "got back the question for use in a form"
    );

    foreach ( @{ _get_answers($captcha) } ) {
        ok( !$original_answers{$_},
            "one of multiple answers for use in a form (which does not look like what we put in)" );
    }

    my $test_captcha = sub {
        my ( $answer, $msg, %opts ) = @_;
        return _run_test( $content, $auth, $answer, $msg, $opts{fail} ? 1 : 0 );
    };

    # now validate user responses
    $test_captcha->( 0,       "correct ('0' is one of the valid choices)" );
    $test_captcha->( "zero",  "correct ('zero' is another of the valid choices)" );
    $test_captcha->( "zilch", "incorrect ('zilch' is not one of the valid choices)", fail => 1 );
};

note("no form auth passed in");
{
    my $content      = $fakeanswers_single;
    my $captcha      = DW::Captcha::textCAPTCHA::Logic::form_data( $content, "" );
    my $captcha_auth = $captcha->{chal};

   # we want the question to be the same
   # but we know the answer will be different -- we don't know and don't care what it will be though
    is(
        $captcha->{question},
        $fakeanswers_single->{question},
        "got back the question for use in a form"
    );
    isnt(
        _get_answers($captcha)->[0],
        $fakeanswers_single->{answer},
        "got back an answer for use in a form (which does not look like what we put in)"
    );

    # now validate user response
    ok(
        !DW::Captcha::textCAPTCHA::Logic::check_answer(
            _get_answers($captcha), "white", "", $captcha_auth
        ),
        "correct answer, but we have no auth"
    );
};

note("tried to reuse captcha + form_auth");
{
    LJ::start_request();
    my $content      = $fakeanswers_single;
    my $auth         = LJ::form_auth(1);
    my $captcha      = DW::Captcha::textCAPTCHA::Logic::form_data( $content, $auth );
    my $captcha_auth = $captcha->{chal};

   # we want the question to be the same
   # but we know the answer will be different -- we don't know and don't care what it will be though
    is(
        $captcha->{question},
        $fakeanswers_single->{question},
        "got back the question for use in a form"
    );
    isnt(
        _get_answers($captcha)->[0],
        $fakeanswers_single->{answer},
        "got back an answer for use in a form (which does not look like what we put in)"
    );

    # now validate user response
    ok(
        DW::Captcha::textCAPTCHA::Logic::check_answer(
            _get_answers($captcha), "white", $auth, $captcha_auth
        ),
        "correct"
    );

    # whoo captcha succeeded! let's try to reuse it
SKIP: {
        skip "Memcache configured but not active.", 1 unless LJ::Test::check_memcache;
        LJ::start_request();
        ok(
            !DW::Captcha::textCAPTCHA::Logic::check_answer(
                _get_answers($captcha), "white", $auth, $captcha_auth
            ),
            "tried to reuse captcha results"
        );
    }
};
