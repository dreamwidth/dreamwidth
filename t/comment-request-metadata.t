#!/usr/bin/perl
#
# t/comment-request-metadata.t
#
# Regression coverage for native request metadata used by comment IP persistence.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

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
