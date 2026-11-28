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

{
    my $master = \&LJ::get_cluster_master;
    no warnings 'redefine';
    local *LJ::get_cluster_master = sub {
        my $dbh = $master->(@_);
        return $dbh unless caller eq 'DW::Controller::Export' && $_[0]->id == $owner->id;
        return bless { dbh => $dbh, fail_logprop2 => 1 }, 'PostedCommentsTestDB';
    };

    my $failed = $download->('xml');
    is( $failed->code, 503, 'entry property query error returns HTTP 503' );
    ok(
        !$failed->header('Content-Disposition'),
        'entry property error does not send an attachment'
    );
    unlike(
        $failed->content,
        qr/<comments>|own-subject|age-blocked-body/,
        'entry property error does not send partial output'
    );
}

my $recovered_props = $download->('xml');
is( $recovered_props->code, 200, 'export succeeds when the destination property read recovers' );
like( $recovered_props->header('Content-Disposition'),
    qr/attachment/, 'recovery sends an attachment' );
like( $recovered_props->content, qr/own-subject/, 'recovery includes the visible comment' );
unlike( $recovered_props->content, qr/age-blocked-body/, 'recovery preserves the hard age block' );

{
    ok( $owner->add_edge( $author, trust => { nonotify => 1 } ), 'restore access to the entry' );
    my $allowed = $download->('xml');
    like( $allowed->content, qr/revoked-body/, 'restored access includes the locked comment' );
    my ( $ownerid, $authorid ) = ( $owner->id, $author->id );
    LJ::MemCache::delete( [ $ownerid, "trustmask:$ownerid:$authorid" ] );

    my $reader = \&LJ::get_db_reader;
    no warnings 'redefine';
    local *LJ::get_db_reader = sub {
        my $dbh = $reader->(@_);
        return $dbh unless caller eq 'DW::User::Edges::WatchTrust::Loader';
        return bless { dbh => $dbh }, 'PostedCommentsTestDB';
    };
    my $failed = $download->('xml');
    is( $failed->code, 503, 'trustmask query error returns HTTP 503' );
    ok( !$failed->header('Content-Disposition'), 'trustmask error does not send an attachment' );
    unlike( $failed->content, qr/<comments>|own-subject/,
        'trustmask error sends no partial export' );
    ok( $owner->remove_edge( $author, trust => { nonotify => 1 } ), 'revoke restored access' );
}

