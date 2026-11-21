# t/shared-admin-posts.t
#
# Test authorization and attribution for shared official community posts.
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
use HTTP::Request;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use lib "$ENV{LJHOME}/t/lib";
use DW::API::Key;
use DW::Request::Standard;
use DW::Setting::SharedAdminPosts;
use DW::Test::API qw(api_request);
use LJ::Protocol;
use LJ::S2;
use LJ::Test qw(temp_user temp_comm);

my $community = temp_comm();
my $other     = temp_comm();
my $author    = temp_user();
my $editor    = temp_user();
my $third     = temp_user();
my $member    = temp_user();

$_->update_self( { status => 'A' } ) for ( $author, $editor, $third, $member );
$editor->update_self( { name => '<em>Display name is not attribution</em>' } );
LJ::set_rel( $community, $_, 'A' ) for ( $author, $editor, $third );
LJ::set_rel( $other, $author, 'A' );
$_->join_community( $community, 1, 1 ) for ( $author, $editor, $third, $member );
$author->join_community( $other, 1, 1 );

sub post_entry {
    my ( $journal, $poster, $body, $official ) = @_;
    my $error;
    my $result = LJ::Protocol::do_request(
        'postevent',
        {
            username   => $poster->user,
            usejournal => $journal->user,
            ver        => 1,
            tz         => 'guess',
            subject    => $body,
            event      => $body,
            security   => 'public',
            props      => { admin_post => $official },
        },
        \$error,
        { noauth => 1, u => $poster, usejournal_okay => 1 },
    );
    BAIL_OUT("Could not create fixture: $error") unless $result;
    return LJ::Entry->new( $journal, jitemid => $result->{itemid} );
}

sub edit_entry {
    my ( $entry, $actor, $body, %changes ) = @_;
    LJ::start_request() unless delete $changes{reuse_request};
    $actor = LJ::load_userid( $actor->id );
    my $error;
    my $result = LJ::Protocol::do_request(
        'editevent',
        {
            username   => $actor->user,
            usejournal => $entry->journal->user,
            ver        => 1,
            itemid     => $entry->jitemid,
            subject    => $body,
            event      => $body,
            %changes,
        },
        \$error,
        $changes{password} ? {} : { noauth => 1, u => $actor },
    );
    return $result ? 0 : ( $error || 'unknown error' );
}

sub entry_text {
    my ($old_entry) = @_;
    my $entry = reload_entry($old_entry);
    DW::Request->reset;
    my $request = DW::Request::Standard->new(
        HTTP::Request->new( GET => 'http://localhost/' . $entry->ditemid . '.html' ) );
    my $ctx = [];
    local $LJ::S2::CURR_CTX = $ctx;
    my ( undef, $s2entry ) = LJ::S2::EntryPage_entry( $entry->journal, undef,
        { getargs => {}, ctx => $ctx, r => $request, ljentry => $entry } );
    DW::Request->reset;
    return $s2entry ? $s2entry->{text} : '';
}

sub reload_entry {
    my ($entry) = @_;
    LJ::Entry->reset_singletons;
    return LJ::Entry->new( $entry->journal, jitemid => $entry->jitemid );
}

sub community_embed_count {
    return LJ::get_cluster_master($community)
        ->selectrow_array( 'SELECT COUNT(*) FROM embedcontent WHERE userid=?',
        undef, $community->id );
}

my $official = post_entry( $community, $author, 'Official announcement',          1 );
my $ordinary = post_entry( $community, $author, 'Ordinary entry',                 0 );
my $external = post_entry( $other,     $author, 'Another community announcement', 1 );
my $forged   = post_entry( $community, $member, 'Member entry',                   1 );
my $msg      = qr/Community admins who also edited this post:/i;

is( $forged->prop('admin_post') || 0, 0, 'a regular member cannot persist the official flag' );
is( edit_entry( $official, $editor, 'Disabled edit' ), 303, 'disabled by default' );
unlike( entry_text($official), $msg, 'no notice before a shared edit' );

my $setting = LJ::get_prop( 'user', 'shared_admin_posts' );
ok( $setting, 'shared admin posts setting is registered' );
ok( LJ::get_prop( 'log', 'admin_post_editor' ), 'editor history property is registered' );
$community->set_prop( shared_admin_posts => 1 ) if $setting;
$other->set_prop( shared_admin_posts => 1 )     if $setting;

