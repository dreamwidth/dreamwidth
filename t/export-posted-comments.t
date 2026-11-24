# t/export-posted-comments.t
#
# Test downloads of comments authored by the signed-in user.
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
use DateTime;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use HTTP::Request::Common;
use LJ::Protocol;
use LJ::Test qw( temp_user );
use Plack::Test;
use Time::Local qw( timegm );

local $LJ::DISABLED{adult_content} = 0;
my $owner  = temp_user();
my $author = temp_user();
$author->set_prop( init_bdate         => DateTime->now->subtract( years => 17 )->ymd );
$author->set_prop( hide_adult_content => 'concepts' );
my $entry   = $owner->t_post_fake_entry( subject => 'entry-only-subject' );
my $parent  = $entry->t_enter_comment( u => $owner, body => 'other-author-body' );
my $comment = $parent->t_reply(
    u       => $author,
    subject => 'own-subject',
    body    => qq{own "quoted", <reply> & text\nnext line},
);
my $screened = $entry->t_enter_comment( u => $author, body => 'own-screened-body' );
LJ::Talk::screen_comment( $owner, $entry->jitemid, $screened->jtalkid );
my $deleted = $entry->t_enter_comment( u => $author, body => 'deleted-body' );
$deleted->delete;
my $restricted = $owner->t_post_fake_entry( security => 'friends' );
ok( $owner->add_edge( $author, trust => { nonotify => 1 } ), 'grant access for posting' );
ok( $restricted->visible_to($author), 'restricted entry is visible before revocation' );
$restricted->t_enter_comment( u => $author, state => 'S', body => 'revoked-body' );
ok( $owner->remove_edge( $author, trust => { nonotify => 1 } ), 'revoke access after posting' );
ok( !$restricted->visible_to($author), 'restricted entry is no longer visible' );
my $explicit = $owner->t_post_fake_entry( subject => 'Explicit fixture entry' );
$explicit->t_enter_comment( u => $author, body => 'age-blocked-body' );
$explicit->set_prop( adult_content => 'explicit' );
my $concepts = $owner->t_post_fake_entry( subject => 'Concepts fixture entry' );
$concepts->t_enter_comment( u => $author, body => 'soft-warning-body' );
$concepts->set_prop( adult_content => 'concepts' );

my $author_db = LJ::get_cluster_master($author);
my $owner_db  = LJ::get_cluster_master($owner);
my $retime    = sub {
    my ( $target, $timestamp ) = @_;
    $author_db->do( 'UPDATE talkleft SET posttime=? WHERE userid=? AND journalid=? AND jtalkid=?',
        undef, $timestamp, $author->id, $owner->id, $target->jtalkid );
};
$author_db->do(
    q{INSERT INTO talkleft (userid, posttime, journalid, nodetype, nodeid, jtalkid)
        VALUES (?, ?, ?, 'L', ?, ?)},
    undef, $author->id, $parent->unixtime, $owner->id, $entry->jitemid, $parent->jtalkid
);

DW::Request->reset;
DW::Request::Standard->new( GET 'http://www.dw.test/' );
my $error;
my $session =
    LJ::Protocol::do_request( 'sessiongenerate',
    { username => $author->user, expiration => 'short' },
    \$error, { noauth => 1 } );
