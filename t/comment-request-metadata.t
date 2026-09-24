#!/usr/bin/perl
# Regression coverage for native request metadata used by comment IP persistence.
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request;
use DW::Request::Plack;
use LJ::Comment;
use LJ::Test qw(temp_user);

sub request {
    my ( $ip, $forwarded ) = @_;

    DW::Request->reset;
    my $body = '';
    open my $input, '<', \$body or die "open request body: $!";
    open my $errors, '>', \( my $error_output = '' ) or die "open error output: $!";

    my %env = (
        REQUEST_METHOD    => 'POST',
        PATH_INFO         => '/',
        QUERY_STRING      => '',
        SERVER_NAME       => 'localhost',
        SERVER_PORT       => 80,
        HTTP_HOST         => 'localhost',
        REMOTE_ADDR       => $ip,
        CONTENT_LENGTH    => 0,
        'psgi.version'    => [ 1, 1 ],
        'psgi.url_scheme' => 'http',
        'psgi.input'      => $input,
        'psgi.errors'     => $errors,
    );
    $env{HTTP_X_FORWARDED_FOR} = $forwarded if defined $forwarded;

    return DW::Request::Plack->new( \%env );
}

subtest 'posting a comment records the real request IP and forwarded chain for abuse review' =>
    sub {
    my $journal = temp_user();
    request( '192.0.2.20', '198.51.100.20' );
    my $comment = $journal->t_post_fake_entry->t_enter_comment;

    is(
        $comment->poster_ip,
        '198.51.100.20, via 192.0.2.20',
        'posting stores the native remote and forwarded metadata'
    );

    LJ::Comment->reset_singletons;
    is(
        LJ::Comment->new( $comment->journal, jtalkid => $comment->jtalkid )->poster_ip,
        '198.51.100.20, via 192.0.2.20',
        'posted metadata survives a fresh comment load'
    );
    };

DW::Request->reset;
done_testing;
