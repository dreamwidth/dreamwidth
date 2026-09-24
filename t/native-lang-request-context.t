#!/usr/bin/perl
# Native LJ::Lang request-context coverage: scope save/restore across nested
# TT renders, the configured getter/substitutions path, the debug-language
# short circuit, nonweb callers, and DB/cache/fallback/source-autoload
# resolution. Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as
# Perl itself.
use strict;
use warnings;
use lib "$ENV{LJHOME}/cgi-bin";
use Test::More;
use File::Temp qw(tempdir);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use DW::Template;
use DW::Template::Filters;

sub request {
    my ( $scope, $query ) = @_;
    DW::Request->reset;
    open my $input, '<', \( my $body = '' ) or die $!;
    my $r = DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => $query || '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        },
    );
    $r->note( ml_scope => $scope ) if defined $scope;
    return $r;
}

subtest 'nested TT scope save/restore across normal and exception paths' => sub {
    my $dir = tempdir( 'lang-scope-XXXXXX', DIR => "$ENV{LJHOME}/views", CLEANUP => 1 );
    my ($name) = $dir =~ m{/([^/]+)$};
    my %files = (
        'outer.tt' =>
qq{outer:[% '.outer' | ml %]|[% dw.scoped_include( '$name/child.tt' ) %]|[% '.outer' | ml %]},
        'child.tt'      => q{child:[% '.child' | ml %]},
        'bad.tt'        => qq{[% dw.scoped_include( '$name/fail.tt' ) %]},
        'fail.tt'       => q{[% THROW error "scope failure" %]},
        'outer.tt.text' => ";; -*- coding: utf-8 -*-\n.outer=Outer\n",
        'child.tt.text' => ";; -*- coding: utf-8 -*-\n.child=Child\n",
    );
    while ( my ( $file, $contents ) = each %files ) {
        open my $fh, '>', "$dir/$file" or die $!;
        print {$fh} $contents;
        close $fh or die $!;
    }

    local $LJ::IS_DEV_SERVER = 1;

    # A native TT render nested inside an active outer request scope.
    request();
    LJ::Lang::set_request_scope('/legacy.bml');
    LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
    is(
        DW::Template->template_string( "$name/outer.tt", {}, {} ),
        'outer:Outer|child:Child|Outer',
        'nested scoped TT include translates both scopes through native LJ::Lang::ml'
    );
    is(
        LJ::Lang::ml('.key'),
        '[missing string /legacy.bml.key]',
        'outer scope is restored after nested modern template render'
    );
    my $ok = eval { DW::Template->template_string( "$name/bad.tt", {}, {} ); 1 };
    ok( !$ok, 'nested TT exception propagates' );
    is(
        LJ::Lang::ml('.key'),
        '[missing string /legacy.bml.key]',
        'outer scope is restored before nested exception propagates'
    );
    DW::Request->reset;

    request();
    LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
    is(
        DW::Template->template_string( "$name/outer.tt", {}, {} ),
        'outer:Outer|child:Child|Outer',
        'modern render also works without a prior scope'
    );
    ok(
        !defined DW::Request->get->note('ml_scope'),
        'successful modern render restores undef request scope'
    );
    $ok = eval { DW::Template->template_string( "$name/bad.tt", {}, {} ); 1 };
    ok( !$ok, 'modern template error propagates with no prior scope' );
    ok(
        !defined DW::Request->get->note('ml_scope'),
        'failed modern render restores undef request scope'
    );
    DW::Request->reset;
};

subtest 'web keys, scope, and substitutions use the configured getter' => sub {
    my @calls;
    request('/entry/form.tt');
    LJ::Lang::set_request_context(
        lang   => 'en',
        getter => sub { push @calls, [@_]; return join '|', @_[ 0, 1 ]; }
    );
    is(
        LJ::Lang::ml( '.draft.autosave', { time => 3 } ),
        'en|/entry/form.tt.draft.autosave',
        'relative key uses request scope'
    );
    is(
        LJ::Lang::ml( '/customize/index.bml.title', { name => 'x' } ),
        'en|/customize/index.bml.title',
        'full key stays full'
    );
    is_deeply( $calls[0][3], { time => 3 }, 'substitutions reach language getter unchanged' );
};

subtest 'debug language returns keys without invoking a getter' => sub {
    request('/entry/form.tt');
    LJ::Lang::set_request_context(
        lang   => 'debug',
        getter => sub { die 'debug must not translate' }
    );
    is( LJ::Lang::ml('.draft.autosave'), '.draft.autosave', 'debug preserves relative key' );
    is(
        LJ::Lang::ml('/entry/form.tt.draft.autosave'),
        '/entry/form.tt.draft.autosave',
        'debug preserves full key'
    );
    is( LJ::Lang::get_effective_lang(),
        $LJ::DEFAULT_LANG, 'debug context falls back for direct data lookups' );

    LJ::Lang::set_request_context( lang => 'not-a-language' );
    is( LJ::Lang::get_effective_lang(),
        $LJ::DEFAULT_LANG, 'invalid context language falls back for direct data lookups' );

    request( '/entry/form.tt', 'uselang=debug' );
    is( DW::Template::Filters::ml()->('.key'),
        '/entry/form.tt.key', 'TT filter resolves a scoped debug key before returning it' );
    is( LJ::Lang::ml('.key'), '.key', 'direct native debug lookup preserves its supplied key' );
};

