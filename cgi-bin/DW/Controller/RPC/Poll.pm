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
#
package DW::Controller::RPC::Poll;

use strict;
use DW::Routing;
use LJ::JSON;

DW::Routing->register_rpc( "poll",     \&poll_handler,     format => 'json' );
DW::Routing->register_rpc( "pollvote", \&pollvote_handler, format => 'json' );

sub poll_handler {
    my $r    = DW::Request->get;
    my $args = $r->post_args;

    my $ret = {};

    my $err = sub {
        my $msg = shift;
        $r->print(
            to_json(
                {
                    error => "Error: $msg",
                }
            )
        );
        return $r->OK;
    };

    my $pollid   = ( ( $args->{pollid} || 0 ) + 0 ) or return $err->("No pollid");
    my $pollqid  = ( $args->{pollqid} || 0 ) + 0;
    my $userid   = ( $args->{userid} || 0 ) + 0;
    my $action   = $args->{action};
    my $page     = ( $args->{page} || 0 ) + 0;
    my $pagesize = ( $args->{pagesize} || 2000 ) + 0;

    my $poll = LJ::Poll->new($pollid) or return $err->("Error loading poll $pollid");

    my $remote = LJ::get_remote();
    unless ( $poll->can_view($remote) ) {
        return $err->("You cannot view this poll");
    }

    if ( $action eq 'get_answers' ) {
        return $err->("No pollqid") unless $pollqid;

        my $question = $poll->question($pollqid)
            or return $err->("Error loading question $pollqid");
        my $pages = $question->answers_pages( $poll->journalid, $pagesize );
        $ret->{paging_html} =
            $question->paging_bar_as_html( $page, $pages, $pagesize, $poll->journalid, $pollid,
            $pollqid );
        $ret->{answer_html} =
            $question->answers_as_html( $poll->journalid, $poll->isanon, $page, $pagesize, $pages );
    }
    elsif ( $action eq 'get_respondents' ) {
        $ret->{answer_html} = $poll->respondents_as_html;
    }
    elsif ( $action eq 'get_user_answers' ) {
        return $err->("No userid") unless $userid;

        $ret->{answer_html} = $poll->user_answers_as_html($userid);
    }
    else {
        return $err->("Invalid action $action");
    }

    $ret = {
        %$ret,
        pollid  => $pollid,
        pollqid => $pollqid,
        userid  => $userid,
        page    => $page,
    };

    $r->print( to_json($ret) );

    return $r->OK;
}

sub pollvote_handler {
    my $r    = DW::Request->get;
    my $args = $r->post_args;

    my $ret = {};

    my $err = sub {
        my $msg = shift;
        $r->print(
            to_json(
                {
                    error => "Error: $msg",
                }
            )
        );
        return $r->OK;
    };

    # Flatten multi-arg into comma seperated
    my %values;
    foreach my $key ( keys %$args ) {
        $values{$key} = join( ",", $args->get_all($key) );
    }

    my $remote = LJ::get_remote();

    my $pollid = $args->{pollid} or return $err->("No pollid");

    my $poll = LJ::Poll->new($pollid);

    unless ( $poll && $poll->valid ) {
        return $err->("Poll not found");
    }

    my $u = $poll->journal;

    # load the item being shown
    my $entry = $poll->entry;
    unless ($entry) {
        return $err->("Post was deleted");
    }

    unless ( $entry->visible_to($remote) ) {
        return $err->("You don't have the permissions to view this poll");
    }

    my $action = $args->{action};

    if ( $action eq "vote" ) {
        unless ( $r->did_post ) {

            # I am not sure we can even get here
            return $err->("Post is required");
        }

        unless ( LJ::check_form_auth( $args->{lj_form_auth} ) ) {
            return $err->("Form is invalid; reload and try again");
        }

        my $error;
        LJ::Poll->process_submission( \%values, \$error );
        if ($error) {
            return $err->($error);
        }

        $ret->{results_html} = $poll->render( mode => "results" );

        $ret = { %$ret, pollid => $pollid };

    }
    elsif ( $action eq "change" ) {
        $ret->{results_html} = $poll->render( mode => "enter" );

        $ret = { %$ret, pollid => $pollid };

    }
    elsif ( $action eq "display" ) {
        $ret->{results_html} = $poll->render( mode => "results" );

        $ret = { %$ret, pollid => $pollid };
    }

    $r->print( to_json($ret) );
    return $r->OK;

}

1;
