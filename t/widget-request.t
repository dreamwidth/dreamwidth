#!/usr/bin/perl
#
# t/widget-request.t
#
# Widget POST dispatch: form auth, repeated fields, redirects, ThemeNav URLs.
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
use HTTP::Request::Common;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use LJ::Widget;
use LJ::Widget::ThemeNav;

{

    package LJ::Widget::RequestTest;
    our @ISA = ('LJ::Widget');
    our @seen;

    sub handle_post {
        my ( $class, $post ) = @_;
        push @seen, $post;
        return ( saved => 1 );
    }
}

{

    package LJ::Widget::RedirectTest;
    our @ISA  = (q{LJ::Widget});
    our $seen = 0;

    sub handle_post {
        $seen++;
        return ( redirect => q{/redirected} );
    }
}
{

    package LJ::Widget::AfterRedirectTest;
    our @ISA  = (q{LJ::Widget});
    our $seen = 0;

    sub handle_post { $seen++ }
}

sub request {
    my $http = shift;
    DW::Request->reset;
    DW::Cache->request->clear;
    return DW::Request::Standard->new($http);
}

no warnings 'redefine';
local *LJ::check_form_auth = sub { return defined $_[0] && $_[0] eq 'valid'; };
local *LJ::Lang::ml        = sub { return $_[0]; };
local $LJ::WIDGET_NO_AUTH_CHECK = 0;

my $r = request(
    POST 'http://localhost/example',
    Content => [
        lj_form_auth                 => 'valid',
        'Widget[RequestTest]_choice' => 'one',
        'Widget[RequestTest]_choice' => 'two',
    ]
);
LJ::Widget->handle_post( $r->post_args, 'RequestTest' );
is( $LJ::Widget::RequestTest::seen[0]->{choice}, "one\0two", 'dispatch preserves repeated values' );

$r = request(
    POST 'http://localhost/example',
    Content => [
        lj_form_auth                 => 'invalid',
        'Widget[RequestTest]_choice' => 'denied'
    ]
);
LJ::Widget->handle_post( $r->post_args, 'RequestTest' );
is( scalar @LJ::Widget::RequestTest::seen, 1, 'invalid token never dispatches a mutation' );
is_deeply( LJ::Widget->errors, ['error.invalidform'], 'invalid token is reported' );

$r = request(
    POST q{http://localhost/example},
    Content => [
        lj_form_auth                              => q{valid},
        q{Widget[RedirectTest]_submit}            => 1,
        q{Widget[AfterRedirectTest]_must_not_run} => 1,
    ]
);
my %redirect_result = LJ::Widget->handle_post( $r->post_args, qw(RedirectTest AfterRedirectTest) );
is( $redirect_result{redirect}, q{/redirected}, q{widget redirect result is propagated} );
is( $LJ::Widget::AfterRedirectTest::seen, 0, q{redirect stops later widget mutations} );

request(
    POST q{http://localhost/customize/?page=2&mypage=2&search=homepage=2&page=3&encoded=page%3D2} );
my %theme_nav_result = LJ::Widget::ThemeNav->handle_post( { page => 4 } );
is(
    $theme_nav_result{redirect},
    "$LJ::SITEROOT/customize/?mypage=2&search=homepage=2&encoded=page%3D2&page=4",
    q{ThemeNav removes only complete repeated page query parameters}
);

done_testing;
