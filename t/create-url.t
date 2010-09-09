# -*-perl-*-
use strict;
use Test::More tests => 5 * 14; # replace last number with the number of check_req calls
use lib "$ENV{LJHOME}/cgi-bin";

require 'ljlib.pl';
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
        format => "light",
        style => "site",
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
        format => "light",
        style => "site",
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
    { ssl => 0, host => "foo.example.com", uri=>"/", },
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

sub check_req {
    my ( $url, $path, $opts, $eopts, $expected ) = @_;

    my $rq = HTTP::Request->new(GET => $url);
    my ( $https, $host ) = $url =~ m!^(http(?:s)?)://(.+?)/!;
    $LJ::IS_SSL = ( $https eq 'https' ) ? 1 : 0;
    $rq->header("Host", $host);

    DW::Request->reset;
    my $r = DW::Request::Standard->new($rq);

    my $nurl = LJ::create_url( $path, %$opts );

    validate_req($nurl,$eopts,$expected);
}

sub validate_req {
    my ( $url, $eopts, $expected ) = @_;

    my ( $https, $host, $blah, $fragment, $blah2 ) = $url =~ m!^(http(?:s)?)://(.+?)/(.*?)((?:#.+?)?)((?:\?.+?)?)$!;
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

    my $fail = '';
    my $args = $r->get_args;

    foreach my $k ( keys %$args ) {
        if ( $args->{$k} ne $expected->{$k} ) {
            $fail .= "$k ( $args->{$k} != $expected->{$k} ), ";
        }
        delete $expected->{$k};
    }

    $fail .= " -- missing: " . join(",", keys %$expected) if ( %$expected );

    ok( ! $fail, "args mismatch: $fail");
}