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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
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
    LJ::start_request();
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
        { noauth => 1, u => $actor },
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

$author->update_self( { statusvis => 'S' } );
is( edit_entry( $official, $editor, 'Suspended author' ),
    303, 'cannot edit a suspended author’s post' );
$author->update_self( { statusvis => 'V' } );

$official->set_prop( statusvis => 'S' );
is( edit_entry( $official, $editor, 'Suspended entry' ), 303, 'cannot edit a suspended entry' );
$official->set_prop( statusvis => undef );

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
$official->set_prop( picture_keyword => 'Original author icon' );
is(
    edit_entry(
        $official, $editor, 'Second admin edited again',
        security => 'public',
        props    => { picture_keyword => '' }
    ),
    0,
    'a repeat edit succeeds'
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

is( edit_entry( $official, $editor, 'Flag removed', props => { admin_post => 0 } ),
    0, 'a shared edit can remove the flag' );
is( edit_entry( $official, $third, 'After removal' ), 303, 'removing the flag revokes sharing' );
like( entry_text($official), $msg, 'removing the flag does not erase attribution' );

is( edit_entry( $official, $author, 'Flag restored', props => { admin_post => 1 } ),
    0, 'the author can restore the flag' );
$community->set_prop( shared_admin_posts => 0 ) if $setting;
is( edit_entry( $official, $editor, 'Disabled again' ), 303, 'turning sharing off revokes access' );
is( edit_entry( $ordinary, $editor, '' ), 0, 'existing admin moderation deletion is unchanged' );

done_testing();
