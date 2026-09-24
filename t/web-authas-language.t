#!/usr/bin/perl
# Native language coverage for LJ::make_authas_select.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use LJ::Web;

{

    package WebAuthasLanguage::User;
    sub new { bless { user => $_[1], list => $_[2] }, $_[0] }
    sub user            { $_[0]{user} }
    sub get_authas_list { @{ $_[0]{list} } }
}

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
        }
    );
}

sub native {
    my ( $tag, $calls ) = @_;
    LJ::Lang::set_request_context(
        lang   => 'fr',
        getter => sub {
            push @$calls, $_[1];
            return "$tag:$_[1]" . ( $_[3]{menu} || '' );
        }
    );
}

my $owner = WebAuthasLanguage::User->new( 'owner', [qw(owner community)] );
subtest 'native labels preserve Foundation and legacy authas output' => sub {
    my @calls;
    request();
    native( 'A', \@calls );
    my $foundation = LJ::make_authas_select( $owner, { authas => 'community', foundation => 1 } );
    like(
        $foundation,
        qr/A:web\.authas\.select\.label/,
        'Foundation label uses request-native full key'
    );
    like(
        $foundation,
        qr/value="community" selected=['"]selected['"]/,
        'Foundation selected community is unchanged'
    );
    like( $foundation, qr/A:web\.authas\.btn/,   'Foundation button uses request-native full key' );
    like( $foundation, qr/class='row collapse'/, 'Foundation wrapper remains unchanged' );
    is_deeply(
        \@calls,
        [qw(web.authas.btn web.authas.select.label)],
        'Foundation uses only the two migrated global labels'
    );

    @calls = ();
    request();
    native( 'B', \@calls );
    my $legacy = LJ::make_authas_select( $owner, { authas => 'owner' } );
    like( $legacy, qr/B:web\.authas\.btn/, 'sequential request uses B button translation' );
    like( $legacy, qr/B:web\.authas\.select/,
        'legacy select sentence uses its existing native label path' );
    like(
        $legacy,
        qr/value="owner" selected=['"]selected['"]/,
        'legacy selected value is unchanged'
    );
    unlike( $legacy, qr/A:web\.authas\.btn/, 'sequential request does not leak prior translation' );
};

subtest 'explicit options and no-choice paths preserve old HTML contracts' => sub {
    request();
    native( 'C', [] );
    my $explicit = LJ::make_authas_select(
        $owner,
        {
            authas     => 'community',
            label      => '<b>Custom label</b>',
            button     => 'Custom button',
            foundation => 1,
        }
    );
    like(
        $explicit,
        qr/<b>Custom label<\/b>/,
        'explicit label takes precedence without escaping changes'
    );
    like( $explicit, qr/value="Custom button"/, 'explicit button takes precedence' );

    my $selectonly = LJ::make_authas_select( $owner, { authas => 'community', selectonly => 1 } );
    like( $selectonly, qr/<select/, 'selectonly remains a bare select' );
    unlike( $selectonly, qr/(?:Custom|web\.authas|<input)/,
        'selectonly emits no labels or button' );

    my $alone = WebAuthasLanguage::User->new( 'owner', ['owner'] );
    like(
        LJ::make_authas_select( $alone, {} ),
        qr/\A<input type=['"]hidden['"] name="authas" value="owner" \/>\z/,
        'no-choice path remains hidden authas input'
    );
};

subtest 'no request retains language fallback' => sub {
    DW::Request->reset;
    LJ::Lang::set_request_context( lang => undef, getter => undef );
    my $html = LJ::make_authas_select( $owner, { authas => 'owner' } );
    like( $html, qr/<select/,
        'no-request helper remains renderable through default language fallback' );
    like( $html, qr/Work as/,        'no-request fallback renders the default authas label' );
    like( $html, qr/value="Switch"/, 'no-request fallback renders the default authas button' );
    unlike(
        $html,
        qr/\[missing string .*web\.authas\.(?:btn|select\.label)/,
        'no-request fallback has neither migrated-key missing-string banner'
    );
    unlike( $html, qr/(?:A|B|C):web\.authas/,
        'no-request helper does not retain request getter output' );

    my $foundation = LJ::make_authas_select( $owner, { authas => 'owner', foundation => 1 } );
    like(
        $foundation,
        qr/>Work as<\/label>/,
        'Foundation no-request fallback renders the migrated default label'
    );
    like( $foundation, qr/value="Switch"/,
        'Foundation no-request fallback renders the default button' );
    unlike(
        $foundation,
        qr/\[missing string .*web\.authas\.(?:btn|select\.label)/,
        'Foundation no-request fallback has no migrated-key missing-string banner'
    );
};

done_testing;
