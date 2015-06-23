# t/create-url.t
#
# Test TODO
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

use Test::More tests => 22;


BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use HTTP::Request;

check_req(
    "http://www.example.com/",
    undef, {
        args => {
            foo => "bar"
        },
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    { foo => "bar", },
);

check_req(
    "http://www.example.com/?bar=baz",
    undef, {
        args => {
            foo => 'bar',
        },
        keep_args => [ 'bar' ],
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    {
        foo => "bar",
        bar => "baz",
    },
);

check_req(
    "http://www.example.com/?bar=baz",
    undef, {
        args => {
            foo => 'bar',
        },
        keep_args => [ 'bar' ],
        fragment => 'yay',
    },
    { ssl => 0, host => "www.example.com", uri=>"/", fragment=>"yay" },
    {
        foo => "bar",
        bar => "baz",
    },
);

check_req(
    "http://www.example.com/?bar=baz&s2id=5&format=light&style=site",
    undef, {
        args => {
            foo => 'bar',
        },
        keep_args => [ 'bar' ],
        viewing_style => 1
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    {
        foo => "bar",
        bar => "baz",
        s2id => 5,
        style => "site",
        format => "light",
    },
);

check_req(
    "http://www.example.com/?bar=baz&s2id=5&format=light&style=site",
    undef, {
        args => {
            foo => 'bar',
            s2id => undef,
            bar => "kitten",
        },
        keep_args => [ 'bar' ],
        viewing_style => 1
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    {
        foo => "bar",
        bar => "kitten",
        style => "site",
        format => "light",
    },
);

check_req(
    "http://www.example.com/?bar=baz&s2id=5&format=light&style=site&some=other&cruft=1",
    undef, {
        args => {
            foo => 'bar',
            bar => undef,
            mew => undef,
        },
        keep_args => [ 'bar' ],
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    {
        foo => "bar",
    },
);

check_req(
    "https://www.example.com/",
    undef, {
    },
    { ssl => 1, host => "www.example.com", uri=>"/", },
    {},
);

check_req(
    "https://www.example.com/",
    undef, {
        ssl => 0,
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    {},
);

check_req(
    "https://www.example.com/",
    undef, {
        ssl => 1,
    },
    { ssl => 1, host => "www.example.com", uri=>"/", },
    {},
);

check_req(
    "http://www.example.com/",
    undef, {
        ssl => 1,
    },
    { ssl => 1, host => "www.example.com", uri=>"/", },
    {},
);

check_req(
    "https://www.example.com/",
    undef, {
        host => "foo.example.com",
    },
    { ssl => 1, host => "foo.example.com", uri=>"/", },
    {},
);

check_req(
    "https://www.example.com/",
    undef, {
        host => "foo.example.com",
        ssl => 1,
    },
    { ssl => 1, host => "foo.example.com", uri=>"/", },
    {},
);

check_req(
    "https://www.example.com/",
    undef, {
        host => "foo.example.com",
        ssl => 0,
    },
    { ssl => 0, host => "foo.example.com", uri=>"/", },
    {},
);

check_req(
    "http://www.example.com/",
    undef, {
        host => "foo.example.com",
        ssl => 1,
    },
    { ssl => 1, host => "foo.example.com", uri=>"/", },
    {},
);

check_req(
    "http://www.example.com/",
    "/mmm_path", {
    },
    { ssl => 0, host => "www.example.com", uri=>"/mmm_path", },
    {},
);

check_req(
    "http://www.example.com/meow",
    undef, {
    },
    { ssl => 0, host => "www.example.com", uri=>"/meow", },
    {},
);

check_req(
    "http://www.example.com/meow",
    undef, {
        fragment => "kitten",
    },
    { ssl => 0, host => "www.example.com", uri=>"/meow", fragment => "kitten" },
    {},
);

check_req(
    "http://www.example.com/?bar=baz&s2id=5&format=light&style=site&ping=pong&no=1",
    undef, {
        args => {
            foo => 'bar',
            no => undef,
        },
        keep_args => 1,
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    {
        foo => "bar",
        bar => "baz",
        s2id => 5,
        format => "light",
        style => "site",
        ping => "pong",
    },
);

check_req(
    "http://www.example.com/?bar=baz&s2id=5&format=light&style=site&ping=pong&no=1",
    undef, {
        args => {
            foo => 'bar',
            no => undef,
        },
        keep_args => 1,
        viewing_style => 1,
    },
    { ssl => 0, host => "www.example.com", uri=>"/", },
    {
        foo => "bar",
        bar => "baz",
        s2id => 5,
        format => "light",
        style => "site",
        ping => "pong",
    },
);

check_req(
    "http://www.example.com/?bar=baz&s2id=5&format=light&style=site&ping=pong&no=1",
    undef, {
        args => {
            foo => 'bar',
            no => undef,
        },
        keep_args => 0,
    },
    { ssl => 0, host => "www.example.com", uri => "/", },
    {
        foo => "bar",
    },
);

check_req(
    "http://www.example.com/?format=light",
    undef, {
        keep_args => 1,
    },
    { ssl => 0, host => "www.example.com", uri => "/", },
    {
        format => "light",
    },
);

check_req(
    "http://www.ExAmPlE.com/",
    undef, {
        keep_args => 1,
    },
    { ssl => 0, host => "www.example.com", uri => "/", },
    {},
);

sub check_req {
    my ( $url, $path, $opts, $eopts, $expected ) = @_;

    # Telling Test::Builder ( which Test::More uses ) to
    # look one level further up the call stack.
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    subtest $url, sub {
        plan tests => 5;

        my $rq = HTTP::Request->new(GET => $url);
        my ( $https, $host ) = $url =~ m!^(http(?:s)?)://(.+?)/!;
        $LJ::IS_SSL = ( $https eq 'https' ) ? 1 : 0;
        $rq->header("Host", $host);

        DW::Request->reset;
        my $r = DW::Request::Standard->new($rq);

        my $nurl = LJ::create_url( $path, %$opts );

        validate_req($nurl,$eopts,$expected);
    };
}

sub validate_req {
    my ( $url, $eopts, $expected ) = @_;

    my ( $https, $host, $blah, $blah2, $fragment ) = $url =~ m!^(http(?:s)?)://(.+?)/(.*?)((?:\?.+?)?)((?:#.+?)?)$!;
    my $ssl = ( $https eq 'https' ) ? 1 : 0;
    my $rq = HTTP::Request->new(GET => $url);

    DW::Request->reset;
    my $r = DW::Request::Standard->new($rq);

    is( $r->uri, $eopts->{uri}, "uri mismatch" );
    is( $host, $eopts->{host}, "host mismatch" );
    is( $ssl, $eopts->{ssl}, "invalid ssl" );

    if ( $fragment ) {
        $fragment =~ s/^#//;
    } else {
        $fragment = undef;
    }

    is( $fragment, $eopts->{fragment}, "invalid fragment" );

    my $args = $r->get_args;

    subtest "args", sub {
        my $tests_run = 0;
        foreach my $k ( keys %$args ) {
            is( $args->{$k}, $expected->{$k}, "argument '$k'");
            delete $expected->{$k};
            $tests_run++;
        }
        foreach my $k ( keys %$expected ) {
            is( $args->{$k}, $expected->{$k}, "argument '$k'");
            $tests_run++;
        }
        ok("no argument tests") if $tests_run == 0;
    };
}
