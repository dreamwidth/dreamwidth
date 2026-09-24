#!/usr/bin/perl
# Regression coverage for native language-name lookup without BML globals.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Hooks::PrivList;
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;

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

sub native_name_list {
    my @codes = @_;
    my @list;
    for my $code (@codes) {
        my $lang = LJ::Lang::get_lang($code) or next;
        push @list, $code, LJ::Lang::get_text( $lang->{lncode}, "langname.$code" );
    }
    return \@list;
}

ok( !defined &BML::ml, 'plain ljlib nonweb setup does not load BML::ml' );

{
    local @LJ::LANGS        = ('en_DW');
    local $LJ::DEFAULT_LANG = 'en';
    is_deeply(
        LJ::Lang::get_lang_names(),
        native_name_list('en_DW'),
        'configured LANGS order is used without adding DEFAULT_LANG'
    );
}

my @reordered          = qw(en en_DW not-a-language);
my $expected_reordered = native_name_list(@reordered);
is_deeply( LJ::Lang::get_lang_names(@reordered),
    $expected_reordered,
    'explicit reordered valid language codes use native names and skip unknown codes' );

for my $context (qw(first second)) {
    request();
    LJ::Lang::set_request_context(
        lang   => $context,
        getter => sub { die "request getter must not be used for language names" },
    );
    is_deeply( LJ::Lang::get_lang_names(@reordered),
        $expected_reordered,
        "$context request context cannot affect direct native language-name lookup" );
}

DW::Request->reset;
is_deeply( LJ::Lang::get_lang_names(@reordered),
    $expected_reordered,
    'nonweb language-name lookup remains native after sequential request contexts' );

{
    local @LJ::LANGS = qw(en_DW en);
    my $args = LJ::list_valid_args('translate');
    is(
        $args->{en_DW},
        'Can translate English',
        'PrivList renders the configured native en_DW language name'
    );
    is(
        $args->{en},
        'Can translate English',
        'PrivList renders the configured native en language name'
    );
    is(
        $args->{'[itemdelete]'},
        'Can delete translation strings',
        'PrivList retains the item-delete special translate argument'
    );
    is(
        $args->{'[itemrename]'},
        'Can rename translation strings',
        'PrivList retains the item-rename special translate argument'
    );
}

done_testing;
