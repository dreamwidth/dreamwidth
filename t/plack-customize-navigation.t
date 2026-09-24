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
use LJ::Test qw(temp_comm temp_user);

plan skip_all => 'Customization integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

local $LJ::DEFAULT_STYLE = {
    core   => 'core2',
    layout => 'ciel/layout',
    theme  => 'ciel/indil',
};

sub customize_actions {
    my ($body) = @_;
    my %action;

    while ( $body =~ m{<a\b([^>]*)href=['"]([^'"]+)['"]([^>]*)>}g ) {
        my ( $before, $raw_href, $after ) = ( $1, decode_entities($2), $3 );
        my $attrs = $before . $after;
        my $uri   = URI->new($raw_href);
        next unless $uri->path =~ m!\A/customize/?\z!;

        my %query = $uri->query_form;
        if ( $attrs =~ /\btheme-nav-cat\b/ && defined $query{cat} && $query{cat} ne 'all' ) {
            $action{category} //= [ $uri, \%query ];
        }
        elsif ( $attrs =~ /\btheme-designer\b/ && defined $query{designer} ) {
            $action{designer} //= [ $uri, \%query ];
        }
        elsif ( $attrs =~ /\btheme-layout\b/ && defined $query{layoutid} && $query{layoutid} ) {
            $action{layout} //= [ $uri, \%query ];
        }
    }

    return \%action;
}

sub result_metadata {
    my ( $body, $class, $attribute ) = @_;
    my @values;

    while ( $body =~ m{<a\b([^>]*)>}g ) {
        my $attrs = $1;
        next unless $attrs =~ /\bclass=['"][^'"]*\b\Q$class\E\b[^'"]*['"]/;
        next unless $attrs =~ /\b\Q$attribute\E=['"]([^'"]+)['"]/;
        push @values, decode_entities($1);
    }

    return @values;
}

sub selected_category {
    my ($body) = @_;
    while (
        $body =~ m{<li\b[^>]*class=['"][^'"]*\bon\b[^'"]*['"][^>]*>\s*
                    <a\b[^>]*href=['"]([^'"]+)['"][^>]*\btheme-nav-cat\b}gx
        )
    {
        my $uri = URI->new( decode_entities($1) );
        my %q   = $uri->query_form;
        return $q{cat} if defined $q{cat};
    }
    return;
}

my $app = do "$ENV{LJHOME}/app.psgi";
my $u   = temp_user();
my $c   = temp_comm();
LJ::set_rel( $c, $u, 'A' );

test_psgi $app, sub {
    my $cb = shift;

    for my $case (
        { label => 'personal',  target => $u, expect_authas => 0 },
        { label => 'community', target => $c, expect_authas => 1 },
        )
    {
        my $target = $case->{target};
        my $source = '/customize/?as=' . $u->user . '&authas=' . $target->user . '&show=24&cat=all';
        my $res    = $cb->( GET $source );
        is( $res->code, 200, "$case->{label} filter source renders" );

        my $actions = customize_actions( $res->content );
        for my $kind (qw(category designer layout)) {
            my $action = $actions->{$kind};
            ok( $action, "$case->{label} has a rendered $kind action" ) or next;

            my ( $uri, $query ) = @$action;
            is( $query->{show}, 24, "$case->{label} $kind href retains show=24" );
            if ( $case->{expect_authas} ) {
                is( $query->{authas}, $target->user,
                    "$case->{label} $kind href retains the community authas" );
            }
            else {
                ok(
                    !defined $query->{authas} || $query->{authas} eq $target->user,
                    "$case->{label} $kind href has no foreign authas"
                );
            }

            ok( !defined $query->{as},
                "$case->{label} $kind href does not synthesize dev authentication" );
            if ( $kind eq 'category' ) {
                ok( $query->{cat}, "$case->{label} category href has a concrete category" );
                isnt( $query->{cat}, 'all',
                    "$case->{label} category action differs from the source all filter" );
                ok(
                    !defined $query->{designer} && !defined $query->{layoutid},
                    "$case->{label} category action resets other filters"
                );
            }
            elsif ( $kind eq 'designer' ) {
                ok( length $query->{designer},
                    "$case->{label} designer href has a concrete designer" );
                ok(
                    !defined $query->{cat} && !defined $query->{layoutid},
                    "$case->{label} designer action resets other filters"
                );
            }
            else {
                ok( $query->{layoutid} =~ /\A[1-9]\d*\z/,
                    "$case->{label} layout href has a concrete layout id" );
                ok(
                    !defined $query->{cat} && !defined $query->{designer},
                    "$case->{label} layout action resets other filters"
                );
            }

            # The development-only actor is not part of a rendered link.  Add it only
            # to authenticate the follow-up request; do not repair authas or show.
            $uri->query_param_append( as => $u->user );
            $res = $cb->( GET $uri->as_string );
            is( $res->code, 200, "$case->{label} rendered $kind action follows" );

            my $body = $res->content;
            if ( $kind eq 'category' ) {
                is( selected_category($body),
                    $query->{cat}, "$case->{label} category result selects its rendered category" );
            }
            elsif ( $kind eq 'designer' ) {
                my @designers = result_metadata( $body, 'theme-designer', 'data-designer' );
                ok( @designers, "$case->{label} designer result has rendered themes" );
                is_deeply(
                    \@designers,
                    [ ( $query->{designer} ) x @designers ],
                    "$case->{label} designer result contains only its rendered designer"
                );
            }
            else {
                my @layouts = result_metadata( $body, 'theme-layout', 'data-layout' );
                ok( @layouts, "$case->{label} layout result has rendered themes" );
                is_deeply(
                    \@layouts,
                    [ ( $query->{layoutid} ) x @layouts ],
                    "$case->{label} layout result contains only its rendered layout"
                );
            }
        }
    }
};

done_testing;
