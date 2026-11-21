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

use Test::More;
use URI;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::S2;

no warnings 'redefine';
local *LJ::S2::Page   = sub { return { head_content => '' }; };
local *LJ::S2::Friend = sub { return {}; };
local *LJ::S2::Entry_from_entryobj =
    sub { return { time => { year => 2000, month => 1, day => 1 } }; };
local *LJ::Talk::init_s2journal_js          = sub { };
local *LJ::Talk::init_s2journal_shortcut_js = sub { };
local *LJ::need_res                         = sub { };
local *S2::get_property_value               = sub { return 2; };
use warnings 'redefine';

with_fake_memcache {
    my $reader = temp_user();
    my $writer = temp_user();
    $reader->{_journalbase} = 'https://journal.example';
    $reader->add_edge( $writer, watch => { nonotify => 1 } );
    my $oldest = $writer->t_post_fake_entry();
    $writer->t_post_fake_entry( body => "Reading page entry $_" ) for 1 .. 4;
    my $date = LJ::mysql_date( $oldest->logtime_unix );

    my $read_page = sub {
        my ( $viewer, %query ) = @_;
        LJ::set_remote($viewer);
        return LJ::S2::FriendsPage( $reader, $viewer, { view => 'read', getargs => \%query } );
    };
    my $older = sub {
        my ($page) = @_;
        return { URI->new( $page->{nav}->{backward_url} || '' )->query_form };
    };

    $reader->add_to_class('paid_user') or die 'Cannot make test reader paid';
    ok( $reader->can_use_daily_readpage, 'the paid test reader can browse by date' );
    local $LJ::MAX_SCROLLBACK_FRIENDS = 1000;

    is( $older->( $read_page->($reader) )->{skip}, 2, 'ordinary pages still use skip pagination' );
    my $last = $read_page->( $reader, skip => 4, show => 'P', filter => 0 );
    is_deeply(
        $older->($last),
        { date => $date, show => 'P', filter => 0 },
'the last page links to the oldest entry’s posting date, retaining filters and dropping skip'
    );
    my $daily = $older->($last)->{date} && $read_page->( $reader, %{ $older->($last) } );
    is( $daily && $older->($daily)->{skip}, 2, 'the date link opens daily pagination' );
    my $yesterday = LJ::mysql_date( LJ::mysqldate_to_time($date) - 86400 );
    is( $older->( $read_page->( $reader, date => $date, skip => 4 ) )->{date},
        $yesterday, 'the last page for a day links to the previous day' );
    is(
        $older->( $read_page->( $reader, date => $yesterday ) )->{date},
        LJ::mysql_date( LJ::mysqldate_to_time($yesterday) - 86400 ),
        'an empty dated page still links to the previous day'
    );

    local $LJ::MAX_SCROLLBACK_FRIENDS = 4;
    is( $older->( $read_page->( $reader, skip => 2 ) )->{date},
        $date, 'the entry-count limit also switches to a date' );
    ok(
        !$older->( $read_page->( $writer, skip => 2 ) )->{date},
        'someone else’s reading page does not offer date mode'
    );

    $reader->remove_from_class('paid_user') or die 'Cannot make test reader free';
    ok( !$reader->can_use_daily_readpage, 'the free test reader cannot browse by date' );
    ok(
        !$older->( $read_page->( $reader, skip => 2 ) )->{date},
        'an account without the capability does not get a date link'
    );
    LJ::unset_remote();
};

done_testing;
