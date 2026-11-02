#!/usr/bin/perl
#
# t/plack-entry-moderated-post.t
#
# Characterize moderated community posting through the native entry form.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common;
use HTML::Form;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Session;
use LJ::Test qw(temp_comm temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub moderation_requests {
    my ($comm) = @_;
    my $dbcm = LJ::get_cluster_master($comm);
    return $dbcm->selectall_arrayref(
        'SELECT posterid, subject FROM modlog WHERE journalid=? ORDER BY modid',
        { Slice => {} },
        $comm->id
    );
}

my $poster = temp_user();
$poster->update_self( { status => 'A' } );
my $community = temp_comm();
$community->set_prop( moderated => 1 );
LJ::set_rel( $community, $poster, 'P' );
my ($approved) =
    LJ::get_db_writer()
    ->selectrow_array( q{SELECT COUNT(*) FROM reluser WHERE userid=? AND targetid=? AND type='N'},
    undef, $community->id, $poster->id );
is( $approved, 0, 'ordinary poster has no moderation preapproval relation' );

my $session = LJ::Session->create( $poster, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'moderatedPostCharacterization';

my @spam_checks;
local $LJ::HOOKS{spam_check} = [ sub { push @spam_checks, [@_]; return; } ];

my $path = '/entry/new?usejournal=' . $community->user;

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    no warnings qw(redefine once);
    local *LJ::BetaFeatures::user_in_beta              = sub { 0 };
    local *LJ::Event::CommunityModeratedEntryNew::fire = sub { 1 };

    my $res = $request->( GET $path );
    my ($form) =
        grep {
               $_->find_input('subject')
            && $_->find_input('event')
            && $_->find_input('action:post')
        } HTML::Form->parse( $res->content, "http://localhost$path" );
    ok( $form, 'native new-entry form exposes its posting form' )
        or BAIL_OUT('native new-entry posting form missing');
    $form->value( subject  => 'Moderated subject' );
    $form->value( event    => 'Moderated body' );
    $form->value( security => 'public' );
    my $post = $form->click('action:post');
    $post->uri("http://localhost$path");
    $post->header( Referer => "http://localhost$path" );
    $request->($post);

    my $requests = moderation_requests($community);
    is( scalar @$requests,        1,                   'post creates one moderation request' );
    is( $requests->[0]{posterid}, $poster->id,         'moderation request records the poster' );
    is( $requests->[0]{subject},  'Moderated subject', 'moderation request holds the post' );
    my ($published) = $community->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
        undef, $community->id );
    is( $published, 0, 'post publishes no community entry' );
};

done_testing;
