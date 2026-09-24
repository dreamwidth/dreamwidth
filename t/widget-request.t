# Widgets must work without BML input globals and isolate request errors.
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.
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
        $class->error('widget validation failed') if $post->{fail};
        return ( saved => 1 );
    }
    sub authas { 1 }
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

{
    no warnings 'redefine';
    local *LJ::check_form_auth = sub { return defined $_[0] && $_[0] eq 'valid'; };
    local *LJ::Lang::ml        = sub { return $_[0]; };
    local $LJ::WIDGET_NO_AUTH_CHECK = 0;
    my $r = request(
        POST 'http://localhost/example?choice=one',
        Content => [
            lj_form_auth                 => 'valid',
            'Widget[RequestTest]_choice' => 'one',
            'Widget[RequestTest]_choice' => 'two',
            'Widget[Other]_forbidden'    => 'x'
        ]
    );
    is( LJ::Widget->get_args->{choice}, 'one', 'GET fields come from request' );
    my $fields = LJ::Widget->post_fields_of_widget('RequestTest');
    is( $fields->{choice}, "one\0two",
        'implicit POST preserves repeated values for legacy widgets' );
    is( LJ::Widget::RequestTest->post_fields->{choice},
        "one\0two", 'subclass implicit POST also works' );
    my %res = LJ::Widget->handle_post( $r->post_args, 'RequestTest' );
    is( $res{saved},                           1, 'widget result preserved' );
    is( scalar @LJ::Widget::RequestTest::seen, 1, 'only allowed widget dispatched' );
    is( $LJ::Widget::RequestTest::seen[0]->{choice},
        "one\0two", 'dispatch preserves repeated values' );
    like( ( LJ::Widget->error_list )[0], qr/disallowed class/, 'disallowed widget is reported' );

    $r = request(
        POST 'http://localhost/example',
        Content => [
            lj_form_auth                 => 'invalid',
            'Widget[RequestTest]_choice' => 'denied'
        ]
    );
    is_deeply( LJ::Widget->errors, [], 'new request clears errors' );
    LJ::Widget->handle_post( $r->post_args, 'RequestTest' );
    is( scalar @LJ::Widget::RequestTest::seen, 1, 'invalid token never dispatches a mutation' );
    is_deeply( LJ::Widget->errors, ['error.invalidform'], 'invalid token is reported' );

    $r = request(
        POST 'http://localhost/example',
        Content => [
            lj_form_auth               => 'valid',
            'Widget[RequestTest]_fail' => 1
        ]
    );
    LJ::Widget->handle_post( $r->post_args, 'RequestTest' );
    is_deeply(
        LJ::Widget->errors,
        ['widget validation failed'],
        'subclass errors use request state'
    );
    my @explicit;
    LJ::Widget->handle_error( 'explicit', \@explicit );
    is_deeply( \@explicit, ['explicit'], 'explicit error accumulator is honored' );
    is( scalar @{ LJ::Widget->errors }, 1, 'explicit errors do not leak to request accumulator' );

    $r = request( GET 'http://localhost/example' );
    LJ::Widget->handle_post( { 'Widget[RequestTest]_choice' => 'no GET mutation' }, 'RequestTest' );
    is( scalar @LJ::Widget::RequestTest::seen, 2, 'GET never dispatches a mutation' );
    is_deeply( LJ::Widget->errors, [],                   'later GET has no stale errors' );
    is_deeply( LJ::Widget::RequestTest->post_fields, {}, 'later GET has no stale POST inputs' );

    $r = request(
        POST 'http://localhost/example',
        Content => [
            'Widget[RequestTest]_choice' => 'AJAX authorized'
        ]
    );
    {
        local $LJ::WIDGET_NO_AUTH_CHECK = 1;
        LJ::Widget->handle_post( $r->post_args, 'RequestTest' );
    }
    is( scalar @LJ::Widget::RequestTest::seen, 3, 'verified AJAX authorization permits dispatch' );
    LJ::Widget->handle_post( $r->post_args, 'RequestTest' );
    is( scalar @LJ::Widget::RequestTest::seen, 3, q{AJAX authorization does not escape its scope} );

    $r = request(
        POST q{http://localhost/example},
        Content => [
            lj_form_auth                              => q{valid},
            q{Widget[RedirectTest]_submit}            => 1,
            q{Widget[AfterRedirectTest]_must_not_run} => 1,
        ]
    );
    my %redirect_result =
        LJ::Widget->handle_post( $r->post_args, qw(RedirectTest AfterRedirectTest) );
    is( $redirect_result{redirect}, q{/redirected}, q{widget redirect result is propagated} );
    is( $LJ::Widget::RedirectTest::seen, 1, q{redirecting widget dispatched} );
    is( $LJ::Widget::AfterRedirectTest::seen, 0, q{redirect stops later widget mutations} );

    $r =
        request( POST
q{http://localhost/customize/?authas=team%2Bone&show=24&show=48&search=old&page=2&page=3}
        );
    my %theme_nav_result = LJ::Widget::ThemeNav->handle_post( { search => q{new search} } );
    is(
        $theme_nav_result{redirect},
        "$LJ::SITEROOT/customize/?search=new+search&authas=team%2Bone&show=24&show=48",
        q{ThemeNav search preserves repeated encoded authas and show query values}
    );
    %theme_nav_result = LJ::Widget::ThemeNav->handle_post( { page => 4 } );
    is(
        $theme_nav_result{redirect},
        "$LJ::SITEROOT/customize/?authas=team%2Bone&show=24&show=48&search=old&page=4",
        q{ThemeNav page redirect preserves raw non-page query values}
    );

    # The BML renderer temporarily supplies its legacy error array to the cache.
    $r =
        request( POST
            q{http://localhost/customize/?page=2&mypage=2&search=homepage=2&page=3&encoded=page%3D2}
        );
    %theme_nav_result = LJ::Widget::ThemeNav->handle_post( { page => 4 } );
    is(
        $theme_nav_result{redirect},
        "$LJ::SITEROOT/customize/?mypage=2&search=homepage=2&encoded=page%3D2&page=4",
        q{ThemeNav removes only complete repeated page query parameters}
    );

    my @legacy;
    DW::Cache->request->set( 'widget', 'errors', \@legacy );
    LJ::Widget->error('legacy page error');
    is_deeply( \@legacy, ['legacy page error'], 'legacy page can bridge its own error array' );
}
{

    package WidgetRequestRemote;
    sub user { 'owner' }
}
{
    no warnings 'redefine';
    my $remote = bless {}, 'WidgetRequestRemote';
    local *LJ::get_remote      = sub { $remote };
    local *LJ::is_web_context  = sub { 1 };
    local *LJ::get_authas_user = sub { return $_[0] };
    local $BMLCodeBlock::GET{authas} = 'stale_community';
    request( GET 'http://localhost/example?authas=current_community' );
    is( LJ::get_effective_remote(), 'current_community', 'authas comes from current request' );
    request( GET 'http://localhost/example' );
    is( LJ::get_effective_remote(), $remote, 'previous BML authas does not leak' );
    request( POST 'http://localhost/example', Content => [ authas => 'post_community' ] );
    is( LJ::get_effective_remote(), 'post_community', 'widget RPC POST authas works' );
}
done_testing;
