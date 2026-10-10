#!/usr/bin/perl
#
# t/plack-image-dialog.t
#
# FCK image dialog access.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common;
use Plack::Test;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::IS_DEV_SERVER = 1;
my $u = temp_user();
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET '/imguploadrte' );
    unlike( $res->content, qr/id="txtUrl"/, 'anonymous cannot open insertion form' );

    # The vendored FCK editor JS opens the dialog at this path.
    $res = $cb->( GET '/stc/fck/editor/dialog/imguploadrte?as=' . $u->user );
    is( $res->code, 200, 'FCK dialog path opens for a logged-in user' );
    like( $res->content, qr/id="txtUrl"/, 'FCK dialog path renders the insertion form' );
};
done_testing;