is( edit_entry( $ordinary, $editor, 'Not official', props => { admin_post => 1 } ),
    303, 'cannot grant yourself permission by flagging an ordinary entry' );
is( edit_entry( $official, $member, 'Member edit' ), 303, 'membership does not grant edits' );
is( edit_entry( $official, $member, 'Member edit', security => 'private' ),
    106, 'a member cannot make another author’s entry private' );
is( edit_entry( $external, $editor, 'Cross-community edit' ),
    303, 'admin rights in one community do not grant edits in another' );
is( edit_entry( $forged, $editor, 'Forged flag' ), 303, 'a member cannot create an official post' );
is( edit_entry( $official, $member, '' ), 304, 'a member cannot delete an official post' );

$editor->update_self( { statusvis => 'S' } );
is( edit_entry( $official, $editor, 'Suspended editor' ), 305, 'suspended admins cannot edit' );
$editor->update_self( { statusvis => 'V' } );

$editor->set_password('shared-post-test-password');
$editor->update_self( { statusvis => 'D' } );
LJ::start_request();
$editor = LJ::load_userid( $editor->id );
ok( $editor->can_manage($community),   'deleted editor still has the admin relationship' );
ok( !$official->editable_by($editor),  'deleted admin cannot open the shared edit form' );
ok( !$official->deletable_by($editor), 'deleted admin cannot open the moderation form' );
ok( !LJ::Tags::can_add_entry_tags( $editor, $official ), 'deleted admin cannot edit entry tags' );
{
    local $LJ::CACHED_REMOTE = 1;
    local $LJ::CACHE_REMOTE  = $editor;
    ok(
        !DW::Setting::SharedAdminPosts->should_render($community),
        'deleted admin cannot manage the shared editing setting'
    );
}
is( edit_entry( $official, $editor, 'Deleted editor', password => 'shared-post-test-password' ),
    305, 'authenticated deleted admin cannot edit' );
my $app      = do "$ENV{LJHOME}/app.psgi" or die $@;
my $app_test = Plack::Test->create($app);
{
    my %edit = (
        username   => $editor->user,
        password   => 'shared-post-test-password',
        ver        => 1,
        usejournal => $community->user,
        itemid     => $official->jitemid,
        event      => 'Deleted editor over XML-RPC',
        subject    => 'Official announcement',
    );
    my $members = join '', map {
              "<member><name>$_</name><value><string>"
            . LJ::exml( $edit{$_} )
            . '</string></value></member>'
    } sort keys %edit;
    my $request = HTTP::Request->new(
        POST => 'http://www.dw.test/interface/xmlrpc',
        [ 'Content-Type' => 'text/xml' ],
        '<?xml version="1.0"?><methodCall><methodName>LJ.XMLRPC.editevent</methodName>'
            . "<params><param><value><struct>$members</struct></value></param></params></methodCall>"
    );
    my $response = $app_test->request($request);
    like(
        $response->content,
        qr{<name>faultCode</name>\s*<value><(?:int|i4|string)>305</},
        'XML-RPC rejects a deleted admin using valid credentials'
    );
}
$editor->update_self( { statusvis => 'V' } );
is( edit_entry( $official, $editor, 'Active editor', password => 'shared-post-test-password' ),
    0, 'the same protocol credentials work for an active admin' );
$editor = LJ::load_userid( $editor->id );
{
    my $path = '/journals/' . $community->user . '/entries/' . $official->ditemid;
    my ($response) = api_request(
        POST => $path,
        key  => DW::API::Key->new_for_user($editor)->hash,
        json => { text => 'Second admin edited over REST' }
    );
    is( $response->code, 200, 'active community admin can edit via authenticated REST' );
    is(
        reload_entry($official)->event_raw,
        'Second admin edited over REST',
        'REST saves the new content'
    );
    is( reload_entry($official)->posterid, $author->id, 'REST preserves the original author' );

    my $entries         = '/journals/' . $community->user . '/entries/';
    my $key             = DW::API::Key->new_for_user($editor)->hash;
    my $missing         = ( $official->jitemid + 1000 ) * 256;
    my $wrong_anum      = $official->jitemid * 256 + ( $official->anum + 1 ) % 256;
    my $removed         = post_entry( $community, $author, 'Removed entry fixture', 1 );
    my $removed_ditemid = $removed->ditemid;
    is( edit_entry( $removed, $author, '' ), 0, 'author deletes the REST fixture' );
    for my $target (
        [ $missing,         'missing entry' ],
        [ $wrong_anum,      'wrong anum' ],
        [ $removed_ditemid, 'deleted entry' ]
        )
    {
        my ($response) = api_request(
            POST => $entries . $target->[0],
            key  => $key,
            json => { text => 'Unmatched edit' }
        );
        is( $response->code, 404, "REST POST returns 404 for $target->[1]" );
    }
}

