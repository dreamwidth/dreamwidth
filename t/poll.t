# t/poll.t
#
# Test user polls
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More; # TODO no plan yet

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

if ( @LJ::CLUSTERS < 2 || @{$LJ::DEFAULT_CLUSTER||[]} < 2) {
    plan skip_all => "Less than two clusters.";
    exit 0;
}

use LJ::Test qw( temp_user );
use LJ::Poll;

note( "Set up a poll where the voter is on a different cluster" );
{
    my $poll_journal = temp_user( cluster => $LJ::DEFAULT_CLUSTER->[0] );

    my $entry = $poll_journal->t_post_fake_entry();
    my $poll = LJ::Poll->create(
            entry => $entry,
            questions => [ { type => "text", qtext => "a text question" } ],
            name => "poll answer across clusters",

            isanon => 'no',
            whovote => 'all',
            whoview => 'all',
        );


    my $voter = temp_user( cluster => $LJ::DEFAULT_CLUSTER->[1] );
    LJ::set_remote( $voter );

    LJ::Poll->process_submission( { pollid => $poll->id, "pollq-1" => "voter's answers" } );

    is_deeply( { $poll->get_pollanswers( $voter ) },
        {
            1 => "voter's answers"
        }, "Checking that we got the voter's answers correctly when journal / poll are on different clusters" );
}

done_testing();

1;

