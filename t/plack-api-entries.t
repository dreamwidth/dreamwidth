# t/plack-api-entries.t
#
# REST API entry endpoints: reading, posting, and editing entries.
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
use lib "$ENV{LJHOME}/t/lib";
use LJ::Community;
use LJ::Protocol;
use LJ::Test qw(temp_comm);
use DW::Test::API;

my ( $owner,    $okey ) = api_user();
my ( $friend,   $fkey ) = api_user();
my ( $stranger, $skey ) = api_user();
my $ou   = $owner->user;
my $base = "/journals/$ou/entries";

$owner->add_edge( $friend, trust => { nonotify => 1 } );
my $group = $owner->create_trust_group( groupname => 'api test group' );
$owner->edit_trustmask( $friend, add => $group );

# Posts directly through the protocol, for setups the API can't express.
# Each body is unique, because postevent treats a repeated body as a duplicate.
my $post_count = 0;

sub proto_post {
    my ( $u, %args ) = @_;
    my $err = 0;
    $post_count++;
    my $res = LJ::Protocol::do_request(
        'postevent',
        {
            ver      => $LJ::PROTOCOL_VER,
            username => $u->user,
            event    => "body $post_count",
            subject  => 'subject',
            tz       => 'guess',
            %args
        },
        \$err,
        { noauth => 1, nomod => 1 }
    );
    die LJ::Protocol::error_message($err) unless $res;
    return $res->{itemid} * 256 + $res->{anum};
}

subtest 'visibility of locked entries' => sub {
    my $access = proto_post( $owner, security => 'usemask', allowmask => 1 );
    my $custom = proto_post( $owner, security => 'usemask', allowmask => 1 << $group );

    my ( $res, $body ) = api_request( GET => "$base/$access", key => $okey );
    is( $res->code,        200,      'owner can read an access-locked entry' );
    is( $body->{security}, 'access', 'access-locked entry reports access' );

    ( $res, $body ) = api_request( GET => "$base/$custom", key => $okey );
    is( $res->code,        200,      'owner can read a custom-filtered entry' );
    is( $body->{security}, 'custom', 'owner sees custom security' );
    is_deeply( $body->{custom_groups}, [$group], 'owner sees the custom group' );

    ( $res, $body ) = api_request( GET => "$base/$custom", key => $fkey );
    is( $res->code,        200,      'group member can read a custom-filtered entry' );
    is( $body->{security}, 'access', 'group member sees access' );
    ok( !exists $body->{custom_groups}, 'group member does not see the groups' );

    ( $res, $body ) = api_request( GET => "$base/$access", key => $skey );
    is( $res->code, 403, 'stranger cannot read an access-locked entry' );

    ( $res, $body ) = api_request( GET => $base, key => $okey );
    is( $res->code, 200, 'owner can list a journal with locked entries' );
    my %listed = map { $_->{security} => 1 } @$body;
    ok( $listed{access} && $listed{custom}, 'owner list includes the locked entries' );

    ( $res, $body ) = api_request( GET => $base, key => $skey );
    is( $res->code, 200, 'stranger can list the journal' );
    ok( !( grep { $_->{security} ne 'public' } @$body ), 'stranger list has only public entries' );

    ( $res, $body ) = api_request( GET => "$base/" . ( $access + 256 * 1000 ), key => $okey );
    is( $res->code, 404, 'nonexistent entry is a 404' );
};

subtest 'posting' => sub {
    my ( $res, $body ) = api_request( POST => $base, key => $okey, json => { text => 'minimal' } );
    is( $res->code, 200, 'minimal post' );
    ok( $body->{entry_id} && $body->{url}, 'post returns entry_id and url' );

    ( $res, $body ) = api_request( GET => "$base/$body->{entry_id}", key => $okey );
    is( $body->{body},     'minimal', 'posted text reads back' );
    is( $body->{security}, 'public',  'default security is public' );

    ( $res, $body ) = api_request(
        POST => $base,
        key  => $okey,
        json => {
            text     => 'full',
            subject  => 'a subject',
            security => 'access',
            datetime => '2021-03-04 05:06',
            tags     => [ 'one', 'two' ],
        }
    );
    is( $res->code, 200, 'post with options' );
    my $entry = fresh_entry( $owner, $body->{entry_id} );
    my $state = entry_state($entry);
    is( $state->{subject},   'a subject',           'subject' );
    is( $state->{allowmask}, 1,                     'access security' );
    is( $state->{eventtime}, '2021-03-04 05:06:00', 'datetime' );
    is( $state->{tags},      'one, two',            'tags given as an array' );

    ( $res, $body ) = api_request( POST => $base, key => $okey, json => { text => '' } );
    is( $res->code, 400, 'empty text is rejected' );

    ( $res, $body ) = api_request( POST => $base, key => $skey, json => { text => 'intrusion' } );
    is( $res->code, 403, "cannot post to someone else's journal" );

TODO: {
        local $TODO = 'tag validation runs before the arrayref is joined';

        ( $res, $body ) =
            api_request( POST => $base, key => $okey, json => { text => 'x', tags => ['<b>'] } );
        is( $res->code, 400, 'invalid tag in the array is rejected' );
    }
};

