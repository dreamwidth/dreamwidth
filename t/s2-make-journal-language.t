#!/usr/bin/perl
# Native language initialization boundary coverage for S2 journal rendering.
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
use LJ::S2;

{

    package S2MakeJournalLanguage::Journal;
    sub new { bless { user => 'journal' }, shift }
    sub user         { $_[0]{user} }
    sub journal_base { '/journal/' }
}

{

    package S2MakeJournalLanguage::Apache;
    sub new { bless { notes => {} }, shift }
    sub notes        { $_[0]{notes} }
    sub OK           { 200 }
    sub status       { }
    sub content_type { }
}

{

    package S2MakeJournalLanguage::PageStats;
    sub render_head { '' }
}

sub request {
    my ($scope) = @_;
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    DW::Request->get(
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
    LJ::Lang::set_request_context( scope => $scope ) if defined $scope;
}

sub opts {
    my ($apache) = @_;
    return {
        r                         => $apache,
        style_u                   => undef,
        getargs                   => {},
        headers                   => {},
        header                    => {},
        vhost                     => '',
        pathextra                 => '',
        handle_with_siteviews_ref => \( my $siteviews = 0 ),
    };
}

sub with_make_journal_stubs {
    my ( $labels, $code ) = @_;
    no warnings 'redefine';
    my $ctx = [];
    $ctx->[S2::SCRATCH] = {};
    $ctx->[S2::PROPS]   = { tags_aware => 1 };
    local *LJ::S2::s2_context                  = sub { return $ctx };
    local *LJ::S2::use_journalstyle_entry_page = sub { 1 };
    local *LJ::S2::use_journalstyle_icons_page = sub { 1 };
    local *LJ::S2::s2_run                      = sub { return 1 };
    local *LJ::S2::cleanup_layers              = sub { };
    local *LJ::BetaFeatures::user_in_beta      = sub { 1 };
    local *LJ::set_active_resource_group       = sub { };
    local *LJ::need_res                        = sub { };
    local *LJ::res_includes_head               = sub { '' };
    local *LJ::S2::get_script_tags             = sub { '' };
    local *LJ::PageStats::new = sub { bless {}, 'S2MakeJournalLanguage::PageStats' };
    my $constructor = sub {
        push @$labels, LJ::Lang::ml('.label');
        return { head_content => '', show_control_strip => 0 };
    };
    local *LJ::S2::RecentPage  = $constructor;
    local *LJ::S2::YearPage    = $constructor;
    local *LJ::S2::DayPage     = $constructor;
    local *LJ::S2::FriendsPage = $constructor;
    local *LJ::S2::MonthPage   = $constructor;
    local *LJ::S2::TagsPage    = $constructor;
    return $code->();
}

sub run_view {
    my ( $view, $labels ) = @_;
    my $apache = S2MakeJournalLanguage::Apache->new;
    return LJ::S2::make_journal( S2MakeJournalLanguage::Journal->new, 1, $view, undef,
        opts($apache), );
}

subtest 'make_journal initializes all ordinary views through native context only' => sub {
    my @labels;
    request('/s2/ordinary.tt');
    local $LJ::DEFAULT_LANG   = 'en';
    local *LJ::Lang::get_text = sub {
        my ( $lang, $code ) = @_;
        return "$lang:$code";
    };
    with_make_journal_stubs( \@labels,
        sub { run_view( $_, \@labels ) for qw(lastn archive day read month tag) } );
    is_deeply(
        \@labels,
        [ ('en:/s2/ordinary.tt.label') x 6 ],
'lastn, archive, day, read, month, and tag constructors receive default language, getter, and scope'
    );
    is( LJ::Lang::request_context->{scope},
        '/s2/ordinary.tt', 'make_journal preserves the caller translation scope' );
};

subtest 'sequential S2 requests replace language context without leaking scope or getter' => sub {
    my @first;
    request('/s2/first.tt');
    local $LJ::DEFAULT_LANG   = 'en';
    local *LJ::Lang::get_text = sub { return "first:$_[0]:$_[1]" };
    with_make_journal_stubs( \@first, sub { run_view( 'lastn', \@first ) } );

    my @second;
    request('/s2/second.tt');
    local *LJ::Lang::get_text = sub { return "second:$_[0]:$_[1]" };
    with_make_journal_stubs( \@second, sub { run_view( 'lastn', \@second ) } );

    is_deeply(
        \@first,
        ['first:en:/s2/first.tt.label'],
        'first request uses its own native context'
    );
    is_deeply(
        \@second,
        ['second:en:/s2/second.tt.label'],
        'second request does not retain first scope or getter'
    );
};

subtest 'no-request S2 rendering retains native default-language fallback' => sub {
    DW::Request->reset;
    my @labels;
    local $LJ::DEFAULT_LANG   = 'en';
    local *LJ::Lang::get_text = sub { return "fallback:$_[0]:$_[1]" };
    with_make_journal_stubs( \@labels, sub { run_view( 'lastn', \@labels ) } );
    is_deeply( \@labels, ['fallback:en:.label'],
        'without a request, S2 uses LJ::Lang native default fallback without BML callbacks' );
};

done_testing;
