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

plan tests => scalar @tests;

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
