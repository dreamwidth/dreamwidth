# t/plack-media-edit.t
#
# Test sorting and pagination on the bulk image editor.
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
use HTML::Entities qw(decode_entities);
use HTTP::Request::Common;
use Plack::Test;
use URI;
use URI::QueryParam;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die "Failed to load app.psgi: $@ $!" unless ref $app eq 'CODE';

my $owner  = temp_user();
my $viewer = temp_user();

END {
    if ($owner) {
        my $status = $?;
        for my $table (qw(media_versions media)) {
            $owner->do( "DELETE FROM $table WHERE userid = ?", undef, $owner->id )
                or die $owner->errstr;
        }
        $? = $status;
    }
}

for my $mediaid ( 1 .. 21 ) {
    my $bytes = $mediaid == 2 ? 5000 : $mediaid == 20 ? 100 : 700;
    my $width = $mediaid == 2 ? 400  : 100;
    $owner->do(
        q{INSERT INTO media (userid, mediaid, anum, ext, state, mediatype, security,
            allowmask, logtime, mimetype, filesize)
          VALUES (?, ?, 0, 'png', 'A', 1, 'private', 0, ?, 'image/png', ?)},
        undef, $owner->id, $mediaid, 1_700_000_000 + $mediaid, $bytes
    ) or die $owner->errstr;
    $owner->do(
        q{INSERT INTO media_versions (userid, mediaid, versionid, width, height, filesize)
          VALUES (?, ?, ?, ?, ?, ?)},
        undef, $owner->id, $mediaid, $mediaid, $width, $width, $bytes
    ) or die $owner->errstr;
}

$owner->do(
    q{INSERT INTO media_versions (userid, mediaid, versionid, width, height, filesize)
      VALUES (?, 2, 22, 200, 200, 80)}, undef, $owner->id
) or die $owner->errstr;

sub image_ids {
    my ($response) = @_;
    return [ map { $_ >> 8 } $response->decoded_content =~ /\bid=['"]edit-title-(\d+)['"]/g ];
}

sub edit_links {
    my ($response) = @_;
    return grep { $_->path eq '/file/edit' }
        map     { URI->new( decode_entities($_) ) }
        $response->decoded_content =~ /<a\b[^>]*\bhref="([^"]+)"/g;
}

my $edit      = 'http://localhost/file/edit';
my $mine      = "$edit?as=" . $owner->user;
my @newest    = reverse 2 .. 21;
my @same_size = grep { $_ != 2 && $_ != 20 } reverse 1 .. 21;

local $LJ::IS_DEV_SERVER = 1;
local $LJ::CAP_DEF{media_file_quota} = 500;
test_psgi $app, sub {
    my $request = shift;

    my $default = $request->( GET $mine );
    is( $default->code, 200, 'owner can open the bulk editor' );
    is_deeply( image_ids($default), \@newest, 'the default is newest first' );
    is_deeply(
        image_ids( $request->( GET "$mine&sort=oldest" ) ),
        [ 1 .. 20 ],
        'oldest uploads come first'
    );
    is_deeply(
        image_ids( $request->( GET "$mine&sort=largest" ) ),
        [ 2, @same_size ],
        'largest original comes first even with the smallest thumbnail'
    );
    is_deeply(
        image_ids( $request->( GET "$mine&sort=smallest" ) ),
        [ 20, @same_size ],
        'smallest original comes first'
    );

    my $first = $request->( GET "$mine&sort=oldest&security=private" );
    my ($next) = grep { ( $_->query_param('page') // '' ) eq '2' } edit_links($first);
    ok( $next, 'first page links to the second' );
    if ($next) {
        is( $next->query_param('sort'),     'oldest',  'pagination keeps the sort' );
        is( $next->query_param('security'), 'private', 'pagination keeps other query arguments' );
        my $second = $request->( GET "$next" );
        is_deeply( image_ids($second), [21], 'page two continues the oldest-first order' );

        my ($action) = $second->decoded_content =~ /<form id="media-manage"[^>]+action="([^"]+)"/;
        my $post_uri = URI->new( decode_entities( $action // '' ) );
        is( $post_uri->query_param('sort'), 'oldest', 'the bulk POST action retains the sort' );
        is( $post_uri->query_param('page'), '2',      'the bulk POST action retains the page' );

        my ($largest) = grep { ( $_->query_param('sort') // '' ) eq 'largest' } edit_links($second);
        ok( $largest, 'page two links to the largest-first sort' );
        if ($largest) {
            ok( !$largest->query_param('page'), 'changing sort starts at the first page' );
            is( $largest->query_param('security'),
                'private', 'changing sort keeps other arguments' );
        }
    }

    my $invalid = $request->( GET "$mine&sort=not-a-sort" );
    is( $invalid->code, 200, 'unknown sort still renders the editor' );
    is_deeply( image_ids($invalid), \@newest, 'unknown sort falls back to newest first' );
    ok( !grep( { ( $_->query_param('sort') // '' ) eq 'not-a-sort' } edit_links($invalid) ),
        'navigation does not carry an invalid sort forward' );

    my $anonymous = $request->( GET "$edit?sort=largest" );
    like( $anonymous->header('Location'), qr{/login\?}, 'anonymous requests require login' );
    my $other =
        $request->( GET "$edit?as=" . $viewer->user . '&sort=largest&user=' . $owner->user );
    is( $other->code, 200, 'another user can open their own editor' );
    is_deeply( image_ids($other), [],
        'the user parameter cannot expose images from another account' );

    $request->(
        POST "$mine&sort=oldest&page=2",
        [ 'action:edit' => 1, 'security-5376' => 'public' ]
    );
    my ($security) =
        $owner->selectrow_array( 'SELECT security FROM media WHERE userid = ? AND mediaid = 21',
        undef, $owner->id );
    is( $security, 'private', 'a sorted bulk edit still requires form authentication' );
};

done_testing;
