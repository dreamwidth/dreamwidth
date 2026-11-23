# t/browser/fixtures/inbox-svg.pl
#
# Create and remove a journal with an SVG entry and its inbox notification.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use File::Temp qw(tempdir);
use JSON qw(encode_json);
use LJ::Event::JournalNewComment;
use LJ::Event::JournalNewEntry;
use LJ::Test ();

my $prefix = 'tbrowser_svg_';
my $email  = 'inbox-svg@example.invalid';
local $LJ::TASK_QUEUE_BACKEND    = 'localdisk';
local $LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

sub cleanup {
    my ($user) = @_;
    die 'Not an inbox SVG fixture' unless $user->email_raw eq $email;
    for my $entry ( $user->recent_entries ) {
        LJ::delete_entry( $user, $entry->jitemid, 0, $entry->anum );
    }
    $user->delete_and_purge_completely;
}

if ( @ARGV == 2 && $ARGV[0] eq '--delete' ) {
    die 'Not a fixture username' unless $ARGV[1] =~ /\A\Q$prefix\E[a-z0-9]{6}\z/;
    my $user = LJ::load_user( $ARGV[1] ) or exit 0;
    cleanup($user);
    exit 0;
}

my $username = $prefix . lc LJ::rand_chars(6);
my $password = LJ::rand_chars(24);
die 'Fixture username already exists' if LJ::load_user($username);
local @LJ::INITIAL_SUBSCRIPTIONS = ();
my $user = LJ::User->create_personal(
    user     => $username,
    email    => $email,
    password => $password,
    name     => 'Inbox SVG demo',
) or die 'Could not create fixture user';

eval {
    $user->update_self( { status => 'A', statusvis => 'V', opt_gettalkemail => 'X' } );
    my $svg =
          '<svg xmlns="http://www.w3.org/2000/svg" width="90" height="48" viewBox="0 0 90 48">'
        . '<rect width="90" height="48" rx="6" fill="#306bb1"></rect>'
        . '<circle cx="45" cy="24" r="14" fill="#ffdf78"></circle></svg>';
    my $embedded = '<img src="data:image/svg+xml,%3Csvg%2F%3E" alt="Data URL probe">';
    my $entry    = $user->t_post_fake_entry(
        subject => 'An entry with inline SVG',
        body    => "An inbox notification with a drawing.<br>$svg$embedded",
    );
    my $comment = $entry->t_enter_comment(
        u       => $user,
        subject => 'A comment with inline SVG markup',
        body    => "Comment cleaner probe.<br>$svg$embedded",
    );
    my $inbox        = $user->notification_inbox;
    my $comment_item = $inbox->enqueue( event => LJ::Event::JournalNewComment->new($comment) )
        or die 'Unable to enqueue comment notification';
    my $entry_item = $inbox->enqueue( event => LJ::Event::JournalNewEntry->new($entry) )
        or die 'Unable to enqueue entry notification';
    print encode_json(
        {
            user       => $username,
            password   => $password,
            entryQid   => $entry_item->qid,
            commentQid => $comment_item->qid,
        }
    );
    1;
} or do {
    my $error = $@;
    cleanup($user);
    die $error;
};
