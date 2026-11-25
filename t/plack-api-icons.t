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
use JSON;
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

# Names a decoded JSON boolean, so that a number or string fails a comparison.
sub bool_name {
    my ($value) = @_;
    return '<not a JSON boolean>' unless JSON::is_bool($value);
    return $value ? 'true' : 'false';
}

# Returns { picid => 'true' or 'false' } for the icons the list endpoint shows.
sub listed_defaults {
    my ($apikey) = @_;
    my ( undef, $list ) = api_request( GET => $base, key => $apikey );
    return { map { $_->{picid} => bool_name( $_->{default} ) } @$list };
}

sub icon_default {
    my ( $picid, $apikey ) = @_;
    my ( undef, $single ) = api_request( GET => "$base/$picid", key => $apikey );
    return bool_name( $single->{default} );
}

subtest 'default flag' => sub {
    my ( $first, $second ) = ( $icon->picid, $bare->picid );

    is_deeply(
        listed_defaults($vkey),
        { $first => 'false', $second => 'false' },
        'no icon is the default when the account has none'
    );
    ( $res, $body ) = api_request( GET => "$base/$first", key => $vkey );
    is_deeply(
        [ sort keys %$body ],
        [qw( comment default keywords picid url username )],
        'fields another user sees, on an account with no default'
    );

    $icon->make_default;
    is_deeply(
        listed_defaults($vkey),
        { $first => 'true', $second => 'false' },
        'only the default icon is flagged in the list'
    );
    is( icon_default( $first,  $vkey ), 'true',  'single default icon' );
    is( icon_default( $second, $vkey ), 'false', 'single icon that is not the default' );
    is_deeply(
        listed_defaults($key),
        { $first => 'true', $second => 'false' },
        'owner sees the same flags'
    );

    $bare->make_default;
    is_deeply(
        listed_defaults($vkey),
        { $first => 'false', $second => 'true' },
        'flag follows a change of default'
    );
};

# API key requests have no remote user, so set one to check who TO_JSON shows
# what. It recognises the owner by object identity, hence $own_icon->u below.
subtest 'inactive stays owner-only beside the default flag' => sub {
    my $own_icon = LJ::Userpic->get( $u, $bare->picid );

    LJ::set_remote($viewer);
    my $seen = $own_icon->TO_JSON;
    ok( !exists $seen->{inactive}, 'another user is not told whether an icon is inactive' );
    is( bool_name( $seen->{default} ), 'true', 'another user is told it is the default' );

    LJ::set_remote( $own_icon->u );
    $seen = $own_icon->TO_JSON;
    ok( exists $seen->{inactive}, 'owner is told whether an icon is inactive' );
    is( bool_name( $seen->{default} ), 'true', 'owner is told it is the default' );

    LJ::set_remote(undef);
};

subtest 'icon embedded in an entry' => sub {
    my $entries = '/journals/' . $u->user . '/entries';

    # $bare is the default here; 'first' is the keyword of $icon.
    ( $res, $body ) =
        api_request( POST => $entries, key => $key, json => { text => 'a', icon => 'first' } );
    my $with_keyword = $body->{entry_id};
    ( $res, $body ) = api_request( POST => $entries, key => $key, json => { text => 'b' } );
    my $with_default = $body->{entry_id};

    ( $res, $body ) = api_request( GET => "$entries/$with_keyword", key => $vkey );
    is( $body->{icon}{picid},                $icon->picid, 'entry uses the icon it named' );
    is( bool_name( $body->{icon}{default} ), 'false',      'which is not the default' );

    ( $res, $body ) = api_request( GET => "$entries/$with_default", key => $vkey );
    is( $body->{icon}{picid}, $bare->picid, 'entry with no keyword uses the default icon' );
    is( bool_name( $body->{icon}{default} ), 'true', 'which is flagged as the default' );

    ( $res, $body ) = api_request( GET => $entries, key => $vkey );
    is_deeply(
        { map { $_->{entry_id} => bool_name( $_->{icon}{default} ) } @$body },
        { $with_keyword => 'false', $with_default => 'true' },
        'entry list carries the flag too'
    );

    $icon->make_default;
    ( $res, $body ) = api_request( GET => "$entries/$with_keyword", key => $vkey );
    is( bool_name( $body->{icon}{default} ),
        'true', 'flag reflects the current default, not the one at posting time' );
};

done_testing;
