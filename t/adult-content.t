# Adult-content eligibility, rating validation, and reading filters.
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.

use strict;
use warnings;
use Test::More;
use DateTime;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm with_fake_memcache);
use DW::Logic::AdultContent;
use DW::User::ContentFilters::Filter;

local $LJ::DISABLED{adult_content} = 0;
my $owner   = temp_user();
my $minor   = temp_user();
my $adult   = temp_user();
my $unknown = temp_user();
$minor->set_prop( init_bdate => DateTime->now->subtract( years => 17 )->ymd );
$adult->set_prop( init_bdate => DateTime->now->subtract( years => 18 )->ymd );
my $entry = $owner->t_post_fake_entry( body => 'Restricted test body' );
my $logic = 'DW::Logic::AdultContent';
my $type  = sub {
    return $logic->interstitial_type( user => $_[0], journal => $owner, entry => $entry );
};

with_fake_memcache {
    for my $case (
        [ $minor,   'none',     'explicit', 'explicit_blocked' ],
        [ $minor,   'concepts', 'explicit', 'explicit_blocked' ],
        [ $minor,   'explicit', 'concepts', undef ],
        [ $minor,   'concepts', 'concepts', 'concepts' ],
        [ $adult,   'none',     'explicit', undef ],
        [ $adult,   'explicit', 'explicit', 'explicit' ],
        [ $adult,   'explicit', 'concepts', undef ],
        [ $adult,   'concepts', 'concepts', 'concepts' ],
        [ $unknown, 'none',     'explicit', 'explicit' ],
        [ $unknown, 'none',     'concepts', 'concepts' ],
        [ undef,    '',         'explicit', 'explicit' ],
        [ undef,    '',         'concepts', 'concepts' ],
        [ $minor,   'concepts', 'none',     undef ],
        [ undef,    '',         'none',     undef ],
        )
    {
        my ( $viewer, $hide, $rating, $expected ) = @$case;
        $viewer->set_prop( hide_adult_content => $hide ) if $viewer;
        $entry->set_prop( adult_content => $rating );
        is( $type->($viewer), $expected,
            ( $viewer ? $viewer->best_guess_age || 'unknown' : 'anonymous' )
                . " / $hide / $rating" );
    }

    $owner->set_prop( adult_content => 'explicit' );
    $entry->set_prop( adult_content => '' );
    is( $type->($minor), 'explicit_blocked', 'journal default inherited' );
    $entry->set_prop( adult_content => 'none' );
    is( $type->($minor), undef, 'explicit entry none overrides journal default' );
    $entry->set_prop( adult_content => 'explicit' );
    is( $type->($owner), undef, 'owner can view own restricted post' );
    {
        local $LJ::DISABLED{adult_content} = 1;
        is( $type->($minor), undef, 'feature switch disables gate' );
    }

    $adult->set_prop( hide_adult_content => 'explicit' );
    ok(
        $logic->set_confirmed_pages(
            user          => $adult,
            journalid     => $owner->id,
            entryid       => $entry->ditemid,
            adult_content => 'explicit'
        ),
        'adult confirmation stored'
    );
    is( $type->($adult), undef, 'adult confirmation permits entry' );
    my $other = $owner->t_post_fake_entry;
    $other->set_prop( adult_content => 'explicit' );
    is( $logic->interstitial_type( user => $adult, journal => $owner, entry => $other ),
        'explicit', 'entry approval does not authorize another entry' );
    ok(
        !$logic->set_confirmed_pages(
            user          => $minor,
            journalid     => $owner->id,
            entryid       => $entry->ditemid,
            adult_content => 'explicit'
        ),
        'minor confirmation rejected'
    );

    # Simulate approval left over from the old handler or a subsequently corrected birthdate.
    LJ::MemCache::set(
        $logic->_memcache_key($minor),
        {
            explicit => { $owner->id => [ $entry->ditemid ] }
        }
    );
    is( $type->($minor), 'explicit_blocked', 'age denial wins over cached approval' );

    $entry->set_prop( adult_content      => 'concepts' );
    $minor->set_prop( hide_adult_content => 'concepts' );
    ok(
        $logic->set_confirmed_pages(
            user          => $minor,
            journalid     => $owner->id,
            entryid       => $entry->ditemid,
            adult_content => 'concepts'
        ),
        'minor can confirm discretion warning'
    );
    is( $type->($minor), undef, 'discretion approval honored' );
    $entry->set_prop( adult_content => 'explicit' );
    is( $type->($minor), 'explicit_blocked',
        'discretion approval cannot authorize explicit content' );
};

