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

        my $failure_code;
        {
            no warnings 'redefine';
            local *LJ::Memories::get_by_keyword = sub { return undef };
            my $res = $cb->( GET $base . '&keyword=' . LJ::eurl('Known public') );
            like( $res->content, $database_error,
                'A failed known-category lookup retains the database error' );
            isnt( $res->code, 404, 'A lookup failure is not classified as an unknown category' );
            $failure_code = $res->code;
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

        # Fail each real keyword-map SELECT on the database handle itself, so the
        # helper sees the same nonthrowing DBI error a lost connection produces.
        my $memkey     = [ $u->id, 'memkwid:' . $u->id ];
        my $def_reader = \&LJ::get_cluster_def_reader;
        my $reader     = \&LJ::get_cluster_reader;
        for my $spec (
            [ 'category ID query',   qr/^SELECT DISTINCT kwid FROM memkeyword2 / ],
            [ 'category name query', qr/^SELECT kwid, keyword FROM userkeywords / ],
            )
        {
            my ( $label, $query ) = @$spec;
            LJ::Memories::clear_memcache($u);
            {
                no warnings 'redefine';
                local *LJ::get_cluster_def_reader = failing_reader( $def_reader, $query );
                local *LJ::get_cluster_reader     = failing_reader( $reader,     $query );

                ok( !defined LJ::Memories::get_keywords($u), "A failed $label returns an error" );
                ok( !defined LJ::MemCache::get($memkey),     "A failed $label is not cached" );

                my $res = $cb->( GET $base . '&keyword=' . LJ::eurl('Known public') );
                is( $res->code, $failure_code, "A failed $label keeps the lookup-failure status" );
                like( $res->content, $database_error, "A failed $label reports a database error" );
                unlike( $res->content, qr/find that page/i, "A failed $label is not missing" );

                my $list = $cb->( GET $base );
                like( $list->content, $database_error, "A failed $label fails the category list" );
            }

            my $res = $cb->( GET $base . '&keyword=' . LJ::eurl('Known public') );
            is( $res->code, 200, "The category renders once the $label recovers" );
            like( $res->content, qr/Public memory example/, 'Its memory is visible again' );
            my $cached = LJ::MemCache::get($memkey);
            ok( $cached && scalar( grep { $_ eq 'Known public' } values %$cached ),
                'Only the successful map is cached' );
        }

        {
            no warnings 'redefine';
            LJ::Memories::clear_memcache($u);
            local *LJ::get_cluster_def_reader = failing_reader($def_reader);
            local *LJ::get_cluster_reader     = failing_reader($reader);
            my $map = eval { LJ::Memories::get_keywords($u) };
            ok( !$@ && !defined $map, 'No database handle returns an error instead of dying' );
            my $res = $cb->( GET $base . '&keyword=' . LJ::eurl('Known public') );
            is( $res->code, $failure_code, 'No database handle keeps the lookup-failure status' );
            like( $res->content, $database_error, 'No database handle reports the database error' );
        }
    };
};

# Wraps a cluster-handle getter for LJ::Memories::get_keywords only. With a query
# pattern, matching SQL gains an unknown column so MySQL rejects it; without one,
# the getter reports that no handle is available.
sub failing_reader {
    my ( $getter, $query ) = @_;
    return sub {
        my $dbh = $getter->(@_);
        return $dbh  unless ( ( caller(1) )[3] // '' ) eq 'LJ::Memories::get_keywords';
        return undef unless $query;
        return FailingQueryHandle->new( $dbh, $query );
    };
}

package FailingQueryHandle;

our $AUTOLOAD;

sub new {
    my ( $class, $dbh, $query ) = @_;
    return bless { dbh => $dbh, query => $query }, $class;
}

sub selectcol_arrayref { return $_[0]->_select( 'selectcol_arrayref', @_[ 1 .. $#_ ] ) }
sub selectall_arrayref { return $_[0]->_select( 'selectall_arrayref', @_[ 1 .. $#_ ] ) }

sub _select {
    my ( $self, $method, $sql, @args ) = @_;
    $sql .= ' AND no_such_column = 1' if $sql =~ $self->{query};
    return $self->{dbh}->$method( $sql, @args );
}

sub AUTOLOAD {
    my $self = shift;
    ( my $method = $AUTOLOAD ) =~ s/.*:://;
    return $self->{dbh}->$method(@_);
}

sub DESTROY { }

package main;

done_testing;
