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

sub fresh_comment {
    my ($comment) = @_;
    my $journal   = $comment->journal;
    my $jtalkid   = $comment->jtalkid;
    LJ::Comment->reset_singletons;
    return LJ::Comment->new( $journal, jtalkid => $jtalkid );
}

sub post_comment {
    my ($journal) = @_;
    return $journal->t_post_fake_entry->t_enter_comment;
}

my $journal = temp_user();

subtest 'set_poster_ip preserves no-request, forwarded, and historical values' => sub {
    my $no_request = post_comment($journal);
    DW::Request->reset;
    is( $no_request->set_poster_ip, '', 'no request leaves a comment IP unset' );
    ok( !defined $no_request->poster_ip, 'no-request update does not persist metadata' );

    my $comment = post_comment($journal);
    request('192.0.2.10');
    is( $comment->set_poster_ip, '192.0.2.10', 'native request records an unforwarded address' );
    is( fresh_comment($comment)->poster_ip,
        '192.0.2.10', 'unforwarded address is persisted for display' );

    request('192.0.2.10');
    is( $comment->set_poster_ip, '192.0.2.10', 'repeated equal address has no history suffix' );
    is( fresh_comment($comment)->poster_ip, '192.0.2.10',
        'equal update remains persisted exactly' );

    request( '192.0.2.11', '198.51.100.7' );
    is(
        $comment->set_poster_ip,
        '198.51.100.7, via 192.0.2.11 (originally 192.0.2.10)',
        'distinct forwarded address preserves the original address'
    );
    is(
        fresh_comment($comment)->poster_ip,
        '198.51.100.7, via 192.0.2.11 (originally 192.0.2.10)',
        'forwarded display metadata is persisted exactly'
    );

    is(
        $comment->set_poster_ip,
        '198.51.100.7, via 192.0.2.11 (originally 192.0.2.10)',
        'repeated forwarded update does not duplicate history'
    );
    is(
        fresh_comment($comment)->poster_ip,
        '198.51.100.7, via 192.0.2.11 (originally 192.0.2.10)',
        'repeated update remains persisted exactly'
    );

    my $equal_forwarded = post_comment( temp_user() );
    $equal_forwarded->set_prop( poster_ip => undef );
    request( '192.0.2.12', '192.0.2.12' );
    is( $equal_forwarded->set_poster_ip,
        '192.0.2.12', 'equal forwarded and remote values keep the legacy single-address form' );
    is( fresh_comment($equal_forwarded)->poster_ip,
        '192.0.2.12', 'equal forwarded value is persisted for display' );
};

subtest 'comment posting stores native request metadata through LJ::Talk' => sub {
    request( '192.0.2.20', '198.51.100.20' );
    my $comment = post_comment($journal);

    is(
        $comment->poster_ip,
        '198.51.100.20, via 192.0.2.20',
        'posting stores the native remote and forwarded metadata'
    );
    is(
        fresh_comment($comment)->poster_ip,
        '198.51.100.20, via 192.0.2.20',
        'posted metadata survives a fresh comment load'
    );
};

DW::Request->reset;
done_testing;
