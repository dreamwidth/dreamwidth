# Image-preview standalone document and ancient-link compatibility.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
test_psgi $app, sub {
    my $cb = shift;
    for my $path ( '/imgpreview', '/imgpreview.bml' ) {
        my $res = $cb->( GET $path );
        is( $res->code, 200, "$path is anonymously available" );
        like( $res->content_type, qr{text/html},       'HTML document' );
        like( $res->content,      qr/id="imgPreview"/, 'image callback target' );
        like( $res->content,      qr/id="lnkPreview"/, 'link callback target' );
        like(
            $res->content,
            qr/window.parent.SetPreviewElements/,
            'parent initialization contract'
        );
        like( $res->content, qr/window.parent.UpdateOriginal/, 'image load callback' );
        unlike( $res->content, qr/id="(?:header|footer|content)"/, 'no site wrapper in iframe' );
    }
};
done_testing;
