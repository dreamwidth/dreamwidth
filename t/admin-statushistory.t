#!/usr/bin/perl
# t/admin-statushistory.t
#
# Database, controller and template regression tests for status history paging.
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
use Digest::SHA qw(sha256_hex);
use HTTP::Request::Common qw(GET POST);
use URI;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test qw(temp_user with_fake_memcache);
use DW::Controller::Admin::UserHistory;
use DW::Request::Standard;
use DW::Template;

my $dbh = LJ::get_db_writer();
my @fixture_users;

END {
    # Never touch unrelated history, even when an assertion or request dies.
    if ( $dbh && @fixture_users ) {
        my $ids = join ',', map { $_->id } @fixture_users;
        $dbh->do("DELETE FROM statushistory WHERE userid IN ($ids)");
    }
}

with_fake_memcache {
    no warnings 'redefine';

    # Authentication is supplied at the controller boundary; permission checks,
    # MySQL queries, request parsing and TT rendering all use production code.
    local $LJ::IS_DEV_SERVER = 0;
    local *LJ::remote_bounce_url = sub { undef };
    local *DW::Captcha::should_captcha_view = sub { 0 };
    local *LJ::get_db_reader = sub { $dbh };    # no test replica lag
    local *LJ::send_mail = sub { die 'Status history tests must not send mail' };
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = '2815abcdef012345';

    my ( $viewer, $limited, $plain, $subject, $other, $actor, $other_actor ) =
        map { temp_user() } 1 .. 7;
    @fixture_users = ( $subject, $other );
    ok( $viewer->grant_priv('historyview'), 'unrestricted history viewer' );

    # Include URL/HTML metacharacters in an actual stored filter value.
    my $type = 'p' . $subject->id . q{&'<>+};
    ok( length($type) <= 20, 'fixture fits the real shtype column' );
    ok( $limited->grant_priv( 'historyview', $type ), 'type-restricted history viewer' );

    my $insert = $dbh->prepare(
        'INSERT INTO statushistory (userid, adminid, shtype, shdate, notes) VALUES (?,?,?,?,?)'
    );
    my @notes = map { ( 'x' x 1100 ) . sprintf( ' synthetic row %04d', $_ ) } 1 .. 2005;
    push @notes, $notes[0], '<b>synthetic</b>' . "\n" . 'second line';

    # Every main row shares a timestamp, user, actor and type. Long notes also
    # share a prefix longer than MySQL's usual max_sort_length. Insert backwards
    # so storage order cannot accidentally satisfy the tie-breaking expectation.
    for my $note ( reverse @notes ) {
        $insert->execute( $subject->id, $actor->id, $type, '2001-01-01 00:00:00', $note );
        die $dbh->errstr if $dbh->err;
    }
    $insert->execute( $other->id, $actor->id, 'other_type', '2001-01-02 00:00:00',
        'same actor, different user and type' );
    $insert->execute( $subject->id, $other_actor->id, 'other_type', '2001-01-03 00:00:00',
        'same user, different actor and type' );
    $insert->execute( $other->id, $other_actor->id, $type, '2001-01-04 00:00:00',
        'same type, different user and actor' );
    $insert->execute( $subject->id, $actor->id, uc($type), '2001-01-05 00:00:00',
        'case-sensitive privilege must hide this' );
    my $boundary_type = 'b' . $other->id;
    for my $size ( 1000, 1001 ) {
        for my $i ( 1 .. $size ) {
            $insert->execute( $other->id, $other_actor->id, "$boundary_type-$size",
                '2001-01-01 00:00:00', "boundary $i" );
            die $dbh->errstr if $dbh->err;
        }
    }
    my $sort_type = 's' . $other->id;
    for my $i ( 1 .. 4 ) {
        $insert->execute( $i % 2 ? $subject->id : $other->id,
            $i <= 2 ? $actor->id : $other_actor->id, $sort_type,
            "2001-01-0$i 00:00:00", ( 'a', 'b', 'c', 'd' )[ $i - 1 ] );
    }
    die $dbh->errstr if $dbh->err;

    my $remote;
    local *LJ::get_remote = sub { $remote };
    local *LJ::statushistory_add = sub { die 'Viewing history must not add history' };

    my $request = sub {
        my ( $args, %opts ) = @_;
        $remote = exists $opts{remote} ? $opts{remote} : $viewer;
        LJ::start_request();
        my $uri = URI->new('http://localhost/admin/statushistory');
        $uri->query_form(%$args) unless $opts{post};
        my $http = $opts{post} ? POST( $uri, $args ) : GET($uri);
        $http->header( Host => 'localhost' );
        my $r = DW::Request::Standard->new($http);
        my ( $vars, $html, $template );

        # Render the real templates, omitting only the outer site scheme.
        local *DW::Template::render_template = sub {
            ( undef, $template, $vars ) = @_;
            $html = DW::Template->template_string( $template, $vars, {} );
            return $r->OK;
        };
        my $status = DW::Controller::Admin::UserHistory::statushistory_controller();
        return { vars => $vars, html => $html || '', template => $template,
            status => $status, r => $r };
    };

    my $history = sub {
        return $dbh->selectall_arrayref(
            'SELECT userid, adminid, shtype, shdate, notes FROM statushistory '
                . 'WHERE userid IN (?,?) '
                . 'ORDER BY shdate, userid, adminid, BINARY shtype, SHA2(notes, 256)',
            undef, $subject->id, $other->id
        );
    };
    my $before = $history->();

    my %query = ( user => $subject->user, admin => $actor->user, type => $type );
    # The existing type search is case insensitive; restrict this traversal to
    # the exact type via the viewer's real privilege, as well as all three filters.
    my @expected = sort { sha256_hex($a) cmp sha256_hex($b) } @notes;

    subtest 'traverse more than 1000 rows with timestamp and long-note ties' => sub {
        my @seen;
        for my $page ( 1 .. 3 ) {
            my $res = $request->( { %query, page => $page }, remote => $limited );
            is( $res->{template}, 'admin/statushistory.tt', 'renders the history template' );
            is_deeply( $res->{vars}{pages}, { current => $page, total_pages => 3 },
                "page $page of three" );
            my $rows = $res->{vars}{rows};
            is( scalar @$rows, $page == 3 ? 7 : 1000, 'bounded page with exact last boundary' );
            push @seen, map { $_->{notes} } @$rows;
            my @rendered_cells = $res->{html} =~ /<td>/g;
            is( scalar @rendered_cells, 5 * @$rows, 'all permitted rows really render' );
            unlike( $res->{html}, qr/\[truncated\]/, 'no obsolete truncation warning' );
        }
        is_deeply( \@seen, \@expected, 'every record appears in deterministic order, including duplicates' );
        my $first = $request->( { %query, page => 1 }, remote => $limited );
        is_deeply( [ map { $_->{notes} } @{ $first->{vars}{rows} } ],
            [ @expected[ 0 .. 999 ] ], 'revisiting a page preserves its contents' );
        my $all_html = join '', map {
            $request->( { %query, page => $_ }, remote => $limited )->{html}
        } 1 .. 3;
        like( $all_html, qr/&lt;b&gt;synthetic&lt;\/b&gt;<br \/>/,
            'history notes retain escaping and newline formatting' );
        unlike( $all_html, qr/<b>synthetic<\/b>/, 'history notes cannot inject HTML' );
    };

    subtest 'pager and sort links retain filters without retaining POST secrets' => sub {
        my $res = $request->( { %query, page => 2, orderby => 'notes', flow => 'asc',
                lj_form_auth => 'must-not-propagate', unexpected => 'must-not-propagate' },
            remote => $limited );
        my @bars = $res->{html} =~ /<ul class="pagination">(.*?)<\/ul>/sg;
        is( scalar @bars, 2, 'pager above and below the table' );
        for my $bar (@bars) {
            my @links = $bar =~ /href="([^"]+)"/g;
            ok( @links, 'pager has real navigation links' );
            for my $link (@links) {
                my $url = URI->new($link);
                my %args = $url->query_form;
                is( $url->path, '/admin/statushistory', 'correct destination' );
                is_deeply( { map { $_ => $args{$_} } qw(user admin type orderby flow) },
                    { %query, orderby => 'notes', flow => 'asc' }, 'filters and sort round-trip' );
                ok( !exists $args{lj_form_auth} && !exists $args{unexpected}, 'only search arguments retained' );
                my $dest = $request->( \%args, remote => $limited );
                is( $dest->{vars}{pages}{current}, $args{page}, 'following pager reaches requested page' );
            }
        }
        my @sort_links = $res->{html} =~ /<th><a href='([^']+)'/g;
        is( scalar @sort_links, 5, 'each column still sorts' );
        for my $link (@sort_links) {
            my %args = URI->new($link)->query_form;
            is_deeply( { map { $_ => $args{$_} } qw(user admin type) }, \%query, 'sort retains filters' );
            ok( !exists $args{page}, 'sorting restarts at the first page' );
        }
    };

    subtest 'each supported sort traverses a fixed dataset without losing records' => sub {
        for my $column (qw(user admin shdate shtype notes)) {
            for my $flow (qw(asc desc)) {
                my @seen;
                for my $page ( 1 .. 3 ) {
                    my $res = $request->( { %query, page => $page, orderby => $column,
                            flow => $flow }, remote => $limited );
                    push @seen, map { $_->{notes} } @{ $res->{vars}{rows} };
                }
                is_deeply( [ sort @seen ], [ sort @notes ], "$column $flow keeps the complete multiset" );
            }
        }
        for my $column (qw(user admin shdate notes)) {
            for my $flow (qw(asc desc)) {
                my $res = $request->( { type => $sort_type, orderby => $column, flow => $flow } );
                my @values = map { $_->{$column} } @{ $res->{vars}{rows} };
                my @sorted = sort @values;
                @sorted = reverse @sorted if $flow eq 'desc';
                is( scalar @values, 4, 'small sort fixture is complete' );
                is_deeply( \@values, \@sorted, "$column still sorts $flow" );
            }
        }
    };

    subtest 'exact page boundaries' => sub {
        for my $size ( 1000, 1001 ) {
            my $res = $request->( { type => "$boundary_type-$size" } );
            is( scalar @{ $res->{vars}{rows} }, 1000, 'first page has exactly 1000 rows' );
            is( $res->{vars}{pages}{total_pages}, $size == 1000 ? 1 : 2,
                'page count handles exact and one-over boundaries' );
            if ( $size == 1000 ) {
                unlike( $res->{html}, qr/class="pagination"/, 'no phantom page at the boundary' );
            }
            else {
                like( $res->{html}, qr/class="pagination"/, 'one extra row produces a pager' );
                $res = $request->( { type => "$boundary_type-$size", page => 2 } );
                is( scalar @{ $res->{vars}{rows} }, 1, 'second page contains the extra row' );
            }
        }
    };

    subtest 'user, admin and type searches are independent intersections' => sub {
        for my $filter (qw(user admin type)) {
            my $res = $request->( { $filter => $query{$filter} } );
            my $field = $filter eq 'type' ? 'shtype' : $filter;
            ok( !grep( { lc( $_->{$field} ) ne lc( $query{$filter} ) } @{ $res->{vars}{rows} } ),
                "$filter search excludes disjoint values" );
            is( $res->{vars}{pages}{total_pages}, 3, "$filter search includes its larger result set" );
        }
        my $res = $request->( { user => $other->user, admin => $other_actor->user, type => 'other_type' } );
        is_deeply( $res->{vars}{rows}, [], 'disjoint combination has no matches' );
        unlike( $res->{html}, qr/class="pagination"/, 'empty result has no pager' );
        $res = $request->( { user => $other->user, admin => $actor->user, type => 'other_type' } );
        is( scalar @{ $res->{vars}{rows} }, 1, 'single-page intersection' );
        unlike( $res->{html}, qr/class="pagination"/, 'single-page result has no pager' );
    };

    subtest 'invalid inputs and permission gates' => sub {
        for my $page ( '', 0, -1, 'abc', '1.5', '1e2', '01', "2\n", '2 OR 1=1',
            4, 999999999, '999999999999999999999999999999999999' ) {
            my $res = $request->( { %query, page => $page, orderby => 'invalid', flow => 'invalid' },
                remote => $limited );
            is( $res->{vars}{pages}{current}, 1, "invalid/out-of-range page '$page' uses page one" );
            is_deeply( [ map { $_->{notes} } @{ $res->{vars}{rows} } ],
                [ @expected[ 0 .. 999 ] ], 'invalid sort safely uses date descending' );
        }
        my $res = $request->( { page => 2 } );
        ok( !$res->{vars}{showtable} && !$res->{vars}{rows}, 'page alone does not search all history' );
        for my $filter (qw(user admin)) {
            $res = $request->( { %query, $filter => 'no_such_user_2815', page => 2 } );
            ok( $res->{vars}{errors}->exist && !$res->{vars}{showtable}, 'invalid user/admin still shows error' );
        }
        $res = $request->( { user => $subject->user, type => 'other_type', page => 2 }, remote => $limited );
        is_deeply( $res->{vars}{rows}, [], 'limited viewer cannot query another type' );
        is( $res->{vars}{pages}{total_pages}, 1, 'hidden rows do not affect page count' );
        unlike( $res->{html}, qr/class="pagination"|different actor|must hide/, 'no hidden data or pager leak' );
        $res = $request->( { user => $other->user, type => "$boundary_type-1001", page => 2 },
            remote => $limited );
        is_deeply( $res->{vars}{rows}, [], 'more than 1000 hidden rows stay hidden' );
        is( $res->{vars}{pages}{total_pages}, 1, 'hidden multi-page result does not leak its size' );
        unlike( $res->{html}, qr/class="pagination"/, 'hidden multi-page result has no navigation' );
        $res = $request->( { %query, page => 2 }, remote => $plain );
        is( $res->{template}, 'error.tt', 'unprivileged viewer is rejected before history rendering' );
        ok( !$res->{vars}{rows}, 'no history rows returned to unprivileged viewer' );
        {
            local $LJ::IS_DEV_SERVER = 1;
            $res = $request->( { %query, page => 2 }, remote => $plain );
            is( $res->{template}, 'admin/statushistory.tt', 'existing development-server exemption remains' );
            is( scalar @{ $res->{vars}{rows} }, 1000, 'development viewer can page' );
        }
        ok( $plain->grant_priv( 'historyview', '*' ), 'wildcard viewer' );
        $res = $request->( { %query, page => 2 }, remote => $plain );
        is( scalar @{ $res->{vars}{rows} }, 1000, 'wildcard historyview still permits every type' );
        $res = $request->( { %query, page => 2 }, remote => undef );
        is( $res->{status}, $res->{r}->REDIRECT, 'anonymous viewer must log in' );
        ok( !$res->{template}, 'anonymous request does not render history' );
        $res = $request->( \%query, post => 1 );
        is( $res->{template}, 'error.tt', 'POST still requires form authentication' );
        ok( !$res->{vars}{rows}, 'invalid POST has no history rows' );

        # A real form token proves the existing POST search can generate GET links.
        $request->( \%query );
        my $token = LJ::form_auth(1);
        $res = $request->( { %query, lj_form_auth => $token }, post => 1 );
        is( $res->{template}, 'admin/statushistory.tt', 'valid POST search remains supported' );
        like( $res->{html}, qr/class="pagination"/, 'POST search renders a pager' );
        unlike( $res->{html}, qr/href=[^>]*lj_form_auth/, 'POST authentication token stays out of links' );
    };

    is_deeply( $history->(), $before, 'searching, sorting and pagination never change history' );
};

done_testing;
