# t/plack-media-filter-privacy.t
#
# Test image access when trust group bits are validated and reused.
#
# Authors:
#      Dreamwidth contributors
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Media;
use LJ::JSON;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

$LJ::CAP{$_}{media_file_quota} = 10 for keys %LJ::CAP;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'mediaFilterTest';

my $owner  = temp_user();
my $viewer = temp_user();
$owner->add_edge( $viewer, trust => { nonotify => 1 } );
my $filter   = $owner->create_trust_group( id => 60, groupname => 'Art exchange' );
my $mask     = 1 << $filter;
my $fixture  = 'htdocs/img/videoplaceholder.png';
my $image    = DW::Media->upload_media( user => $owner, file => $fixture, security => 'private' );
my $id       = $image->displayid;
my $load     = sub { DW::Media->new( user => $owner, mediaid => $image->id ) };
my $host     = 'http://localhost';
my $as_owner = 'as=' . $owner->user;
my $edit     = "$host/file/edit?$as_owner";

test_psgi $app, sub {
    my ($request) = @_;
    my $api = sub {
        return $request->(
            POST "$host/api/v1/file/edit?$as_owner",
            Content_Type => 'application/json',
            Content      => to_json( { $id => { security => 'usemask', @_ } } )
        );
    };
    my $render = sub {
        my ($form)  = @_;
        my ($auth)  = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        my ($group) = $form->content =~ /name="group-$id" value="([^"]+)"/;
        ok( defined $auth && defined $group, 'bulk edit renders the form and filter choice' );
        return ( $auth, $group );
    };
    my $bulk = sub {
        my ( $auth, $group ) = @_;
        return $request->(
            POST $edit,
            Content => [
                lj_form_auth   => $auth,
                'action:edit'  => 1,
                "security-$id" => 'custom',
                "group-$id"    => $group
            ]
        );
    };

    my $upload = $request->(
        POST "$host/api/v1/file/new?$as_owner&initial_security=private",
        Content_Type => 'form-data',
        Content      => [ files => [ $fixture, 'test.png', Content_Type => 'image/png' ] ]
    );
    is( $upload->code, 200, 'upload accepts the staged image' );
    my $uploaded = eval { from_json( $upload->content )->{result}{id} };
    ok( $uploaded, 'upload returns a staged image ID' );
    my $staged = $uploaded && DW::Media->new( user => $owner, mediaid => $uploaded >> 8 );
    is( $staged ? $staged->security : undef, 'private', 'staged image is private in storage' );
    $staged->delete if $staged;

    for my $bad_mask ( 1 << 59, $mask | ( 1 << 59 ), 1 << 61, '18446744073709551617' ) {
        is( $api->( allowmask => $bad_mask )->code, 400, "rejects raw mask $bad_mask" );
        my $stored = $load->();
        is_deeply(
            [ $stored->security, $stored->allowmask ],
            [ 'private',         0 ],
            'rejection leaves stored security unchanged'
        );
    }
    for my $valid_mask ( 1, $mask, $mask | 1 ) {
        is( $api->( allowmask => $valid_mask )->code, 200,         "accepts raw mask $valid_mask" );
        is( $load->()->allowmask,                     $valid_mask, 'stores the exact legacy mask' );
    }
    is( $api->( groups => [] )->code, 200, 'accepts an empty API selection' );
    is( $load->()->allowmask,         0,   'empty API selection stores no access bits' );
    ok( !$load->()->visible_to($viewer), 'empty API selection denies a trusted viewer' );

    my $old_form   = $request->( GET $edit );
    my @old_choice = $render->($old_form);
    my $lock       = LJ::locker()->trylock( 'trustgroup:' . $owner->id, class => 'trustgroup' );
    ok( $lock, 'holds the owner lock on a separate database connection' ) or return;
    is( $api->( groups => [$filter] )->code, 409, 'API save cannot bypass the owner lock' );
    is( $bulk->(@old_choice)->code,          409, 'bulk save cannot bypass the owner lock' );
    is( $load->()->allowmask, 0, 'contended saves do not change image visibility' );
    ok( !$owner->delete_trust_group( id => $filter ), 'delete cannot bypass the owner lock' );
    ok( !$owner->create_trust_group( id => 59, groupname => 'Contended filter' ),
        'allocation cannot bypass the owner lock' );
    $lock->release;

    $owner->delete_trust_group( id => 59 )      if $owner->trust_groups( id => 59 );
    $owner->delete_trust_group( id => $filter ) if $owner->trust_groups( id => $filter );
    is( $owner->create_trust_group( id => $filter, groupname => 'Art exchange' ),
        $filter, 'reuses the same number and name for a new filter' );
    $owner->edit_trustmask( $viewer, add => $filter );
    is( $bulk->(@old_choice)->code, 400, 'an old bulk form cannot select the replacement' );
    is( $api->( groups => [ $old_choice[1] ] )->code,
        400, 'an old upload form cannot select the replacement through the API' );
    ok( !$load->()->visible_to($viewer), 'stale saves do not expose the image to new members' );
    my @fresh_choice = $render->( $request->( GET $edit ) );
    is( $bulk->(@fresh_choice)->code, 200, 'a fresh form can select the replacement' );
    ok( $load->()->visible_to($viewer), 'the selected replacement grants access' );
};

$image->delete;
done_testing;
