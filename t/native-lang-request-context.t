#!/usr/bin/perl
#
# t/native-lang-request-context.t
#
# Native LJ::Lang request-context coverage: scope save/restore across nested
# TT renders (including across a thrown exception), and the nonweb/background
# caller fallback.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
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

subtest 'nonweb callers use default language and direct translation' => sub {
    DW::Request->reset;
    local $LJ::DEFAULT_LANG = 'zz';
    no warnings 'redefine';
    local *LJ::Lang::get_text = sub { return join ':', @_[ 0, 1 ]; };
    is( LJ::Lang::ml( 'worker.key', { ignored => 1 } ),
        'zz:worker.key', 'background caller defaults without any active request' );
};

done_testing;
