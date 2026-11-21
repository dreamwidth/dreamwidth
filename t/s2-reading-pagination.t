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

use POSIX qw(tzset);
use Test::More;
use URI;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::S2;

no warnings 'redefine';
local *LJ::S2::Page   = sub { return { head_content => '' }; };
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
        my ( $journal, $time, $security ) = @_;
        my $entry =
            $journal->t_post_fake_entry( security => $security, body => "Fixture at $time" );
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
    LJ::unset_remote();
};
tzset();

done_testing;
