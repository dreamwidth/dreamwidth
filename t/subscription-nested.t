use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }

use LJ::Comment;
use LJ::Talk;
use LJ::Test qw( temp_user );

sub check_thread_subscription {
    my ( $entry, $u, $no_sub ) = @_;

    subtest "checking thread subscription" => sub {
        my $time = time();
        my @comments = $entry->comment_list;

        foreach my $comment ( @comments ) {
            my $time = time();
            my $has_sub = $comment->thread_has_subscription( $u, $entry->journal );

            if ( $no_sub->{$comment->jtalkid} ) {
                ok( ! $has_sub, $no_sub->{$comment->jtalkid} );
            } else {
                ok( $has_sub, "ancestor of " . $comment->jtalkid . " is tracked" );
            }
        }
    }
}

note("shallow comment threads");
{
    my $u = temp_user();
    my $e = $u->t_post_fake_entry;

    my @comments;
    my $c = $e->t_enter_comment;
    push @comments, $c;

    foreach ( 1...10 ) {
        $c = $c->t_reply;
        push @comments, $c;
    }

    $u->subscribe(  event   => "JournalNewComment",
                    method  => "Email",
                    journal => $u,
                    arg2    => $comments[2]->jtalkid,
                  );

    check_thread_subscription( $e, $u, {
        # not subscribed to #     because....
        1                     =>  "above subscription point",
        2                     =>  "above subscription point",
        3                     =>  "subscribed starting from this comment (but not subscribed to ancestor)",
    } );
}

note("deep comment thread");
{
    my $u = temp_user();
    my $e = $u->t_post_fake_entry;

    my @comments;
    my $c = $e->t_enter_comment;
    push @comments, $c;

    foreach ( 1...500 ) {
        $c = $c->t_reply;
        push @comments, $c;
    }

    $u->subscribe(  event   => "JournalNewComment",
                    method  => "Email",
                    journal => $u,
                    arg2    => $comments[2]->jtalkid,
                  );

    check_thread_subscription( $e, $u, {
        # not subscribed to #     because....
        1                     =>  "above subscription point",
        2                     =>  "above subscription point",
        3                     =>  "subscribed starting from this comment (but not subscribed to ancestor)",
    } );
}

done_testing();
