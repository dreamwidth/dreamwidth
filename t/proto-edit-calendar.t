# t/proto-edit-calendar.t
#
# Calendar day counts must follow entry date changes.
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
use HTTP::Request;
use DW::Request::Standard;
use LJ::Protocol;
use LJ::Test qw(temp_user with_fake_memcache);

with_fake_memcache {
    for my $security ( 'public', 'private', 'friends' ) {
        subtest $security => sub {
            my $u      = temp_user();
            my $viewer = temp_user();
            $u->add_edge( $viewer, trust => {} );
            my $mask           = $security eq 'friends' ? 1         : 0;
            my $proto_security = $security eq 'friends' ? 'usemask' : $security;
            my $request        = sub {
                my ( $mode, %args ) = @_;
                my $err = 0;
                my $res = LJ::Protocol::do_request(
                    $mode,
                    {
                        username  => $u->user,
                        ver       => $LJ::PROTOCOL_VER,
                        tz        => 'guess',
                        security  => $proto_security,
                        allowmask => $mask,
                        %args
                    },
                    \$err,
                    { noauth => 1 }
                );
                is( $err, 0, "$mode succeeds" );
                DW::Request->reset;
                DW::Request::Standard->new( HTTP::Request->new( GET => 'http://localhost/' ) );
                return $res;
            };
            my $res = $request->(
                'postevent',
                event => "Calendar example $security",
                year  => 2020,
                mon   => 1,
                day   => 10,
                hour  => 12,
                min   => 0
            );
            my @views = (
                [ 'owner', $u, 1 ],
                [ 'anonymous', undef, $security eq 'public' ? 1 : 0 ],
                [ 'trusted', $viewer, $security ne 'private' ? 1 : 0 ]
            );
            for my $view (@views) {
                my ( $label, $remote, $visible ) = @$view;
                is_deeply(
                    $u->get_daycounts($remote),
                    $visible ? [ [ 2020, 1, 10, 1 ] ] : [],
                    "$label warms the old date counts"
                );
            }
            $request->(
                'editevent',
                event  => "Calendar example $security",
                itemid => $res->{itemid},
                year   => 2020,
                mon    => 2,
                day    => 20,
            );
            for my $view (@views) {
                my ( $label, $remote, $visible ) = @$view;
                is_deeply(
                    $u->get_daycounts($remote),
                    $visible ? [ [ 2020, 2, 20, 1 ] ] : [],
                    "$label sees the new date without cache expiry"
                );
                is_deeply(
                    $u->get_daycounts($remote),
                    $u->get_daycounts( $remote, 1 ),
                    "$label cached counts match the database"
                );
            }
            $request->( 'editevent', itemid => $res->{itemid}, event => 'Content-only edit' );
            is_deeply(
                $u->get_daycounts($u),
                [ [ 2020, 2, 20, 1 ] ],
                'A content-only edit preserves the calendar'
            );

            my $new_security = $security eq 'public' ? 'private' : 'public';
            $request->(
                'editevent',
                itemid    => $res->{itemid},
                event     => 'Date and security edit',
                security  => $new_security,
                allowmask => 0,
                year      => 2020,
                mon       => 3,
                day       => 3,
            );
            for my $view (@views) {
                my ( $label, $remote ) = @$view;
                my $visible = $label eq 'owner' || $new_security eq 'public';
                is_deeply(
                    $u->get_daycounts($remote),
                    $visible ? [ [ 2020, 3, 3, 1 ] ] : [],
                    "$label sees correct counts after a date and security change"
                );
            }
        };
    }
};
done_testing;