subtest 'nonweb callers use default language and direct translation' => sub {
    DW::Request->reset;
    local $LJ::DEFAULT_LANG = 'zz';
    no warnings 'redefine';
    local *LJ::Lang::get_text = sub { return join ':', @_[ 0, 1 ]; };
    is( LJ::Lang::ml( 'worker.key', { ignored => 1 } ),
        'zz:worker.key', 'background caller defaults without any active request' );
};

subtest 'native request context handles DB, fallback, misses, and source autoload' => sub {
    my $general = LJ::Lang::get_dom('general');
    plan skip_all => 'ML general domain not loaded in test DB' unless $general;
    my $dmid   = $general->{dmid};
    my $prefix = 'zzz.lang_request.' . $$ . '.' . int( rand 1_000_000 );
    my @cleanup;
    my $flush = sub {
        my ($code) = @_;
        LJ::MemCache::delete( "ml.$_.$dmid." . lc $code ) for ( 'en', @LJ::LANGS );
    };
    my $fresh = sub {
        my ($code) = @_;
        push @cleanup, $code;
        eval { LJ::Lang::remove_text( $dmid, $code ); };
        $flush->($code);
        return $code;
    };
    my $child;
    my $en = LJ::Lang::get_lang('en');
    if ($en) {
        my $dbr = LJ::get_db_reader();
        ($child) = $dbr->selectrow_array(
            "SELECT lncode FROM ml_langs WHERE parentlnid = ? AND lncode <> 'en' LIMIT 1",
            undef, $en->{lnid} );
    }

    my $db_code          = $fresh->("$prefix.db");
    my $missing_code     = $fresh->("$prefix.missing");
    my $cached_miss_code = $fresh->("$prefix.cached-miss");
    my $source_dir    = tempdir( 'LANG-native-XXXXXX', DIR => "$ENV{LJHOME}/views", CLEANUP => 1 );
    my ($source_name) = $source_dir =~ m{/([^/]+)$};
    my $source_code   = $fresh->("/$source_name/autoload.tt.value");
    open my $source, '>', "$source_dir/autoload.tt.text" or die $!;
    print {$source} ";; -*- coding: utf-8 -*-\n.value=Source [[name]]\n";
    close $source or die $!;
    utime time - 10, time - 10, "$source_dir/autoload.tt.text" or die $!;

    eval {
        ok(
            LJ::Lang::set_text(
                $dmid, 'en', $db_code,
                'Database [[name]]',
                { childrenlatest => 1 }
            ),
            'isolated DB fixture is stored with child fallback'
        );
        request('/native.tt');
        LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
        local $LJ::IS_DEV_SERVER = 0;
        {
            local $LJ::NO_ML_CACHE = 1;
            is(
                LJ::Lang::ml( $db_code, { name => 'cold' } ),
                'Database cold',
                'cold DB lookup bypasses caches through native request context'
            );
            is( LJ::Lang::ml($missing_code),
                '', 'cold DB miss keeps production missing-string contract' );
        }
        $flush->($db_code);
        is(
            LJ::Lang::ml( $db_code, { name => 'warm' } ),
            'Database warm',
            'normal-cache warm DB lookup preserves substitutions through native context'
        );
        is( LJ::Lang::ml($missing_code),
            '', 'normal-cache warm DB miss keeps production missing-string contract' );
        is( LJ::Lang::ml($cached_miss_code),
            '', 'normal-cache miss is cached through native context' );
        ok( LJ::Lang::set_text( $dmid, 'en', $cached_miss_code, 'Now cached', {} ),
            'set_text updates isolated cached-miss fixture' );
        is( LJ::Lang::ml($cached_miss_code),
            'Now cached', 'set_text invalidates the native request cached miss' );
        DW::Request->reset;

    SKIP: {
            skip 'no child language available in isolated test DB', 1 unless $child;
            request('/native.tt');
            LJ::Lang::set_request_context( lang => $child, getter => \&LJ::Lang::get_text );
            is(
                LJ::Lang::ml( $db_code, { name => 'fallback' } ),
                'Database fallback',
                'child language uses childrenlatest DB fallback through native context'
            );
            DW::Request->reset;
        }

        request('/native.tt');
        LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );
        {
            local $LJ::IS_DEV_SERVER = 1;
            is( LJ::Lang::ml( $source_code, { name => 'dev' } ),
                'Source dev',
                'dev source lookup goes through native request context without DB persistence' );
        }
        {
            local $LJ::IS_DEV_SERVER = 0;
            is( LJ::Lang::ml( $source_code, { name => 'cold' } ),
                'Source cold',
                'production cold lookup auto-loads source through native request context' );
            is( LJ::Lang::ml( $source_code, { name => 'warm' } ),
                'Source warm',
                'production warm lookup uses the normalized source-autoload cache entry' );
        }
        DW::Request->reset;
        1;
    };
    my $error = $@;
    DW::Request->reset;
    eval { LJ::Lang::remove_text( $dmid, $_ ); $flush->($_); } for @cleanup;
    die $error if $error;
};

done_testing;