subtest 'community posting and editing' => sub {
    my $comm = temp_comm();
    LJ::set_rel( $comm, $owner, 'A' );
    $friend->update_self( { status => 'A' } );    # posting to a community needs a validated email
    $friend->join_community( $comm, 0, 1 );
    my $cbase = '/journals/' . $comm->user . '/entries';

    my ( $res, $body ) =
        api_request( POST => $cbase, key => $fkey, json => { text => 'member post' } );
    is( $res->code, 200, 'member can post to the community' );
    my $id = $body->{entry_id};

    ( $res, $body ) = api_request( POST => $cbase, key => $skey, json => { text => 'outsider' } );
    is( $res->code, 403, 'non-member cannot post to the community' );

TODO: {
        local $TODO = 'refusal uses an invalid HTTP status';

        ( $res, $body ) =
            api_request( POST => "$cbase/$id", key => $okey, json => { text => 'mod' } );
        is( $res->code, 403, "maintainer cannot edit a member's entry through the API" );
        like( $body->{error}, qr/[a-z]/i, 'with an error message' );
    }
};

subtest 'editing: tags' => sub {
    my ( $res, $body ) =
        api_request( POST => $base, key => $okey, json => { text => 'tagged', tags => ['old'] } );
    my $id = $body->{entry_id};

    ( $res, $body ) = api_request(
        POST => "$base/$id",
        key  => $okey,
        json => { text => 'e', tags => [ 'a', 'b' ] }
    );
    is( $res->code, 200, 'edit with tags' );
    my $entry = fresh_entry( $owner, $id );
    is( entry_state($entry)->{tags}, 'a, b', 'tags given as an array replace the old tags' );
    unlike( $entry->prop('taglist') // '', qr/ARRAY\(/, 'taglist prop is not a stringified ref' );

TODO: {
        local $TODO = 'tag validation runs before the arrayref is joined';

        ( $res, $body ) = api_request(
            POST => "$base/$id",
            key  => $okey,
            json => { text => 'e', tags => ['<b>'] }
        );
        is( $res->code, 400, 'invalid tag in the array is rejected' );
    }

    ( $res, $body ) = api_request( POST => "$base/$id", key => $okey, json => { text => 'e2' } );
    is( entry_state( fresh_entry( $owner, $id ) )->{tags}, 'a, b', 'omitted tags are kept' );

    ( $res, $body ) =
        api_request( POST => "$base/$id", key => $okey, json => { text => 'e3', tags => [] } );
    is( entry_state( fresh_entry( $owner, $id ) )->{tags}, '', 'an empty array clears the tags' );
};

subtest 'editing: omitted fields are unchanged' => sub {
    for my $sec (
        [ custom  => { security => 'usemask', allowmask => 1 << $group } ],
        [ access  => { security => 'usemask', allowmask => 1 } ],
        [ private => { security => 'private' } ],
        )
    {
        my ( $name, $security ) = @$sec;
        my $id = proto_post(
            $owner,
            %$security,
            slug  => "kept-$name",
            year  => 2020,
            mon   => 1,
            day   => 2,
            hour  => 3,
            min   => 4,
            props => {
                opt_backdated        => 1,
                opt_nocomments       => 1,
                opt_screening        => 'A',
                adult_content        => 'explicit',
                adult_content_reason => 'a reason',
                current_music        => 'a song',
                current_location     => 'a place',
                taglist              => 'keep, me',
            },
        );
        my $before = entry_state( fresh_entry( $owner, $id ) );
        is_deeply(
            [ @$before{qw( tags slug opt_backdated adult_content )} ],
            [ 'keep, me', "kept-$name", 1, 'explicit' ],
            "$name: entry set up with the settings under test"
        );

        my ( $res, $body ) =
            api_request( POST => "$base/$id", key => $okey, json => { text => 'new text' } );
        is( $res->code, 200, "$name: text-only edit" );
        my $after = entry_state( fresh_entry( $owner, $id ) );
        is( $after->{event}, 'new text', "$name: text changed" );

        for my $field ( sort grep { $_ ne 'event' } keys %$before ) {
            is( $after->{$field}, $before->{$field}, "$name: $field kept" );
        }
    }
};

subtest 'editing: explicit changes' => sub {
    my $id = proto_post( $owner, props => { adult_content => 'explicit', opt_nocomments => 1 } );

    my ( $res, $body ) = api_request(
        POST => "$base/$id",
        key  => $okey,
        json => {
            text             => 'changed',
            subject          => 'new subject',
            security         => 'private',
            age_restriction  => 'none',
            comment_settings => 'noemail',
        }
    );
    is( $res->code, 200, 'edit with explicit changes' );
    my $state = entry_state( fresh_entry( $owner, $id ) );
    is( $state->{subject},       'new subject', 'subject changed' );
    is( $state->{security},      'private',     'security changed' );
    is( $state->{adult_content}, 'none',        'age restriction changed' );
    ok( !$state->{opt_nocomments}, 'comments re-enabled' );
    is( $state->{opt_noemail}, 1, 'comment email turned off' );

    ( $res, $body ) = api_request(
        POST => "$base/$id",
        key  => $okey,
        json => { text => 'changed', datetime => '2019-05-06 07:08' }
    );
    is(
        entry_state( fresh_entry( $owner, $id ) )->{eventtime},
        '2019-05-06 07:08:00',
        'datetime changed'
    );

    ( $res, $body ) =
        api_request( POST => "$base/$id", key => $okey, json => { subject => 'only subject' } );
    is( $res->code, 200, 'edit without text' );
    $state = entry_state( fresh_entry( $owner, $id ) );
    is( $state->{subject}, 'only subject', 'subject changed without text' );
    is( $state->{event},   'changed',      'text kept' );
};

subtest 'editing: authorization' => sub {
    my $id = proto_post($owner);

    my ( $res, $body ) =
        api_request( POST => "$base/$id", key => $skey, json => { text => 'intrusion' } );
    is( $res->code, 404, "editing someone else's entry looks like a missing entry" );

    my $wrong_anum = ( $id & ~255 ) | ( ( $id + 1 ) & 255 );
    ( $res, $body ) =
        api_request( POST => "$base/$wrong_anum", key => $okey, json => { text => 'x' } );
    is( $res->code, 404, 'wrong anum is a 404' );

    is( entry_state( fresh_entry( $owner, $id ) )->{event}, "body $post_count", 'entry unchanged' );
};

subtest 'listing' => sub {
    my ( $lister, $lkey ) = api_user();
    my $lbase = '/journals/' . $lister->user . '/entries';
    for my $n ( 1 .. 3 ) {
        api_request(
            POST => $lbase,
            key  => $lkey,
            json => { text => "entry $n", tags => $n == 2 ? ['two'] : [] }
        );
    }

    my ( $res, $body ) = api_request( GET => $lbase, key => $lkey, query => { count => 2 } );
    is( scalar @$body, 2, 'count limits the list' );

    ( $res, $body ) =
        api_request( GET => $lbase, key => $lkey, query => { count => 2, offset => 2 } );
    is( scalar @$body, 1, 'offset skips entries' );

    ( $res, $body ) = api_request( GET => $lbase, key => $lkey, query => { tag => 'two' } );
    is_deeply( [ map { $_->{body} } @$body ], ['entry 2'], 'tag filter' );

    ( $res, $body ) = api_request( GET => $lbase, key => $lkey, query => { tag => 'nope' } );
    is_deeply( $body, [], 'unknown tag gives an empty list' );

    ( $res, $body ) = api_request( GET => $lbase, key => $lkey, query => { count => -1 } );
    is( $res->code, 400, 'negative count fails validation' );
};

done_testing;
