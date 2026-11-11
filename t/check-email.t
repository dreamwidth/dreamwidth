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

plan tests => scalar @tests + 3;

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

subtest 'email rejections use translated messages' => sub {
    my @calls;
    no warnings 'redefine';
    local *LJ::Lang::ml = sub {
        my ( $key, $params ) = @_;
        push @calls, [ $key, $params || {} ];
        return "translated:$key";
    };
    my @cases = (
        [ '',                        'empty',        {} ],
        [ 'example.com',             'bad_form',     {} ],
        [ 'a,b@example.com',         'bad_username', {} ],
        [ 'example@a.baddomainname', 'bad_domain',   {} ],
        [
            ' Example@GMALI.COM ',
            'bad_spelling', { email => 'example@gmali.com', domain => 'gmail.com' }
        ],
        [ 'www.a@example.com', 'web_address', { email => 'www.a@example.com' } ],
    );
    for my $case (@cases) {
        my ( $email, $code, $params ) = @$case;
        my ( @errors, @codes );
        @calls = ();
        LJ::check_email( $email, \@errors, undef, undef, \@codes );
        is_deeply( \@errors, ["translated:email.check.$code"], "$code is translated" );
        is_deeply( \@codes, [$code], "$code retains its error code" );
        is_deeply(
            \@calls,
            [ [ "email.check.$code", $params ] ],
            "$code passes the expected translation parameters"
        );
    }
};

subtest 'spelling confirmation label is translated' => sub {
    no warnings 'redefine';
    local *LJ::Lang::ml = sub { return "translated:$_[0]" };
    for my $force ( 0, 1 ) {
        my ( @errors, @codes, $checkbox );
        LJ::check_email( 'example@gmali.com', \@errors, { force_spelling => $force },
            \$checkbox, \@codes );
        like(
            $checkbox,
            qr{<label for="force_spelling">translated:email.check.confirm</label>},
            "translated label remains associated with the checkbox (force=$force)"
        );
        is( !!( $checkbox =~ /checked="checked"/ ),
            !!$force, "checkbox retains its checked state (force=$force)" );
        is_deeply(
            \@codes,
            $force ? [] : ['bad_spelling'],
            "confirmation preserves spelling validation (force=$force)"
        );
    }
};

subtest 'valid addresses need no translated error' => sub {
    my @calls;
    no warnings 'redefine';
    local *LJ::Lang::ml = sub { push @calls, [@_]; return 'unexpected translation' };
    my ( @errors, @codes, $checkbox );
    LJ::check_email( 'example@example.com', \@errors, {}, \$checkbox, \@codes );
    is_deeply( \@errors, [], 'no errors for a valid address' );
    is_deeply( \@codes,  [], 'no error codes for a valid address' );
    is_deeply( \@calls,  [], 'no unnecessary translation calls' );
    is( $checkbox, undef, 'no spelling confirmation for a valid address' );
};