my $legacy = $entry->t_enter_comment( u => $author, body => 'legacy fixture' );
$retime->( $legacy, timegm( 0, 0, 0, 1, 0, 2023 ) );
ok( $owner->update_self( { oldenc => 10 } ), 'set the journal legacy encoding to ISO-8859-1' );
my $mapid = $author->get_mapid_from_keyword( 'legacy-icon', create => 1 ) or die 'icon mapid';
$legacy->set_props( unknown8bit => 1, picture_mapid => $mapid );
$owner_db->do( 'UPDATE talktext2 SET subject=?, body=? WHERE journalid=? AND jtalkid=?',
    undef, "caf\xE9", "cr\xE8me", $owner->id, $legacy->jtalkid )
    or die $owner_db->errstr;
{
    my $reader     = \&LJ::get_cluster_reader;
    my $def_reader = \&LJ::get_cluster_def_reader;
    no warnings 'redefine';
    local *LJ::get_cluster_reader = sub {
        return if caller eq 'LJ' && ( caller(1) )[3] eq 'LJ::load_talk_props2';
        return $reader->(@_);
    };
    local *LJ::get_cluster_def_reader = sub {
        return if caller eq 'LJ' && ( caller(1) )[3] eq 'LJ::load_talk_props2';
        return $def_reader->(@_);
    };
    my $journalid = $owner->id;
    my $jtalkid   = $legacy->jtalkid;
    LJ::MemCache::delete( [ $journalid, "talkprop:$journalid:$jtalkid" ] );
    my $available = $download->( 'xml', year => 2023, month => 1 );
    is( $available->code, 200, 'export works without a comment-property reader' );
    like(
        $available->content,
        qr{<icon_keyword>legacy-icon</icon_keyword>},
        'exports the icon keyword'
    );
    like( $available->content, qr{<subject>caf\xC3\xA9</subject>}, 'converts the legacy subject' );
    like( $available->content, qr{<body>cr\xC3\xA8me</body>},      'converts the legacy body' );

    my $master = \&LJ::get_cluster_master;
    local *LJ::get_cluster_master = sub {
        my $dbh = $master->(@_);
        return $dbh unless caller eq 'DW::Controller::Export' && $_[0]->id == $journalid;
        return bless { dbh => $dbh, fail_talkprop2 => 1 }, 'PostedCommentsTestDB';
    };
    my $failed = $download->( 'xml', year => 2023, month => 1 );
    is( $failed->code, 503, 'comment property query error returns HTTP 503' );
    ok( !$failed->header('Content-Disposition'), 'comment property error sends no attachment' );
    unlike( $failed->content, qr/<comments>/, 'comment property error sends no partial export' );
}

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
    my $writer        = \&LJ::get_db_writer;
    my $reader        = \&LJ::get_db_reader;
    my $faulty_lookup = sub {
        my ( $failure, $get_db ) = @_;
        return sub {
            return $get_db->(@_)
                unless caller eq 'DW::Controller::Export'
                || ( caller(1) )[3] eq 'LJ::load_userids_multiple';
            return if $failure eq 'unavailable';
            return bless { dbh => $get_db->(@_), fail_user => 1 }, 'PostedCommentsTestDB';
        };
    };

    local $LJ::CACHE_NO_ISAM{user} = 1;
    no warnings 'redefine';
    for my $failure ( 'query error', 'unavailable' ) {
        local *LJ::get_db_writer = $faulty_lookup->( $failure, $writer );
        local *LJ::get_db_reader = $faulty_lookup->( $failure, $reader );
        LJ::memcache_kill( $owner->id, 'userid' );
        my $failed = $download->( 'xml', year => 2024, month => 3, day => 1 );
        is( $failed->code, 503, "central user lookup with $failure returns HTTP 503" );
        ok( !$failed->header('Content-Disposition'), 'central user failure is not an attachment' );
        unlike(
            $failed->content,
            qr/<comments>|next-month-boundary/,
            'central user failure sends no archive data'
        );
    }
}

{
    my ($missing_journalid) =
        LJ::get_db_writer()->selectrow_array('SELECT MAX(userid) + 1 FROM user');
    $author_db->do(
        q{INSERT INTO talkleft (userid, posttime, journalid, nodetype, nodeid, jtalkid)
            VALUES (?, ?, ?, 'L', ?, ?)},
        undef, $author->id, $march, $missing_journalid, $entry->jitemid, $adjacent->jtalkid
    ) or die $author_db->errstr;
    my $available = $download->( 'xml', year => 2024, month => 3, day => 1 );
    is( $available->code, 200, 'a confirmed missing journal does not abort the download' );
    like( $available->content, qr/next-month-boundary/, 'keeps the comment in the live journal' );
    my @comments = $available->content =~ /<comment>/g;
    is( scalar @comments, 1, 'skips the index row for the missing journal' );
    $author_db->do( 'DELETE FROM talkleft WHERE userid=? AND journalid=?',
        undef, $author->id, $missing_journalid )
        or die $author_db->errstr;
}

{
    my $loaded = DW::Controller::Export::_load_posted_entry_metadata( $owner,
        { $concepts->jitemid => $concepts } );
    ok( $loaded->{ $concepts->jitemid }, 'an entry with comments is recognized as live' );
    is( $concepts->prop('adult_content'), 'concepts', 'preloads the stored age restriction' );
    is( $concepts->prop('replycount'),    undef,      'reply count is not an entry property' );
}

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

