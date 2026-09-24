#!/usr/bin/perl
# Regression coverage for native language lookups in S2 page constructors.
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
require LJ::S2::FriendsPage;
require LJ::S2::RecentPage;
require LJ::S2::DayPage;

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

    package NativeS2Language::Journal;
    sub new { my ( $class, %args ) = @_; return bless \%args, $class; }
    sub user                { $_[0]->{user} }
    sub journal_base        { return $_[0]->{journal_base} || '/journal' }
    sub should_block_robots { 0 }
    sub is_community        { $_[0]->{community} }
    sub prop                { return }
}

sub opts {
    return {
        getargs                   => {},
        header                    => {},
        headers                   => {},
        view                      => 'read',
        pathextra                 => '',
        ctx                       => {},
        vhost                     => '',
        handle_with_siteviews_ref => \( my $off = 0 ),
    };
}

sub with_constructor_stubs {
    my ( $page, $code ) = @_;
    no warnings 'redefine';
    local *LJ::S2::Page                = sub { return $page; };
    local *LJ::S2::Link                = sub { return ''; };
    local *LJ::S2::Image_std           = sub { return ''; };
    local *LJ::S2::tracking_popup_js   = sub { return (); };
    local *LJ::need_res                = sub { return; };
    local *LJ::robot_meta_tags         = sub { return ''; };
    local *LJ::Talk::init_s2journal_js = sub { return; };
    return $code->();
}

sub assert_labels {
    my ( $head, $prefix, $suffix ) = @_;
    $suffix ||= '';
    like(
        $head,
        qr/expanded = '${prefix}widget\.cuttag\.expanded${suffix}';/,
        'expanded label is emitted into page JS'
    );
    like(
        $head,
        qr/collapsed = '${prefix}widget\.cuttag\.collapsed${suffix}';/,
        'collapsed label is emitted into page JS'
    );
    like(
        $head,
        qr/collapseAll = '${prefix}widget\.cuttag\.collapseAll${suffix}';/,
        'collapse-all label is emitted into page JS'
    );
    like(
        $head,
        qr/expandAll = '${prefix}widget\.cuttag\.expandAll${suffix}';/,
        'expand-all label is emitted into page JS'
    );
}

subtest 'S2 constructors use request-native full keys and retain rendered label bytes' => sub {
    my @calls;
    request();
    LJ::Lang::set_request_context(
        lang   => 'fr',
        getter => sub {
            my ( $lang, $code ) = @_;
            push @calls, [ $lang, $code ];
            return "fr:$code";
        },
    );

    for my $method (qw(FriendsPage RecentPage)) {
        my $page    = { head_content => '' };
        my $journal = NativeS2Language::Journal->new(
            user                => 'journal',
            journal_base        => '/journal',
            friendspagetitle    => '',
            friendspagesubtitle => '',
        );
        my $ok = eval {
            with_constructor_stubs(
                $page,
                sub {
                    local *LJ::Talk::init_s2journal_shortcut_js = sub { die "stop-$method"; };
                    LJ::S2->can($method)->( $journal, undef, opts() );
                }
            );
            1;
        };
        like( $@, qr/stop-$method/, "$method reaches the post-label render boundary" );
        assert_labels( $page->{head_content}, 'fr:' );
    }

    my $day_page = { head_content => '' };
    my $day_journal =
        NativeS2Language::Journal->new( user => 'journal', journal_base => '/journal' );
    my $day_opts = opts();
    $day_opts->{getargs} = { year => 'invalid', month => 'invalid', day => 'invalid' };
    is(
        with_constructor_stubs(
            $day_page, sub { LJ::S2::DayPage( $day_journal, undef, $day_opts ) }
        ),
        undef,
        'DayPage returns through its existing invalid-date branch after building cut labels'
    );
    assert_labels( $day_page->{head_content}, 'fr:' );

    is_deeply(
        [ map { $_->[1] } @calls ],
        [ ( map { "widget.cuttag.$_" } qw(collapsed expanded collapseAll expandAll) ) x 3 ],
        'each real page constructor resolves the same four full global cut-label keys'
    );
    is_deeply(
        [ map { $_->[0] } @calls ],
        [ ('fr') x 12 ],
        'request language, rather than journal identity, controls S2 cut-label lookup'
    );
    DW::Request->reset;
};

subtest 'S2 page constructor retains nonweb fallback and existing escaped label output' => sub {
    DW::Request->reset;
    my $page    = { head_content => '' };
    my $journal = NativeS2Language::Journal->new( user => 'journal', journal_base => '/journal' );
    local *LJ::Lang::get_text = sub {
        my ( $lang, $code ) = @_;
        return "background:$lang:$code:&amp;";
    };
    my $day_opts = opts();
    $day_opts->{getargs} = { year => 'invalid', month => 'invalid', day => 'invalid' };
    with_constructor_stubs( $page, sub { LJ::S2::DayPage( $journal, undef, $day_opts ) } );
    assert_labels( $page->{head_content}, "background:$LJ::DEFAULT_LANG:", q{:&amp;} );
    like( $page->{head_content}, qr/&amp;/,
        'existing pre-escaped translation output is preserved in the rendered script' );
};

done_testing;
