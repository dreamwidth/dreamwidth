# t/markdown-entry-source.t
#
# Test preservation of Markdown source when entries contain embeds or polls.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Entry::Moderated;
use DW::Pay;
use LJ::Entry;
use LJ::Poll;
use LJ::Protocol;
use LJ::Test qw( temp_comm temp_user );

my $user = temp_user();

sub request {
    my ( $mode, %args ) = @_;
    my $error  = 0;
    my $result = LJ::Protocol::do_request(
        $mode,
        {
            ver      => $LJ::PROTOCOL_VER,
            username => $user->user,
            subject  => 'Markdown source test',
            props    => { editor => 'markdown0' },
            tz       => 'guess',
            %args,
        },
        \$error,
        { noauth => 1 }
    );
    return ( $result, $error );
}

sub saved_source {
    my ($itemid) = @_;
    LJ::Entry->reset_singletons;
    LJ::start_request();
    return LJ::Entry->new( $user, jitemid => $itemid )->event_raw;
}

my $before =
      "Caf\xc3\xa9: "
    . q{`<UppercaseAnglebracketedText>` and `<<<<<Example Text Here` and}
    . ' `Some More There>>>>>`';
my $after = q{A closing `</MixedCase>` and <SPAN title='A &amp; B'>HTML</SPAN>.};
my $embed = '<site-embed><object></object></site-embed>';

subtest 'Embeds on post and edit' => sub {
    my ( $result, $error ) = request( 'postevent', event => "$before\n\n$embed\n\n$after" );
    is( $error, 0, 'posted entry with an embed' ) or return;
    my $itemid = $result->{itemid};

    like(
        saved_source($itemid),
        qr/\A\Q$before\E\n\n<site-embed id="[1-9]\d*"\/>\n\n\Q$after\E\z/,
        'posting replaces only the embed, preserving the rest of the Markdown'
    );

    ( $result, $error ) =
        request( 'editevent', itemid => $itemid, event => "$after\n\n$embed\n\n$before" );
    is( $error, 0, 'edited entry with an embed' ) or return;
    like(
        saved_source($itemid),
        qr/\A\Q$after\E\n\n<site-embed id="[1-9]\d*"\/>\n\n\Q$before\E\z/,
        'editing replaces only the embed, preserving the rest of the Markdown'
    );
};

subtest 'Bare embed on post' => sub {
    my $bare_embed = '<embed src="https://example.invalid/movie.swf">';
    my ( $result, $error ) = request( 'postevent', event => "$before\n\n$bare_embed\n\n$after" );
    is( $error, 0, 'posted an entry with a bare embed' ) or return;

    like(
        saved_source( $result->{itemid} ),
        qr/\A\Q$before\E\n\n<site-embed id="[1-9]\d*"\/>\n\n\Q$after\E\z/,
        'posting replaces a bare embed without changing the surrounding Markdown'
    );
};

subtest 'Polls on post' => sub {
    $user->update_self( { status => 'A' } );
    DW::Pay::add_paid_time( $user, 'paid', 2 );
    my $poll = '<poll name="Example"><poll-question type="text">Question?</poll-question></poll>';
    my ( $result, $error ) = request( 'postevent', event => "$before\n\n$poll\n\n$after" );
    is( $error, 0, 'posted entry with a poll' ) or return;

    my $saved = saved_source( $result->{itemid} );
    like(
        $saved,
        qr/\A\Q$before\E\n\n<poll-[1-9]\d*>\n\n\Q$after\E\z/,
        'posting replaces only the poll, preserving the rest of the Markdown'
    );
    my ($pollid) = $saved =~ /<poll-([1-9]\d*)>/;
    ok( $pollid, 'the stored entry refers to a real poll ID' ) or return;
    is( LJ::Poll->new($pollid)->name, 'Example', 'the poll was saved' );

    ( $result, $error ) = request( 'postevent', event => "$before\n\n<poll></poll>\n\n$after" );
    like( $error, qr/^103(?:$|:)/, 'an invalid poll still prevents posting' );
};

subtest 'Literal poll-placeholder attribute and legacy embed wrapper with poll' => sub {
    my $attr_tag = q{<span title='<poll-placeholder>'>Example</span>};
    my $poll     = '<poll name="Safe"><poll-question type="text">Q?</poll-question></poll>';
    my ( $result, $error ) = request( 'postevent', event => "$attr_tag\n\n$poll\n\n$after" );
    is( $error, 0, 'posted entry containing literal <poll-placeholder> attribute before poll' )
        or return;

    my $saved = saved_source( $result->{itemid} );
    like( $saved, qr/\A\Q$attr_tag\E\n\n<poll-[1-9]\d*>\n\n\Q$after\E\z/,
'literal <poll-placeholder> in attribute is untouched and real poll is linked at poll position'
    );

    my $legacy_embed = q{<div class='ljembed' embedid='42'>fallback content</div>};
    ( $result, $error ) = request( 'postevent', event => "$before\n\n$poll\n\n$legacy_embed" );
    is( $error, 0, 'posted entry combining poll and single-quoted legacy ljembed wrapper' )
        or return;

    my $saved_combo = saved_source( $result->{itemid} );
    like(
        $saved_combo,
        qr/\A\Q$before\E\n\n<poll-[1-9]\d*>\n\n<site-embed id="[1-9]\d*"\/>\z/,
'poll and single-quoted legacy ljembed wrapper both convert cleanly alongside preserved Markdown'
    );
};

subtest 'Moderation preview with a stray closing poll tag' => sub {
    my $community = temp_comm();
    $community->set_prop( moderated => 1 );
    LJ::set_rel( $community, $user, 'P' );
    my ( $result, $error ) = request(
        'postevent',
        usejournal => $community->user,
        event      => 'A closing `</poll>` tag in a code example.',
    );
    is( $error, 0, 'submitted a Markdown entry for moderation' ) or return;

    my ($modid) = $community->selectrow_array( 'SELECT modid FROM modlog WHERE journalid=?',
        undef, $community->id );
    my $entry = $modid && DW::Entry::Moderated->new( $community, $modid );
    ok( $entry, 'loaded the queued entry' ) or return;

    my $rendered = eval { $entry->event };
    is( $@, '', 'moderation preview renders without throwing' ) or return;
    like(
        $rendered,
        qr{<code>&lt;/poll&gt;</code>},
        'moderation preview preserves the code example'
    );
};

done_testing;