DW::Request->reset;
my $cookie  = 'ljsession=' . ( $session->{ljsession} or die "sessiongenerate: $error" );
my $app     = do "$ENV{LJHOME}/app.psgi" or die $@;
my $test    = Plack::Test->create($app);
my $page    = $test->request( GET 'http://www.dw.test/export', Cookie => $cookie );
my ($token) = $page->content =~ /name=["']lj_form_auth["'][^>]*value=["']([^"']+)/;
ok( $token, 'export page provides form authorization' ) or diag( $page->status_line );

my ( $month, $year ) = ( gmtime( $comment->unixtime ) )[ 4, 5 ];
my $download = sub {
    my ( $format, %extra ) = @_;
    return $test->request(
        POST 'http://www.dw.test/export_posted_comments',
        Cookie  => $cookie,
        Content => {
            lj_form_auth => $token,
            format       => $format,
            year         => $year + 1900,
            month        => $month + 1,
            %extra
        },
    );
};

my $xml      = $download->('xml');
my $xml_body = $xml->header('Content-Disposition') ? $xml->content : '';
ok( $xml->is_success, 'XML download succeeds' ) or diag( $xml->status_line );
like( $xml->header('Content-Disposition'), qr/attachment;.*\.xml/, 'XML is an attachment' );
like( $xml_body, qr{<subject>own-subject</subject>}, 'exports my subject' );
like(
    $xml_body,
    qr{own &quot;quoted&quot;, &lt;reply&gt; &amp; text\nnext line},
    'exports my body with XML escaping'
);
like( $xml_body, qr{<journal>\Q${\ $owner->user }\E</journal>}, 'includes the journal' );
like(
    $xml_body,
    qr{<permalink>[^<]+\?thread=\Q${\ $comment->dtalkid }\E\b},
    'includes the direct comment link'
);
like(
    $xml_body,
    qr{<datetime>\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|\+00:00)</datetime>},
    'includes the timestamp in UTC'
);
like( $xml_body, qr/own-screened-body/, 'includes my screened comment when I can see it' );
like( $xml_body, qr/soft-warning-body/, 'a soft viewing warning does not block my comment' );
unlike(
    $xml_body,
    qr/entry-only-subject|other-author-body|revoked-body|deleted-body|age-blocked-body/,
    'excludes stale foreign index rows, revoked access, deleted comments and the hard age block'
);
my @comments = $xml_body =~ /<comment>/g;
is( scalar @comments, 3, 'only eligible comments are exported' );

my $csv      = $download->('csv');
my $csv_body = $csv->header('Content-Disposition') ? $csv->content : '';
like( $csv->header('Content-Disposition'), qr/attachment;.*\.csv/, 'CSV is an attachment' );
like( $csv_body, qr/^journal,permalink,datetime,subject,body,icon_keyword\n/, 'CSV has a header' );
like(
    $csv_body,
    qr/"own ""quoted"", <reply> & text\nnext line"/,
    'CSV quotes commas, quotes and line breaks'
);
my $empty = $download->( 'xml', year => 2000 );
like(
    $empty->content,
    qr{\A<\?xml[^\n]+\n<comments>\n</comments>\n\z},
    'empty export outside the selected month'
);
ok( !$download->( 'xml', month => 13 )->header('Content-Disposition'), 'rejects invalid dates' );
ok( !$download->( 'xml', year => 2023, month => 2, day => 29 )->header('Content-Disposition'),
    'rejects a nonexistent day' );
ok( !$download->( 'xml', lj_form_auth => '' )->header('Content-Disposition'),
    'rejects missing form authorization' );

my $boundary = $entry->t_enter_comment( u => $author, body => 'day-end-boundary' );
my $adjacent = $entry->t_enter_comment( u => $author, body => 'next-month-boundary' );
my $march = timegm( 0, 0, 0, 1, 2, 2024 );
$retime->( $boundary, $march - 1 );
$retime->( $adjacent, $march );
my $leap_day = $download->( 'xml', year => 2024, month => 2, day => 29 );
like( $leap_day->header('Content-Disposition'), qr/-2024-02-29\.xml/, 'day in filename' );
like( $leap_day->content, qr/day-end-boundary/, 'includes the last second of the leap day' );
unlike( $leap_day->content, qr/next-month-boundary/, 'excludes the next UTC month' );

{
    my $reader = \&LJ::get_cluster_reader;
    no warnings 'redefine';
    local *LJ::get_cluster_reader = sub {
        my $dbh = $reader->(@_);
        return $dbh unless caller eq 'DW::Controller::Export' && $_[0]->id == $author->id;
        return bless { dbh => $dbh, talkleft_filter => '1 = 0' }, 'PostedCommentsTestDB';
    };

    my $lagged = $download->( 'xml', year => 2024, month => 3, day => 1 );
    is( $lagged->code, 200, 'an index replica miss does not abort the download' );
    like( $lagged->content, qr/next-month-boundary/,
        'exports the comment missing from the replica index' );
}

{
    my $master = \&LJ::get_cluster_master;
    no warnings 'redefine';
    for my $failure ( 'unavailable', 'query error' ) {
        local *LJ::get_cluster_master = sub {
            return $master->(@_)
                unless caller eq 'DW::Controller::Export' && $_[0]->id == $author->id;
            return if $failure eq 'unavailable';
            return bless { dbh => $master->(@_), talkleft_filter => 'no_such_column = 1' },
                'PostedCommentsTestDB';
        };
        my $failed = $download->( 'xml', year => 2024, month => 3, day => 1 );
        is( $failed->code, 503, "index lookup with primary $failure returns HTTP 503" );
        ok( !$failed->header('Content-Disposition'), 'failed index lookup is not an attachment' );
    }
}

{
    my $reader    = \&LJ::get_cluster_reader;
    my $master    = \&LJ::get_cluster_master;
    my $journalid = $owner->id;
    my $jtalkid   = $adjacent->jtalkid;
    LJ::Talk::invalidate_talk2row_memcache( $journalid, $jtalkid );

    no warnings 'redefine';
    local *LJ::get_cluster_reader = sub {
        my $dbh = $reader->(@_);
        return $dbh unless ( caller(1) )[3] eq 'LJ::Talk::get_talk2_row_multi';
        return bless { dbh => $dbh, journalid => $journalid, jtalkid => $jtalkid },
            'PostedCommentsTestDB';
    };

    my $lagged = $download->( 'xml', year => 2024, month => 3, day => 1 );
    is( $lagged->code, 200, 'a metadata replica miss does not abort the download' );
    like( $lagged->content, qr/next-month-boundary/,
        'exports the live comment missing on the replica' );

    for my $failure ( 'unavailable', 'query error' ) {
        local *LJ::get_cluster_master = sub {
            return $master->(@_)
                unless caller eq 'DW::Controller::Export' && $_[0]->id == $journalid;
            return if $failure eq 'unavailable';
            return bless { dbh => $master->(@_) }, 'PostedCommentsTestDB';
        };
        my $failed = $download->( 'xml', year => 2024, month => 3, day => 1 );
        is( $failed->code, 503, "metadata retry with primary $failure returns HTTP 503" );
        ok( !$failed->header('Content-Disposition'), 'failed metadata retry is not an attachment' );
    }
}

my $absent_id = $adjacent->jtalkid + 1000;
$author_db->do(
    q{INSERT INTO talkleft (userid, posttime, journalid, nodetype, nodeid, jtalkid)
        VALUES (?, ?, ?, 'L', ?, ?)},
    undef, $author->id, $march, $owner->id, $entry->jitemid, $absent_id
) or die $author_db->errstr;
my $stale = $download->( 'xml', year => 2024, month => 3, day => 1 );
is( $stale->code, 200, 'a comment absent on primary does not abort the download' );
my @remaining = $stale->content =~ /<comment>/g;
is( scalar @remaining, 1, 'skips the stale index row and keeps the live comment' );

my $unavailable = $entry->t_enter_comment( u => $author, body => 'missing-text-fixture' );
$retime->( $unavailable, $march - 1 );
$owner_db->do( 'DELETE FROM talktext2 WHERE journalid=? AND jtalkid=?',
    undef, $owner->id, $unavailable->jtalkid );
my $retry = $download->( 'xml', year => 2024, month => 2 );
is( $retry->code, 503, 'live comment without text makes the whole export retryable' );
ok( !$retry->header('Content-Disposition'), 'retry response is not an attachment' );
like( $retry->content, qr/try again later/i, 'retry response explains how to proceed' );
unlike( $retry->content, qr/day-end-boundary/, 'retry response contains no partial export' );
LJ::Talk::delete_comment( $owner, $entry->jitemid, $unavailable->jtalkid, 'A' );

my $vanishing = $entry->t_enter_comment( u => $author, body => 'vanishing-body' );
$retime->( $vanishing, $march - 1 );
my $vanishing_id = $vanishing->jtalkid;
{
    my $load_text = \&DW::Controller::Export::_read_posted_comment_text;
    my $removed;
    no warnings 'redefine';
    local *DW::Controller::Export::_read_posted_comment_text = sub {
        my ( undef, $journal, $comments ) = @_;
        if (  !$removed
            && $journal->id == $owner->id
            && grep { $_->jtalkid == $vanishing_id } @$comments )
        {
            $removed = LJ::Talk::delete_comment( $owner, $entry->jitemid, $vanishing_id, 'A' );
        }
        return $load_text->(@_);
    };
    my $recovered = $download->( 'xml', year => 2024, month => 2 );
    ok( $removed, 'fixture was deleted between eligibility and text reads' );
    is( $recovered->code, 200, 'confirmed deletion does not abort the download' );
    like( $recovered->content, qr/day-end-boundary/, 'keeps the remaining eligible comment' );
    unlike( $recovered->content, qr/vanishing-body/, 'omits the disappeared comment' );
}

my @index_rows = (q{(?, ?, ?, 'L', ?, ?)}) x 500;
$author_db->do(
    'INSERT INTO talkleft (userid, posttime, journalid, nodetype, nodeid, jtalkid) VALUES '
        . join( ',', @index_rows ),
    undef,
    ( $author->id, $march - 86401, $owner->id, $entry->jitemid, $boundary->jtalkid ) x 500
);
my $oversized = $download->( 'xml', year => 2024, month => 2 );
is( $oversized->code, 422, 'rejects a month over the candidate limit' );
ok( !$oversized->header('Content-Disposition'), 'row limit does not produce a partial archive' );
like( $oversized->content, qr/select a day/i, 'month limit offers a narrower download' );
my $narrow = $download->( 'xml', year => 2024, month => 2, day => 29 );
like( $narrow->content, qr/day-end-boundary/, 'the narrower request succeeds' );

my $january = timegm( 0, 0, 0, 1, 0, 2024 );
for my $number ( 1 .. 26 ) {
    my $large = $entry->t_enter_comment( u => $author, body => $number . ( '&' x 65000 ) );
    $retime->( $large, $january + ( $number % 2 ) * 86400 );
}
my $too_many_bytes = $download->( 'xml', year => 2024, month => 1 );
is( $too_many_bytes->code, 422, 'caps response bytes after XML escaping below the row limit' );
ok( !$too_many_bytes->header('Content-Disposition'), 'byte limit does not produce an attachment' );

package PostedCommentsTestDB {

    sub prepare {
        my ( $self, $sql, @args ) = @_;
        $sql =~ s{(FROM talk2 WHERE )(.+)}
            {$1($2) AND (journalid <> $self->{journalid} OR jtalkid <> $self->{jtalkid})};
        return $self->{dbh}->prepare( $sql, @args );
    }

    sub selectall_arrayref {
        my ( $self, $sql, @args ) = @_;
        if ( defined $self->{talkleft_filter} ) {
            $sql =~ s/FROM talkleft WHERE /FROM talkleft WHERE $self->{talkleft_filter} AND /;
        }
        $sql .= ' AND no_such_column = 1' if $sql =~ /FROM talk2 WHERE /;
        return $self->{dbh}->selectall_arrayref( $sql, @args );
    }

    sub err { return $_[0]->{dbh}->err }
}

done_testing;
