#!/usr/bin/perl
#
# t/plack-customize-navigation.t
#
# Rendered customization filter navigation acceptance.
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

use HTML::Entities qw(decode_entities);
use HTTP::Request::Common;
use Plack::Test;
use Test::More;
use URI;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

plan skip_all => 'Customization integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

local $LJ::DEFAULT_STYLE = {
    core   => 'core2',
    layout => 'ciel/layout',
    theme  => 'ciel/indil',
};

my $app = do "$ENV{LJHOME}/app.psgi";
my $u   = temp_user();

test_psgi $app, sub {
    my $cb = shift;
    my $res =
        $cb->( GET '/customize/?as=' . $u->user . '&authas=' . $u->user . '&show=24&cat=all' );
    is( $res->code, 200, 'filter source renders' );

    my $body = $res->content;
    my @hrefs;
    while ( $body =~ m{<a\b([^>]*)href=['"]([^'"]+)['"]}g ) {
        my $uri = URI->new( decode_entities($2) );
        push @hrefs, $uri if $uri->path =~ m!\A/customize/?\z!;
    }
    ok( @hrefs, 'rendered page has customize filter links to check' );
    my @leaked = grep { my %query = $_->query_form; defined $query{as} } @hrefs;
    is_deeply( \@leaked, [],
        'no rendered customize filter link leaks the dev-only as= synthetic-auth param' );
};

done_testing;
