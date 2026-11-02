#!/usr/bin/perl
#
# t/native-lang-request-context.t
#
# A nested scoped TT render restores the outer ml scope, including when the
# nested render throws.
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
use Test::More;
use File::Temp qw(tempdir);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use DW::Template;

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
LJ::Lang::set_request_scope('/outer/page.tt');
LJ::Lang::set_request_context( lang => 'en', getter => \&LJ::Lang::get_text );

is(
    DW::Template->template_string( "$name/outer.tt", {}, {} ),
    'outer:Outer|child:Child|Outer',
    'nested scoped TT include translates both scopes'
);
is(
    LJ::Lang::ml('.key'),
    '[missing string /outer/page.tt.key]',
    'outer scope is restored after nested render'
);
my $ok = eval { DW::Template->template_string( "$name/bad.tt", {}, {} ); 1 };
ok( !$ok, 'nested TT exception propagates' );
is(
    LJ::Lang::ml('.key'),
    '[missing string /outer/page.tt.key]',
    'outer scope is restored before nested exception propagates'
);

DW::Request->reset;
done_testing;
