# t/plack-api-icons.t
#
# REST API icon endpoints.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use lib "$ENV{LJHOME}/t/lib";
use LJ::Userpic;
use DW::Test::API;

my ( $u,      $key )  = api_user();
my ( $viewer, $vkey ) = api_user();
my $base = '/users/' . $u->user . '/icons';

my ( $res, $body ) = api_request( GET => $base, key => $vkey );
is( $res->code, 200, 'list icons for a user with none' );
is_deeply( $body, [], 'empty list' );

sub make_icon {
    my ($file) = @_;
    open( my $fh, '<', "$ENV{LJHOME}/t/data/userpics/$file" ) or die "Can't open $file: $!";
    binmode $fh;
    my $data = do { local $/; <$fh> };
    return LJ::Userpic->create( $u, data => \$data );
}

my $icon = make_icon('good.png');
$icon->set_keywords('first');
$icon->set_comment('a comment');
my $bare   = make_icon('good.jpg');
my $hidden = make_icon('good.gif');
$hidden->set_keywords('hidden');
$u->suspend_userpic( $hidden->picid );

( $res, $body ) = api_request( GET => $base, key => $vkey );
is( $res->code, 200, 'list icons' );
is_deeply(
    [ sort { $a <=> $b } map { $_->{picid} } @$body ],
    [ sort { $a <=> $b } $icon->picid, $bare->picid ],
    'list leaves out the suspended icon'
);

( $res, $body ) = api_request( GET => "$base/" . $icon->picid, key => $vkey );
is( $res->code,        200,          'single icon' );
is( $body->{picid},    $icon->picid, 'picid' );
is( $body->{comment},  'a comment',  'comment' );
is( $body->{username}, $u->user,     'username' );
is_deeply( $body->{keywords}, ['first'], 'keywords' );

( $res, $body ) = api_request( GET => "$base/" . $bare->picid, key => $vkey );
is( $res->code, 200, 'icon with no comment or keywords' );

( $res, $body ) = api_request( GET => "$base/" . ( $icon->picid + 100000 ), key => $vkey );
is( $res->code, 404, 'unknown picid is a 404' );

( $res, $body ) = api_request( GET => '/users/nosuchuser0000/icons', key => $vkey );
is( $res->code, 404, 'unknown user is a 404' );

done_testing;