{
    no warnings 'redefine';
    my $partial      = post_entry( $community, $author, 'Original REST content', 1 );
    my $path         = '/journals/' . $community->user . '/entries/' . $partial->ditemid;
    my $trylock      = \&DW::Locker::trylock;
    my $entry_lock   = 'official-entry:' . $community->id . ':' . $partial->jitemid;
    my $author_saved = 0;
    local *DW::Locker::trylock = sub {
        if ( $_[1] eq $entry_lock && !$author_saved++ ) {
            is(
                edit_entry(
                    $partial, $author, 'Author changed the body',
                    subject       => 'Author changed the subject',
                    props         => { taglist => 'author correction' },
                    reuse_request => 1
                ),
                0,
                'author saves subject, body and tags before the REST edit takes the lock'
            );
        }
        return $trylock->(@_);
    };
    my ($response) = api_request(
        POST => $path,
        key  => DW::API::Key->new_for_user($editor)->hash,
        json => { datetime => '2020-01-02 03:04' }
    );
    is( $response->code, 200, 'date-only REST edit succeeds' );
    my $saved = reload_entry($partial);
    like( $saved->eventtime_mysql, qr/^2020-01-02 03:04/, 'REST saves the requested date' );
    is( $saved->subject_raw, 'Author changed the subject', 'REST preserves the newer subject' );
    is( $saved->event_raw,   'Author changed the body',    'REST preserves the newer body' );
    is_deeply( [ $saved->tags ], ['author correction'], 'REST preserves the newer tags' );
}

{
    my $personal = temp_user();
    $personal->update_self( { status => 'A', oldenc => 1 } );
    my $key     = DW::API::Key->new_for_user($personal)->hash;
    my %visible = ( subject => "Caf\xc3\xa9", text => "Cr\xc3\xa8me" );
    for my $field (qw(subject text)) {
        my $entry  = post_entry( $personal, $personal, "Legacy $field fixture", 0 );
        my $itemid = $entry->jitemid;
        LJ::get_cluster_master($personal)
            ->do( 'UPDATE logtext2 SET subject = ?, event = ? WHERE journalid = ? AND jitemid = ?',
            undef, "Caf\xe9", "Cr\xe8me", $personal->id, $itemid )
            or BAIL_OUT('Could not store legacy fixture text');
        $entry->set_prop( unknown8bit => 1 );
        LJ::MemCache::delete(
            [ $personal->id, join( ':', 'logtext', $personal->clusterid, $personal->id, $itemid ) ]
        );
        my $path   = '/journals/' . $personal->user . '/entries/' . $entry->ditemid;
        my $before = reload_entry($entry);
        is( $before->subject_raw, $visible{subject}, 'legacy subject decodes before editing' );
        is( $before->event_raw,   $visible{text},    'legacy body decodes before editing' );

        my ($response) = api_request(
            POST => $path,
            key  => $key,
            json => { datetime => '2020-01-02 03:04' }
        );
        is( $response->code, 200, 'date-only edit succeeds for legacy entry' );
        my $saved = reload_entry($entry);
        ok( $saved->prop('unknown8bit'), 'date-only edit preserves the legacy encoding marker' );
        is( $saved->subject_raw, $visible{subject}, 'date-only edit preserves the legacy subject' );
        is( $saved->event_raw,   $visible{text},    'date-only edit preserves the legacy body' );

        $saved->set_prop( unknown8bit => 1 );
        ($response) = api_request( POST => $path, key => $key, json => { $field => 'New text' } );
        is( $response->code, 200, "a legacy entry accepts a $field-only edit" );
        $saved = reload_entry($entry);
        ok( !$saved->prop('unknown8bit'), 'a content edit clears the legacy encoding marker' );
        is(
            $saved->subject_raw,
            $field eq 'subject' ? 'New text' : $visible{subject},
            "a $field-only edit saves the expected subject"
        );
        is(
            $saved->event_raw,
            $field eq 'text' ? 'New text' : $visible{text},
            "a $field-only edit saves the expected body"
        );
    }
}

