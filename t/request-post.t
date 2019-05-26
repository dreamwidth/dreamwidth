# t/request-multi.t
#
# Test DW::Request POST data.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 5;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use HTTP::Request;
use HTTP::Request::Common;
use Test::Exception;
use LJ::JSON;

# Test multipart
check_request(
    "Standard POST",
    POST( "/foobar", Content => [ foo => 1 ] ),
    sub {
        plan tests => 7;

        my $r = DW::Request->get;

        ok( $r->did_post, "In a POST" );

        # 1 - Check post args
        my $args = $r->post_args;
        isnt( $args, undef, "POST args defined" );
        is( $args->{foo}, 1,     "Foo is correct" );
        is( $args->{bar}, undef, "Bar is undefined" );

        my $args2 = $r->post_args;
        is( $args, $args2, "Returns cached post_args" );

        # 5 - Try uploads
        throws_ok { $r->uploads } qr/content type in upload/, "uploads failed";

        # 6 - Try JSON
        is( $r->json, undef, "json returns undefined" );
    }
);

check_request(
    "multipart/form-data POST",
    POST(
        "/foobar",
        Content_Type => 'form-data',
        Content      => [
            foo => [ undef, 'rar.txt', Content => "Rar!" ],
            bar => [ undef, 'rar.txt', Content => "Rawr!", 'X-Meaning-Of-Life' => 42 ],
        ]
    ),
    sub {
        plan tests => 9;

        my $r = DW::Request->get;

        ok( $r->did_post, "In a POST" );

        # 1 - Check post args
        my $args = $r->post_args;
        isnt( $args, undef, "POST args defined" );
        is( scalar $args->flatten, 0, "POST args empty" );

        # 3 - Try uploads
        my $uploads = $r->uploads;
        isnt( $uploads, undef, "Uploads defined" );
        my %values = map { $_->{name} => $_ } @$uploads;

        is( $values{foo}->{body},                "Rar!",  "body correct" );
        is( $values{bar}->{body},                "Rawr!", "body correct, with headers" );
        is( $values{bar}->{'x-meaning-of-life'}, 42,      "header correct" );

        my $uploads2 = $r->uploads;
        is( $uploads, $uploads2, "Returns cached uploads" );

        # 8 - Try JSON
        is( $r->json, undef, "json returns undefined" );
    }
);

check_request(
    "Invalid multipart/form-data POST, no boundary",
    POST( "/foobar", 'Content-Type' => 'multipart/form-data', Content => "I don't care" ),
    sub {
        plan tests => 1;

        my $r = DW::Request->get;
        throws_ok { $r->uploads } qr/content type in upload/, "uploads failed";
    }
);

check_request(
    "Invalid multipart/form-data POST, no boundary in content",
    POST( "/foobar", 'Content-Type' => 'multipart/form-data;boundary=FooBar', Content => <<EOB),
--FooBaz
This is invalid.
EOB
    sub {
        plan tests => 1;

        my $r = DW::Request->get;
        throws_ok { $r->uploads } qr/it looks invalid/, "uploads failed";
    }
);

check_request(
    "application/json POST",
    POST(
        "/foobar",
        'Content-Type' => 'application/json',
        Content        => to_json( { Hello => 'World' } )
    ),
    sub {
        plan tests => 7;

        my $r = DW::Request->get;

        ok( $r->did_post, "In a POST" );

        # 1 - Check post args
        my $args = $r->post_args;
        isnt( $args, undef, "POST args defined" );
        is( scalar $args->flatten, 0, "POST args empty" );

        # 3 - Try uploads
        throws_ok { $r->uploads } qr/content type in upload/, "uploads failed";

        # 4 - Try JSON
        my $json = $r->json;
        isnt( $json, undef, "json returns defined" );
        is( $json->{Hello}, "World", "JSON decodes correctly" );

        my $json2 = $r->json;
        is( $json, $json2, "Returns cached json" );
    }
);

sub check_request {
    my ( $name, $rq, $sv ) = @_;

    # Telling Test::Builder ( which Test::More uses ) to
    # look one level further up the call stack.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    DW::Request->reset;
    my $r = DW::Request::Standard->new($rq);

    subtest "$name", sub { $sv->() };
}
