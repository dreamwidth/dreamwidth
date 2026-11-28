# t/headings-interests.t
#
# Heading outlines and fragment links on the Interests pages.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use HTML::Parser;
use HTTP::Request;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use DW::Template;

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'interestsHeadingTest';

sub check_headings {
    my ( $name, $template, $vars, $expected, $outline, $targets ) = @_;
    subtest $name => sub {
        local $DW::Request::cur_req;
        local $DW::Request::determined;
        DW::Request::Standard->new( HTTP::Request->new( GET => 'http://localhost/interests' ) );
        my $sections = {};
        my $body     = DW::Template->template_string( "interests/$template.tt", $vars, $sections );

        my ( @headings, @links, $current );
        my $parser = HTML::Parser->new( api_version => 3 );
        $parser->handler(
            start => sub {
                my ( $tag, $attr ) = @_;
                if ( $tag =~ /^h([1-6])$/ ) {
                    $current = { level => $1, text => '', id => $attr->{id} };
                    push @headings, $current;
                }
                push @links, $1 if $tag eq 'a' && ( $attr->{href} // '' ) =~ /^#(.+)$/;
            },
            'tagname, attr'
        );
        $parser->handler( text => sub { $current->{text} .= $_[0] if $current; }, 'dtext' );
        $parser->handler( end => sub { $current = undef if $_[0] =~ /^h[1-6]$/; }, 'tagname' );
        $parser->parse("<h1>$sections->{title}</h1>$body");
        $parser->eof;

        my @levels = map { $_->{level} } @headings;
        is( scalar( grep { $_ == 1 } @levels ), 1, 'only the site title is h1' );
        my @skips = grep { $levels[$_] > $levels[ $_ - 1 ] + 1 } 1 .. $#levels;
        is_deeply( \@skips, [], 'no skipped levels' ) or diag( 'Outline: ' . join ' > ', @levels );
        is_deeply( \@levels, $outline, 'headings have the expected hierarchy' );
        my $titles = join "\n", map { $_->{text} =~ s/^\s+|\s+$//gr } @headings;
        like( $titles, $expected, 'expected headings render in order' );

        if ($targets) {
            is_deeply( \@links, $targets, 'jump links match the available account types' );
            is_deeply( [ map { $_->{id} } grep { defined $_->{id} } @headings ],
                $targets, 'jump links point to the account headings' );
        }
    };
}

my $profile = { profile_url => '/profile', ljuser_display => 'reader' };
check_headings(
    'add confirmation',
    'add', { need_post => { int => 'books', intid => 1 } },
    qr/\AInterests\nConfirm\z/, [ 1, 2 ]
);
check_headings( 'add success', 'add', { remote => $profile }, qr/\AInterests\nAdded\b/, [ 1, 2 ] );

my @merge_results = qw(added both deleted del_and_toomany nothing toomany);
for my $result (@merge_results) {
    check_headings(
        "bulk update: $result",
        'enmasse_do',
        {
            u                 => $profile,
            fromu             => $result eq 'nothing' ? undef : $profile,
            enmasse_do_result => "interests.results.$result",
            toomany           => 2,
        },
        qr/\AInterests\nResults\z/,
        [ 1, 2 ]
    );
}

my @account_types = (
    [ 'P', 'personal',  'Personal' ],
    [ 'C', 'community', 'Community' ],
    [ 'I', 'identity',  'OpenID' ],
);
for my $mask ( 1 .. 7 ) {
    my @types   = @account_types[ grep { $mask & ( 1 << $_ ) } 0 .. $#account_types ];
    my @targets = map { $_->[1] } @types;
    my $groups  = join '', map { "$_->[2] Accounts\n" } @types;
    check_headings(
        'similar accounts: ' . join( ', ', @targets ),
        'findsim',
        {
            remote        => $mask == 1 ? undef : $profile,
            nocircle      => $mask == 7,
            circle_link   => '/interests?mode=findsim_do',
            findsim_u     => $profile,
            findsim_count => { map { $_->[0] => 1 } @types },
            findsim_data  => {
                map { $_->[0] => [ { count => 1, user => 'reader', magic => '12.000' } ] } @types
            },
        },
        qr/\AInterests\nSimilar Accounts\n\Q$groups\E[^\n]*Magic Index[^\n]*\z/,
        [ 1, 2, (3) x @types, 2 ],
        \@targets
    );
}

my %search = (
    interest       => 'books',
    query_count    => 1,
    type_list      => [ 'none', 'P' ],
    type_link      => sub { $_[0] eq 'none' ? undef : '/interests?int=books&type=P' },
    not_interested => [ { int => 'books', intid => 1 } ],
);
my $search_titles = qr/Interests\nSearch results for "books"/;
check_headings(
    'search with matches',
    'int',
    {
        %search,
        allcount     => 2,
        comm_count   => 1,
        warn_toolong => 'Interest truncated',
        data         => [
            { u => $profile },
            { u => $profile, updated => 'recently', desclabel => 'Description:', desc => 'Books' },
        ],
    },
    qr/\A$search_titles\n2 matches:/,
    [ 1, 2, 3 ]
);
check_headings(
    'filtered search without visible matches',
    'int',
    { %search, allcount => 2, filtered => 1, type_count => 0 },
    qr/\A$search_titles\n2 matches, showing 0 results:/,
    [ 1, 2, 3 ]
);
check_headings(
    'unfiltered search without visible matches',
    'int',
    { %search, allcount => 2, type_count => 0 },
    qr/\A$search_titles\n2 matches, showing 0 results:/,
    [ 1, 2, 3 ]
);
check_headings(
    'search with an unlisted interest',
    'int', { %search, no_users => 'books', no_users_count => 1 },
    qr/\A$search_titles\z/, [ 1, 2 ]
);
check_headings(
    'search without a joint match',
    'int', { %search, query_count => 2 },
    qr/\A$search_titles\z/, [ 1, 2 ]
);

done_testing;
