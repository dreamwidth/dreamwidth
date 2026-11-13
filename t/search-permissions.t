# t/search-permissions.t
#
# Journal search settings and community search permissions.
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

use LJ::Test qw(temp_user temp_comm temp_feed);
use DW::Setting::AllowSearchBy;
use HTML::TokeParser;

my $journal  = temp_user();
my $comm     = temp_comm();
my $member   = temp_user();
my $admin    = temp_user();
my $outsider = temp_user();
my $feed     = temp_feed();
$member->join_community($comm);
LJ::set_rel( $comm, $admin, 'A' );
$journal->add_edge( $member, trust => { nonotify => 1 } );

# Account billing is the only substituted service. Relationships and settings
# below use real users, properties and membership storage.
my %paid = ( $member->id => 1, $admin->id => 1, $outsider->id => 1 );
no warnings 'redefine';
local *DW::Pay::get_account_type = sub { $paid{ $_[0]->id } ? 'paid' : 'free' };

my $setting = 'DW::Setting::AllowSearchBy';
my $field   = $setting->pkgkey . 'allowsearchby';

sub selected_value {
    my ( $u, $args ) = @_;
    my $html   = $setting->option( $u, undef, $args || {} );
    my $parser = HTML::TokeParser->new( \$html );
    while ( my $tag = $parser->get_tag('option') ) {
        return $tag->[1]->{value} if exists $tag->[1]->{selected};
    }
    return undef;
}

sub save_setting {
    my ( $u, $value ) = @_;
    LJ::Setting->save_all( $u, { $field => $value }, [$setting] );
}

subtest 'setting visibility, defaults and persistence' => sub {
    ok( $setting->should_render($journal), 'personal setting remains visible' );
    ok( $setting->should_render($comm),    'community setting is visible' );
    ok( !$setting->should_render($feed),   'feed setting stays hidden' );
    ok( !$setting->should_render(undef),   'anonymous setting stays hidden' );
    is( selected_value($journal), 'F', 'personal default stays access-only' );
    is( selected_value($comm),    'A', 'community default preserves unrestricted search' );
    for my $u ( $journal, $comm ) {
        for my $value (qw(A F N)) {
            save_setting( $u, $value );
            is( $u->prop('opt_allowsearchby'), $value, 'setting saves the shared property' );
            is( selected_value($u),            $value, 'saved option is selected' );
        }
        is( selected_value( $u, { allowsearchby => 'F' } ), 'F', 'posted selection wins' );
        save_setting( $u, 'invalid' );
        is( $u->prop('opt_allowsearchby'), 'N', 'invalid option does not change property' );
        LJ::Setting->save_all( $u, {}, [$setting] );
        is( $u->prop('opt_allowsearchby'), 'N', 'unrelated save preserves property' );
        $u->clear_prop('opt_allowsearchby');
    }
};

subtest 'community search follows the saved setting' => sub {
    ok( $comm->allow_search_by($outsider), 'unset property preserves community search' );
    for my $case ( [ A => 1, 1 ], [ F => 1, 0 ], [ N => 0, 0 ] ) {
        my ( $value, $member_allowed, $outsider_allowed ) = @$case;
        save_setting( $comm, $value );
        is( !!$comm->allow_search_by($member),   !!$member_allowed,   "$value: member access" );
        is( !!$comm->allow_search_by($outsider), !!$outsider_allowed, "$value: outsider access" );
        ok( $comm->allow_search_by($admin), "$value: administrator can search" );
        ok( !$comm->allow_search_by(undef), "$value: anonymous cannot search" );
        ok( !$comm->allow_search_by($feed), "$value: feed cannot search" );
    }
    is( $comm->prop('opt_blockglobalsearch'),
        undef, 'journal search does not alter site inclusion' );
    $paid{ $member->id } = 0;
    $paid{ $admin->id }  = 0;
    save_setting( $comm, 'A' );
    ok( !$comm->allow_search_by($member), 'free member and free community cannot search' );
    ok( !$comm->allow_search_by($admin),  'administrator still needs paid search' );
    $paid{ $comm->id } = 1;
    ok( $comm->allow_search_by($member), 'paid community permits a free member' );
    save_setting( $comm, 'F' );
    ok( !$comm->allow_search_by($outsider), 'paid community still enforces members-only' );
    $paid{ $outsider->id } = 0;
    save_setting( $comm, 'A' );
    ok( $comm->allow_search_by($outsider), 'paid community permits a free outsider when allowed' );
    $paid{ $member->id }   = 1;
    $paid{ $outsider->id } = 1;
};

subtest 'personal search behavior stays the same' => sub {
    $paid{ $journal->id } = 1;
    for my $case ( [ A => 1, 1 ], [ F => 1, 0 ], [ N => 0, 0 ] ) {
        my ( $value, $trusted_allowed, $outsider_allowed ) = @$case;
        save_setting( $journal, $value );
        is( !!$journal->allow_search_by($member),   !!$trusted_allowed,  "$value: trusted person" );
        is( !!$journal->allow_search_by($outsider), !!$outsider_allowed, "$value: outsider" );
        ok( $journal->allow_search_by($journal), "$value: owner can search" );
    }
    $journal->clear_prop('opt_allowsearchby');
    ok( $journal->allow_search_by($member),    'unset personal property allows trusted person' );
    ok( !$journal->allow_search_by($outsider), 'unset personal property excludes outsider' );
};

done_testing();
