# t/talkpost-reply-policy.t
#
# Test the journal and target restrictions on submitting replies.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
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
use LJ::Test qw( temp_user temp_comm temp_feed );
use LJ::Talk;

local $LJ::DISABLED{captcha} = 1;

sub validated_user {
    my $user = temp_user();
    $user->update_self( { status => 'A' } );
    return $user;
}

sub check_reply {
    my ( $message, $entry, $commenter, $parent, @expected_errors ) = @_;
    DW::Cache->request->clear_ns('rel');

    my $parenttalkid = $parent ? $parent->jtalkid : 0;
    my @errors;
    my $captcha;
    my $reply = LJ::Talk::Post::prepare_and_validate_comment(
        { body => 'Test reply', subject => 'Test', parenttalkid => $parenttalkid },
        $commenter, $entry, \$captcha, \@errors );

    if (@expected_errors) {
        ok( !$reply, "$message: rejected" );
        is( scalar @errors, scalar @expected_errors, "$message: number of errors" );
        for my $index ( 0 .. $#expected_errors ) {
            like( $errors[$index] // '', $expected_errors[$index], "$message: error $index" );
        }
    }
    else {
        is( $reply && $reply->{parent}{talkid}, $parenttalkid, "$message: accepted" )
            or diag( join "\n", @errors );
    }
}

subtest 'journal settings and identities' => sub {
    my $journal   = validated_user();
    my $commenter = validated_user();
    my $openid    = temp_user( journaltype => 'I' );
    my $entry     = $journal->t_post_fake_entry;

    $journal->update_self( { opt_whocanreply => 'all' } );
    check_reply( 'public journal allows anonymous',          $entry, undef,   undef );
    check_reply( 'public journal allows unvalidated OpenID', $entry, $openid, undef );
    my $feed = temp_feed();
    $feed->update_self( { opt_whocanreply => 'all' } );
    ok( $feed->does_not_allow_comments_from(undef), 'feeds still disallow anonymous replies' );

    $journal->update_self( { opt_whocanreply => 'reg' } );
    check_reply( 'registered only rejects anonymous', $entry, undef, undef, qr/post anonymously/ );
    check_reply( 'registered only accepts regular accounts', $entry, $commenter, undef );
    check_reply( 'registered only rejects unconfirmed OpenID',
        $entry, $openid, undef, qr/confirm<\/a> your email/ );
    $journal->add_edge( $openid, trust => { nonotify => 1 } );
    check_reply( 'registered only allows trusted unconfirmed OpenID', $entry, $openid, undef );

    $journal->update_self( { opt_whocanreply => 'friends' } );
    check_reply(
        'access only rejects anonymous with both reasons',
        $entry, undef, undef,
        qr/post anonymously/,
        qr/Only friends/
    );
    check_reply( 'access only rejects a stranger', $entry, $commenter, undef, qr/Access List/ );
    $journal->add_edge( $commenter, trust => { nonotify => 1 } );
    check_reply( 'access only accepts an account with access', $entry, $commenter, undef );

    $commenter->update_self( { statusvis => 'S' } );
    check_reply( 'access does not override suspension', $entry, $commenter, undef, qr/suspended/ );
    $commenter->update_self( { statusvis => 'O' } );
    check_reply( 'access does not override read-only status',
        $entry, $commenter, undef, qr/read-only/ );
};

subtest 'community membership and scoped bans' => sub {
    my $journal       = temp_comm();
    my $entry_author  = validated_user();
    my $parent_author = validated_user();
    my $commenter     = validated_user();
    my $entry         = $entry_author->t_post_fake_comm_entry($journal);
    my $parent        = $entry->t_enter_comment( u => $parent_author );
    my $anonymous     = $entry->t_enter_comment;

    $journal->update_self( { opt_whocanreply => 'friends' } );
    LJ::set_rel( $journal, $commenter, 'A' );
    check_reply( 'admin still needs membership',
        $entry, $commenter, undef, qr/restricted to members/ );
    $commenter->join_community( $journal, 1, 1 );
    check_reply( 'community member can reply', $entry, $commenter, $parent );

    $parent_author->ban_user($commenter);
    check_reply( 'parent author ban does not affect entry replies', $entry, $commenter, undef );
    check_reply( 'parent author ban does not affect anonymous parent',
        $entry, $commenter, $anonymous );
    check_reply( 'parent author ban blocks reply to their comment',
        $entry, $commenter, $parent, qr/banned from replying/ );

    $entry_author->ban_user($commenter);
    check_reply( 'entry author ban blocks top-level replies',
        $entry, $commenter, undef, qr/banned from commenting on entries/ );
    check_reply(
        'entry and parent author bans both apply to nested replies',
        $entry, $commenter, $parent,
        qr/banned from commenting on entries/,
        qr/banned from replying/
    );
    ok(
        !$journal->does_not_allow_comments_from($commenter),
        'the targetless form policy ignores author bans'
    );

    $journal->ban_user($commenter);
    check_reply(
        'journal ban replaces entry ban but not parent ban',
        $entry, $commenter, $parent,
        qr/not allowed to post in this community/,
        qr/banned from replying/
    );
    ok(
        $journal->does_not_allow_comments_from($commenter),
        'the targetless form policy includes journal bans'
    );
};

subtest 'entry and parent availability' => sub {
    my $owner     = validated_user();
    my $commenter = validated_user();
    my $author    = validated_user();
    my $entry     = $owner->t_post_fake_entry;
    my $private   = $owner->t_post_fake_entry( security => 'private' );
    my $screened  = $entry->t_enter_comment( u => $author, state => 'S' );
    my $frozen    = $entry->t_enter_comment( u => $author, state => 'F' );
    my $hidden    = $entry->t_enter_comment( u => $author );

    check_reply( 'private entry rejects a stranger',
        $private, $commenter, undef, qr/protected entry/ );
    check_reply( 'owner can reply to their private entry', $private, $owner, undef );
    check_reply( 'parent on a different entry looks missing',
        $private, $owner, $screened, qr/non-existent comment/ );
    check_reply( 'invisible screened parent looks missing',
        $entry, $commenter, $screened, qr/non-existent comment/ );
    check_reply( 'owner can reply to a screened parent', $entry, $owner, $screened );
    check_reply( 'frozen parent rejects even the owner', $entry, $owner, $frozen, qr/frozen/ );
    $author->update_self( { statusvis => 'S' } );
    check_reply( 'suspended parent author makes their parent look missing',
        $entry, $commenter, $hidden, qr/non-existent comment/ );

    for my $prop ( 'opt_nocomments', 'opt_nocomments_maintainer' ) {
        $entry->set_prop( $prop, 1 );
        check_reply( "$prop closes entry and comment replies", $entry, $owner, undef,
            qr/disabled/ );
        check_reply( "$prop takes precedence over parent state",
            $entry, $owner, $frozen, qr/disabled/ );
        $entry->set_prop( $prop, 0 );
    }
    $entry->set_prop( statusvis => 'S' );
    check_reply( 'entry poster cannot reply to their suspended entry',
        $entry, $owner, undef, qr/entry is suspended/ );
    check_reply( 'stranger cannot learn that the entry is suspended',
        $entry, $commenter, undef, qr/protected entry/ );
};

done_testing();
