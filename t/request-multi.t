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

use Test::More tests => 13;

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

# A repeated param whose last value is empty (multi=x&multi=) must keep the trailing ''.
check_get(
    "multi=x&multi=",
    sub {
        plan tests => 1;
        my $args = DW::Request->get->get_args;
        is_deeply(
            [ $args->get_all('multi') ],
            [ 'x', '' ],
            "trailing empty value in a repeated GET param is preserved"
        );
    }
);

check_post(
    "multi=x&multi=",
    sub {
        plan tests => 1;
        my $args = DW::Request->get->post_args;
        is_deeply(
            [ $args->get_all('multi') ],
            [ 'x', '' ],
            "trailing empty value in a repeated POST param is preserved"
        );
    }
);

check_get( undef, sub { is_empty_args( DW::Request->get->get_args ) } );
check_get( '',    sub { is_empty_args( DW::Request->get->get_args ) } );
check_post( '', sub { is_empty_args( DW::Request->get->post_args ) } );

my $encoded =
    'leading=&zero=0&blank=&leading=x&zero=x&blank=&nul=a%00b&eq=a=b' . '&flag&&foo+%2B=a+%2Bb';
check_get( $encoded, sub { check_decoded_args( DW::Request->get->get_args ) } );
check_post( $encoded, sub { check_decoded_args( DW::Request->get->post_args ) } );

check_get(
    'Foo=1&f%6Fo=2&Foo=3',
    sub {
        my $args = DW::Request->get->get_args;
        is_deeply(
            [ $args->get_all('foo') ],
            [ '1', '2', '3' ],
            'GET lowercases decoded keys without reordering values'
        );
    }
);

check_get(
    'Foo=1&f%6Fo=2&Foo=3',
    sub {
        my $args = DW::Request->get->get_args( preserve_case => 1 );
        is_deeply( [ $args->get_all('Foo') ], [ '1', '3' ], 'GET can preserve uppercase keys' );
        is_deeply( [ $args->get_all('foo') ], ['2'], 'case-preserving GET keeps keys distinct' );
    }
);

sub is_empty_args {
    my ($args) = @_;
    isa_ok( $args, 'Hash::MultiValue' );
    is_deeply( $args->as_hashref, {}, 'no arguments, not even an empty key' );
}

sub check_decoded_args {
    my ($args) = @_;

    is_deeply( [ $args->get_all('leading') ], [ '',  'x' ], 'leading empty value survives' );
    is_deeply( [ $args->get_all('zero') ],    [ '0', 'x' ], 'leading zero stays separate' );
    is_deeply( [ $args->get_all('blank') ],   [ '',  '' ],  'both empty values survive' );
    is_deeply( [ $args->get_all('nul') ], ["a\0b"], 'NUL stays in its original value' );
    is( $args->{eq},      'a=b',  'only the first equals separates key and value' );
    is( $args->{flag},    '',     'bare key has an empty value' );
    is( $args->{'foo +'}, 'a +b', 'plus and percent escapes decode in keys and values' );
    ok( !exists $args->{''}, 'empty segment does not create a key' );

    my @keys;
    $args->each( sub { push @keys, $_[0]; } );
    is_deeply(
        \@keys,
        [ 'leading', 'zero', 'blank', 'leading', 'zero', 'blank', 'nul', 'eq', 'flag', 'foo +' ],
        'arguments retain their order across keys'
    );
}

sub check_get {
    my ( $args, $sv ) = @_;

    # Telling Test::Builder ( which Test::More uses ) to
    # look one level further up the call stack.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $query = defined $args ? "?$args" : '';
    my $rq    = HTTP::Request->new( GET => "http://www.example.com/test$query" );

    DW::Request->reset;
    my $r = DW::Request::Standard->new($rq);

    subtest "GET /test$query", sub { $sv->() };
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
