# t/plack-rpc-addcomment.t
#
# Regression test for the /__rpc_addcomment quick-reply endpoint: a logged-out
# POST that carries a valid form-auth token must return the login requirement,
# not a 500 from dereferencing the absent remote. The guard returns before any
# comment is created, so this path touches no moderation side effects to stub.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# ?as= impersonation is dev-only; form auth binds to a fixed uniq below.
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'rpcAddCommentTest';

test_psgi $app, sub {
    my $cb = shift;

    # Mint a form-auth token bound to the logged-out viewer and the fixed uniq,
    # which is what the app recomputes for the ?as=<invalid> request.
    LJ::set_remote(undef);
    delete $LJ::REQ_GLOBAL{form_auth_chal};
    my $form_auth = LJ::form_auth(1);

    my $res = $cb->(
        POST "http://localhost/__rpc_addcomment?as=nobody_exists",
        Content => [
            lj_form_auth => $form_auth,
            journal      => 'nobody_exists',
            itemid       => 1,
            parenttalkid => 0,
            subject      => 'reply subject',
            body         => 'reply body',
        ],
    );

    is( $res->code, 200, 'logged-out quick-reply POST does not 500' );
    unlike( $res->content, qr/Can't call method/, 'response is not the undef-remote deref error' );
    like( $res->content, qr/"error"/, 'response is a JSON error, not a posted comment' );
};

done_testing();
