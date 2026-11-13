# t/plack-multisearch.t
#
# Entry search in the shared search widget preserves the query and opens the
# existing content-search form without changing account lookup or access checks.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::TreeBuilder;
use Plack::Test;
use URI;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $u = temp_user();
local $LJ::IS_DEV_SERVER = 1;

with_fake_memcache {
    test_psgi $app, sub {
        my $cb = shift;

        subtest 'entry search is offered only when configured' => sub {
            for my $enabled ( 0, 1 ) {

                # Rendering and prefilling need no search-engine connection.
                local @LJ::MANTICORE = $enabled ? ( '127.0.0.1', 9312, 9306 ) : ();
                my $res = $cb->( GET 'http://localhost/tools/search?skin=gradation-vertical' );
                is( $res->code, 200, 'search tools render' );
                my $tree = HTML::TreeBuilder->new_from_content( $res->content );
                for my $region ( 'header-search', 'content' ) {
                    my $container = $tree->look_down( id => $region );
                    ok( $container, "$region search container renders" );
                    next unless $container;
                    my $entry = $container->look_down( _tag => 'option', value => 'content' );
                    is( !!$entry, !!$enabled, "$region entry option follows availability" );
                    ok( $container->look_down( _tag => 'option', value => 'nav_and_user' ),
                        "$region account lookup remains available" );
                }
                $tree->delete;
            }
        };

        subtest 'GET and POST preserve entry queries in a local redirect' => sub {
            for my $query ( 'Mixed Case "Exact phrase" & plus+ #tag? 1=2', '0', '' ) {
                my $url = URI->new('http://localhost/multisearch');
                $url->query_form( type => 'CoNtEnT', q => $query );
                for my $request (
                    GET($url),
                    POST(
                        'http://localhost/multisearch',
                        Content => [ type => 'content', q => $query ]
                    )
                    )
                {
                    my $res = $cb->($request);
                    is( $res->code, 303, 'multisearch redirects to the search form' );
                    my $location = URI->new( $res->header('Location') );
                    is( $location->path, '/search', 'destination is content search' );
                    is_deeply(
                        { $location->query_form },
                        { query => $query },
                        'query retains case and cannot inject another argument'
                    );
                    ok( !$location->fragment, 'query cannot inject a fragment' );
                }
            }
        };

        subtest 'the destination prefills without executing a search' => sub {
            local @LJ::MANTICORE = ( '127.0.0.1', 9312, 9306 );
            my $query = 'Mixed Case "Exact phrase" & plus+';
            my $url   = URI->new('http://localhost/search');
            $url->query_form( query => $query, as => $u->user );
            my $res = $cb->( GET $url );
            is( $res->code, 200, 'existing search form renders for a signed-in user' );
            my $tree  = HTML::TreeBuilder->new_from_content( $res->content );
            my $field = $tree->look_down( _tag => 'input', name => 'query' );
            is( $field ? $field->attr('value') : undef, $query, 'query is prefilled' );
            ok(
                $tree->look_down( _tag => 'input', name => 'lj_form_auth' ),
                'search still uses its existing form-auth control'
            );
            $tree->delete;
        };

        subtest 'account and fallback callers keep their destinations' => sub {
            my $url = URI->new('http://localhost/multisearch');
            $url->query_form( type => 'nav_and_user', q => uc $u->user );
            my $res = $cb->( GET $url );
            is( $res->code,               303,             'account lookup redirects' );
            is( $res->header('Location'), $u->profile_url, 'account opens its profile' );

            $res = $cb->( GET 'http://localhost/multisearch?type=unknown&q=example' );
            is(
                URI->new( $res->header('Location') )->path,
                '/tools/search',
                'unknown types still open the search tools'
            );
        };
    };
};

done_testing;
