# t/check-email.t
#
# Test email checking logic
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::User;

my @tests = (
    ['example@example.com'],
    ['EXAMPLE@EXAMPLE.COM'],

    # basic error-checking
    [ ' ',                 'empty' ],
    [ 'example.com',       'bad_form' ],
    [ 'a,b@example.com',   'bad_username' ],
    [ 'www.a@example.com', 'web_address' ],

    # domain name
    [ 'example@email.email', ],
    [ 'example@email.ph', ],
    [ 'example@a.baddomainname', 'bad_domain' ],

    # misspellings
    [ 'example@gmali.com',  'bad_spelling' ],
    [ 'example@yaaho.com',  'bad_spelling' ],
    [ 'example@hotmail.cm', 'bad_spelling' ],
    [ 'example@outlok.com', 'bad_spelling' ],
    [ 'example@aoll.com',   'bad_spelling' ],
    [ 'example@liev.com',   'bad_spelling' ],

);

plan tests => scalar @tests + 2;

sub check_email {
    my ( $email, $expected_error ) = @_;
    $expected_error ||= "";

    my @email_errors;
    LJ::check_email( $email, undef, undef, undef, \@email_errors );
    is_deeply(
        \@email_errors,
        $expected_error ? [$expected_error] : [],
        "checked '$email' with error '$expected_error'"
    );
}

foreach my $test (@tests) {
    check_email(@$test);
}

subtest 'rejections explain the problem to the user' => sub {
    my @cases = (
        [ '',                        'empty',        qr/cannot be blank/ ],
        [ 'example.com',             'bad_form',     qr/did not give a valid email address/ ],
        [ 'a,b@example.com',         'bad_username', qr/invalid characters/ ],
        [ 'example@a.baddomainname', 'bad_domain',   qr/domain is invalid/ ],

        # The message shows the normalized address and the suggested domain.
        [ ' Example@GMALI.COM ', 'bad_spelling', qr/example\@gmali\.com\b.*\bgmail\.com\?/ ],
        [ 'www.a@example.com',   'web_address',  qr/www\.a\@example\.com\b.*web address/ ],
    );
    for my $case (@cases) {
        my ( $email, $code, $message ) = @$case;
        my ( @errors, @codes );
        LJ::check_email( $email, \@errors, undef, undef, \@codes );
        is_deeply( \@codes, [$code], "$code: rejected with its error code" );
        is( scalar @errors, 1, "$code: one message for the user" );
        like( $errors[0], $message, "$code: the message describes the problem" );
    }
};

subtest 'spelling confirmation' => sub {
    for my $force ( 0, 1 ) {
        my ( @errors, @codes, $checkbox );
        LJ::check_email( 'example@gmali.com', \@errors, { force_spelling => $force },
            \$checkbox, \@codes );
        like(
            $checkbox,
            qr{id="force_spelling".*<label for="force_spelling">[^<]+</label>}s,
            "the checkbox has a label (force=$force)"
        );
        is( !!( $checkbox =~ /checked="checked"/ ),
            !!$force, "checkbox keeps its checked state (force=$force)" );
        is_deeply(
            \@codes,
            $force ? [] : ['bad_spelling'],
            "confirming overrides only the spelling check (force=$force)"
        );
    }

    my ( @errors, @codes, $checkbox );
    LJ::check_email( 'example@example.com', \@errors, {}, \$checkbox, \@codes );
    is( $checkbox, undef, 'a valid address gets no confirmation checkbox' );
};
