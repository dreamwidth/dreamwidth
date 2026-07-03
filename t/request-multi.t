# t/request-multi.t
#
# Test DW::Request.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 4;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use HTTP::Request;

check_get(
    "foo=bar&bar=baz&foo=qux",
    sub {
        plan tests => 6;

        my $r    = DW::Request->get;
        my $args = $r->get_args;

        is( 'qux', $args->{foo} );
        is( 'qux', $args->get('foo') );
        is_deeply( [ 'bar', 'qux' ], [ $args->get_all('foo') ] );

        is( 'baz', $args->{bar} );
        is( 'baz', $args->get('bar') );
        is_deeply( ['baz'], [ $args->get_all('bar') ] );
    }
);

check_post(
    "foo=bar&bar=baz&foo=qux",
    sub {
        plan tests => 6;

        my $r    = DW::Request->get;
        my $args = $r->post_args;

        is( 'qux', $args->{foo} );
        is( 'qux', $args->get('foo') );
        is_deeply( [ 'bar', 'qux' ], [ $args->get_all('foo') ] );

        is( 'baz', $args->{bar} );
        is( 'baz', $args->get('bar') );
        is_deeply( ['baz'], [ $args->get_all('bar') ] );
    }
);

# A submitted-but-empty field (foo=) must round-trip as '', not be dropped.
# Pre-Plack, BML pages parsed args without _string_to_multivalue and kept the
# empty; DW::Request must preserve the same behavior.
check_get(
    "empty=&filled=x",
    sub {
        plan tests => 4;

        my $args = DW::Request->get->get_args;

        ok( exists $args->{empty}, "empty GET field is present, not dropped" );
        is( $args->{empty}, '', "empty GET field round-trips as ''" );
        is_deeply( [ $args->get_all('empty') ], [''], "empty GET field is a single ''" );
        is( $args->{filled}, 'x', "filled GET field unaffected" );
    }
);

check_post(
    "empty=&filled=x",
    sub {
        plan tests => 4;

        my $args = DW::Request->get->post_args;

        ok( exists $args->{empty}, "empty POST field is present, not dropped" );
        is( $args->{empty}, '', "empty POST field round-trips as ''" );
        is_deeply( [ $args->get_all('empty') ], [''], "empty POST field is a single ''" );
        is( $args->{filled}, 'x', "filled POST field unaffected" );
    }
);

sub check_get {
    my ( $args, $sv ) = @_;

    # Telling Test::Builder ( which Test::More uses ) to
    # look one level further up the call stack.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $rq = HTTP::Request->new( GET => "http://www.example.com/test?$args" );

    DW::Request->reset;
    my $r = DW::Request::Standard->new($rq);

    subtest "GET $args", sub { $sv->() };
}

sub check_post {
    my ( $args, $sv ) = @_;

    # Telling Test::Builder ( which Test::More uses ) to
    # look one level further up the call stack.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $rq = HTTP::Request->new( POST => "http://www.example.com/test" );
    $rq->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
    $rq->add_content_utf8($args);

    DW::Request->reset;
    my $r = DW::Request::Standard->new($rq);

    subtest "POST $args", sub { $sv->() };
}
