#!/usr/bin/perl
# Verify conversion of old entry-form submissions into native form fields.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

use strict;
use warnings;

use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
use DW::Entry::Legacy;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

sub decode {
    my ( $post, $request ) = @_;
    $request ||= {};
    return DW::Entry::Legacy::decode_entry_form( $request, $post );
}

sub date_post {
    return {
        security      => 'public',
        subject       => 'Legacy subject',
        event         => 'Legacy body',
        date_ymd_mm   => '02',
        date_ymd_dd   => '03',
        date_ymd_yyyy => '2020',
        hour          => '04',
        min           => '05',
        @_,
    };
}

subtest 'security preserves friends and all custom-bit positions through bit 60' => sub {
    my $friends = decode( date_post( security => 'friends' ) );
    is( $friends->{security},  'usemask', 'friends is protocol usemask security' );
    is( $friends->{allowmask}, 1,         'friends keeps the first access bit' );

    my $custom = decode(
        date_post(
            security      => 'custom',
            custom_bit_1  => 1,
            custom_bit_17 => 1,
            custom_bit_60 => 1,
        )
    );
    is( $custom->{security}, 'usemask', 'custom is protocol usemask security' );
    is(
        $custom->{allowmask},
        ( 1 << 1 ) | ( 1 << 17 ) | ( 1 << 60 ),
        'custom mask retains low, middle, and bit-60 groups'
    );
};

subtest 'date trust only replaces timezone fields for changed or no-JavaScript dates' => sub {
    my $trusted = decode( date_post(), { tz => 'UTC', year => 'old-year' } );
    is( $trusted->{tz},   'UTC',      'unchanged browser date retains the supplied timezone' );
    is( $trusted->{year}, 'old-year', 'unchanged browser date does not overwrite protocol date' );

    my $changed = decode( date_post( date_diff => 1 ), { tz => 'UTC' } );
    ok( !exists $changed->{tz}, 'changed browser date removes timezone guessing' );
    is_deeply( [ @{$changed}{qw(year mon day hour min)} ],
        [qw(2020 02 03 04 05)], 'changed browser date supplies protocol components' );

    my $nojs = decode( date_post( date_diff_nojs => 1 ), { tz => 'UTC' } );
    ok( !exists $nojs->{tz}, 'no-JavaScript date also supplies explicit date components' );
};

subtest 'metadata, adult content, and comment settings retain legacy precedence' => sub {
    no warnings 'redefine';
    local *LJ::is_enabled = sub { $_[0] eq 'adult_content' };
    my $decoded = decode(
        date_post(
            prop_picture_keyword      => 'legacy-picture',
            prop_current_music        => 'legacy music',
            prop_current_location     => 'legacy location',
            prop_current_coords       => '1.2,3.4',
            prop_taglist              => "  \t ",
            prop_opt_nocomments       => 1,
            prop_opt_noemail          => 1,
            comment_settings          => 'nocomments',
            prop_adult_content        => 'explicit',
            prop_adult_content_reason => 'fixture reason',
        )
    );
    is( $decoded->{prop_picture_keyword},  'legacy-picture',  'userpic keyword is copied' );
    is( $decoded->{prop_current_music},    'legacy music',    'music metadata is copied' );
    is( $decoded->{prop_current_location}, 'legacy location', 'location metadata is copied' );
    is( $decoded->{prop_current_coords},   '1.2,3.4',         'coordinates metadata is copied' );
    is( $decoded->{prop_taglist},          '',                'whitespace-only tags are cleared' );
    is( $decoded->{prop_opt_nocomments}, 1, 'explicit no-comments wins comment-settings fallback' );
    is( $decoded->{prop_opt_noemail},    1, 'explicit no-email wins comment-settings fallback' );
    is( $decoded->{prop_adult_content}, 'explicit', 'recognized adult level is retained' );
    is( $decoded->{prop_adult_content_reason}, 'fixture reason', 'adult reason is retained' );

    my $invalid = decode( date_post( prop_adult_content => 'unexpected-level' ) );
    is( $invalid->{prop_adult_content}, '', 'unknown adult level is cleared' );
};

subtest 'RTE conversion and mood normalization preserve submitted content' => sub {
    no warnings 'redefine';
    local *DW::Mood::mood_id = sub { $_[1] eq 'fixture mood' ? 77 : undef };
    my $post = date_post(
        event                 => "first<br />second",
        switched_rte_on       => 1,
        prop_opt_preformatted => 1,
        prop_current_mood     => 'fixture mood',
    );
    my $request = {};
    my $decoded = decode( $post, $request );
    is( $decoded->{event}, "first\nsecond", 'RTE line breaks are converted to parser input' );
    is( $decoded->{prop_used_rte},         1,  'RTE submission records used_rte' );
    is( $decoded->{prop_opt_preformatted}, 0,  'plain RTE conversion clears preformatted mode' );
    is( $decoded->{prop_current_moodid},   77, 'typed known mood becomes its mood id' );
    ok( !exists $decoded->{prop_current_mood}, 'known typed mood name is removed' );

};

done_testing;
