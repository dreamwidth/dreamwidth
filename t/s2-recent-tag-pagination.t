# t/s2-recent-tag-pagination.t
#
# Test that tag pagination URLs survive S2 output cleaning.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test;
use LJ::S2;
use HTMLCleaner;
use HTML::Parser;
use URI;

my $u = temp_user();
$u->{_journalbase} = 'https://journal.example';
$u->t_post_fake_entry( subject => "Pagination entry $_" ) for 1 .. 3;

# Exercise RecentPage's real navigation builder and entry selection while
# keeping the surrounding S2 rendering and JavaScript setup out of this test.
no warnings 'redefine';
local *LJ::S2::Page                = sub { return { base_url => $_[0]->{_journalbase} }; };
local *LJ::S2::Image_std           = sub { return {}; };
local *LJ::S2::Entry_from_entryobj = sub { return {}; };
local *LJ::Talk::init_s2journal_js = sub { };
local *S2::get_property_value      = sub { return 2; };
use warnings 'redefine';

for my $tag (
    'about: book thoughts 2',
    'ABOUT: mixed case',
    'notes about: a topic',
    'javascript: reference',
    'vbscript: reference',
    'ordinary tag',
    )
{
    for my $skip ( 0, 2 ) {
        my $page = LJ::S2::RecentPage(
            $u, undef,
            {
                getargs => { tag => $tag, skip => $skip },
                tags    => [$tag],
            }
        );
        my $direction = $skip ? 'forward' : 'backward';
        my $url       = $page->{nav}->{ $direction . '_url' };
        my %query     = URI->new($url)->query_form;
        is( $query{tag},               $tag,          "$direction retains tag: $tag" );
        is( 0 + ( $query{skip} || 0 ), $skip ? 0 : 2, "$direction skip count: $tag" );

        my $cleaned = '';
        my $cleaner = HTMLCleaner->new( output => sub { $cleaned .= $_[0] } );
        $cleaner->parse( '<a href="' . LJ::ehtml($url) . '">page</a>' );
        $cleaner->eof;
        my $href;
        my $parser = HTML::Parser->new(
            api_version => 3,
            start_h     => [ sub { $href = $_[1]->{href} if $_[0] eq 'a'; }, 'tagname,attr' ],
        );
        $parser->parse($cleaned);
        $parser->eof;
        is( $href, $url, "$direction link survives output cleaning: $tag" );
    }
}
done_testing;
