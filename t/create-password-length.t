# t/create-password-length.t
#
# Password length errors must report the configured maximum.
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
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CreatePage;
local $LJ::DISABLED{password_check} = 0;
local $LJ::PASSWORD_MINLENGTH = 6;
my $seen;
{
    no warnings 'redefine';
    local *LJ::Lang::ml = sub {
        my ( $key, $params ) = @_;
        $seen = $params;
        return $key;
    };
    for my $maximum ( 72, 16 ) {
        local $LJ::PASSWORD_MAXLENGTH = $maximum;
        my $candidate = substr( 'mQ7!pZ2r' x 12, 0, $maximum );
        is( LJ::CreatePage->verify_password( password => $candidate ),
            undef, "configured maximum $maximum is accepted" );
        is(
            LJ::CreatePage->verify_password( password => $candidate . '8' ),
            'widget.createaccount.error.password.toolong',
            "one character beyond $maximum is rejected"
        );
        is_deeply(
            $seen,
            { maxlength => $maximum },
            "length error receives the configured maximum $maximum"
        );
    }
    is(
        LJ::CreatePage->verify_password( password => 'aB1!' ),
        'widget.createaccount.error.password.tooshort',
        'short passwords still rejected'
    );
    is(
        LJ::CreatePage->verify_password( password => '' ),
        'widget.createaccount.error.password.blank',
        'blank passwords still rejected'
    );
    is(
        LJ::CreatePage->verify_password( password => 'abcd1!' . chr(233) ),
        'widget.createaccount.error.password.asciionly',
        'non-ASCII passwords still rejected'
    );
}
done_testing;
