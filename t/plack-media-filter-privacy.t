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
use DW::Cache;
use LJ::Console;
use LJ::JSON;
use LJ::Protocol;
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

    # Mixed mask (bit 0 + custom filter) must survive a metadata-only save through Bulk Edit
    {
        my $mixed_form = $request->( GET $edit );
        is( $mixed_form->code, 200, 'bulk edit loads for an image with a mixed mask' );
        my ($auth) = $mixed_form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        my ($select_html) =
            $mixed_form->content =~ m{<select[^>]*name=["']security-$id["'][^>]*>(.*?)</select>}s;
        my ($selected_sec);
        if ( defined $select_html ) {
            if (   $select_html =~ m{<option[^>]*selected[^>]*value=["']([^"']+)["']}s
                || $select_html =~ m{<option[^>]*value=["']([^"']+)["'][^>]*selected}s )
            {
                $selected_sec = $1;
            }
        }
        my @checked_groups =
            $mixed_form->content =~ m{name="group-$id" value="([^"]+)"[^>]*checked}g;
        ok( defined $auth && defined $selected_sec, 'reads rendered mixed-mask security selector' );

        my $meta_save = $request->(
            POST $edit,
            Content => [
                lj_form_auth   => $auth,
                'action:edit'  => 1,
                "title-$id"    => 'Mixed mask title',
                "security-$id" => $selected_sec,
                map { ( "group-$id" => $_ ) } @checked_groups,
            ]
        );
        is( $meta_save->code, 200, 'metadata-only bulk edit succeeds on a mixed mask' );
        my $after_meta = $load->();
        is( $after_meta->prop('title'), 'Mixed mask title', 'metadata update is saved' );
        is( $after_meta->security,      'usemask',          'mixed mask security stays usemask' );
        is( $after_meta->allowmask, $mask | 1, 'metadata-only bulk save preserves the mixed mask' );

        my $to_access = $request->(
            POST $edit,
            Content => [
                lj_form_auth   => $auth,
                'action:edit'  => 1,
                "security-$id" => 'usemask',
            ]
        );
        is( $to_access->code,     200, 'explicitly switching to Access List succeeds' );
        is( $load->()->allowmask, 1,   'switching to Access List clears custom bits' );

        my $bad_keep = $request->(
            POST $edit,
            Content => [
                lj_form_auth   => $auth,
                'action:edit'  => 1,
                "security-$id" => 'keep',
            ]
        );
        is( $bad_keep->code, 400, 'keep security option is rejected for a non-mixed mask' );
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

    my $circle    = "$host/circle/" . $viewer->user . "/edit?$as_owner";
    my $filters   = "$host/manage/circle/editfilters?$as_owner";
    my $form_data = sub {
        my ($url)      = @_;
        my $form       = $request->( GET $url );
        my ($auth)     = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        my ($revision) = $form->content =~ /name=['"]group_revision['"][^>]*value=['"]([^'"]+)/;
        ok( $form->is_success && defined $auth, "loads membership form at $url" );
        return ( lj_form_auth => $auth, defined $revision ? ( group_revision => $revision ) : () );
    };
    my @old_circle  = $form_data->($circle);
    my @old_filters = $form_data->($filters);
    my $circle_bulk = "$host/manage/circle/edit?$as_owner";
    my @bulk_auth   = $form_data->($circle_bulk);
    my @membership  = (
        'editfriend_maskhi_' . $viewer->user => $mask >> 31,
        'editfriend_masklo_' . $viewer->user => 1
    );

    ok( $owner->add_edge( $viewer, watch => { nonotify => 1 } ), 'also watches the old member' );
    my $old_image = $load->();
    my $console   = sub {
        my ($command) = @_;
        local $LJ::T_NO_COMMAND_PRINT = 1;
        LJ::set_remote($owner);
        my $response = LJ::Console->run_commands_text($command);
        LJ::set_remote(undef);
        return $response;
    };
    $lock = $owner->lock_trust_groups;
    ok(
        !$owner->add_edge( $viewer, watch => { nonotify => 1 } ),
        'watch rewrite cannot overlap a filter mutation'
    );
    ok(
        !$owner->remove_edge( $viewer, watch => { nonotify => 1 } ),
        'remove-watch rewrite cannot overlap a filter mutation'
    );
    ok(
        !$owner->edit_trustmask( $viewer, remove => $filter ),
        'membership edit cannot overlap a filter mutation'
    );
    my $failed_deletion = $request->(
        POST $filters,
        Content => [
            @old_filters,
            mode                                 => 'save',
            "efg_delete_$filter"                 => 1,
            'editfriend_maskhi_' . $viewer->user => 0,
            'editfriend_masklo_' . $viewer->user => 1
        ]
    );
    ok( $failed_deletion->content !~ /Your access filters are now saved/i,
        'a contended deletion is not reported as saved' );
    ok( $owner->trust_groups( id => $filter, force_database => 1 ),
        'the contended filter remains' );
    my $failed_revoke = $request->(
        POST $circle_bulk,
        Content => [ @bulk_auth, 'editfriend_edit_' . $viewer->id . '_user' => 1 ]
    );
    is( $failed_revoke->code, 409, 'Bulk Manage Circle reports the contended revocation' );
    like( $console->( 'manage_circle del_access ' . $viewer->user ),
        qr/^error:/, 'the console reports the contended revocation' );

    foreach my $action (
        [ settrustgroups    => { $filter => { name => 'New name' } } ],
        [ deletetrustgroups => [$filter] ],
        [ add => [ { username => $viewer->user, groupmask => 1 } ] ],
        [ add => [ { username => $viewer->user, edge      => 0 } ] ]
        )
    {
        my $error = 0;
        LJ::Protocol::do_request( 'editcircle', { username => $owner->user, @$action },
            \$error, { noauth => 1 } );
        like( $error, qr/^5\d\d(?:$|:)/, "editcircle reports a contended $action->[0] mutation" );
    }
    ok(
        $owner->trustmask_from_primary($viewer) & $mask,
        'contended revocations leave membership unchanged'
    );
    ok( !$old_image->visible_to($viewer), 'custom image access fails closed on a contended read' );
    $lock->release;

    my $list_lock = LJ::locker()->trylock( 'get_wt_list:' . $owner->id, class => 'watchtrust' );
    ok( $list_lock, 'holds the list read lock without holding the owner lock' );
    my $failed_membership_save = $request->(
        POST $filters,
        Content => [
            @old_filters,
            mode                                 => 'save',
            'editfriend_maskhi_' . $viewer->user => 0,
            'editfriend_masklo_' . $viewer->user => 1
        ]
    );
    $list_lock->release if $list_lock;
    like(
        $failed_membership_save->content,
        qr/reload the page and try again/i,
        'Edit Access Filters reports an unavailable membership list'
    );
    unlike(
        $failed_membership_save->content,
        qr/Your access filters are now saved/i,
        'an unavailable membership list cannot produce a success message'
    );
    ok( $owner->trustmask_from_primary($viewer) & $mask,
        'a failed membership read leaves the existing membership unchanged' );

    ok( $owner->delete_trust_group( id => $filter ), 'deletes the old membership filter' );
    my $db = LJ::get_db_writer();
    $db->do(
        'UPDATE wt_edges SET groupmask = groupmask | ? WHERE from_userid = ? AND to_userid = ?',
        undef, $mask, $owner->id, $viewer->id );
    is( $owner->create_trust_group( id => $filter, groupname => 'Art exchange' ),
        $filter, 'allocates the same slot even when an orphaned edge bit exists' );
    my $new_member = temp_user();
    ok( $owner->add_edge( $new_member, trust => { mask => $mask, nonotify => 1 } ),
        'a different viewer joins only the replacement filter' );
    ok( !$old_image->visible_to($new_member),
        'an old image snapshot cannot grant access to a replacement filter member' );
    is( $api->( groups => [$filter] )->code, 200, 'a fresh image save selects the replacement' );
    ok( !$load->()->visible_to($viewer), 'allocation does not inherit orphaned membership' );
    $owner->edit_trustmask( $viewer, remove => $filter );

    my $key    = $owner->id . ':' . $viewer->id;
    my $memkey = [ $owner->id, "trustmask:$key" ];
    LJ::MemCache::set( $memkey, $mask | 1, 3600 );
    DW::Cache->request->set( 'trustmask', $key, $mask | 1 );
    ok( !$load->()->visible_to($viewer), 'image authorization ignores stale cached membership' );
    my $grant = 'manage_circle add_access ' . $viewer->user;
    like( $console->($grant), qr/Done\./, 'the console can grant ordinary access' );
    is( $owner->trustmask_from_primary($viewer),
        1, 'an ordinary console grant does not restore stale custom membership' );
    like( $console->("$grant 59"), qr/^error:/, 'the console rejects an unallocated filter slot' );
    is( $owner->trustmask_from_primary($viewer),
        1, 'invalid console selection does not write bits' );
    like( $console->("$grant $filter"), qr/Done\./, 'the console accepts an existing filter slot' );
    is( $owner->trustmask_from_primary($viewer),
        $mask | 1, 'an explicit console selection grants the current filter' );
    $owner->trustmask( $viewer, 1 );
    LJ::MemCache::delete($memkey);
    DW::Cache->request->remove( 'trustmask', $key );

    my $stale_circle = $request->(
        POST $circle, Content => [ @old_circle, 'action:accessfilters' => 1, "bit_$filter" => 1 ]
    );
    ok(
        $stale_circle->content =~ /reload.*try again/is,
        'Circle tells the owner to reload stale choices'
    );
    ok( !$load->()->visible_to($viewer), 'the stale Circle save cannot grant image access' );
    $owner->edit_trustmask( $viewer, remove => $filter );

    my $stale_filters =
        $request->( POST $filters, Content => [ @old_filters, mode => 'save', @membership ] );
    ok( $stale_filters->content =~ /reload.*try again/is, 'editfilters rejects stale choices' );
    ok( !$load->()->visible_to($viewer), 'the stale editfilters save cannot grant image access' );
    $owner->edit_trustmask( $viewer, remove => $filter );

    my @fresh_circle = $form_data->($circle);
    $request->(
        POST $circle, Content => [ @fresh_circle, 'action:accessfilters' => 1, "bit_$filter" => 1 ]
    );
    ok( $load->()->visible_to($viewer), 'a fresh explicit membership grant authorizes the image' );

    # Actual HTTP media delivery (full-size and resized variant): cache policy and revocation
    {
        my $outsider = temp_user();
        $owner->add_edge( $outsider, trust => { nonotify => 1 } );
        my $large_fixture = 'htdocs/img/styles/abstractia/northernlights.png';
        my $photo         = DW::Media->upload_media(
            user     => $owner,
            file     => $large_fixture,
            security => 'public',
        );
        ok( $photo, 'uploaded a photo larger than 200x200 for delivery tests' );
        my $thumb = DW::Media->new(
            user    => $owner,
            mediaid => $photo->id,
            width   => 200,
            height  => 200,
        );
        ok( $thumb && $thumb->versionid != $photo->id, 'generated a distinct 200x200 variant' );
        my $full_url  = $photo->full_url;
        my $thumb_url = $thumb->url;
        my $path_thumb_url =
            "$host/~" . $owner->user . '/file/200x200/' . $photo->displayid . '.' . $photo->ext;

        my $check_no_store = sub {
            my ( $res, $label ) = @_;
            my $cc = $res->header('Cache-Control') // '';
            like( $cc, qr/\bno-store\b/i,        "$label Cache-Control sets no-store" );
            like( $cc, qr/\bno-cache\b/i,        "$label Cache-Control sets no-cache" );
            like( $cc, qr/\bmust-revalidate\b/i, "$label Cache-Control sets must-revalidate" );
            is( $res->header('Expires'), '0', "$label sets Expires: 0" );
        };

        for my $case (
            [ 'full',           $full_url ],
            [ 'thumbnail',      $thumb_url ],
            [ 'path-thumbnail', $path_thumb_url ]
            )
        {
            my ( $kind, $url ) = @$case;
            my $pub = $request->( GET $url );
            is( $pub->code,                   200,         "public $kind delivery returns 200" );
            is( $pub->header('Content-Type'), 'image/png', "public $kind returns PNG content" );
            $check_no_store->( $pub, "public $kind" );
        }

        ok( $photo->set_security( security => 'usemask', allowmask => $mask ),
            'narrowed photo from public to custom filter' );

        for my $case (
            [ 'full',           $full_url ],
            [ 'thumbnail',      $thumb_url ],
            [ 'path-thumbnail', $path_thumb_url ]
            )
        {
            my ( $kind, $url ) = @$case;
            my $anon = $request->( GET $url );
            is( $anon->code, 403, "anonymous viewer denied $kind after narrowing" );
            $check_no_store->( $anon, "denied anonymous $kind" );

            my $other = $request->( GET "$url?as=" . $outsider->user );
            is( $other->code, 403, "non-member trusted viewer denied $kind" );

            my $allowed = $request->( GET "$url?as=" . $viewer->user );
            is( $allowed->code, 200, "entitled filter member receives $kind" );
            is( $allowed->header('Content-Type'), 'image/png', "entitled $kind returns PNG bytes" );
            $check_no_store->( $allowed, "authorized custom $kind" );
        }

        ok( $owner->edit_trustmask( $viewer, remove => $filter ),
            'revoked viewer from custom filter' );
        for my $case (
            [ 'full',           $full_url ],
            [ 'thumbnail',      $thumb_url ],
            [ 'path-thumbnail', $path_thumb_url ]
            )
        {
            my ( $kind, $url ) = @$case;
            my $revoked = $request->( GET "$url?as=" . $viewer->user );
            is( $revoked->code, 403, "revoked viewer is denied $kind" );
            $check_no_store->( $revoked, "revoked $kind" );
        }

        $photo->delete if $photo;
    }
};

$image->delete;
done_testing;
