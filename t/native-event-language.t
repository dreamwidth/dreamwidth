#!/usr/bin/perl
# Regression coverage for native request-language event callers.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';

use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use LJ::Event::AddedToCircle;
use LJ::Event::RemovedFromCircle;
use LJ::Event::NewUserpic;
use LJ::Event::PollVote;
use LJ::Event::CommunityInvite;
use LJ::Event::CommunityJoinRequest;
use LJ::Event::InvitedFriendJoins;
use LJ::Event::OfficialPost;
use LJ::Event::UserExpunged;
use LJ::Event::JournalNewEntry;
use LJ::Event::JournalNewComment;
use LJ::Event::JournalNewComment::Reply;
use LJ::Event::VgiftApproved;

sub request {
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    return DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        },
    );
}

{

    package NativeEventLanguage::User;
    sub new { my ( $class, %args ) = @_; return bless \%args, $class; }
    sub equals         { $_[0]->{id} eq $_[1]->{id} }
    sub is_comm        { $_[0]->{comm} }
    sub is_identity    { 0 }
    sub ljuser_display { $_[0]->{display} }
}

{

    package NativeEventLanguage::Subscription;
    sub new { my ( $class, %args ) = @_; return bless \%args, $class; }
    sub journal { $_[0]->{journal} }
    sub owner   { $_[0]->{owner} }
    sub arg1    { $_[0]->{arg1} }
    sub arg2    { $_[0]->{arg2} }
}

{

    package NativeEventLanguage::Vgift;
    sub new { my ( $class, %args ) = @_; return bless \%args, $class; }
    sub name         { $_[0]->{name} }
    sub name_ehtml   { $_[0]->{name} }
    sub approved     { $_[0]->{approved} }
    sub approved_why { $_[0]->{why} }
}

sub native_context {
    my @calls;
    request();
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub {
            my ( $lang, $code, $unused, $vars ) = @_;
            $vars ||= {};
            push @calls, [ $code, {%$vars} ];
            return 'native:' . $code . ':' . join ',', map { "$_=$vars->{$_}" } sort keys %$vars;
        },
    );
    return \@calls;
}

