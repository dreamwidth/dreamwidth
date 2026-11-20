# t/plack-media-filters.t
#
# Test image access filters through the Plack routes.
#
# Authors:
#      Dreamwidth contributors
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
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

{
    my $owner   = temp_user();
    my $first   = temp_user();
    my $second  = temp_user();
    my $outside = temp_user();
    $owner->add_edge( $_, trust => { nonotify => 1 } ) for ( $first, $second, $outside );
    my $low  = $owner->create_trust_group( groupname => 'First filter' );
    my $high = $owner->create_trust_group( id        => 60, groupname => 'Second filter' );
    $owner->edit_trustmask( $first,  add => $low );
    $owner->edit_trustmask( $second, add => $high );

    my $fixture = 'htdocs/img/videoplaceholder.png';
    my $image = DW::Media->upload_media( user => $owner, file => $fixture, security => 'private' );
    ok( $image, 'created a private image for editing' ) or BAIL_OUT('Fixture upload failed');
    my $id       = $image->displayid;
    my $load     = sub { DW::Media->new( user => $owner, mediaid => $image->id ) };
    my $host     = 'http://localhost';
    my $as_owner = 'as=' . $owner->user;
    my $edit     = "$host/file/edit?$as_owner";

    test_psgi $app, sub {
        my ($request) = @_;
        my $save = sub {
            my ( $choice, @extra ) = @_;
            my $form = $request->( GET $edit );
            my ($auth) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
            return $request->(
                POST $edit,
                Content => [
                    lj_form_auth   => $auth,
                    'action:edit'  => 1,
                    "security-$id" => $choice,
                    @extra,
                ]
            );
        };
        my $api = sub {
            my ( $who, %fields ) = @_;
            return $request->(
                POST "$host/api/v1/file/edit?as=" . $who->user,
                Content_Type => 'application/json',
                Content      => to_json( { $id => \%fields } )
            );
        };
        my $form = $request->( GET "$host/file/new?$as_owner" );
        ok(
            scalar( $form->content =~ /Second filter/i ),
            'upload offers the owner\'s custom filters'
        );

        my $upload = $request->(
            POST "$host/api/v1/file/new?$as_owner&initial_security=private",
            Content_Type => 'form-data',
            Content      => [ files => [ $fixture, 'test.png', Content_Type => 'image/png' ] ]
        );
        is( $upload->code, 200, 'upload accepts the staged image' );
        my $uploaded = eval { from_json( $upload->content )->{result}{id} };
        if ($uploaded) {
            my $staged = DW::Media->new( user => $owner, mediaid => $uploaded >> 8 );
            is( $staged->security, 'private', 'upload stays private until its security is saved' );
            $staged->delete;
        }

        my $response = $save->( 'custom', "group-$id" => $low, "group-$id" => $high );
        is( $response->code, 200, 'image management saves multiple custom filters' );
        my $saved = $load->();
        is( $saved->allowmask, ( 1 << $low ) | ( 1 << $high ), 'exact filter bits are saved' );
        ok( $saved->visible_to($first),    'first filter member can view the image' );
        ok( $saved->visible_to($second),   'high-bit filter member can view the image' );
        ok( !$saved->visible_to($outside), 'other access-list member cannot view the image' );
        ok( !$saved->visible_to(undef),    'anonymous viewer cannot view the image' );
        ok( $saved->visible_to($owner),    'owner can view the image' );

        $response = $api->( $owner, security => 'usemask', groups => [$high] );
        is( $response->code,      200,        'upload metadata route accepts a selected filter' );
        is( $load->()->allowmask, 1 << $high, 'upload metadata round-trips bit 60 exactly' );
        is( $api->( $owner, security => 'usemask', groups => [0] )->code,
            400, 'the access-list bit cannot be submitted as a custom filter' );
        is( $api->( $owner, security => 'usemask', groups => [$low], allowmask => 1 )->code,
            400, 'custom groups cannot be combined with a raw allowmask' );
        is( $api->( $owner, security => 'usemask', groups => [59] )->code,
            400, 'unowned filter is rejected' );
        is( $load->()->allowmask, 1 << $high, 'invalid upload metadata leaves security unchanged' );
        is( $api->( $outside, security => 'public' )->code,
            404, 'another account cannot edit the owner\'s image' );

        is( $save->( 'custom', "group-$id" => 59 )->code,
            400, 'bulk edit rejects an unknown filter' );
        is( $load->()->allowmask,    1 << $high, 'invalid bulk edit leaves security unchanged' );
        is( $save->('custom')->code, 200,        'an empty custom selection saves' );
        is( $load->()->allowmask, 0, 'an empty selection does not fall back to the access list' );
        ok( !$load->()->visible_to($outside), 'empty selection does not grant access' );

        is( $save->( 'usemask', "group-$id" => $high )->code, 200, 'access-list mode still saves' );
        is( $load->()->allowmask, 1, 'access-list mode ignores custom checkboxes' );
        ok( $load->()->visible_to($outside), 'access-list mode includes all trusted users' );

        $image->set_security( security => 'usemask', allowmask => ( 1 << $low ) | ( 1 << $high ) );
        ok( $owner->delete_trust_group( id => $high ), 'deleted a filter used by an image' );
        is( $load->()->allowmask, 1 << $low, 'deletion clears only the removed image filter bit' );
        $owner->create_trust_group( id => $high, groupname => 'Replacement filter' );
        $owner->edit_trustmask( $outside, add => $high );
        ok( !$load->()->visible_to($outside),
            'reusing a filter ID cannot grant access to old images' );
        ok( $load->()->visible_to($first), 'the remaining filter still grants access' );
    };
    $image->delete;
}

done_testing;
