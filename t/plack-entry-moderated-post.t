#!/usr/bin/perl
# Characterize moderated community posting through the native entry form.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::Form;
use Plack::Test;
use Storable qw(nfreeze thaw);

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Entry;
use LJ::Session;
use LJ::Test qw(temp_comm temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub form_with_fields {
    my ( $content, $base, @fields ) = @_;
    return (
        grep {
            my $form = $_;
            scalar grep { !$form->find_input($_) } @fields ? 0 : 1;
        } HTML::Form->parse( $content, $base )
    )[0];
}

sub fresh_comm {
    my ($userid) = @_;
    return LJ::load_userid( $userid, 1 );
}

sub fresh_draft_properties {
    my ($user) = @_;
    my $frozen = $user->prop('draft_properties') || '';
    return {} unless length $frozen;
    return thaw($frozen);
}

sub moderation_count {
    my ($comm) = @_;
    my $dbcm = LJ::get_cluster_master($comm);
    return $dbcm->selectrow_array( 'SELECT COUNT(*) FROM modlog WHERE journalid=?', undef,
        $comm->id );
}

sub latest_moderation {
    my ($comm) = @_;
    my $dbcm = LJ::get_cluster_master($comm);
    my ( $journalid, $modid, $posterid, $subject, $frozen ) = $dbcm->selectrow_array(
        'SELECT l.journalid, l.modid, l.posterid, l.subject, b.request_stor '
            . 'FROM modlog l JOIN modblob b ON b.journalid=l.journalid AND b.modid=l.modid '
            . 'WHERE l.journalid=? ORDER BY l.modid DESC LIMIT 1',
        undef, $comm->id
    );
    return unless defined $modid;
    return {
        journalid => $journalid,
        modid     => $modid,
        posterid  => $posterid,
        subject   => $subject,
        request   => thaw($frozen),
    };
}

sub assert_moderated_submission {
    my ( $comm, $poster, $before, $expected, $label ) = @_;
    my $fresh = fresh_comm( $comm->id );
    is( moderation_count($fresh), $before + 1, "$label creates exactly one moderation request" );
    my $stored = latest_moderation($fresh);
    ok( $stored, "$label moderation request loads from the community cluster" ) or return;
    is( $stored->{journalid}, $fresh->id,  "$label stores the exact community target" );
    is( $stored->{posterid},  $poster->id, "$label stores the exact poster" );
    is( $stored->{request}{usejournal},
        $fresh->user, "$label stores the exact community usejournal metadata" );
    is( $stored->{subject}, $expected->{subject}, "$label stores the exact moderated subject" );
    is( $stored->{request}{event}, $expected->{event}, "$label stores the exact moderated body" );
    is( $stored->{request}{security}, 'public', "$label stores public community security" );
    is( $stored->{request}{props}{taglist}, $expected->{taglist}, "$label stores exact tags" );
    is( $stored->{request}{props}{current_location},
        $expected->{location}, "$label stores exact location metadata" );
    is( $stored->{request}{props}{current_music},
        $expected->{music}, "$label stores exact music metadata" );
    my ($published) =
        $fresh->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $fresh->id );
    is( $published, 0, "$label creates no published community entry" );
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
ok( $poster->can_post_to($community), 'ordinary poster has normal community posting access' );
is( fresh_comm( $community->id )->prop('moderated'),
    1, 'forced-fresh community has moderation enabled' );

my $session = LJ::Session->create( $poster, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'moderatedPostCharacterization';

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

    my $expected = {
        subject  => 'Moderated subject',
        event    => 'Moderated body',
        taglist  => '',
        location => 'Moderated location',
        music    => 'Moderated music',
    };
    ok(
        $poster->set_draft_text('Moderated saved draft body'),
        'native new-entry form seeds a disposable draft body'
    );
    $poster->set_prop(
        draft_properties => nfreeze(
            {
                subject => 'Moderated saved draft subject',
                taglist => 'moderated-saved-draft-tag',
            }
        )
    );

    my $res = $request->( GET $path );
    is( $res->code, 200, 'native new-entry form renders for the authorized ordinary poster' );
    my $form =
        form_with_fields( $res->content, "http://localhost$path", qw(subject event action:post) );
    ok( $form, 'native new-entry form exposes its actual posting form' )
        or BAIL_OUT('native new-entry posting form missing');
    ok( $form->find_input('lj_form_auth'), 'native new-entry form has a CSRF token' );
    $form->value( subject          => $expected->{subject} );
    $form->value( event            => $expected->{event} );
    $form->value( security         => 'public' );
    $form->value( current_location => $expected->{location} );
    $form->value( current_music    => $expected->{music} );
    my $before = moderation_count( fresh_comm( $community->id ) );
    my $post   = $form->click('action:post');
    $post->uri("http://localhost$path");
    $post->header( Referer => "http://localhost$path" );
    my @success_hooks;
    my $run_hooks = \&LJ::Hooks::run_hooks;
    my $run_hook  = \&LJ::Hooks::run_hook;
    {
        no warnings 'redefine';
        local *LJ::Hooks::run_hooks = sub {
            my ( $name, @args ) = @_;
            if ( $name eq 'after_entry_post_extra_options' ) {
                push @success_hooks, [ $name, {@args} ];
                return ['<li>Moderated extra option marker</li>'];
            }
            return $run_hooks->(@_);
        };
        local *LJ::Hooks::run_hook = sub {
            my ( $name, @args ) = @_;
            if ( $name eq 'after_entry_post_extra_html' ) {
                push @success_hooks, [ $name, {@args} ];
                return '<p>Moderated extra HTML marker</p>';
            }
            return $run_hook->(@_);
        };
        $res = $request->($post);
    }
    is_deeply( \@success_hooks, [], 'ordinary native moderation invokes no legacy success hooks' );
    unlike(
        $res->content,
        qr/Moderated extra HTML marker/,
        'native response has no legacy hook output'
    );
    is( $res->code, 200, 'native new-entry form valid post returns a moderation response' );
    like(
        $res->content,
        qr/(?:moderation|moderated|approval|queue)/i,
        'native new-entry form response contains a meaningful moderation message'
    );
    unlike(
        $res->content,
        qr/<\?(?:badinput|horizon)\?>/i,
        'native new-entry form response has no broken BML token'
    );
    assert_moderated_submission( $community, $poster, $before, $expected, 'native new-entry form' );
    my $fresh_poster = LJ::load_userid( $poster->id, 1 );
    is( $fresh_poster->draft_text, undef,
        'native new-entry form clears the saved draft body after moderation submission' );
    is_deeply( fresh_draft_properties($fresh_poster),
        {}, 'native new-entry form clears saved draft properties' );
};

done_testing;
