# t/headings-tools-misc.t
#
# Check the heading outline of tools and other site pages.
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

use HTML::TokeParser;
use HTTP::Request;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use DW::Template;
use LJ::Lang;
use LJ::UniqCookie;

sub check_headings {
    my ( $template, $scenario, $vars, $expected, $body_marker ) = @_;

    subtest "$template: $scenario" => sub {
        DW::Request->reset;
        DW::Request::Standard->new( HTTP::Request->new( GET => 'http://www.example.com/' ) );
        LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
        LJ::UniqCookie->set_current_uniq('headingtest1234');
        local %LJ::REQ_GLOBAL;
        local $LJ::ACTIVE_RES_GROUP;
        my %sections;
        my $body = DW::Template->template_string( $template, $vars, \%sections );
        ok( $sections{title}, 'template supplies the site-scheme title' );
        like( $body, $body_marker, 'expected branch content is present' ) if $body_marker;

        my $html   = "<h1>$sections{title}</h1>$body";
        my $parser = HTML::TokeParser->new( \$html );
        my ( @levels, @labels );
        while ( my $tag = $parser->get_tag(qw(h1 h2 h3 h4 h5 h6)) ) {
            my ($level) = $tag->[0] =~ /([1-6])/;
            push @levels, $level;
            push @labels, $parser->get_trimmed_text("/$tag->[0]");
        }

        is( scalar( grep { $_ == 1 } @levels ), 1, 'the page title is the only h1' );
        my @skips = grep { $levels[$_] > $levels[ $_ - 1 ] + 1 } 1 .. $#levels;
        is( scalar @skips, 0, 'no heading levels are skipped' ) or diag join ' → ', @levels;
        shift @labels;
        is( scalar @labels, scalar @$expected, 'expected number of body headings' );
        for my $index ( 0 .. $#$expected ) {
            like( $labels[$index] // '', $expected->[$index], 'expected body heading' );
        }
    };
}

my $confirmed   = { status => 'A', user   => 'tester', email_raw => 'tester@example.com' };
my $unconfirmed = { %$confirmed,   status => 'N' };
my @email_headings = ( qr/Current Email Address/, qr/Previous Email Addresses/ );
check_headings(
    'tools/emailmanage.tt',
    'confirmed with no history',
    { u => $confirmed, rows => [], deleted => [] },
    \@email_headings
);
check_headings(
    'tools/emailmanage.tt',
    'confirmed with history and changes saved',
    {
        u        => $confirmed,
        lastdate => '2026-01-01',
        rows     => [ { email => 'old@example.com', time => '2025-01-01', can_del => 1 } ],
        deleted  => ['Removed another address'],
    },
    [ @email_headings, qr/Changes Saved/ ],
    qr/old\@example\.com/
);
check_headings( 'tools/emailmanage.tt', 'unconfirmed', { u => $unconfirmed, deleted => [] },
    [qr/Email not confirmed/] );

check_headings( 'tools/tellafriend.tt', 'confirmed', { u => $confirmed }, [],
    qr/name=['"]toemail/ );
check_headings( 'tools/tellafriend.tt', 'unconfirmed', { u => $unconfirmed }, [qr/Sorry/] );

for my $state (
    [ ignored   => { ignore     => 1 } ],
    [ error     => { search_err => 1 } ],
    [ empty     => { numusers   => 0 } ],
    [ paginated => { numusers   => 21, results => '<p>Matches</p>' } ]
    )
{
    check_headings( 'directory/results.tt', $state->[0], { %{ $state->[1] } },
        [qr/Search Results/] );
}

my %comment_vars = (
    u        => { is_person => 1, ljuser_display => 'Tester' },
    getextra => {},
    max      => 10,
    sitemax  => 10,
    count    => 10,
    show     => 10,
);
check_headings( 'comments/posted.tt', 'no comments', {%comment_vars}, [qr/Latest Posted/],
    qr/No comments have been posted/ );
check_headings(
    'comments/posted.tt',
    'posted comments',
    {
        %comment_vars,
        canedit  => 1,
        comments => [ { talkid => 1, subject => 'A posted comment', ju => $comment_vars{u} } ],
    },
    [qr/Latest Posted/],
    qr/A posted comment/
);

check_headings( 'latest/mood.tt', 'no mood data', { no_data => 1 }, [], qr/no current mood/ );
check_headings(
    'latest/mood.tt', 'one top mood',
    { top_mood => ['happy'], score => 60 },
    [ qr/^Current Moods?$/, qr/Emotional Weather/ ]
);
check_headings(
    'latest/mood.tt',
    'tied top moods',
    { top_mood => [ 'happy', 'bouncy' ], score => 60 },
    [ qr/Current Moods/, qr/Emotional Weather/ ]
);

my $entry = { subject => 'Queued entry', event => '<p>Entry body</p>' };
check_headings(
    'communities/queue/entries/edit.tt',
    'queued entry', { entry => $entry },
    [qr/Queued entry/]
);
check_headings(
    'communities/queue/entries/edit.tt',
    'validated poster, age restriction, and spam action',
    {
        entry =>
            { %$entry, poster => { is_validated => 1 }, age_restriction_reason => 'Sensitive' },
        can_report_spam => 1,
    },
    [qr/Queued entry/],
    qr/name=['"]action:spam/
);

my $remote = { user => 'tester', ljuser_display => 'Tester', journal_base => '/tester' };
check_headings( 'login.tt', 'signed out', {}, [ qr/Log in to/, qr/Not a .* member\?/ ] );
check_headings(
    'login.tt',
    'sign-in error',
    { errors => [ [ undef, 'Sign-in failed' ] ] },
    [ qr/Log in to/, qr/Not a .* member\?/ ],
    qr/Sign-in failed/
);
check_headings(
    'login.tt',
    'adding an account',
    { remote => $remote, add_account => 1 },
    [], qr/name=['"]switch/
);
check_headings(
    'login.tt',
    'signed in to a journal account',
    { remote => $remote },
    [ qr/Post to your Journal/, qr/View your Reading Page/, qr/Change login options/ ]
);
check_headings(
    'login.tt',
    'signed in to an identity with a return URL',
    { remote => { %$remote, is_identity => 1 }, continue_to => '/update' },
    [ qr/Continue to/, qr/View your Reading Page/, qr/Change login options/ ]
);

my $scope = '/settings/lostpass.tt';
check_headings(
    'success-page.tt',
    'without links',
    { scope => $scope },
    [], qr/A token to reset your password/
);
check_headings( 'success-page.tt', 'with links',
    { scope => $scope, links => [ { text_ml => 'success.next.header', url => '/login' } ] },
    [qr/Next steps:/], qr{href="/login"} );

done_testing;
