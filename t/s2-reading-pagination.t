# t/s2-reading-pagination.t
#
# Test navigation from the end of the reading page into date mode.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use HTML::Entities qw(decode_entities);
use POSIX qw(tzset);
use Test::More;
use URI;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::S2;
use S2;
use S2::Compiler;

S2::set_domain('test-reading-pagination');
my $compiler = S2::Compiler->new( {} );
for my $layer ( [ 1, 'core', 'core2.s2' ], [ 2, 'layout', 'zesty/layout.s2' ] ) {
    my ( $id, $type, $file ) = @$layer;
    open my $source_file, '<', "$ENV{LJHOME}/styles/$file" or die "Cannot open $file: $!";
    my $source = do { local $/; <$source_file> };
    my $compiled;
    $compiler->compile_source(
        {
            type           => $type,
            source         => \$source,
            output         => \$compiled,
            layerid        => $id,
            builtinPackage => 'S2::Builtin::LJ',
        }
    );
    S2::load_layer( $id, $compiled, 0 );
}
my $core2 = S2::make_context(1);
my $zesty = S2::make_context( 1, 2 );

sub render_core2_body {
    my ($page) = @_;
    my $html = '';
    local $S2::pout   = sub { $html .= join '', @_ };
    local $S2::pout_s = $S2::pout;
    S2::run_code( $core2, 'RecentPage::print_body()', $page );
    return $html;
}

sub zesty_reading_url {
    my ( $page, $params ) = @_;
    my $url = S2::run_function( $zesty, 'FriendsPage::lay_build_url(string{})', $page, $params );
    return URI->new( decode_entities($url) );
}

no warnings 'redefine';
local *LJ::S2::Page   = sub { return { head_content => '', base_url => $_[0]->{_journalbase} }; };
local *LJ::S2::Friend = sub { return {}; };
local *LJ::S2::Entry_from_entryobj = sub {
    my ( undef, $entry ) = @_;
    return {
        time => { year => 2000, month => 1, day => 1 },
        id   => join( ':', $entry->journalid, $entry->jitemid ),
    };
};
local *LJ::Talk::init_s2journal_js          = sub { };
local *LJ::Talk::init_s2journal_shortcut_js = sub { };
local *LJ::need_res                         = sub { };
local *S2::get_property_value               = sub { return 3; };
use warnings 'redefine';

