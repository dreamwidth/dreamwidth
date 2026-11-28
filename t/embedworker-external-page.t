#!/usr/bin/perl
#
# t/embedworker-external-page.t
#
# Test embed jobs and external page metadata without loading ljlib.pl.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use Test::More;
use HTTP::Response;
use LJ::TextUtil   ();
use LWP::UserAgent ();
use DW::External::Page;
use DW::Worker::EmbedWorker;

{

    package Test::EmbedJob;

    sub new { bless { arg => $_[1], outcomes => [] }, $_[0] }
    sub arg               { $_[0]->{arg} }
    sub completed         { push @{ $_[0]->{outcomes} }, 'completed' }
    sub failed            { push @{ $_[0]->{outcomes} }, 'retry' }
    sub permanent_failure { push @{ $_[0]->{outcomes} }, 'permanent failure' }
}

{

    package Test::ExternalPageAgent;
    use parent 'LWP::UserAgent';

    sub request {
        my ( $self, $request ) = @_;
        push @{ $self->{requests} }, $request;
        return $self->{response};
    }
}

my $worker = 'DW::Worker::EmbedWorker';

subtest 'invalid embed jobs are discarded without contacting the provider' => sub {
    my $calls = 0;
    local *LJ::EmbedModule::contact_external_sites = sub { $calls++; return 'ok' };

    for my $case (
        [ 'extra key', { contents => '', journalid => 42, unexpected => undef } ],
        [ 'missing contents', { journalid => 42 } ],
        [ 'missing journal',  { contents  => '' } ],
        )
    {
        my ( $description, $arg ) = @$case;
        my $job = Test::EmbedJob->new($arg);
        $worker->work($job);
        is_deeply( $job->{outcomes}, ['permanent failure'], "$description is not retried" );
    }
    is( $calls, 0, 'invalid jobs do not call the embed service' );
};

subtest 'provider results settle embed jobs' => sub {
    my $arg = {
        vid_id    => '2468',
        host      => 'vimeo',
        contents  => '',
        preview   => 0,
        journalid => 42,
        id        => 17,
        cmptext   => 'C-embed',
        linktext  => 'Original title',
        url       => 'https://vimeo.com/2468',
    };
    my ( $provider_result, @requests );
    local *LJ::EmbedModule::contact_external_sites = sub {
        my ( $class, $request ) = @_;
        push @requests, {%$request};
        delete $request->{id};
        return $provider_result;
    };

    for my $case ( [ 1, 'completed' ], [ 'warn', 'retry' ], [ 'fail', 'permanent failure' ] ) {
        my ( $result, $expected ) = @$case;
        my $job = Test::EmbedJob->new( {%$arg} );
        $provider_result = $result;
        @requests        = ();
        $worker->work($job);
        is_deeply( $job->{outcomes}, [$expected], "provider result $result settles the job once" );
        is_deeply( \@requests, [$arg], 'the full embed payload reaches the provider once' );
        is_deeply( $job->arg, $arg, 'the original job payload stays intact' );
    }
};

subtest 'external pages decode the URL and parse metadata' => sub {
    my $agent = Test::ExternalPageAgent->new;
    my @roles;
    local *LJ::get_useragent = sub {
        my %opts = @_;
        push @roles, $opts{role};
        return $agent;
    };
    local $LJ::SITENAME = 'Example Journal';
    $agent->{response} = HTTP::Response->new( 200, 'OK', [], <<'HTML' );
<head>
    <title>  A &amp; B   on the web </title>
    <meta name="description" content="  News &amp; notes  ">
    <meta name="keywords" content="not a description">
    <meta name="description" content="">
</head>
HTML

    my $url  = 'https://example.test/story?id=42';
    my $page = DW::External::Page->new( url => 'https%3A%2F%2Fexample.test%2Fstory%3Fid%3D42' );
    isa_ok( $page, 'DW::External::Page' );
    is( $page && $page->url,   $url,               'the page keeps the decoded URL' );
    is( $page && $page->title, 'A & B on the web', 'the title is decoded and normalized' );
    is( $page && $page->description,
        'News & notes', 'only nonempty description tags provide a summary' );
    is_deeply( \@roles, ['share'], 'the request uses the sharing user agent' );
    is_deeply(
        [ map { [ $_->method, $_->uri->as_string ] } @{ $agent->{requests} // [] } ],
        [ [ GET => $url ] ],
        'the decoded URL is fetched once'
    );
    is( $agent->agent, $LJ::SITENAME, 'the user agent identifies the site' );
};

subtest 'external pages distinguish unusable responses from missing metadata' => sub {
    my $agent = Test::ExternalPageAgent->new;
    local *LJ::get_useragent = sub { return $agent };
    local $LJ::SITENAME      = 'Example Journal';
    my $url = 'https://example.test/story';

    is( DW::External::Page->new( url => '' ), undef, 'an empty URL returns no page' );
    is_deeply( $agent->{requests}, undef, 'an empty URL does not issue a request' );

    $agent->{response} = HTTP::Response->new( 404, 'Not Found', [], '<title>Error page</title>' );
    is( DW::External::Page->new( url => $url ), undef, 'an HTTP error is not parsed as a page' );

    $agent->{response} = HTTP::Response->new( 200, 'OK' );
    is( DW::External::Page->new( url => $url ), undef, 'an empty response returns no page' );

    $agent->{response} = undef;
    is( DW::External::Page->new( url => $url ), undef, 'no response returns no page' );

    $agent->{response} = HTTP::Response->new( 200, 'OK', [], '<p>Article body</p>' );
    my $page = DW::External::Page->new( url => $url );
    isa_ok( $page, 'DW::External::Page' );
    is( $page && $page->title, '', 'a successful page without a title has an empty title' );
    is( $page && $page->description,
        '', 'a successful page without a summary has an empty summary' );
};

ok( !grep( { defined && m{(?:^|/)ljlib[.]pl\z} } keys %INC, values %INC ),
    'ljlib.pl is not loaded' );

done_testing();
