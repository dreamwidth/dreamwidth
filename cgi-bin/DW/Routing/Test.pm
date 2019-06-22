#!/usr/bin/perl
#
# DW::Routing::Test
#
# Testing class for DW::Routing core tests
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011-2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Routing::Test;
use strict;

require 'ljlib.pl';
use DW::Request::Standard;
use HTTP::Request;

use Test::Builder::Module;
our @ISA    = qw(Test::Builder::Module);
our @EXPORT = qw(
    begin_tests got_result expected_format
    handle_request handle_server_error handle_redirect handle_custom
    handler regex_handler
    okay is todo_skip skip plan
    $TODO

    ok is
);

my $CLASS = __PACKAGE__;

my $Test = $CLASS->builder;

my $caller = undef;

sub import_extra {
    my ( $self, $data ) = @_;

    my %args = @$data;

    $args{tests}++ if exists $args{tests};

    $DW::Routing::DONT_LOAD = 1 unless $args{load_table};

    @$data = %args;

    require DW::Routing;
    DW::Routing->import;
    $DW::Routing::T_TESTING_ERRORS = 1;
}

sub begin_tests {
    my $ct = scalar keys %DW::Routing::string_choices;

    $ct += scalar @$_ foreach values %DW::Routing::regex_choices;

    $Test->is_eq( $ct, 0, "routing table empty" );
}

my $expected_format = 'html';
my $result;

sub expected_format { $expected_format = $_[0]; }

sub got_result {
    $result = $_[0];
}

sub handle_request {
    my ( $name, $uri, $valid, $expected, %opts ) = @_;
    $CLASS->builder->subtest(
        $name,
        sub {
            DW::Request->reset;

            my $tb = $CLASS->builder;
            $tb->plan( tests => 3 );

            my $method = $opts{method} || 'GET';

            my $req = HTTP::Request->new( $method => "$uri" );
            my $r   = DW::Request::Standard->new($req);

            my $ret;
            my $fail = 0;
            subtest(
                "handler call",
                sub {
                    $ret = DW::Routing->call(%opts);
                    if ( $tb->current_test == 0 ) {
                        plan( tests => 1 );
                        ok( 1, "no tests to run" );
                    }
                    else {
                        $fail = !$tb->is_passing;
                    }
                }
            );

            if ($fail) {
                _skip("overall failure");
                _skip("overall failure");
                return 1;
            }

            if ( !$valid ) {
                ok( !defined $ret, "return value defined when invalid" );
                _skip("non-valid test");
                return 1;
            }

            my $expected_ret = $opts{expected_error} || $r->OK;
            is( $ret, $expected_ret, "wrong return" );
            if ( $ret != $r->OK ) {
                _skip("non-expected return");
                return 0;
            }
            is( $result, $expected, "handler set wrong value." );
        }
    );
}

sub handle_custom {
    my ( $uri, %test_opts ) = @_;
    $CLASS->builder->subtest(
        $test_opts{name} || $uri,
        sub {
            my $tb = $CLASS->builder;
            $tb->plan( tests => 1 );

            my $schema = $test_opts{schema} || "http";
            my $method = ( $test_opts{method} || "GET" );

            my $req = HTTP::Request->new( $method => "$schema://www.example.com$uri" );
            $req->header( Host => 'www.example.com' );
            DW::Request->reset;
            my $r = DW::Request::Standard->new($req);

            my $opts = DW::Routing->get_call_opts( %{ $test_opts{opts} || {} } );

            unless ($opts) {
                ok( 0, "opts exists" );
                _skip("opts is undef");
                return;
            }

            my $hash = $opts->call_opts;

            unless ( $hash && $hash->{sub} ) {
                ok( 0, "improper opts" );
                _skip("opts are improper");
                return;
            }

            if ( $test_opts{final} ) {
                my $rv = DW::Routing->call_hash($opts);

                $CLASS->builder->subtest(
                    "custom sub",
                    sub {
                        $test_opts{final}->( $r, $rv );
                    }
                );
            }
            else {
                _skip("no final sub");
            }
        }
    );
}

