# t/tags-trustmask-count.t
#
# Regression test for #3646: rendering a tag-heavy journal for a logged-in,
# non-owner viewer must perform a bounded (constant) number of trustmask
# lookups, regardless of how many tags the journal has. The viewer's trust
# relationship to the journal is identical for every tag, so it is computed
# once (LJ::S2::tag_viewer_context) and passed into each TagDetail call, and
# _trustmask memoizes per-request as defense-in-depth.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 4;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );

my $owner  = temp_user();
my $viewer = temp_user();

# owner trusts viewer (mask bit 0 = the plain trust bit); this also flushes
# both the memcache and the per-request trustmask caches for the pair.
$owner->add_edge( $viewer, trust => { mask => 1, nonotify => 1 } );

# view the owner's journal as the (logged-in, non-owner) viewer
LJ::set_remote($viewer);

# count actual _trustmask invocations and the trustmask memcache gets they make
my $tm_calls = 0;
my $mc_gets  = 0;

my $orig_tm = \&DW::User::Edges::WatchTrust::Loader::_trustmask;
my $orig_mc = \&LJ::MemCache::get;

no warnings 'redefine';
local *DW::User::Edges::WatchTrust::Loader::_trustmask = sub {
    $tm_calls++;
    return $orig_tm->(@_);
};
local *LJ::MemCache::get = sub {
    my $key  = $_[0];
    my $name = ref $key eq 'ARRAY' ? $key->[1] : $key;
    $mc_gets++ if defined $name && $name =~ /^trustmask:/;
    return $orig_mc->(@_);
};
use warnings 'redefine';

# a journal with many tags
my $N = 200;
my %tags;
for my $i ( 1 .. $N ) {
    $tags{$i} = {
        name           => "tag$i",
        display        => 1,
        security_level => 'public',
        uses           => 3,
        security       => { public => 3, private => 0, protected => 0, groups => {} },
    };
}

# render the tag list the way the S2 page code does: compute the viewer
# relationship once, then build every TagDetail with it.
DW::RequestCache->clear_ns('trustmask');    # start from a clean per-request slate
my $viewer_ctx = LJ::S2::tag_viewer_context($owner);
my @list       = map { LJ::S2::TagDetail( $owner, $_, $tags{$_}, $viewer_ctx ) } sort keys %tags;

is( scalar @list, $N, "rendered all $N tags" );

# the count reflects the viewer's trust, so the fix must be behavior-preserving:
# public(3) + protected(0) + best group(0) == 3 for a trusted viewer.
is( $list[0]->{use_count}, 3, "use_count is correct for a trusted viewer" );

# the whole point of #3646: work is constant, not O(tags).
is( $tm_calls, 2, "_trustmask called a constant number of times (trusts + trustmask)" );
cmp_ok( $mc_gets, '<=', 1, "trustmask memcache gets bounded regardless of tag count" );
