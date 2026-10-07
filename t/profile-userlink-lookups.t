# t/profile-userlink-lookups.t
#
# Regression test for #3648 (Problem 1): the profile page highlights shared
# relationships for a logged-in viewer by rendering format_userlink once per
# listed user. That highlighting must NOT do a per-user trust/watch lookup
# (which resolved to _trustmask / check_rel and made big profiles ~8s); the
# viewer's circle is precomputed into lookup hashes in the controller and the
# template does an O(1) membership check. Here we render the real _blocks.tt
# listusers/format_userlink over N users and assert zero relationship lookups
# happen during the render, regardless of N, while the highlighting output is
# still correct.
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

use Test::More tests => 5;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );
use Template;

my $u      = temp_user();    # profile owner
my $remote = temp_user();    # logged-in viewer, not the owner

# a list of users displayed on the profile
my $N       = 20;
my @targets = map { temp_user() } 1 .. $N;

# the viewer's circle, precomputed the way the controller does: id => 1 hashes.
# targets[0] trusted, [1] watched, [2] both, the rest unrelated.
my %trusts  = ( $targets[0]->id => 1, $targets[2]->id => 1 );
my %watches = ( $targets[1]->id => 1, $targets[2]->id => 1 );

# count the per-user relationship lookups the render must NOT make
my $tm_calls = 0;
my $cr_calls = 0;
my $orig_tm  = \&DW::User::Edges::WatchTrust::Loader::_trustmask;
my $orig_cr  = \&LJ::check_rel;
no warnings 'redefine';
local *DW::User::Edges::WatchTrust::Loader::_trustmask = sub { $tm_calls++; return $orig_tm->(@_) };
local *LJ::check_rel                                   = sub { $cr_calls++; return $orig_cr->(@_) };
use warnings 'redefine';

my %vars = (
    remote           => $remote,
    u                => $u,
    users            => \@targets,
    remote_watches   => \%watches,
    remote_trusts    => \%trusts,
    remote_member_of => {},

    # the controller passes these subs in; stub the parts listusers touches
    linkify       => sub { my $l = $_[0]; return ref $l eq 'HASH' ? $l->{text} : $l },
    parse_openids => sub { return { sites => {}, shortnames => {} } },
);

my $tt = Template->new(
    { INCLUDE_PATH => join( ':', LJ::get_all_directories('views') ), RECURSION => 1 } )
    or die $Template::ERROR;

my $src =
    "[% PROCESS 'profile/_blocks.tt' -%]\n[%- PROCESS listusers users = users, openids = [] -%]";

# measure only the render; setup above may have touched these
$tm_calls = 0;
$cr_calls = 0;

my $out = '';
$tt->process( \$src, \%vars, \$out ) or die $tt->error;

is( $tm_calls, 0, "no _trustmask lookups while rendering $N user links" );
is( $cr_calls, 0, "no check_rel lookups while rendering $N user links" );

my $trusted_name = $targets[0]->display_name;
my $watched_name = $targets[1]->display_name;
my $neither_name = $targets[3]->display_name;

like( $out, qr{<strong>\Q$trusted_name\E</strong>}, "trusted user rendered bold" );
like( $out, qr{<em>\Q$watched_name\E</em>},         "watched user rendered italic" );
unlike( $out, qr{<(?:strong|em)>\Q$neither_name\E</}, "unrelated user left unstyled" );