{
    my $entry      = post_entry( $community, $author, 'Keep this official entry', 1 );
    my $path       = '/journals/' . $community->user . '/entries/' . $entry->ditemid;
    my ($response) = api_request(
        POST => $path,
        key  => DW::API::Key->new_for_user($editor)->hash,
        json => { text => " \t\n" }
    );
    is( $response->code, 400, 'authenticated shared REST edit rejects a whitespace-only body' );
    my $saved = reload_entry($entry);
    ok( $saved->valid, 'the whitespace-only update does not delete the entry' );
    is( $saved->event_raw, 'Keep this official entry', 'the saved body is unchanged' );
}

{
    my $moderated = post_entry( $community, $author, 'Read-only moderation fixture', 1 );
    $editor->update_self( { statusvis => 'O' } );
    LJ::start_request();
    $editor = LJ::load_userid( $editor->id );
    ok( !reload_entry($moderated)->editable_by($editor),
        'read-only admin cannot open shared edit' );
    ok( reload_entry($moderated)->deletable_by($editor), 'read-only admin can open moderation' );
    is( edit_entry( $moderated, $editor, 'Read-only save' ),
        318, 'read-only admin cannot save content' );
    is( edit_entry( $moderated, $editor, '' ),
        0, 'read-only admin can delete another admin’s post' );
    ok( !reload_entry($moderated)->valid, 'read-only admin’s deletion removes the entry' );
    $editor->update_self( { statusvis => 'V' } );
}

$author->update_self( { statusvis => 'S' } );
is( edit_entry( $official, $editor, 'Suspended author' ),
    303, 'cannot edit a suspended author’s post' );
$author->update_self( { statusvis => 'V' } );

LJ::clear_rel( $community, $author, 'A' );
is( edit_entry( $official, $editor, 'Former admin author' ),
    303, 'removing the author’s admin role revokes sharing' );
LJ::set_rel( $community, $author, 'A' );

$official->set_prop( statusvis => 'S' );
is( edit_entry( $official, $editor, 'Suspended entry' ), 303, 'cannot edit a suspended entry' );
$official->set_prop( statusvis => undef );

{
    no warnings 'redefine';
    my $concurrent   = post_entry( $community, $author, 'Concurrent visibility fixture', 1 );
    my $trylock      = \&DW::Locker::trylock;
    my $entry_lock   = 'official-entry:' . $community->id . ':' . $concurrent->jitemid;
    my $author_saved = 0;
    local *DW::Locker::trylock = sub {
        if ( $_[1] eq $entry_lock && !$author_saved++ ) {
            is(
                edit_entry( $concurrent, $author, 'Made private by author', security => 'private' ),
                0,
                'author changes visibility before releasing the entry lock'
            );
        }
        return $trylock->(@_);
    };
    is( edit_entry( $concurrent, $editor, 'Shared edit without visibility', min => 12 ),
        0, 'shared edit without visibility still saves' );
    is( reload_entry($concurrent)->security,
        'private', 'shared edit preserves the author’s visibility change' );
}

{
    no warnings 'redefine';
    my $restricted = post_entry( $community, $author, 'Members-only fixture', 1 );
    is(
        edit_entry(
            $restricted, $author, 'Members-only content',
            security  => 'usemask',
            allowmask => 1
        ),
        0,
        'author saves members-only visibility'
    );
    my $validate = \&LJ::Protocol::common_event_validation;
    local *LJ::Protocol::common_event_validation = sub {
        my $valid = $validate->(@_);
        LJ::clear_rel( $community, $editor, 'E' );
        return $valid;
    };
    is( edit_entry( $restricted, $editor, 'No longer a member' ),
        303, 'shared edit rechecks whether the admin can still see members-only content' );
    is(
        reload_entry($restricted)->event_raw,
        'Members-only content',
        'membership revocation preserves content'
    );
    LJ::set_rel( $community, $editor, 'E' );
    local *LJ::Protocol::common_event_validation = $validate;
    is( edit_entry( $restricted, $editor, 'Members-only edit', min => 13 ),
        0, 'a member can save without specifying visibility' );
    is( reload_entry($restricted)->allowmask, 1, 'a content edit preserves the members-only mask' );
}

