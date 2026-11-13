# t/comment-notification-links.t
#
# Test navigation links in comment notification emails.
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

use LJ::Comment;
use LJ::Event;
use LJ::Test qw( temp_user );

my $owner    = temp_user();
my $poster   = temp_user();
my $entry    = $owner->t_post_fake_entry;
my $root     = $entry->t_enter_comment( u => $poster );
my $reply    = $root->t_reply( u => $poster );
my $screened = $root->t_reply( u => $poster, state => 'S' );

for my $case ( [ 'top-level', $root ], [ 'nested', $reply ], [ 'screened', $screened ] ) {
    my ( $label, $comment ) = @$case;
    for my $format (qw( text html )) {
        subtest "$label $format notification" => sub {
            my $method = "format_${format}_mail";
            my $body   = $comment->$method($owner);

            unlike( $body, qr/redir_type=threadroot/,       "no thread-root redirect URL" );
            unlike( $body, qr/Go to the top of the thread/, "no redundant thread-root action" );

            for my $link (
                [ 'reply',        $comment->reply_url ],
                [ 'thread',       $comment->thread_url ],
                [ 'all comments', $entry->url . '#comments' ]
                )
            {
                my ( $name, $url ) = @$link;
                my $expected = $format eq 'html' ? qq{href="$url"} : $url;
                like( $body, qr/\Q$expected\E/, "$name link remains usable" );
            }
        };
    }
}

done_testing();
