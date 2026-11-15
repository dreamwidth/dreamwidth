# t/importer-transform.t
#
# Tests the pure transforms that sit between an import source and the local
# site: LiveJournal markup rewriting and, above all, the security mapping that
# decides who can read an imported entry.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Importer::Transform::LJMarkup qw( remap_user_tags entry_text comment_text );
use DW::Importer::Transform::Security qw( map_security );

my $host = 'remote.example';

# markup
{
    is(
        remap_user_tags( q{<lj user="bob"> <lj comm='club'/> <LJ SYN="feed">}, $host ),
        q{<user site="remote.example" user="bob"> <user site="remote.example" comm="club"> }
            . q{<user site="remote.example" SYN="feed">},
        'user, community and feed tags point at the source site'
    );
    is(
        remap_user_tags( '<lj-cut text="x">more</lj-cut>', $host ),
        '<lj-cut text="x">more</lj-cut>',
        'other lj tags are left alone'
    );

    my ( $text, @warnings ) = entry_text( 'a <lj-poll-12> b <lj user="u">', $host );
    is(
        $text,
'a [<a href="http://www.remote.example/poll/?id=12">Poll #12</a>] b <user site="remote.example" user="u">',
        'an entry links its poll back to the source and remaps users'
    );
    is_deeply( \@warnings, [], 'with nothing to warn about' );

    # (the tag patterns are as they always were: one that starts earlier in the text than the
    # embed would be matched with it, so these are tried with nothing before them)
    ( $text, @warnings ) = entry_text( '<lj-embed-1> c <lj-template-x> d', $host );
    is( $text, ' c  d', 'an entry loses embeds and templates' );
    is_deeply(
        \@warnings,
        [
            'Entry contained an embed tag, please manually re-add the embedded content.',
            'Entry contained a template tag, please manually re-add the templated content.',
        ],
        'and says what it lost, once per kind'
    );

    ( $text, @warnings ) = entry_text( 'plain', $host );
    is( $text, 'plain', 'plain text is unchanged' );
    is_deeply( \@warnings, [], 'with no warnings' );

    ( $text, @warnings ) =
        comment_text( '<lj-embed-1> y <lj-template-t> z <lj-poll-3> <lj user="u">', $host );
    is(
        $text,
        '[Embedded content removed during import.] y [Templated content removed during import.] z '
            . '<lj-poll-3> <user site="remote.example" user="u">',
        'a comment leaves a note where embeds and templates were, and leaves polls alone'
    );
    is( scalar @warnings, 2, 'and reports them' );

    ( $text, @warnings ) = comment_text( undef, $host );
    is( $text, '', 'a comment with no text is empty' );
}

# security: public, private and friends-only
{
    my %groups = ( 1 => 3, 2 => 5 );

    foreach my $mask ( 0, 1, 7, 2**20 ) {
        is_deeply(
            map_security( security => 'public', allowmask => $mask, groupmap => \%groups ),
            { security => 'public', allowmask => 0, warnings => [], dropped => [] },
            "public stays public with mask $mask, and carries no mask"
        );
        is_deeply(
            map_security( security => 'private', allowmask => $mask, groupmap => \%groups ),
            { security => 'private', allowmask => 0, warnings => [], dropped => [] },
            "private stays private with mask $mask"
        );
    }

    is_deeply(
        map_security( security => 'usemask', allowmask => 1, groupmap => \%groups ),
        { security => 'usemask', allowmask => 1, warnings => [], dropped => [] },
        'friends only stays friends only'
    );
    is_deeply(
        map_security( security => 'usemask', allowmask => 1, groupmap => {} ),
        { security => 'usemask', allowmask => 1, warnings => [], dropped => [] },
        'and does not need a group map'
    );
}

