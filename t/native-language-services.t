#!/usr/bin/perl
# Regression coverage for native request-language service callers.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';

use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request;
use DW::Request::Plack;
use LJ::Event::UserMessageRecvd;
use LJ::Lang;
use LJ::Message;
use LJ::Poll;
use LJ::Test qw(temp_user);

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

    package NativeLanguageServices::User;

    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub is_renamed          { 0 }
    sub is_person           { $_[0]->{person} }
    sub is_identity         { $_[0]->{identity} }
    sub is_deleted          { $_[0]->{deleted} }
    sub is_expunged         { $_[0]->{expunged} }
    sub can_receive_message { $_[0]->{can_receive} }
    sub ljuser_display      { $_[0]->{display} }
    sub equals              { $_[0] eq $_[1] }
}

{

    package NativeLanguageServices::Subscription;

    sub new {
        my ( $class, %args ) = @_;
        return bless \%args, $class;
    }
    sub journal { $_[0]->{journal} }
    sub owner   { $_[0]->{owner} }
}

subtest 'message validation keeps native request substitutions and background fallback' => sub {
    my $origin    = NativeLanguageServices::User->new( person  => 1, display => 'Origin' );
    my $recipient = NativeLanguageServices::User->new( display => 'Recipient &lt;unsafe&gt;' );
    my %users = ( 1 => $origin, 2 => $recipient );
    local *LJ::want_user = sub { return $users{ $_[0] }; };

    my $message = LJ::Message->new( { journalid => 1, otherid => 2 } );
    my $r       = request();
    my @calls;
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub {
            my ( $lang, $code, $unused, $vars ) = @_;
            push @calls, [ $code, $vars ];
            return "native:$code:$vars->{ljuser}";
        },
    );

    my @errors;
    ok( !$message->can_send( \@errors ), 'non-person recipient is rejected' );
    is(
        $errors[0],
        'native:error.message.individual:Recipient &lt;unsafe&gt;',
        'invalid recipient error uses native getter with preserved escaped ljuser HTML'
    );

    $recipient->{person}  = 1;
    $recipient->{deleted} = 1;
    @errors               = ();
    ok( !$message->can_send( \@errors ), 'deleted recipient is rejected' );
    is(
        $errors[0],
        'native:error.message.deleted:Recipient &lt;unsafe&gt;',
        'deleted error is native'
    );

    $recipient->{deleted}  = 0;
    $recipient->{expunged} = 1;
    @errors                = ();
    ok( !$message->can_send( \@errors ), 'expunged recipient is rejected' );
    is(
        $errors[0],
        'native:error.message.expunged:Recipient &lt;unsafe&gt;',
        'expunged error is native'
    );

    $recipient->{expunged}    = 0;
    $recipient->{can_receive} = 0;
    @errors                   = ();
    ok( !$message->can_send( \@errors ), 'recipient permission denial is rejected' );
    is(
        $errors[0],
        'native:error.message.canreceive:Recipient &lt;unsafe&gt;',
        'permission error is native'
    );
    is_deeply(
        [ map { $_->[0] } @calls ],
        [
            'error.message.individual', 'error.message.deleted',
            'error.message.expunged',   'error.message.canreceive'
        ],
        'each message validation key reaches the request-local getter'
    );

    DW::Request->reset;
    local *LJ::Lang::get_text = sub {
        my ( $lang, $code, $unused, $vars ) = @_;
        return "background:$lang:$code:$vars->{ljuser}";
    };
    $recipient->{person} = 0;
    @errors = ();
    ok( !$message->can_send( \@errors ), 'background validation still rejects invalid recipient' );
    is(
        $errors[0],
        'background:en:error.message.individual:Recipient &lt;unsafe&gt;',
        'background validation uses native default lookup without request context'
    );
};

subtest 'poll rendering uses native request strings for clear and text answers' => sub {
    my $owner = temp_user();
    my $entry = $owner->t_post_fake_entry();
    my $poll  = LJ::Poll->create(
        entry     => $entry,
        questions => [ { type => 'text', qtext => 'Native service question' } ],
        name      => 'native service poll',
        isanon    => 'no',
        whovote   => 'all',
        whoview   => 'all',
    );
    ok( $poll, 'created isolated poll fixture' ) or return;

    my $voter = temp_user();
    LJ::set_remote($voter);
    LJ::Poll->process_submission(
        { pollid => $poll->id, 'pollq-1' => 'answer &lt;kept escaped&gt;' } );

    request();
    my @calls;
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub {
            my ( $lang, $code, $unused, $vars ) = @_;
            push @calls, [ $code, $vars ];
            return 'native poll clear'                  if $code eq 'poll.clear';
            return "native poll answer:$vars->{answer}" if $code eq 'poll.useranswer';
            return LJ::Lang::get_text( $lang, $code, $unused, $vars );
        },
    );

    my $enter = $poll->render_enter;
    like( $enter, qr/native poll clear/, 'real enter rendering uses native clear label' );
    my $results = $poll->render_results;
    like(
        $results,
        qr/native poll answer:answer &lt;kept escaped&gt;/,
        'real results rendering passes cleaned text answer through native substitution'
    );
    ok( grep( $_->[0] eq 'poll.clear', @calls ) && grep( $_->[0] eq 'poll.useranswer', @calls ),
        'both legacy poll labels reached the request-local getter' );
    LJ::unset_remote();
    DW::Request->reset;
};

subtest 'message-received subscription descriptions use native web and background lookups' => sub {
    my $owner   = NativeLanguageServices::User->new( display => 'Owner' );
    my $journal = NativeLanguageServices::User->new( display => 'Journal &lt;unsafe&gt;' );
    my $mine  = NativeLanguageServices::Subscription->new( journal => $owner,   owner => $owner );
    my $other = NativeLanguageServices::Subscription->new( journal => $journal, owner => $owner );

    request();
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub {
            my ( $lang, $code, $unused, $vars ) = @_;
            return "native:$code" unless $vars;
            return "native:$code:$vars->{user}";
        },
    );
    is(
        LJ::Event::UserMessageRecvd->subscription_as_html($mine),
        'native:event.user_message_recvd.me',
        'self subscription description uses native key'
    );
    is(
        LJ::Event::UserMessageRecvd->subscription_as_html($other),
        'native:event.user_message_recvd.user:Journal &lt;unsafe&gt;',
        'other subscription description preserves escaped user substitution'
    );

    DW::Request->reset;
    local *LJ::Lang::get_text = sub {
        my ( $lang, $code, $unused, $vars ) = @_;
        return $vars ? "background:$code:$vars->{user}" : "background:$code";
    };
    is(
        LJ::Event::UserMessageRecvd->subscription_as_html($other),
        'background:event.user_message_recvd.user:Journal &lt;unsafe&gt;',
        'background event description uses native default lookup'
    );
};

done_testing;