with_fake_memcache {
    local $ENV{TZ} = 'UTC+08';
    tzset();
    my $reader          = temp_user();
    my $writer          = temp_user();
    my $midnight_writer = temp_user();
    $reader->{_journalbase} = 'https://journal.example';
    $reader->add_edge( $_, watch => { nonotify => 1 } ) for ( $writer, $midnight_writer );
    $writer->add_edge( $reader, trust => { nonotify => 1 } );
    my $now           = time();
    my $start         = $now - $now % 86400 - 2 * 86400;
    my $end           = $start + 86400;
    my $date          = LJ::mysql_date( $start, 1 );
    my $next_date     = LJ::mysql_date( $end, 1 );
    my $previous_date = LJ::mysql_date( $start - 86400, 1 );
    my $dbh           = LJ::get_db_writer();

    my $post = sub {
        my ( $journal, $time, $security, $statusvis ) = @_;
        my $entry =
            $journal->t_post_fake_entry( security => $security, body => "Fixture at $time" );
        $entry->set_prop( statusvis => $statusvis ) if defined $statusvis;
        $journal->do(
            'UPDATE log2 SET rlogtime=? WHERE journalid=? AND jitemid=?',
            undef, $LJ::EndOfTime - $time,
            $journal->id, $entry->jitemid
        ) or die 'Could not set test posting time';
        return join( ':', $journal->id, $entry->jitemid );
    };

    my @public = map { $post->( $writer, $start + $_, 'public' ) } 0 .. 8;
    my $locked = $post->( $writer, $start + 9, 'friends' );
    $post->( $writer, $start + 10, 'private' );
    my $next        = $post->( $writer,          $end, 'public' );
    my $new_journal = $post->( $midnight_writer, $end, 'public' );
    $dbh->do( 'UPDATE userusage SET timecreate=FROM_UNIXTIME(?) WHERE userid=?',
        undef, $start, $writer->id )
        or die 'Could not set creation time';
    $dbh->do( 'UPDATE userusage SET timecreate=FROM_UNIXTIME(?) WHERE userid=?',
        undef, $end, $midnight_writer->id )
        or die 'Could not set creation time';

    for my $journal ( $writer, $midnight_writer ) {
        LJ::MemCache::delete( [ $journal->id, 'tc:' . $journal->id ] );
        LJ::MemCache::delete( [ $journal->id, 'log2lt:' . $journal->id ] );
    }

    my $read_page = sub {
        my ( $viewer, %query ) = @_;
        LJ::set_remote($viewer);
        return LJ::S2::FriendsPage( $reader, $viewer,
            { view => 'read', getargs => \%query, securityfilter => $query{security} } );
    };
    my $link = sub {
        my ( $page, $direction ) = @_;
        return { URI->new( $page->{nav}->{"${direction}_url"} || '' )->query_form };
    };
    my $older = sub { $link->( $_[0], 'backward' ) };
    my $newer = sub { $link->( $_[0], 'forward' ) };
    my $ids   = sub {
        [ map { $_->{id} } @{ $_[0]->{entries} } ]
    };

    $reader->add_to_class('paid_user') or die 'Cannot make test reader paid';
    ok( $reader->can_use_daily_readpage, 'the paid test reader can browse by date' );
    local $LJ::MAX_SCROLLBACK_FRIENDS = 8;

    my %selection = ( show => 'P', filter => 0, security => 'public' );
    my $first     = $read_page->( $reader, %selection );
    for my $action ( [ '.id', 123 ], [ '.mode', 'expanded' ] ) {
        my ( $param, $value ) = @$action;
        my $url = zesty_reading_url( $first, { $param => $value } );
        is( $url->path, '/read', "Zesty $param keeps the unfiltered reading path" );
        is_deeply(
            { $url->query_form },
            { $param => $value, security => 'public' },
            "Zesty $param preserves the public security filter in the query"
        );
    }
    $reader->create_content_filter( name => 'public' ) or die 'Cannot create public content filter';
    my $content_page = LJ::S2::FriendsPage( $reader, $reader,
        { view => 'read', getargs => {}, pathextra => '/public' } );
    my $content_url = zesty_reading_url( $content_page, { '.mode' => 'expanded' } );
    is( $content_url->path, '/read/public', 'a content filter named public still uses the path' );
    is_deeply(
        { $content_url->query_form },
        { '.mode' => 'expanded' },
        'a content filter does not become a security filter'
    );
    is_deeply( $older->($first), { %selection, skip => 3 }, 'ordinary links preserve filters' );
    my $second = $read_page->( $reader, %{ $older->($first) } );
    is( $older->($second)->{skip}, 5, 'regular navigation links to its actual clamped offset' );
    my $last = $read_page->( $reader, %{ $older->($second) } );
    is_deeply( $newer->($last), { %selection, skip => 3 }, 'newer link reverses the short step' );
    is_deeply(
        $older->($last),
        { %selection, date => $date },
        'the regular limit links to the oldest visible UTC posting date with filters intact'
    );

    my %query = %{ $older->($last) };
    my @seen;
    for my $offset ( 0, 3, 6 ) {
        my $day = $read_page->( $reader, %query );
        push @seen, @{ $ids->($day) };
        my %back = $offset ? ( date => $date ) : ( date => $next_date );
        $back{skip} = $offset - 3 if $offset > 3;
        is_deeply( $newer->($day), { %selection, %back }, "newer link at daily offset $offset" );
        %query = %{ $older->($day) };
    }
    is_deeply(
        \@seen,
        [ reverse @public ],
        'dated links reach every public post, including exact midnight and beyond the regular cap'
    );
    is_deeply(
        \%query,
        { %selection, date => $previous_date },
        'only the final daily page links back a day'
    );
    my $adjacent = $read_page->( $reader, date => $next_date );
    is_deeply(
        [ sort @{ $ids->($adjacent) } ],
        [ sort $next, $new_journal ],
        'next midnight belongs only to the next day, including a journal created at that boundary'
    );
    is_deeply( $ids->( $read_page->( $reader, date => $date, security => 'access' ) ),
        [$locked], 'access filtering returns the trusted entry, not the private or public ones' );

    my $utf8_group = "caf\xc3\xa9 & tea";
    my $group_id   = $reader->create_trust_group( groupname => $utf8_group )
        or die 'Cannot create non-ASCII trust group';
    my %utf8_args = LJ::parse_args("date=$date&security=group%3Acaf%C3%A9%20%26%20tea");
    LJ::set_remote($reader);
    my $group_page = LJ::S2::FriendsPage( $reader, $reader,
        { view => 'read', getargs => \%utf8_args, securityfilter => $group_id } );
    is( $group_page->{filter_name},
        $utf8_group, 'numeric trust group security filter preserves non-ASCII group name' );
    my $group_url  = zesty_reading_url( $group_page, { '.mode' => 'expanded' } );
    my %group_args = LJ::parse_args( $group_url->query );
    is( $group_url->path, '/read', 'Zesty does not put the trust group in the path' );
    is( $group_args{security}, "group:$utf8_group", 'Zesty preserves the encoded trust group' );

    for my $direction (qw(backward forward)) {
        my %parsed = LJ::parse_args( URI->new( $group_page->{nav}->{"${direction}_url"} )->query );
        is( $parsed{security}, "group:$utf8_group",
            "$direction link preserves non-ASCII UTF-8 security=group:... bytes" );
        my ($round_tripped_name) = $parsed{security} =~ /\Agroup:(.+)\z/;

        # _trust_groups shifts the cached arrayref in place, which mutates fake memcache.
        LJ::MemCache::delete( [ $reader->id, 'trust_group:' . $reader->id ] );
        my $resolved = $reader->trust_groups( name => $round_tripped_name );
        is( $resolved ? $resolved->{groupnum} : undef,
            $group_id, "$direction link security group resolves back to the trust group" );
    }

    my $times = LJ::get_times_multi( { memcache_only => 1 }, $writer->id, $midnight_writer->id );
    is( $times->{created}->{ $writer->id }, $start, 'the cached creation time is the day start' );
    is( $times->{created}->{ $midnight_writer->id },
        $end, 'another journal has its own creation time cached' );
    is(
        $older->( $read_page->( $reader, date => $previous_date ) )->{date},
        LJ::mysql_date( $start - 2 * 86400, 1 ),
        'an empty dated page still links to the previous day'
    );
    is( $older->( $read_page->( $reader, date => '1970-01-01' ) )->{date},
        '1969-12-31', 'the Unix epoch is a valid date' );
    is( $older->( $read_page->( $reader, date => '2025-02-30' ) )->{skip},
        3, 'a nonexistent day falls back to regular pagination' );

    local $LJ::MAX_SCROLLBACK_FRIENDS = 1000;
    is( $older->( $read_page->( $reader, skip => 9 ) )->{date},
        $date, 'running out of posts before the count limit also switches to a date' );
    ok(
        !$older->( $read_page->( $writer, skip => 9 ) )->{date},
        'someone else’s reading page does not offer date mode'
    );
    for my $viewer ( $writer, undef ) {
        my $regular = $read_page->($viewer);
        my $dated   = $read_page->( $viewer, date => $date );
        is_deeply( $ids->($dated), $ids->($regular),
            'a non-owner date request shows regular posts' );
        ok( !grep( { $_ eq $locked } @{ $ids->($dated) } ),
            'a non-owner date request does not reveal the access-locked post' );
    }

    $reader->remove_from_class('paid_user') or die 'Cannot make test reader free';
    ok( !$reader->can_use_daily_readpage, 'the free test reader cannot browse by date' );
    ok(
        !$older->( $read_page->( $reader, skip => 9 ) )->{date},
        'an account without the capability does not get a date link'
    );
    is_deeply(
        $ids->( $read_page->( $reader, date => $date ) ),
        $ids->( $read_page->($reader) ),
        'a free owner date request shows regular posts'
    );

    local $LJ::MAX_FRIENDS_VIEW_AGE;
    my $old_reader = temp_user();
    my $old_writer = temp_user();
    $old_reader->{_journalbase} = 'https://older.example';
    $old_reader->add_to_class('paid_user') or die 'Cannot make historical test reader paid';
    $old_reader->add_edge( $old_writer, watch => { nonotify => 1 } );
    my $cutoff   = time() - 14 * 86400;
    my $old_time = $cutoff - 86400;
    my $old_post = $post->( $old_writer, $old_time, 'public' );
    $dbh->do(
'UPDATE userusage SET timecreate=FROM_UNIXTIME(?), timeupdate=FROM_UNIXTIME(?) WHERE userid=?',
        undef,
        $old_time,
        $old_time,
        $old_writer->id
    ) or die 'Could not set historical journal times';
    LJ::MemCache::delete( [ $old_writer->id, "$_:" . $old_writer->id ] ) for qw(tc tu log2lt);

    LJ::set_remote($old_reader);
    my $historical_page = sub {
        return LJ::S2::FriendsPage( $old_reader, $old_reader,
            { view => 'read', getargs => $_[0] } );
    };
    my $empty = $historical_page->( {} );
    is_deeply( $ids->($empty), [], 'posts before the age limit do not appear in regular mode' );
    is_deeply(
        $older->($empty),
        { date => LJ::mysql_date( $cutoff, 1 ) },
        'an empty paid reading page links to the UTC date of the age cutoff'
    );
    ok( $empty->{nav}->{backward_by_date}, 'the empty page labels the link as a date handoff' );
    my $regular_html = render_core2_body($empty);
    like(
        $regular_html,
        qr/only the most recent 1000 entries posted within the last 14 days/,
        'Core2 explains the regular scrollback limit on the empty paid reading page'
    );
    like(
        $regular_html,
        qr{<a\b[^>]*>Earlier entries by date</a>},
        'Core2 renders the date handoff beside the regular reading notice'
    );
    unlike(
        $regular_html,
        qr/There were no entries on this day\./,
        'Core2 does not show the empty-day notice in regular mode'
    );

    my $cutoff_page = $historical_page->( $older->($empty) );
    my $dated_html  = render_core2_body($cutoff_page);
    like(
        $dated_html,
        qr/There were no entries on this day\./,
        'Core2 shows the empty-day notice in date mode'
    );
    like(
        $dated_html,
        qr{<a\b[^>]*>Previous Day</a>},
        'Core2 renders the previous-day link beside the empty-day notice'
    );
    unlike(
        $dated_html,
        qr/only the most recent 1000 entries posted within the last 14 days/,
        'Core2 does not show the regular scrollback notice in date mode'
    );
    is_deeply( $ids->( $historical_page->( $older->($cutoff_page) ) ),
        [$old_post], 'the cutoff link lets readers navigate to an older subscribed entry' );
    {
        local $LJ::MAX_FRIENDS_VIEW_AGE = 7 * 86400;
        is(
            $older->( $historical_page->( {} ) )->{date},
            LJ::mysql_date( time() - 7 * 86400, 1 ),
            'the handoff uses the configured age cutoff'
        );
    }

    subtest 'a final scrollback page of suspended entries' => sub {
        local $LJ::MAX_SCROLLBACK_FRIENDS = 4;
        my $reader = temp_user();
        my $writer = temp_user();
        $reader->{_journalbase} = 'https://suspensions.example';
        $reader->add_to_class('paid_user') or die 'Cannot make test reader paid';
        $reader->add_edge( $writer, watch => { nonotify => 1 } );
        my $first_time = $start - 86400;
        my $older_post = $post->( $writer, $first_time, 'public' );
        $post->( $writer, $_, 'public', 'S' ) for ( $first_time + 1, $start, $start + 1 );
        $post->( $writer, $end, 'public' );
        $dbh->do( 'UPDATE userusage SET timecreate=FROM_UNIXTIME(?) WHERE userid=?',
            undef, $first_time, $writer->id )
            or die 'Could not set creation time';
        LJ::MemCache::delete( [ $writer->id, "$_:" . $writer->id ] ) for qw(tc log2lt);

        LJ::set_remote($reader);
        my $read = sub {
            return LJ::S2::FriendsPage( $reader, $reader, { view => 'read', getargs => $_[0] } );
        };
        my $page = $read->( { skip => 1 } );
        is_deeply( $ids->($page), [], 'regular mode hides every entry on the final page' );
        is_deeply(
            $older->($page),
            { date => $previous_date },
            'the handoff uses the oldest scanned UTC date, not the age cutoff'
        );
        is_deeply( $ids->( $read->( $older->($page) ) ),
            [$older_post], 'the handoff reaches the readable post beyond the count limit' );
    };
    LJ::unset_remote();
};
tzset();

done_testing;