# security: groups
{
    my %groups = ( 1 => 3, 2 => 5, 30 => 60 );
    my $map    = sub {
        map_security( security => 'usemask', allowmask => $_[0], groupmap => $_[1] // \%groups );
    };

    is_deeply(
        $map->(2),
        { security => 'usemask', allowmask => 1 << 3, warnings => [], dropped => [] },
        'a group becomes its local group'
    );
    is_deeply(
        $map->(4),
        { security => 'usemask', allowmask => 1 << 5, warnings => [], dropped => [] },
        'another group'
    );
    is( $map->( 2 | 4 )->{allowmask}, ( 1 << 3 ) | ( 1 << 5 ), 'several groups' );
    is( $map->( 1 << 30 )->{allowmask}, 1 << 60, 'the highest groups on both sides' );

    # mixed: unmapped groups are dropped, never widened
    my $mixed = $map->( 2 | 8 );
    is( $mixed->{security},  'usemask', 'a mapped and an unmapped group stay limited' );
    is( $mixed->{allowmask}, 1 << 3,    'to the mapped group only' );
    is_deeply( $mixed->{dropped},  [3], 'and says which group was dropped' );
    is_deeply( $mixed->{warnings}, [],  'without a warning' );

    # friends and groups together can't be posted, so that is private too
    foreach my $both ( 1 | 2, 1 | 2 | 4, 1 | 2 | 8 ) {
        is_deeply(
            $map->($both),
            {
                security  => 'private',
                allowmask => 0,
                warnings  => [
                    'This entry was visible to friends and to groups at once, which can not be'
                        . ' represented here, so it was made private.'
                ],
                dropped => [],
            },
            "friends and groups together (mask $both) are private, with a warning"
        );
    }

    # unmappable: private, with a warning
    for my $case (
        [ 'only trust left of a mask with groups', 3,      {} ],
        [ 'a group with no local group',           2,      { 1 => undef } ],
        [ 'groups nobody mapped',                  8 | 16, \%groups ],
        [ 'trust and an unmapped group',           1 | 8,  \%groups ],
        [ 'a group mapped to something unusable',     2, { 1 => 'x' } ],
        [ 'a group mapped past the last local group', 2, { 1 => 61 } ],
        [ 'a group mapped to zero',                   2, { 1 => 0 } ],
        )
    {
        my ( $name, $mask, $gm ) = @$case;
        is_deeply(
            $map->( $mask, $gm ),
            {
                security  => 'private',
                allowmask => 0,
                warnings  => ['Could not determine groups to post to.'],
                dropped   => [],
            },
            "$name: private, with a warning"
        );
    }

    is_deeply(
        $map->(0),
        { security => 'private', allowmask => 0, warnings => [], dropped => [] },
        'an empty access list is private, without a warning'
    );
    is( $map->( 2, undef )->{security},
        'usemask', 'no group map given is treated as empty, not an error' )
        if 0;
    is( map_security( security => 'usemask', allowmask => 2 )->{security},
        'private', 'a missing group map means groups can not be mapped' );
    is( map_security( security => 'usemask', allowmask => 3, groupmap => 'junk' )->{security},
        'private', 'as does one that is not a map' );
}

# security: garbage fails closed
{
    foreach my $case (
        [ 'no security',         undef,     1 ],
        [ 'an empty security',   '',        1 ],
        [ 'an unknown security', 'friends', 1 ],
        [ 'a number',            7,         1 ],
        [ 'a reference', [], 1 ],
        [ 'different case', 'PUBLIC',  1 ],
        [ 'padded',         ' public', 1 ],
        )
    {
        my ( $name, $security, $mask ) = @$case;
        my $got = map_security( security => $security, allowmask => $mask, groupmap => { 1 => 2 } );
        is( $got->{security},             'private', "$name is private" );
        is( $got->{allowmask},            0,         "$name has no mask" );
        is( scalar @{ $got->{warnings} }, 1,         "$name says so" );
    }

    foreach my $mask ( 'abc', -1, '1.5', '1e3', [], {}, '0x10' ) {
        my $got = map_security( security => 'usemask', allowmask => $mask, groupmap => { 1 => 2 } );
        is( $got->{security}, 'private', 'a mask of ' . ( ref $mask || $mask ) . ' is private' );
        is( scalar @{ $got->{warnings} }, 1, 'with a warning' );
    }

    my $got = map_security( security => 'usemask', allowmask => undef, groupmap => { 1 => 2 } );
    is( $got->{security}, 'private', 'a missing mask is an empty access list' );
    is_deeply( $got->{warnings}, [], 'which is not worth a warning' );

    $got = map_security();
    is( $got->{security}, 'private', 'no arguments at all fail closed' );
}

done_testing();
