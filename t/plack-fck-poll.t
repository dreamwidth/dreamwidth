# FCK poll dialog route and standalone callback contract.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::IS_DEV_SERVER = 1;
test_psgi $app, sub {
    my $cb = shift;
    for my $path ( '/tools/fck_poll', '/tools/fck_poll.bml' ) {
        my $res = $cb->( GET $path );
        is( $res->code, 200, "$path remains available" );
        like( $res->content_type, qr{text/html},             'HTML document' );
        like( $res->content,      qr{fck_dialog_common\.js}, 'FCK dialog callback helper' );
        like( $res->content,      qr{(?:/js|/fck)/poll\.js}, 'poll model resource' );
        like( $res->content,      qr{name="question_0"},     'first question field retained' );
        like( $res->content,      qr{LJPollCommand\.Add},    'editor insertion callback retained' );
        unlike( $res->content, qr{id="(?:header|footer|content)"}, 'standalone document' );
        $res = $cb->( POST $path, Content => [] );
        is( $res->code, 200, 'POST redisplays without publishing or mutation' );
    }
};
done_testing;
