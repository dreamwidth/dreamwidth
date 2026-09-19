# t/talkpost-validate-comment.t
#
# Test the thing that checks permissions/validity/coherency of submitted
# comments (and puts them into the expected format for the functions that
# enter comments into the database).
#
# Authors:
#      Nick Fagerlund <nick.fagerlund@gmail.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user temp_comm );

use LJ::Entry;
use LJ::Talk;

# Refresher on form structure:
#   - body
#   - subject
#   - prop_something (various)
#   - editid and editreason, if editing
#   - parenttalkid: integer, comment being replied to (0 if replying to entry)
#   - replyto: duplicate of parenttalkid, for some reason
#   - subjecticon
#   - any captcha-related fields from the talkform (varies by captcha type)
#   - all other fields are ignored. MOST NOTABLY, this function stays away from
#   the user info fields.

my $journalu = temp_user();
my $entry    = $journalu->t_post_fake_entry();

note("Comment form from a logged in user:");

my $form = {
    body        => "Comment body",
    subject     => "Comment subject",
    subjecticon => "none",
};

my $commenter    = temp_user();
my $need_captcha = 0;
my @errors       = ();
my $comment;

# There's a nasty observer effect due to this cache: once something asks whether
# two users have a particular relationship, you can never again modify that
# relationship. And prepare_and_validate_comment asks about basically every
# possible relationship. So SCORCH THE EARTH.
my $reset = sub {
    DW::Cache->request->clear_ns('rel');
    $comment      = undef;
    @errors       = ();
    $need_captcha = 0;
};

note("...who ain't validated:");
$comment = LJ::Talk::Post::prepare_and_validate_comment( $form, $commenter, $entry, \$need_captcha,
    \@errors );
ok( !defined $comment, "Returned undef, not allowed." );
note( scalar @errors . " Validation errors: " . join( "\n", @errors ) );
$reset->();

note("...who has validated their email:");
$commenter->update_self( { status => 'A' } );
$comment = LJ::Talk::Post::prepare_and_validate_comment( $form, $commenter, $entry, \$need_captcha,
    \@errors );
ok( ref $comment eq 'HASH', "Succeeded, returned comment" );
ok( scalar @errors == 0,    "Didn't append any errors" );
note( scalar @errors . " Validation errors: " . join( "\n", @errors ) );
ok( $comment->{body} eq $form->{body}, "Comment body survived" );
ok( $comment->{subjecticon} eq '',     "'none' subjecticon (w/ left beef) munged to empty string" );
$reset->();

note("...who's banned:");
$journalu->ban_user($commenter);
$comment = LJ::Talk::Post::prepare_and_validate_comment( $form, $commenter, $entry, \$need_captcha,
    \@errors );
ok( !defined $comment, "Returned undef, not allowed." );
note( scalar @errors . " Validation errors: " . join( "\n", @errors ) );
$reset->();

# A stale checkbox from a manager's form must not lend that manager's powers
# to a different posting identity. Exercise the final write, not just the UI.
{
    no warnings 'redefine';
    my $owner = temp_user();
    my $other = temp_user();
    $_->update_self( { status => 'A' } ) for ( $owner, $other );
    my $post = $owner->t_post_fake_entry;
    local *LJ::get_remote = sub { $owner };
    for my $author ( $other, $owner ) {
        my $parent = $post->t_enter_comment( u => $other, state => 'S' );
        my $reply  = {
            u            => $author,
            entry        => $post,
            parent       => { talkid => $parent->jtalkid, state => 'S' },
            parenttalkid => $parent->jtalkid,
            state        => 'A',
            body         => 'Reply as ' . $author->user,
        };
        my ( $ok, $id ) = LJ::Talk::Post::post_comment( $reply, 1 );
        ok( $ok, 'Reply posts with stale unscreen request' );
        my ($state) =
            $owner->selectrow_array( 'SELECT state FROM talk2 WHERE journalid = ? AND jtalkid = ?',
            undef, $owner->id, $parent->jtalkid );
        is(
            $state,
            $author->equals($owner) ? 'A' : 'S',
            'Unscreen uses selected commenter permissions'
        );
    }
    my $original = $post->t_enter_comment( u => $owner );
    local $LJ::DISABLED{edit_comments} = 0;
    local *LJ::User::can_edit_comments = sub { 1 };
    my $edit_error;
    ok(
        $original->user_can_edit( $owner, \$edit_error ),
        'Browsing owner can edit original comment'
    );
    my ($edited) = LJ::Talk::Post::edit_comment(
        {
            u      => $other,
            entry  => $post,
            editid => $original->dtalkid,
            body   => 'Attempted edit'
        }
    );
    ok( !$edited, 'Selected account cannot edit browsing account comment' );
}
done_testing();