{
    my $reader = \&LJ::get_cluster_def_reader;
    my $master = \&LJ::get_cluster_master;
    my $key    = [ $owner->id, 'log2:' . $owner->id . ':' . $entry->jitemid ];

    no warnings 'redefine';
    local *LJ::get_cluster_def_reader = sub {
        return
            if caller eq 'LJ' && ( caller(1) )[3] eq 'LJ::get_log2_row' && $_[0]->id == $owner->id;
        return $reader->(@_);
    };

    LJ::MemCache::delete($key);
    my $reader_down = $download->( 'xml', year => 2024, month => 3, day => 1 );
    is( $reader_down->code, 200,
        'an unavailable entry reader does not abort a primary-backed export' );
    like( $reader_down->content, qr/next-month-boundary/,
        'exports the live entry comment from primary' );

    for my $failure ( 'unavailable', 'query error' ) {
        local *LJ::get_cluster_master = sub {
            return $master->(@_)
                unless caller eq 'DW::Controller::Export' && $_[0]->id == $owner->id;
            return if $failure eq 'unavailable';
            return bless { dbh => $master->(@_), fail_log2 => 1 }, 'PostedCommentsTestDB';
        };
        LJ::MemCache::delete($key);
        my $failed = $download->( 'xml', year => 2024, month => 3, day => 1 );
        is( $failed->code, 503, "entry lookup with primary $failure returns HTTP 503" );
        ok( !$failed->header('Content-Disposition'), 'failed entry lookup is not an attachment' );
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

{
    my $reply =
        $parent->t_reply( u => $author, state => 'S', body => 'screened-reply-reader-outage' );
    $retime->( $reply, $march );
    ok( $reply->is_screened, 'outage fixture is screened' );
    is( $reply->parenttalkid, $parent->jtalkid, 'outage fixture replies to another author' );

    my $reader           = \&LJ::get_cluster_reader;
    my $master           = \&LJ::get_cluster_master;
    my $journalid        = $owner->id;
    my $clusterid        = $owner->clusterid;
    my @uncached_talkids = map { $_->jtalkid } ( $adjacent, $reply, $parent );

    no warnings 'redefine';
    local *LJ::get_cluster_reader = sub {
        return if ( caller(1) )[3] eq 'LJ::Talk::get_talk2_row_multi' && $_[0] == $clusterid;
        return $reader->(@_);
    };

    for my $failure ( 'unavailable', 'query error' ) {
        local *LJ::get_cluster_master = sub {
            return $master->(@_)
                unless caller eq 'DW::Controller::Export' && $_[0]->id == $journalid;
            return if $failure eq 'unavailable';
            return bless { dbh => $master->(@_) }, 'PostedCommentsTestDB';
        };
        LJ::Talk::invalidate_talk2row_memcache( $journalid, @uncached_talkids );
        my $failed = $download->( 'xml', year => 2024, month => 3, day => 1 );
        is( $failed->code, 503, "reader outage with primary $failure returns HTTP 503" );
        ok( !$failed->header('Content-Disposition'), 'reader outage does not send an attachment' );
        unlike(
            $failed->content,
            qr/<comments>|next-month-boundary|screened-reply-reader-outage/,
            'reader outage does not send partial output'
        );
    }

    LJ::Talk::invalidate_talk2row_memcache( $journalid, @uncached_talkids );
    my ( $recovered, @warnings );
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        $recovered = $download->( 'xml', year => 2024, month => 3, day => 1 );
    }
    like(
        join( '', @warnings ),
        qr/unable to get cluster reader: $clusterid\b/,
        'primary fallback logs the replica error'
    );
    is( $recovered->code, 200, 'primary recovers the export while the reader is still down' );
    like( $recovered->header('Content-Disposition'),
        qr/attachment/, 'recovered XML is an attachment' );
    like( $recovered->content, qr/next-month-boundary/,
        'recovered export contains the live comment' );
    like(
        $recovered->content,
        qr/screened-reply-reader-outage/,
        'recovered export includes the screened reply without loading its parent'
    );
    my @recovered_comments = $recovered->content =~ /<comment>/g;
    is( scalar @recovered_comments, 2, 'primary retry skips the stale index row' );

    LJ::Comment->reset_singletons;
    LJ::Talk::invalidate_talk2row_memcache( $journalid, $adjacent->jtalkid );
    my $pending = LJ::Comment->new( $owner, jtalkid => $adjacent->jtalkid );
    eval { LJ::Comment->preload_rows( discard_pending => 1 ) };
    like( $@, qr/unable to get cluster reader/, 'failed preload reports the reader outage' );
    my $invalid = eval { !$pending->valid };
    ok( $invalid, 'discarded pending comment can be checked without querying the reader again' );
}

my $deleted_entry = $owner->t_post_fake_entry;
$retime->( $deleted_entry->t_enter_comment( u => $author, body => 'deleted-entry-body' ), $march );
$owner_db->do( 'DELETE FROM log2 WHERE journalid=? AND jitemid=?',
    undef, $owner->id, $deleted_entry->jitemid )
    or die $owner_db->errstr;
LJ::MemCache::delete( [ $owner->id, 'log2:' . $owner->id . ':' . $deleted_entry->jitemid ] );

my $private_entry = $owner->t_post_fake_entry( security => 'private' );
$retime->( $private_entry->t_enter_comment( u => $author, body => 'private-entry-body' ), $march );

my $not_visible = $download->( 'xml', year => 2024, month => 3, day => 1 );
is( $not_visible->code, 200, 'deleted and private entries do not abort the download' );
like( $not_visible->content, qr/next-month-boundary/, 'keeps the visible entry comment' );
unlike( $not_visible->content, qr/deleted-entry-body/, 'skips the comment on a deleted entry' );
unlike( $not_visible->content, qr/private-entry-body/, 'skips the comment on a private entry' );

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
        $sql .= ' AND no_such_column = 1' if $self->{fail_user} && $sql =~ /FROM user WHERE /;
        $sql =~ s{(FROM talk2 WHERE )(.+)}
            {$1($2) AND (journalid <> $self->{journalid} OR jtalkid <> $self->{jtalkid})};
        return $self->{dbh}->prepare( $sql, @args );
    }

    sub selectall_arrayref {
        my ( $self, $sql, @args ) = @_;
        if ( $self->{fail_user} ) {
            $sql .= ' AND no_such_column = 1' if $sql =~ /FROM user WHERE /;
        }
        elsif ( $self->{fail_log2} || $self->{fail_logprop2} || $self->{fail_talkprop2} ) {
            $sql .= ' AND no_such_column = 1'
                if ( $self->{fail_log2} && $sql =~ /\blog2\b/ )
                || ( $self->{fail_logprop2}  && $sql =~ /\blogprop2\b/ )
                || ( $self->{fail_talkprop2} && $sql =~ /\btalkprop2\b/ );
        }
        elsif ( defined $self->{talkleft_filter} ) {
            $sql =~ s/FROM talkleft WHERE /FROM talkleft WHERE $self->{talkleft_filter} AND /;
        }
        else {
            $sql .= ' AND no_such_column = 1' if $sql =~ /FROM talk2 WHERE /;
        }
        return $self->{dbh}->selectall_arrayref( $sql, @args );
    }

    sub selectrow_array {
        my ( $self, $sql, @args ) = @_;
        $sql .= ' AND no_such_column = 1' if $sql =~ /\bwt_edges\b/;
        return $self->{dbh}->selectrow_array( $sql, @args );
    }

    sub err   { return $_[0]->{dbh}->err }
    sub quote { return $_[0]->{dbh}->quote( $_[1] ) }
}

done_testing;