subtest 'event subscription labels use native request translations and preserve substitutions' =>
    sub {
    my $calls = native_context();
    my $owner = NativeEventLanguage::User->new( id => 1, display => '<a>Owner</a>' );
    my $comm  = NativeEventLanguage::User->new( id => 2, comm => 1, display => '<a>Community</a>' );
    my $sub_owner = NativeEventLanguage::Subscription->new(
        journal => $owner,
        owner   => $owner,
        arg1    => 0,
        arg2    => 0
    );
    my $sub_comm = NativeEventLanguage::Subscription->new(
        journal => $comm,
        owner   => $owner,
        arg1    => 0,
        arg2    => 0
    );

    is(
        LJ::Event::AddedToCircle->subscription_as_html($sub_owner),
        'native:event.addedtocircle.me:',
        'AddedToCircle keeps the owner branch'
    );
    is(
        LJ::Event::AddedToCircle->subscription_as_html($sub_comm),
        'native:event.addedtocircle.user:user=<a>Community</a>',
        'AddedToCircle preserves display HTML substitution'
    );
    is(
        LJ::Event::RemovedFromCircle->subscription_as_html($sub_comm),
        'native:event.removedfromcircle.user:user=<a>Community</a>',
        'RemovedFromCircle preserves display HTML substitution'
    );
    is(
        LJ::Event::NewUserpic->subscription_as_html($sub_comm),
        'native:event.userpic_upload.user:user=<a>Community</a>',
        'NewUserpic uses the watched-journal branch'
    );
    is(
        LJ::Event::NewUserpic->subscription_as_html( NativeEventLanguage::Subscription->new ),
        'native:event.userpic_upload.me:',
        'NewUserpic keeps the no-journal branch'
    );
    is(
        LJ::Event::PollVote->subscription_as_html(
            NativeEventLanguage::Subscription->new( arg1 => 9 )
        ),
        'native:event.poll_vote.id:',
        'PollVote keeps the poll-id branch'
    );
    is(
        LJ::Event::PollVote->subscription_as_html(
            NativeEventLanguage::Subscription->new( arg1 => 0 )
        ),
        'native:event.poll_vote.me:',
        'PollVote keeps the owner branch'
    );
    is( LJ::Event::CommunityInvite->subscription_as_html($sub_owner),
        'native:event.comm_invite:', 'CommunityInvite uses native translation' );
    is(
        LJ::Event::CommunityJoinRequest->subscription_as_html($sub_owner),
        'native:event.community_join_requst:',
        'CommunityJoinRequest preserves its historical dynamic spelling'
    );
    is(
        LJ::Event::InvitedFriendJoins->subscription_as_html($sub_owner),
        'native:event.invited_friend_joins:',
        'InvitedFriendJoins uses native translation'
    );
    local $LJ::SITENAME = 'Dream &amp; Width';
    is(
        LJ::Event::OfficialPost->subscription_as_html($sub_owner),
        'native:event.officialpost:sitename=Dream &amp; Width',
        'OfficialPost preserves sitename substitution'
    );
    is(
        LJ::Event::UserExpunged->subscription_as_html($sub_comm),
        'native:event.user_expunged:user=<a>Community</a>',
        'UserExpunged preserves journal display substitution'
    );

    is(
        LJ::Event::JournalNewEntry->subscription_as_html($sub_comm),
        'native:event.journal_new_entry.community:user=<a>Community</a>',
        'JournalNewEntry resolves its community dynamic key through native context'
    );
    is(
        LJ::Event::JournalNewComment->subscription_as_html($sub_owner),
        'native:event.journal_new_comment.my_journal:user=my journal',
        'JournalNewComment resolves owner dynamic key and substitution'
    );
    is(
        LJ::Event::JournalNewComment::Reply->subscription_as_html(
            NativeEventLanguage::Subscription->new( arg2 => 2 )
        ),
        'native:event.journal_new_comment.reply.mycomment:',
        'JournalNewComment Reply resolves its argument-selected dynamic key'
    );

    my $gift  = NativeEventLanguage::Vgift->new( name => 'Gift &amp; Name', approved => 'Y' );
    my $event = bless {}, 'LJ::Event::VgiftApproved';
    local *LJ::Event::VgiftApproved::vgift = sub { return $gift; };
    local *LJ::Event::VgiftApproved::fromu = sub { return $comm; };
    is(
        $event->as_html,
        'native:event.vgift.approved.content.Y:admin=<a>Community</a>,vgift=Gift &amp; Name',
        'VgiftApproved keeps escaped gift and administrator substitutions'
    );

    is_deeply(
        [ map { $_->[0] } @$calls ],
        [
            qw(
                event.addedtocircle.me event.addedtocircle.user event.removedfromcircle.user
                event.userpic_upload.user event.userpic_upload.me event.poll_vote.id event.poll_vote.me
                event.comm_invite event.community_join_requst event.invited_friend_joins event.officialpost
                event.user_expunged event.journal_new_entry.community
                event.journal_new_comment.my_journal event.journal_new_comment.reply.mycomment
                event.vgift.approved.content.Y
                )
        ],
        'all covered event labels reach the request-native getter with their existing global keys'
    );
    DW::Request->reset;
    };

subtest 'event labels retain nonweb language fallback' => sub {
    my $owner = NativeEventLanguage::User->new( id => 1, display => 'Owner' );
    my $other = NativeEventLanguage::User->new( id => 2, display => 'Other' );
    my $sub = NativeEventLanguage::Subscription->new( journal => $other, owner => $owner );
    DW::Request->reset;
    local *LJ::Lang::get_text = sub {
        my ( $lang, $code, $unused, $vars ) = @_;
        return "background:$lang:$code:$vars->{user}";
    };
    is(
        LJ::Event::RemovedFromCircle->subscription_as_html($sub),
        "background:$LJ::DEFAULT_LANG:event.removedfromcircle.user:Other",
        'background event rendering falls back to default-language text lookup'
    );
};

done_testing;
