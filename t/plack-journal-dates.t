# t/plack-journal-dates.t
#
# Invalid calendar days must use the standard missing-page response.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $u    = temp_user();
my $base = 'http://localhost/users/' . $u->user;

# The test DB has no S2 layers. Mark the renderer boundary so the full Plack
# routing/error stack can be tested without needing a journal style.
with_fake_memcache {
    no warnings 'redefine';
    local *LJ::make_journal = sub { return 'JOURNAL_RENDERED' };

    test_psgi $app, sub {
        my $cb = shift;
        for my $date (
            '2026/02/30', '2025/02/29', '2026/04/31', '2026/06/31', '2026/09/31', '2026/11/31',
            '2026/01/00', '2026/01/32', '2026/00/01', '2026/13/01',
            )
        {
            for my $slash ( '', '/' ) {
                my $path = "/$date$slash";
                my $res  = $cb->( GET $base . $path );
                is( $res->code, 404, "$path returns 404" );
                like( $res->content, qr/find that page/i, "$path uses the stock error page" );
                unlike( $res->content, qr/JOURNAL_RENDERED/, "$path does not render a journal" );
            }
        }

        for my $date ( '2024/02/29', '2000/02/29', '2026/02/28', '2026/04/30', '2026/12/31' ) {
            my $res = $cb->( GET "$base/$date/" );
            is( $res->code, 200, "$date is a valid day" );
            like( $res->content, qr/JOURNAL_RENDERED/, "$date reaches the renderer" );

            my $redirect = $cb->( GET "$base/$date" );
            is( $redirect->code, 303, "$date without slash keeps its redirect" );
            like( $redirect->header('Location'),
                qr{/$date/$}, "$date redirects to its canonical URL" );
        }

        for my $path ( '/2026/', '/2026/02/', '/2026/04/', '/2024/02/' ) {
            my $res = $cb->( GET $base . $path );
            is( $res->code, 200, "$path still renders" );
            like( $res->content, qr/JOURNAL_RENDERED/, "$path reaches the renderer" );
        }
    };
};

done_testing;
