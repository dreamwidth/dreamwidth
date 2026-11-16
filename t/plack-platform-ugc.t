# t/plack-platform-ugc.t
#
# Official support notices and FAQs keep their platform-authored link metadata.
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

use Test::More;
use HTTP::Request::Common;
use HTML::TokeParser;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Faq;
use LJ::Test qw( temp_user with_fake_memcache );

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $summary = 'https://example.test/faq-summary';
my $answer  = '<a href="https://example.test/faq-answer" rel="noreferrer">answer</a>';

sub fixture_faq {
    return LJ::Faq->new(
        faqid         => 2147483000,
        question      => 'Platform link regression',
        summary       => $summary,
        answer        => $answer,
        faqcat        => '',
        lastmoduserid => 0,
        sortorder     => 1,
        lastmodtime   => 'November 16, 2026',
        unixmodtime   => 1794787200,
        @_,
    );
}

sub platform_links {
    my ( $res, $name, $expected ) = @_;
    is( $res->code, 200, "$name renders" );
    my $html   = $res->content;
    my $parser = HTML::TokeParser->new( \$html );
    my %found;
    while ( my $token = $parser->get_tag('a') ) {
        my $a    = $token->[1];
        my $href = $a->{href} || '';
        next unless exists $expected->{$href};
        $found{$href}++;
        my %rel = map { lc($_) => 1 } split /[ \t\n\f\r]+/, $a->{rel} || '';
        ok( !$rel{ugc},                 "$name: official $href is not UGC" );
        ok( $rel{ $expected->{$href} }, "$name: existing rel token survives" )
            if $expected->{$href};
    }
    is_deeply(
        [ sort keys %found ],
        [ sort keys %$expected ],
        "$name: all expected destinations survive"
    );
}

with_fake_memcache {
    my $load_include = \&LJ::load_include;
    my $load_faq     = \&LJ::Faq::load;
    my $enabled      = \&LJ::is_enabled;

    # Supply deterministic content only: route, permissions, cleaner and templates stay real.
    no warnings 'redefine';
    local *LJ::load_include = sub {
        return '<a href="https://example.test/status" rel="nofollow">status</a>'
            . ' https://example.test/status-plain'
            if $_[0] eq 'support-currentproblems';
        return $load_include->(@_);
    };
    local *LJ::Faq::load = sub {
        return fixture_faq() if defined $_[1] && $_[1] == 2147483000;
        return $load_faq->(@_);
    };
    local *LJ::is_enabled = sub {
        return 1 if $_[0] eq 'faq_summaries';
        return $enabled->(@_);
    };

    test_psgi $app, sub {
        my $cb = shift;
        platform_links(
            $cb->( GET 'http://localhost/support/index?as=nobody_exists' ),
            'support notice',
            {
                'https://example.test/status'       => 'nofollow',
                'https://example.test/status-plain' => '',
            }
        );

        my %faq_links = (
            'https://example.test/faq-summary' => '',
            'https://example.test/faq-answer'  => 'noreferrer',
        );
        platform_links(
            $cb->( GET 'http://localhost/support/faqbrowse?faqid=2147483000&as=nobody_exists' ),
            'public FAQ', \%faq_links );

        my $u = temp_user();
        $u->grant_priv( 'faqadd', '*' );
        my $as   = 'as=' . $u->user;
        my $form = $cb->( GET "http://localhost/admin/faq/faqedit?$as" );
        is( $form->code, 200, 'authorized FAQ preview form renders' );
        my ($token) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        ok( $token, 'FAQ preview uses a signed CSRF token' );
        platform_links(
            $cb->(
                POST "http://localhost/admin/faq/faqedit?$as",
                Content => [
                    lj_form_auth     => $token,
                    'action:preview' => 1,
                    q                => 'Platform link regression',
                    s                => $summary,
                    a                => $answer,
                    faqcat           => '',
                    sortorder        => 1,
                ]
            ),
            'FAQ preview',
            \%faq_links
        );

        # The administration view escapes FAQ markup before cleaning it.
        local *LJ::Faq::load_all = sub {
            fixture_faq( answer => 'https://example.test/faq-answer' );
        };
        platform_links(
            $cb->( GET "http://localhost/admin/faq/readcat?$as" ),
            'FAQ administration',
            { 'https://example.test/faq-answer' => '' }
        );
        $u->revoke_priv( 'faqadd', '*' );
    };
};

done_testing();
