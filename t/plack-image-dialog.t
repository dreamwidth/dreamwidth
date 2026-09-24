#!/usr/bin/perl
#
# t/plack-image-dialog.t
#
# FCK image dialog permissions and embedding contract.
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
    for my $path (
        '/imguploadrte',                       '/imguploadrte.bml',
        '/stc/fck/editor/dialog/imguploadrte', '/stc/fck/editor/dialog/imguploadrte.bml'
        )
    {
        my $url = "$path?as=" . $u->user;
        $res = $cb->( GET $url);
        is( $res->code, 200, "$path opens authenticated" );
        like( $res->content_type, qr{text/html}, 'HTML' );
        for my $id (qw(txtUrl txtAlt txtWidth txtHeight txtLnkUrl txtAttId txtAttClasses)) {
            like( $res->content, qr/id="$id"/, "FCK $id field preserved" );
        }
        like( $res->content, qr{src="[^"]*/imgpreview"},  'preview iframe' );
        like( $res->content, qr{fck_image/fck_image\.js}, 'dialog callbacks' );
        like(
            $res->content,
            qr{id="txtAlt" style="WIDTH: 80%"},
            'legacy path reaches the native standalone template rather than a static duplicate'
        );
        unlike( $res->content, qr{id="(?:header|footer|content)"}, 'standalone document' );
        $res = $cb->( POST $url, Content => [] );
        is( $res->code, 200, "$path render-only POST redisplays without mutating" );
        like(
            $res->content,
            qr{id="txtAlt" style="WIDTH: 80%"},
            "$path render-only POST reaches the native standalone template"
        );
    }
};
done_testing;
