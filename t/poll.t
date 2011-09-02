# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

use LJ::Test qw( temp_user );
use LJ::Poll;

note( "Set up a poll where the voter is on a different cluster" );
{
    $LJ::DEFAULT_CLUSTER = 1;
    my $poll_journal = temp_user();

    my $entry = $poll_journal->t_post_fake_entry();
    my $poll = LJ::Poll->create(
            entry => $entry,
            questions => [ { type => "text", qtext => "a text question" } ],
            name => "poll answer across clusters",

            isanon => 'no',
            whovote => 'all',
            whoview => 'all',
        );


    $LJ::DEFAULT_CLUSTER = 2;
    my $voter = temp_user();
    LJ::set_remote( $voter );

    LJ::Poll->process_submission( { pollid => $poll->id, "pollq-1" => "voter's answers" } );

    is_deeply( { $poll->get_pollanswers( $voter ) },
        {
            1 => "voter's answers"
        }, "Checking that we got the voter's answers correctly when journal / poll are on different clusters" );
}

done_testing();

1;

