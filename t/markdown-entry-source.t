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

use DW::Pay;
use LJ::Entry;
use LJ::Poll;
use LJ::Protocol;
use LJ::Test qw( temp_user );

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

done_testing;