{
    no warnings 'redefine';
    local $LJ::DISABLED{embed_module} = 0;
    my $validate = \&LJ::Protocol::common_event_validation;
    for my $revocation (
        [
            'flag',
            sub { $official->set_prop( admin_post => 0 ) },
            sub { $official->set_prop( admin_post => 1 ) }
        ],
        [
            'setting',
            sub { $community->set_prop( shared_admin_posts => 0 ) },
            sub { $community->set_prop( shared_admin_posts => 1 ) }
        ],
        [
            'admin role',
            sub { LJ::clear_rel( $community, $editor, 'A' ) },
            sub { LJ::set_rel( $community, $editor, 'A' ) }
        ],
        )
    {
        my ( $name, $revoke, $restore ) = @$revocation;
        my $before = reload_entry($official)->event_raw;
        local *LJ::Protocol::common_event_validation = sub {
            my $valid = $validate->(@_);
            $revoke->();
            return $valid;
        };
        my $embed_count = community_embed_count();
        my $body = qq{Revoked $name <iframe src="https://www.youtube.com/embed/example"></iframe>};
        is( edit_entry( $official, $editor, $body, props => { admin_post => 1 } ),
            303, "in-flight save cannot outlive revocation of the $name" );
        is( community_embed_count(), $embed_count, "revoking the $name prevents embed writes" );
        is( reload_entry($official)->event_raw, $before, "revoking the $name preserves content" );
        ok( !reload_entry($official)->prop('admin_post'), 'stale form does not restore the flag' )
            if $name eq 'flag';
        $restore->();
    }
}

{
    no warnings 'redefine';
    local $LJ::DISABLED{embed_module} = 0;
    my $before      = reload_entry($official)->event_raw;
    my $embed_count = community_embed_count();
    my $body = 'Unattributed edit <iframe src="https://www.youtube.com/embed/example"></iframe>';
    local *LJ::Entry::put_logprop_in_history = sub { return undef };
    like( edit_entry( $official, $third, $body, security => 'private' ),
        qr/^501\b/, 'failure to record a new editor rejects the edit' );
    is( community_embed_count(), $embed_count, 'history failure rolls back the new embed' );
    is( reload_entry($official)->event_raw, $before,  'history failure leaves content unchanged' );
    is( reload_entry($official)->security,  'public', 'history failure leaves security unchanged' );
}

{
    local $LJ::DISABLED{embed_module} = 0;
    my $embedded = post_entry( $community, $author, 'Approved embed fixture', 1 );
    my $before   = community_embed_count();
    my $body     = 'Approved edit <iframe src="https://example.invalid/video"></iframe>';
    is( edit_entry( $embedded, $editor, $body ), 0, 'an approved shared edit saves an embed' );
    is( community_embed_count(), $before + 1, 'the community owns the committed embed' );
    like(
        reload_entry($embedded)->event_raw,
        qr/<site-embed id="\d+"\/>/,
        'the updated entry references the committed embed'
    );
}