my $comm       = temp_comm();
my $maintainer = temp_user();
LJ::set_rel( $comm, $maintainer, 'A' );
$comm->set_prop( adult_content => 'explicit' );
my $comm_entry = $minor->t_post_fake_entry( usejournal => $comm->user, usejournal_okay => 1 );
is( $logic->interstitial_type( user => $minor, journal => $comm, entry => $comm_entry ),
    undef, 'community poster can view own entry' );
is( $logic->interstitial_type( user => $maintainer, journal => $comm, entry => $comm_entry ),
    undef, 'community maintainer exemption preserved' );
is( $logic->interstitial_type( user => $unknown, journal => $comm, entry => $comm_entry ),
    'explicit', 'other community viewers still require confirmation' );

for my $case (
    [ 'explicit',       'none',           'explicit' ],
    [ 'concepts',       'explicit',       'explicit' ],
    [ 'none',           'explicit',       'explicit' ],
    [ 'invalid-rating', 'explicit',       'explicit' ],
    [ 'invalid-rating', 'concepts',       'concepts' ],
    [ 'invalid-rating', '',               undef ],
    [ 'explicit',       'invalid-rating', 'explicit' ],
    )
{
    $entry->set_prop( adult_content            => $case->[0] );
    $entry->set_prop( adult_content_maintainer => $case->[1] );
    is( $entry->adult_content_calculated, $case->[2], "rating precedence: @$case[0,1]" );
}
$entry->set_prop( adult_content            => 'invalid-rating' );
$entry->set_prop( adult_content_maintainer => '' );
is( $type->($minor), 'explicit_blocked', 'legacy invalid rating inherits journal restriction' );
isnt(
    $logic->transform_post(
        post    => 'Restricted test body',
        entry   => $entry,
        journal => $owner,
        remote  => $minor
    ),
    'Restricted test body',
    'legacy invalid rating stays collapsed'
);

for my $mode ( 'postevent', 'editevent' ) {
    for my $value ( 'invalid-rating', '0', 'Explicit' ) {
        my %req = (
            mode               => $mode,
            ver                => $LJ::PROTOCOL_VER,
            user               => $owner->user,
            itemid             => $entry->jitemid,
            event              => 'Protocol test body',
            subject            => 'Rating test',
            year               => 2026,
            mon                => 1,
            day                => 1,
            hour               => 12,
            min                => 0,
            security           => 'public',
            prop_adult_content => $value
        );
        my %res;
        LJ::do_request( \%req, \%res, { noauth => 1, nomod => 1 } );
        is( $res{success}, 'FAIL', "$mode rejects invalid rating [$value]" );
        like( $res{errmsg}, qr/adult_content/, 'failure identifies invalid rating' );
    }
}

# Valid edits and clearing the property must remain supported.
for my $value ( 'none', 'concepts', 'explicit', '' ) {
    my %req = (
        mode               => 'editevent',
        ver                => $LJ::PROTOCOL_VER,
        user               => $owner->user,
        itemid             => $entry->jitemid,
        event              => 'Protocol test body',
        subject            => 'Rating test',
        year               => 2026,
        mon                => 1,
        day                => 1,
        hour               => 12,
        min                => 0,
        security           => 'public',
        prop_adult_content => $value
    );
    my %res;
    LJ::do_request( \%req, \%res, { noauth => 1 } );
    is( $res{success}, 'OK', "valid rating [$value] accepted" );
}

{
    no warnings 'redefine';
    local *LJ::User::is_paid = sub { 1 };
    local $LJ::IS_DEV_SERVER = 0;
    $entry->set_prop( adult_content_maintainer => '' );
    for my $level ( 'sfw', 'nonexplicit' ) {
        my $filter = DW::User::ContentFilters::Filter->new(
            id      => 1,
            ownerid => $adult->id,
            _data   => { $owner->id => { adultcontent => $level } }
        );
        my $item = { journalid => $owner->id, ditemid => $entry->ditemid };
        $entry->set_prop( adult_content => '' );
        ok( !$filter->show_entry($item), "$level blocks inherited explicit rating" );
        $entry->set_prop( adult_content => 'none' );
        ok( $filter->show_entry($item), "$level honors explicit none override" );
        $entry->set_prop( adult_content => 'concepts' );
        is(
            $filter->show_entry($item),
            $level eq 'nonexplicit' ? 1 : 0,
            "$level handles discretion rating"
        );
    }
}
done_testing;
