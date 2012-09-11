# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

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

