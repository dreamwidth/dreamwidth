#!/usr/bin/perl
# t/plack-admin-recent-comments.t
#
# Admin recent comments retain relative ages alongside UTC timestamps.
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
use HTTP::Request::Common;
use Plack::Test;
use POSIX qw(tzset);
use Time::Local qw(timegm);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $admin = temp_user();
$admin->grant_priv( 'siteadmin', 'commentview' );
my $entry = $admin->t_post_fake_entry( body => 'Recent comment timestamp test' );
my @cases = (
    [ timegm( 0, 3, 1, 4,  11, 2024 ), '2024-12-04 0103 UTC' ],
    [ timegm( 0, 5, 0, 29, 1,  2024 ), '2024-02-29 0005 UTC' ],
    [ timegm( 0, 0, 0, 1,  0,  2025 ), '2025-01-01 0000 UTC' ],
);

for my $case (@cases) {
    my $comment = $entry->t_enter_comment( u => $admin, body => $case->[1] );
    $admin->do( 'UPDATE talkleft SET posttime=? WHERE userid=? AND journalid=? AND jtalkid=?',
        undef, $case->[0], $admin->id, $admin->id, $comment->jtalkid );
    die 'missing recent-comment row'
        unless $admin->selectrow_array(
        'SELECT COUNT(*) FROM talkleft WHERE userid=? AND jtalkid=? AND posttime=?',
        undef, $admin->id, $comment->jtalkid, $case->[0] );
    push @$case, $comment->dtalkid;
}

with_fake_memcache {
    for my $zone ( 'UTC', 'America/Los_Angeles' ) {
        subtest $zone => sub {
            local $ENV{TZ} = $zone;
            tzset();
            test_psgi $app, sub {
                my $cb   = shift;
                my $user = $admin->user;
                my $res = $cb->( GET "http://localhost/admin/recent_comments?user=$user&as=$user" );
                is( $res->code, 200, 'real admin route renders' );
                for my $case (@cases) {
                    my ( $epoch, $utc, $id ) = @$case;
                    like(
                        $res->content,
                        qr/\Q$utc\E \(\d+\.\d hr ago\)/,
                        "$utc appears with the relative age"
                    );
                    my ($age) = $res->content =~
                        m{(\d+\.\d) hr ago(?:\))? in (?:(?!<br).)*?thread=\Q$id\E}s;
                    ok( defined $age, "$utc retains its relative age and comment link" );
                    cmp_ok( abs( ( $age // -1 ) - ( time() - $epoch ) / 3600 ),
                        '<=', 0.051, "$utc relative age is still measured in hours" );
                }
            };
        };
    }
};
tzset();
done_testing();
