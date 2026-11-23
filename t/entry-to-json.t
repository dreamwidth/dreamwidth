# t/entry-to-json.t
#
# Test LJ::Entry::TO_JSON, which builds the entry representation returned by
# the REST API.
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
use JSON;
use LJ::Entry;
use LJ::Protocol;
use LJ::Test qw(temp_user);

my $u     = temp_user();
my $other = temp_user();

sub post {
    my (%extra) = @_;
    my $err     = 0;
    my $res     = LJ::Protocol::do_request(
        'postevent',
        {
            ver      => $LJ::PROTOCOL_VER,
            username => $u->user,
            event    => 'body',
            subject  => 'subj',
            tz       => 'guess',
            %extra,
        },
        \$err,
        { noauth => 1, nomod => 1 }
    );
    die LJ::Protocol::error_message($err) unless $res;
    return LJ::Entry->new( $u, jitemid => $res->{itemid} );
}

my $public  = post( security => 'public' );
my $private = post( security => 'private' );
my $access  = post( security => 'usemask', allowmask => 1 );
my $custom  = post( security => 'usemask', allowmask => ( 1 << 2 ) | ( 1 << 5 ) );

is( $public->TO_JSON($u)->{security},  'public',  'public entry' );
is( $private->TO_JSON($u)->{security}, 'private', 'private entry' );

my $json = eval { $access->TO_JSON($u) };
ok( $json, 'access-locked entry serializes' ) or diag $@;
is( $json->{security}, 'access', 'access-locked entry shows as access' );
ok( !exists $json->{custom_groups}, 'access-locked entry has no custom groups' );

$json = eval { $custom->TO_JSON($u) };
ok( $json, 'custom-filtered entry serializes' ) or diag $@;
is( $json->{security}, 'custom', 'owner sees custom security' );
is_deeply( $json->{custom_groups}, [ 2, 5 ], 'owner sees the custom group numbers' );

$json = eval { $custom->TO_JSON($other) };
is( $json->{security}, 'access', 'another user sees custom as access' );
ok( !exists $json->{custom_groups}, 'another user does not see the groups' );

$json = eval { $custom->TO_JSON(undef) };
is( $json->{security}, 'access', 'anonymous viewer sees custom as access' );
ok( !exists $json->{custom_groups}, 'anonymous viewer does not see the groups' );

ok( eval { JSON->new->convert_blessed->encode( $custom->TO_JSON($u) ) }, 'encodes as JSON' )
    or diag $@;

done_testing;
