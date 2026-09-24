#!/usr/bin/perl
# Native global-label coverage for LJ::Web::control_strip.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Test qw(temp_user);
use LJ::Lang;
use LJ::Web;

sub request {
    my ($view) = @_;
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    my $r = DW::Request->get(
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
        }
    );
    $r->note( view => $view ) if defined $view;
    return $r;
}

sub native {
    my ($tag) = @_;
    LJ::Lang::set_request_context( lang => 'fr', getter => sub { return "$tag:$_[1]" } );
}

sub render_strip {
    my ( $user, $remote, $tag ) = @_;
    request('entry');
    native($tag);
    my $captured;
    local *LJ::get_remote       = sub { $remote };
    local *LJ::Hooks::are_hooks = sub { 0 };
    local *LJ::Hooks::run_hook  = sub { return };
    local *DW::Template::template_string = sub {
        $captured = $_[2];
        return join "\n", @{ $_[2]{actionlinks} || [] }, $_[2]{userpic_html} || '';
    };
    my $out = LJ::control_strip( user => $user->user );
    return ( $out, $captured );
}
my $journal = temp_user();
$journal->update_self( { status => 'A' } );
subtest 'logged-out and sequential native labels reach actual control-strip output' => sub {
    my ( $a, $args_a ) = render_strip( $journal, undef, 'A' );
    like(
        $a,
        qr/A:web\.controlstrip\.links\.learnmore/,
        'logged-out control strip renders native learn-more label'
    );
    unlike( $a, qr/\$BML::ML/, 'logged-out output contains no global BML label literal' );
    my ($b) = render_strip( $journal, undef, 'B' );
    like( $b, qr/B:web\.controlstrip\.links\.learnmore/, 'sequential request uses B labels' );
    unlike( $b, qr/A:web\.controlstrip/, 'sequential request does not leak A labels' );
};
subtest 'personal remote output preserves native userpic labels and hooks' => sub {
    $journal->make_fake_login_session;
    my ( $out, $args ) = render_strip( $journal, $journal, 'P' );
    like(
        $out,
        qr/P:web\.controlstrip\.(?:userpic|nouserpic)\.(?:alt|title)/,
        'personal output includes native userpic accessibility label'
    );
    ok( $args->{actionlinks}, 'actual helper still supplies action links to its template' );
};
subtest 'community journal rendering retains native labels' => sub {
    my $community = temp_user();
    $community->update_self( { status => 'A', journaltype => 'C' } );
    $community->make_fake_login_session;
    my ( $out, $args ) = render_strip( $community, $community, 'C' );
    like(
        $args->{userpic_html},
        qr/C:web\.controlstrip\.(?:userpic|nouserpic)\.alt/,
        'community control strip receives its native userpic label'
    );
    like(
        $out,
        qr/C:web\.controlstrip\.links\.(?:recentcomments|manageentries)/,
        'community own-journal actions retain native full-key labels'
    );
};

subtest 'native substitutions retain the original control-strip variables and bytes' => sub {
    request('entry');
    my @calls;
    LJ::Lang::set_request_context(
        lang   => 'fr',
        getter => sub {
            my ( $lang, $code, $unused, $vars ) = @_;
            push @calls, [ $code, { %{ $vars || {} } } ];
            return "native:$code:"
                . ( $vars->{sitename} || $vars->{sitenameabbrev} || $vars->{user} || '' );
        }
    );
    local *LJ::get_remote       = sub { return undef };
    local *LJ::Hooks::are_hooks = sub { 0 };
    local *LJ::Hooks::run_hook  = sub { return };
    local *DW::Template::template_string =
        sub { return join '\n', @{ $_[2]{actionlinks} || [] }, $_[2]{statustext} || '' };
    my $out = LJ::control_strip( user => $journal->user );
    like(
        $out,
        qr/native:web\.controlstrip\.links\.create:/,
        'create-link native substitution is rendered into the existing action HTML'
    );
    ok(
        ( grep { $_->[0] eq 'web.controlstrip.links.create' && exists $_->[1]{sitename} } @calls ),
        'create-link preserves its sitename substitution'
    );
    ok( ( grep { $_->[0] eq 'web.controlstrip.status.personal' && exists $_->[1]{user} } @calls ),
        'status text preserves its user substitution' );
};

subtest 'actual control-strip TT preserves default labels and hook arguments' => sub {
    request('entry');
    LJ::Lang::set_request_context( lang => undef, getter => undef );
    my @hooks;
    local *LJ::get_remote       = sub { return undef };
    local *LJ::Hooks::are_hooks = sub { return $_[0] eq 'show_control_strip' };
    local *LJ::Hooks::run_hook  = sub {
        push @hooks, [@_];
        return 1 if $_[0] eq 'show_control_strip';
        return;
        return;
    };
    my $out = LJ::control_strip( user => $journal->user );
    like( $out, qr/<div id='lj_controlstrip'>/, 'actual control-strip TT renders its wrapper' );
    like( $out, qr/Learn More/, 'actual TT output contains the default migrated learn-more label' );
    {
        local *LJ::Hooks::run_hook = sub {
            return 1 if $_[0] eq 'show_control_strip';
            return q{<span id='hook-learn-more'>hook</span>}
                if $_[0] eq 'control_strip_learnmore_link';
            return;
        };
        my $hook_out = LJ::control_strip( user => $journal->user );
        like( $hook_out, qr/id='hook-learn-more'/, 'actual hook return is rendered unchanged' );
    }
    unlike(
        $out,
        qr/\[missing string .*web\.controlstrip\./,
        'actual TT output has no migrated-label missing-string banner'
    );
    ok( ( grep { $_->[0] eq 'control_strip_learnmore_link' && @$_ == 1 } @hooks ),
        'learn-more hook retains its no-argument contract' );
};

subtest 'default-language fallback does not retain request labels' => sub {
    request('entry');
    LJ::Lang::set_request_context( lang => undef, getter => undef );
    my $captured;
    local *LJ::get_remote                = sub { return undef };
    local *LJ::Hooks::are_hooks          = sub { 0 };
    local *LJ::Hooks::run_hook           = sub { return };
    local *DW::Template::template_string = sub { $captured = $_[2]; return 'background' };
    is( LJ::control_strip( user => $journal->user ),
        'background', 'control strip retains default-language fallback' );
    unlike( join( ' ', @{ $captured->{actionlinks} || [] } ),
        qr/[ABP]:web\.controlstrip/, 'default fallback does not retain request getter labels' );
};
done_testing;
