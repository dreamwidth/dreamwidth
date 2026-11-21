# t/plack-poll-create.t
#
# The poll generator must offer the journals a poll can be posted to: free
# accounts can make polls for paid communities they can post to.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# Requests carry no session cookie, so keep the form token's session stable.
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'pollCreateTest';

my ( $FREE, $PAID ) = ( 2, 8 );    # cap classes in t/config-test.pl

my $free      = temp_user();
my $paid      = temp_user();
my $outsider  = temp_user();
my $owner     = temp_user();
my $paidcomm  = temp_comm();
my $freecomm  = temp_comm();
my $maintcomm = temp_comm();
my $freemaint = temp_comm();
my $openpaid  = temp_comm();
my $openfree  = temp_comm();
$_->update_self( { caps => $FREE } ) for ( $free, $outsider, $freecomm, $freemaint, $openfree );
$_->update_self( { caps => $PAID } ) for ( $paid, $paidcomm, $maintcomm, $openpaid );

LJ::set_rel( $_, $free, 'P' ) for ( $paidcomm, $freecomm );
LJ::set_rel( $freecomm, $paid, 'P' );
LJ::set_rel( $_, $free, 'A' ) for ( $maintcomm, $freemaint );

# Communities where anybody can post, including non-members.
for my $comm ( $openpaid, $openfree ) {
    LJ::set_rel( $comm, $owner, 'A' );
    $comm->set_comm_settings( $owner, { postlevel => 'members' } );
    $comm->set_prop( nonmember_posting => 1 );
}

ok( !$free->can_create_polls      && $paidcomm->can_create_polls,   'fixture capabilities' );
ok( $free->can_post_to($openpaid) && !$free->can_manage($openpaid), 'non-members can post' );

my $base = 'http://localhost/poll/create';

# The question form posts back to the selected journal.
sub poll_form_for {
    my ( $content, $journal ) = @_;
    my $query = $journal ? quotemeta( '?authas=' . $journal->user ) : '';
    return $content =~ /<form method='post' action='create$query#new'>/;
}

sub offers {
    my ( $content, $journal ) = @_;
    my $user = $journal->user;
    return $content =~ /<option[^>]*value=['"]\Q$user\E['"]/;
}

test_psgi $app, sub {
    my $cb = shift;

    my $get = sub {
        my ( $u, $journal ) = @_;
        my $query = $journal ? '&authas=' . $journal->user : '';
        return $cb->( GET "$base?as=" . $u->user . $query )->content;
    };

    subtest 'free member of a paid community' => sub {
        my $page = $get->( $free, $paidcomm );
        ok( poll_form_for( $page, $paidcomm ), 'poll form targets the community' );
        ok( offers( $page, $paidcomm ), 'community is in the post-to list' );

        my ($token) = $page =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        ok( $token, 'form has a CSRF token' );

        my $res = $cb->(
            POST "$base?as=" . $free->user . '&authas=' . $paidcomm->user,
            Content => [
                lj_form_auth   => $token,
                count          => 1,
                pq_0_type      => 'text',
                pq_0_opts      => 0,
                pq_0_question  => 'POLL_QUESTION_MARKER',
                pq_0_size      => 50,
                pq_0_maxlength => 255,
                see_code       => 1,
            ]
        );
        my $preview = $res->content;
        like( $preview, qr/POLL_QUESTION_MARKER/, 'poll code is generated' );
        my $user = $paidcomm->user;
        like(
            $preview,
            qr/action='[^']*\?usejournal=\Q$user\E'/,
            'posting the poll goes to the community'
        );

        my $entry = $cb->( GET "http://localhost/entry/$user/new?as=" . $free->user )->content;
        like( $entry, qr{/poll/create\?authas=\Q$user\E"}, 'entry form opens the poll for it' );
    };

    subtest 'free account in its own journal' => sub {
        my $page = $get->($free);
        ok( poll_form_for($page), 'poll form is shown' );
        ok( offers( $page, $paidcomm ),  'paid community is offered' );
        ok( offers( $page, $maintcomm ), 'maintained paid community is offered' );
        ok( !offers( $page, $freecomm ),  'free community is not offered' );
        ok( !offers( $page, $freemaint ), 'maintained free community is not offered' );
    };

    subtest 'free maintainer of a paid community' => sub {
        ok( poll_form_for( $get->( $free, $maintcomm ), $maintcomm ), 'poll form is shown' );
    };

    subtest 'paid member of a free community' => sub {
        my $page = $get->( $paid, $freecomm );
        ok( poll_form_for( $page, $freecomm ), 'poll form targets the community' );
        ok( offers( $page, $freecomm ), 'community is in the post-to list' );
    };

    subtest 'non-members of a community anybody can post to' => sub {
        for my $case (
            [ 'free account, paid community', $free, $openpaid ],
            [ 'paid account, free community', $paid, $openfree ]
            )
        {
            my ( $label, $u, $journal ) = @$case;
            my $page = $get->( $u, $journal );
            ok( poll_form_for( $page, $journal ), "$label: poll form targets the community" );
            ok( offers( $page, $journal ), "$label: community is in the post-to list" );
        }
    };

    subtest 'refused journals' => sub {
        for my $case (
            [ 'free member of a free community',      $free,     $freecomm ],
            [ 'free maintainer of a free community',  $free,     $freemaint ],
            [ 'free non-member, open free community', $free,     $openfree ],
            [ 'non-member of a paid community',       $outsider, $paidcomm ],
            [ 'another person\'s journal',            $free,     $paid ],
            )
        {
            my ( $label, $u, $journal ) = @$case;
            my $page = $get->( $u, $journal );
            ok( !poll_form_for( $page, $journal ), "$label: no poll form" );
            like( $page, qr/be authenticated as the specified account/, "$label: refused" );
        }
    };
};

done_testing;