sub handle_redirect {
    my ( $uri, $expected ) = @_;
    $CLASS->builder->subtest(
        $uri,
        sub {
            my $tb = $CLASS->builder;
            $tb->plan( tests => 3 );

            my $req = HTTP::Request->new( GET => "http://www.example.com$uri" );
            $req->header( Host => 'www.example.com' );
            DW::Request->reset;
            my $r = DW::Request::Standard->new($req);

            my $opts = DW::Routing->get_call_opts();

            unless ($opts) {
                ok( 0, "opts exists" );
                _skip("opts is undef");
                return;
            }

            my $hash = $opts->call_opts;

            unless ( $hash && $hash->{sub} ) {
                ok( 0, "improper opts" );
                _skip("opts are improper");
                return;
            }

            is( $hash->{sub}, \&DW::Routing::_redirect_helper );

            # Safe to call!

            my $rv = DW::Routing->call_hash($opts);

            is( $rv, $r->REDIRECT );
            if ( substr( $expected, 0, 1 ) == '/' ) {
                is( $r->header_out('Location'), "$LJ::PROTOCOL://www.example.com$expected" );
            }
            else {
                is( $r->header_out('Location'), $expected );
            }

        }
    );
}

sub handle_server_error {
    my ( $name, $uri, $format, %opts ) = @_;
    $CLASS->builder->subtest(
        $name,
        sub {
            DW::Request->reset;

            my $tb = $CLASS->builder;
            $tb->plan( tests => 3 );

            my $method = $opts{method} || 'GET';

            my $req = HTTP::Request->new( $method => "$uri" );
            my $r   = DW::Request::Standard->new($req);

            my $ret;
            my $fail = 0;
            subtest(
                "handler call",
                sub {
                    eval { $ret = DW::Routing->call(%opts) };
                    if ( !defined $ret ) {
                        plan( tests => 1 );
                        ok( 0, "test did not run" );
                        $fail = 1;
                    }
                    elsif ( $tb->current_test == 0 ) {
                        plan( tests => 1 );
                        ok( 1, "no tests to run" );
                    }
                    else {
                        $fail = !$tb->is_passing;
                    }
                }
            );

            if ($fail) {
                _skip("overall failure");
                _skip("overall failure");
                return 1;
            }

            my $content_type = $r->content_type;
            is( $r->status, $r->HTTP_SERVER_ERROR, "wrong return" );
            is(
                $content_type,
                {
                    html => "text/html",
                    json => "application/json",
                }->{$format}
                    || "text/plain",
                "wrong returned content type for $format"
            );
        }
    );
}

sub handler {
    my $r = DW::Request->get;
    got_result( $_[0]->args );
    is( $_[0]->format, $expected_format, "format wrong!" );
    return $r->OK;
}

sub regex_handler {
    my $r = DW::Request->get;
    got_result( $_[0]->args->[1] );
    is( $_[0]->format,           $expected_format, "format wrong!" );
    is( $_[0]->subpatterns->[0], $_[0]->args->[0], "capture wrong!" );
    return $r->OK;
}

sub _skip { return $CLASS->builder->skip(@_); }

sub subtest { return $CLASS->builder->subtest(@_); }
sub plan    { return $CLASS->builder->plan(@_); }
sub ok      { return $CLASS->builder->ok(@_); }
sub is      { return $CLASS->builder->is_eq(@_); }

sub skip {
    my ( $why, $how_many ) = @_;
    my $tb = $CLASS->builder;

    $how_many = 1 unless defined $how_many;
    $tb->skip($why) for ( 1 .. $how_many );

    no warnings 'exiting';
    last SKIP;
}

sub todo_skip {
    my ( $why, $how_many ) = @_;
    my $tb = $CLASS->builder;

    $how_many = 1 unless defined $how_many;
    $tb->todo_skip($why) for ( 1 .. $how_many );

    no warnings 'exiting';
    last TODO;
}

1;
