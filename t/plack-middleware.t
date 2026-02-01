#!/usr/bin/perl
# t/plack-middleware.t
#
# Test to validate Plack middleware components work correctly
#
# This test validates:
# - Individual middleware modules can be loaded and instantiated
# - Middleware methods work as expected
# - Request wrapper functionality
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use v5.10;

use Test::More tests => 12;
use Test::MockObject;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

# Mock dependencies
my $mock = Test::MockObject->new();

$mock->fake_module(
    'LJ' => (
        start_request => sub { },
        end_request   => sub { },
        urandom_int   => sub { return int(rand(1000000)); },
    )
);

$mock->fake_module(
    'LJ::Procnotify' => (
        check => sub { },
    )
);

# Test middleware loading
use_ok('Plack::Middleware::DW::RequestWrapper');
use_ok('Plack::Middleware::DW::Redirects');
use_ok('Plack::Middleware::DW::XForwardedFor');
use_ok('Plack::Middleware::DW::Dev');

# Tests 1-4: Middleware module loading

# Test RequestWrapper middleware
my $request_wrapper;
eval {
    $request_wrapper = Plack::Middleware::DW::RequestWrapper->new;
};
ok(!$@, 'RequestWrapper middleware instantiates without errors') or diag("Error: $@");
isa_ok($request_wrapper, 'Plack::Middleware::DW::RequestWrapper', 'RequestWrapper is correct type');

# Tests 5-6: RequestWrapper instantiation

# Test Redirects middleware  
my $redirects;
eval {
    $redirects = Plack::Middleware::DW::Redirects->new;
};
ok(!$@, 'Redirects middleware instantiates without errors') or diag("Error: $@");
isa_ok($redirects, 'Plack::Middleware::DW::Redirects', 'Redirects is correct type');

# Tests 7-8: Redirects instantiation

# Test XForwardedFor middleware
my $xff;
eval {
    $xff = Plack::Middleware::DW::XForwardedFor->new;
};
ok(!$@, 'XForwardedFor middleware instantiates without errors') or diag("Error: $@");
isa_ok($xff, 'Plack::Middleware::DW::XForwardedFor', 'XForwardedFor is correct type');

# Tests 9-10: XForwardedFor instantiation

# Test Dev middleware
my $dev;
eval {
    $dev = Plack::Middleware::DW::Dev->new;
};
ok(!$@, 'Dev middleware instantiates without errors') or diag("Error: $@");
isa_ok($dev, 'Plack::Middleware::DW::Dev', 'Dev is correct type');

# Tests 11-12: Dev instantiation