{
    no warnings 'redefine';
    local $LJ::DISABLED{embed_module} = 0;
    local @LJ::MEMCACHE_SERVERS = ('fake');
    my $original_memcache = LJ::MemCache::get_memcache();
    LJ::MemCache::set_memcache( LJ::Test::FakeMemCache->new );
    my $embedded = post_entry( $community, $author, 'Public embed queue fixture', 1 );
    my $tag      = 'embed queue visibility';
    is(
        edit_entry( $embedded, $author, 'Public fixture with a tag', props => { taglist => $tag } ),
        0,
        'author tags the public entry'
    );
    is( reload_entry($embedded)->security, 'public', 'warm the public entry cache' );
    ok(
        LJ::MemCache::get(
            [ $community->id, 'log2:' . $community->id . ':' . $embedded->jitemid ]
        ),
        'public entry visibility is cached'
    );
    my $dispatch       = \&DW::TaskQueue::dispatch;
    my $media_attempts = 0;
    local *DW::TaskQueue::dispatch = sub {
        if ( grep { $_->isa('DW::Task::EmbedWorker') } @_[ 1 .. $#_ ] ) {
            $media_attempts++;
            die "Simulated embed lookup queue failure\n";
        }
        return $dispatch->(@_);
    };
    my $body  = 'Private embed edit <iframe src="https://www.youtube.com/embed/example"></iframe>';
    my $error = eval { edit_entry( $embedded, $editor, $body, security => 'private' ) };
    is( $media_attempts, 1, 'the recognized embed tries to queue a media lookup' );
    is( $error // $@,    0, 'an unavailable media queue does not fail the committed edit' );
    my $saved = reload_entry($embedded);
    is( $saved->security, 'private', 'the cached entry is no longer public' );
    ok( !$saved->visible_to(undef), 'the warmed cache does not expose the entry to readers' );
    like( $saved->event_raw, qr/Private embed edit <site-embed /, 'the cached text is updated' );
    is_deeply( [ $saved->tags ], [$tag], 'the tag is retained after the visibility change' );
    my ($tag_info) = grep { $_->{name} eq $tag } values %{ LJ::Tags::get_usertags($community) };
    is( $tag_info->{security_level}, 'private', 'tag accounting reflects the private visibility' );
    LJ::MemCache::set_memcache($original_memcache);
}

{
    my $entry = post_entry( $community, $author, 'Tag permissions fixture', 1 );
    my $tag   = 'existing public tag';
    is( edit_entry( $entry, $author, 'Tagged entry', props => { taglist => $tag } ),
        0, 'author applies a public tag' );
    LJ::set_rel( $community, $editor, 'B' );
    ok( !LJ::Tags::can_add_entry_tags( $editor, $entry ), 'the shared editor cannot add tags' );
    ok( !LJ::Tags::can_control_tags( $community, $editor ), 'the shared editor cannot edit tags' );
    is(
        edit_entry(
            $entry, $editor, 'Private entry',
            security => 'private',
            props    => { taglist => 'unauthorized replacement' }
        ),
        0,
        'tag permission denial does not prevent a shared visibility edit'
    );
    LJ::clear_rel( $community, $editor, 'B' );
    my $saved = reload_entry($entry);
    is( $saved->security, 'private', 'the entry becomes private' );
    is_deeply( [ $saved->tags ], [$tag], 'the tag list is unchanged' );
    my ($tag_info) = grep { $_->{name} eq $tag } values %{ LJ::Tags::get_usertags($community) };
    is( $tag_info->{security_level}, 'private', 'the existing tag follows the new visibility' );
}

for my $actor ( $editor, $author ) {
    no warnings 'redefine';
    my $kind  = $actor->equals($author) ? 'author' : 'shared';
    my $entry = post_entry( $community, $author, "Tag write fixture for $kind", 1 );
    my $tag   = "tag write failure for $kind";
    is( edit_entry( $entry, $author, 'Original tagged entry', props => { taglist => $tag } ),
        0, 'author applies a tag before a failing write' );
    my $write         = \&LJ::User::do;
    my $failed_writes = 0;
    local *LJ::User::do = sub {
        my ( $journal, $sql ) = @_;
        if ( $journal->equals($community) && $sql =~ /\A(?:INSERT|REPLACE)\s+INTO logkwsum\b/i ) {
            $failed_writes++;
            return $write->( $journal, 'UPDATE logkwsum SET nonexistent_test_column = 0' );
        }
        return $write->(@_);
    };
    my $error = eval { edit_entry( $entry, $actor, 'Should not save', security => 'private' ) };
    ok( $failed_writes, "$kind edit attempts a tag accounting write" );
    like( $error // $@, qr/^501\b/, "$kind edit reports the failed write" );
    my $saved = reload_entry($entry);
    is( $saved->security, 'public', "$kind edit rolls back entry visibility" );
    is( $saved->event_raw, 'Original tagged entry', "$kind edit leaves the body unchanged" );
    is_deeply( [ $saved->tags ], [$tag], "$kind edit retains the existing tag" );
    my ($tag_info) = grep { $_->{name} eq $tag } values %{ LJ::Tags::get_usertags($community) };
    is( $tag_info->{security_level}, 'public', "$kind edit leaves tag visibility consistent" );
}

like( edit_entry( $official, $author, 'False attribution', props => { admin_post_editor => 1 } ),
    qr/^205\b/, 'clients cannot write the internal attribution property' );

is(
    edit_entry(
        $official, $editor, 'Second admin edited',
        security => 'private',
        props    => { current_music => 'Music' }
    ),
    0,
    'a second admin edits content and metadata'
);
is( reload_entry($official)->prop('current_music'), 'Music', 'shared edit saves metadata' );
is( reload_entry($official)->security, 'private', 'shared edit can update entry visibility' );
my $private_url =
    'http://www.dw.test/users/' . $community->user . '/' . $official->ditemid . '.html';
my $private_res = $app_test->request( HTTP::Request->new( GET => $private_url ) );
unlike( $private_res->content, $msg,
    'a private entry does not reveal attribution to an anonymous reader' );
$official->set_prop( picture_keyword           => 'Original author icon' );
$official->set_prop( opt_nocomments_maintainer => 1 );
is(
    edit_entry(
        $official, $editor, 'Second admin edited again',
        security => 'public',
        props    => { picture_keyword => '', opt_nocomments => 0 }
    ),
    0,
    'a repeat edit succeeds'
);
ok(
    reload_entry($official)->comments_disabled_maintainer,
    'shared saves preserve comment overrides'
);
my $history_prop = LJ::get_prop( 'log', 'admin_post_editor' );
is(
    $community->selectrow_array(
        'SELECT COUNT(*) FROM logprop_history WHERE journalid=? AND jitemid=? AND propid=?',
        undef, $community->id, $official->jitemid, $history_prop->{id}
    ),
    1,
    'repeat saves do not add duplicate editor history'
);
is(
    reload_entry($official)->prop('picture_keyword'),
    'Original author icon',
    'shared edit cannot replace the author’s icon'
);
is( edit_entry( $official, $third, 'Third admin edited' ), 0, 'a third admin can also edit' );
is( edit_entry( $official, $author, 'Original author edited' ),
    0, 'original author can still edit' );

my $html = entry_text($official);
my ($notice) = $html =~ m{(<p class="shared-admin-editors">.*?</p>)}s;
like( $html, qr/Original author edited/, 'content is updated' );
like( $notice // '', $msg, 'entry shows attribution' );
for my $admin ( $editor, $third ) {
    my $name    = $admin->user;
    my @matches = ( $notice // '' ) =~ /\b\Q$name\E\b/g;
    is( scalar @matches, 1, "$name appears once" );
}
unlike( $notice // '', qr/\Q@{[$author->user]}\E/, 'original author is not credited as an editor' );
unlike(
    $notice // '',
    qr/<em>|Display name/,
    'attribution uses usernames, not display-name markup'
);

my $reading_entry =
    LJ::S2::Entry_from_entryobj( $member, reload_entry($official), { getargs => {} } );
like( $reading_entry->{text}, $msg, 'full-body reading view includes attribution' );
my $title_entry = LJ::S2::Entry_from_entryobj( $member, reload_entry($official),
    { getargs => {}, no_entry_body => 1 } );
unlike( $title_entry->{text}, $msg, 'title-only view omits attribution' );

my $old_name      = $third->user;
my $new_name      = 'r_' . substr( $old_name, 2 );
my $third_cluster = $third->clusterid;
$third->update_self( { user => $new_name } );
LJ::start_request();
like( entry_text($official), qr/\Q$new_name\E/,
    'attribution follows the editor’s stable ID after rename' );
unlike( entry_text($official), qr/\Q$old_name\E/, 'attribution omits the former username' );
$third->update_self( { statusvis => 'X', clusterid => 0 } );
LJ::start_request();
unlike( entry_text($official), qr/\Q$new_name\E/,
    'attribution omits an expunged user with a retained ID' );
like( entry_text($official), qr/\Q@{[$editor->user]}\E/, 'attribution still names other editors' );
$third->update_self( { statusvis => 'V', clusterid => $third_cluster } );

is( edit_entry( $official, $editor, 'Flag removed', props => { admin_post => 0 } ),
    0, 'a shared edit can remove the flag' );
is( edit_entry( $official, $editor, 'After removal' ), 303, 'removing the flag revokes sharing' );
like( entry_text($official), $msg, 'removing the flag does not erase attribution' );

is( edit_entry( $official, $author, 'Flag restored', props => { admin_post => 1 } ),
    0, 'the author can restore the flag' );
$community->set_prop( shared_admin_posts => 0 ) if $setting;
is( edit_entry( $official, $editor, 'Disabled again' ), 303, 'turning sharing off revokes access' );
is( edit_entry( $ordinary, $editor, '' ), 0, 'existing admin moderation deletion is unchanged' );
ok( LJ::delete_entry( $community, $official->jitemid ), 'entry deletion completes' );
is(
    $community->selectrow_array(
        'SELECT COUNT(*) FROM logprop_history WHERE journalid=? AND jitemid=? AND propid=?',
        undef, $community->id, $official->jitemid, $history_prop->{id}
    ),
    0,
    'purging entry data also removes shared editor history'
);

done_testing();
