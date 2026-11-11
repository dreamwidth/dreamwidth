# t/plack-memories-keyword.t
#
# Unknown memory categories must not be reported as database outages.
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
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::Memories;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $u              = temp_user();
my $base           = 'http://localhost/tools/memories?user=' . $u->user;
my $database_error = qr/Database temporarily unavailable/i;

with_fake_memcache {
    for my $spec (
        [ 'Known public',  'public',  'Public memory example' ],
        [ 'Known private', 'private', 'Private memory secret' ]
        )
    {
        my ( $keyword, $security, $des ) = @$spec;
        my $entry = $u->t_post_fake_entry( subject => $keyword, body => $des );
        LJ::Memories::create(
            $u,
            {
                journalid => $u->id,
                ditemid   => $entry->ditemid,
                des       => $des,
                security  => $security
            },
            [ $u->get_keyword_id($keyword) ]
        ) or die 'Could not create memory fixture';
    }

    test_psgi $app, sub {
        my $cb = shift;
        {
            no warnings 'redefine';
            my $lookup = \&LJ::Memories::get_by_keyword;
            my $calls  = 0;
            local *LJ::Memories::get_by_keyword = sub { $calls++; return $lookup->(@_); };
            for my $keyword ( 'No such category', 'Missing & category' ) {
                my $res = $cb->( GET $base . '&keyword=' . LJ::eurl($keyword) );
                is( $res->code, 404, "$keyword returns not found" );
                ok( $res->content =~ /find that page/i, "$keyword uses the standard error page" );
                ok( $res->content !~ $database_error, "$keyword does not claim a database outage" );
            }
            is( $calls, 0, 'Unknown categories never reach the memory lookup' );
        }

        my $public = $cb->( GET $base . '&keyword=' . LJ::eurl('Known public') );
        is( $public->code, 200, 'Known public category still renders' );
        like( $public->content, qr/Public memory example/, 'The public memory remains visible' );
        unlike( $public->content, $database_error, 'Known category is not an outage' );

        my $private = $cb->( GET $base . '&keyword=' . LJ::eurl('Known private') );
        is( $private->code, 200, 'An existing category with no visible memories still renders' );
        unlike(
            $private->content,
            qr/Private memory secret/,
            'Private memories stay hidden from anonymous visitors'
        );
        unlike( $private->content, $database_error, 'An empty filtered result is not an outage' );

        my $categories = $cb->( GET $base );
        is( $categories->code, 200, 'Category listing still renders' );
        like( $categories->content, qr/Known public/, 'Public category remains listed' );

        {
            no warnings 'redefine';
            local *LJ::Memories::get_by_keyword = sub { return undef };
            my $res = $cb->( GET $base . '&keyword=' . LJ::eurl('Known public') );
            like( $res->content, $database_error,
                'A failed known-category lookup retains the database error' );
            isnt( $res->code, 404, 'A lookup failure is not classified as an unknown category' );
        }
        {
            no warnings 'redefine';
            local *LJ::Memories::get_keywords = sub { return undef };
            my $res = $cb->( GET $base . '&keyword=' . LJ::eurl('Known public') );
            like( $res->content, $database_error,
                'A failed category-map lookup retains the database error' );
            isnt( $res->code, 404,
                'A category-map failure is not classified as an unknown category' );
        }
    };
};

done_testing;
