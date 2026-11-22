# t/headings-support.t
#
# Check the heading outline rendered by Support templates.
#
# Authors:
#      Alex <saphid@users.noreply.github.com>
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use DW::Template;
use HTML::Parser;
use HTTP::Request;
use LJ::UniqCookie;

my @faqs = (
    { faqid => 42, question => 'How do I post?', display_answer => 1, answer => '<p>Post.</p>' },
    { faqid => 43, question => 'How do I edit?', display_answer => 1, answer => '<p>Edit.</p>' },
);

my @cases = (
    [ 'act', 'touched, already open', { state => 'touched', is_open => 1 }, 1, qr/Touched/ ],
    [ 'act', 'touched, reopened', { state => 'touched' },  1, qr/re-opened/ ],
    [ 'act', 'locked',            { state => 'locked' },   1, qr/been locked/ ],
    [ 'act', 'unlocked',          { state => 'unlocked' }, 1, qr/been unlocked/ ],
    [
        'act', 'closed with navigation', { state => 'closed_nav' }, 1,
        qr/href='see_request\?id=42'/
    ],
    [ 'act', 'closed without navigation', { state => 'closed_simple' }, 1, qr/request.*closed/i ],
    [ 'append_request', 'logged', { state => 'logged' }, 1, qr/has been recorded/ ],
    [
        'append_request', 'bounced',
        { state => 'bounced', addresslist => 'help@example.test' }, 1,
        qr{<p>[^<]*bounced to help\@example\.test}
    ],
    [ 'faqbrowse', 'category answers', { faqcatarg => 1, faqs => \@faqs }, 2, qr/How do I edit/ ],
    [
        'faqbrowse',
        'category summary',
        {
            faqcatarg => 1,
            faqs      => [
                {
                    %{ $faqs[0] },
                    display_answer  => 0,
                    display_summary => 1,
                    summary         => 'Posting overview'
                }
            ]
        },
        1,
        qr/Posting overview/
    ],
    [ 'faqbrowse', 'single answer', { faqidarg => 42, faqs => [ $faqs[0] ] }, 0, qr/<p>Post/ ],
    [ 'faqbrowse', 'not found', {}, 0, qr/doesn't exist/ ],
    [ 'help', 'open requests',   { heading => 'open' },   1, qr/Open Support Requests/ ],
    [ 'help', 'closed requests', { heading => 'closed' }, 1, qr/Recently Closed Support Requests/ ],
    [ 'help', 'replied to', { heading => 'youreplied' }, 1, qr/Requests you replied to/ ],
    [
        'history',
        'account results',
        { get_user => 1, reqs => [ { spid => 42, subject => 'Example request' } ] },
        2, qr/Example request/
    ],
    [
        'history',
        'full search by user ID',
        { get_userid => 1, noresults => 1, fullsearch => 1 },
        1, qr/No results found/
    ],
    [
        'history',
        'search by email',
        { get_email => 1, email => 'reader@example.test' },
        1, qr/Back to account results/
    ],
    [ 'history', 'search form only', { fullsearch => 1 }, 0, qr/Search for Requests/ ],
    [
        'index', 'support home', { f => [ { faqid => 42, q => 'How do I post?' } ] },
        4, qr/How do I post/
    ],
    [
        'submit',
        'signed-out form',
        { include_name => 1, include_email => 1 },
        0, qr/Your email address/
    ],
    [
        'submit',
        'fixed category form',
        { cat_type => 'fixed', catname => 'Example category' },
        0, qr/Example category/
    ],
    [
        'submit', 'submitted',
        { url => '/support/see_request?id=42' }, 1,
        qr/Your request has been filed/
    ],
);

for my $case (@cases) {
    my ( $page, $description, $vars, $body_count, $expected_content ) = @$case;
    subtest "$page: $description" => sub {
        LJ::start_request();
        my $request = DW::Request::Standard->new(
            HTTP::Request->new( GET => "http://example.test/support/$page" ) );
        $request->note( ml_lang => 'en' );
        LJ::UniqCookie->set_current_uniq('headingssupport');
        my %sections;
        my $body = DW::Template->template_string(
            "support/$page.tt",
            {
                page_title => 'Act on Request',
                title      => 'Frequently Asked Questions',
                spid       => 42,
                username   => 'example',
                %$vars
            },
            \%sections
        );

        ok( length $sections{title}, 'site-scheme title set' );
        like( $body, $expected_content, 'expected branch rendered' );

        my @levels;
        my %fragments;
        HTML::Parser->new(
            api_version => 3,
            start_h     => [
                sub {
                    my ( $tag, $attributes ) = @_;
                    push @levels, $1 if $tag =~ /^h([1-6])$/;
                    $fragments{ $attributes->{id} }++ if exists $attributes->{id};
                },
                'tagname, attr'
            ],
        )->parse("<h1>$sections{title}</h1>$body")->eof;

        is( scalar @levels, $body_count + 1, 'expected number of headings rendered' );
        is( scalar( grep { $_ == 1 } @levels ), 1, 'only the site-scheme title is h1' );
        my @skips = grep { $levels[$_] > $levels[ $_ - 1 ] + 1 } 1 .. $#levels;
        is( scalar @skips, 0, 'no skipped heading levels' )
            or diag( 'Outline: ' . join ' ', @levels );
        if ( $vars->{faqcatarg} ) {
            for my $faq ( @{ $vars->{faqs} } ) {
                my $id = "faq$faq->{faqid}";
                like( $body, qr/href=["']?#\Q$id\E["' >]/, "category lists #$id" );
                is( $fragments{$id}, 1, "fragment #$id has one target" );
            }
        }
    };
}

done_testing;
