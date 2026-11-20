# t/admin-entryprops.t
#
# Tests authorization, form authentication, and persistence for entry property edits.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use HTTP::Request::Common;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Controller::Admin::Props;
use DW::Request::Standard;
use LJ::Test qw(temp_user);

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'adminEntryProps';
$LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

my $owner = temp_user();
my $entry = $owner->t_post_fake_entry;
END { LJ::delete_entry( $owner, $entry->jitemid, 0, $entry->anum ) if $entry; }
$entry->set_prop( current_music => 'Original music' );
$entry->set_prop( revnum        => 1 );
my $entry_path = "$LJ::SITEROOT/users/" . $owner->user;
my $entry_url  = "$entry_path/" . $entry->ditemid . '.html';
my $page       = 'http://localhost/admin/entryprops';

sub post_entryprops {
    my ( $remote, %fields ) = @_;
    LJ::start_request();
    local $LJ::IS_DEV_SERVER = 0;
    DW::Request::Standard->new( GET $page );
    LJ::set_remote($remote);
    my $token = LJ::form_auth(1);

    DW::Request->reset;
    $fields{lj_form_auth} = $token unless exists $fields{lj_form_auth};
    my $request = DW::Request::Standard->new( POST $page, Content => [%fields] );
    LJ::set_remote($remote);
    DW::Controller::Admin::Props::entryprops_handler();
    return $request->{res}->content;
}

sub persisted_music {
    my $prop = LJ::get_prop( 'log', 'current_music' );
    return $owner->selectrow_array(
        'SELECT value FROM logprop2 WHERE journalid = ? AND jitemid = ? AND propid = ?',
        undef, $owner->id, $entry->jitemid, $prop->{id} );
}

my $viewer = temp_user();
ok( $viewer->grant_priv( 'canview', 'entryprops' ), 'grant the view privilege' );
my $view = post_entryprops( $viewer, url => $entry_url );
like( $view, qr/Original music/, 'viewer can look up the existing property' );
unlike( $view, qr/\bname=['"]_save['"]/, 'viewer does not see an editor' );
post_entryprops( $viewer, url => $entry_url, _save => 1, prop_current_music => 'Viewer edit' );
is( persisted_music(), 'Original music', 'a direct save by a viewer does not write' );

my $admin = temp_user();
ok( $admin->grant_priv( 'siteadmin', 'entryprops' ), 'grant the edit privilege' );
post_entryprops( $admin, url => $entry_url, _save => 1, prop_current_music => 'No view privilege' );
is( persisted_music(), 'Original music', 'the edit privilege alone cannot write' );
ok( $admin->grant_priv( 'canview', 'entryprops' ), 'grant the editor the view privilege' );

my $form = post_entryprops( $admin, url => $entry_url );
like( $form, qr/\bname=['"]_save['"]/, 'authorized administrator sees an editor' );
my ($auth) = $form =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
ok( $auth, 'editor includes a form-auth token' );

my $not_saved = post_entryprops(
    $admin,
    url                => $entry_url,
    _save              => 1,
    lj_form_auth       => '',
    prop_current_music => 'No form auth'
);
unlike( $not_saved, qr/Original music/, 'a save without form auth does not show the editor' );
is( persisted_music(), 'Original music', 'missing form auth prevents a write' );

foreach my $bad_url ( undef, 'not-an-entry', "$entry_path/9999999.html",
    "$entry_path/" . ( $entry->ditemid ^ 1 ) . '.html' )
{
    my $invalid = post_entryprops(
        $admin,
        url                => $bad_url // '',
        _save              => 1,
        prop_current_music => 'Invalid entry URL'
    );
    like(
        $invalid,
        qr/not a valid entry URL/,
        'empty, malformed, or invalid entry URL is rejected'
    );
    is( persisted_music(), 'Original music', 'invalid entry URL does not update the property' );
}

my $invalid = post_entryprops(
    $admin,
    url                => $entry_url,
    _save              => 1,
    prop_current_music => 'Valid music',
    prop_revnum        => 'x'
);
like( $invalid, qr/whole number/, 'non-numeric revision number is rejected' );
is( persisted_music(), 'Original music', 'invalid property prevents all writes' );

my $music = '<em>Updated</em> & saved';
post_entryprops(
    $admin,
    url                   => $entry_url,
    _save                 => 1,
    lj_form_auth          => $auth // '',
    prop_current_music    => $music,
    prop_replycount       => '10',
    prop_current_location => 'Not set on this entry'
);
is( persisted_music(), $music, 'the authorized edit persists the raw value' );

my $updated = post_entryprops( $viewer, url => $entry_url );
like( $updated, qr/&lt;em&gt;Updated&lt;\/em&gt; &amp; saved/,
    'viewer sees escaped updated value' );
unlike( $updated, qr/Not set on this entry/, 'cannot add an unlisted property by POST' );
is(
    $owner->selectrow_array(
        'SELECT replycount FROM log2 WHERE journalid = ? AND jitemid = ?', undef,
        $owner->id,                                                        $entry->jitemid
    ),
    0,
    'a display-only counter is not writable'
);

my $wildcard = temp_user();
ok( $wildcard->grant_priv( 'canview',   '*' ), 'grant the wildcard view privilege' );
ok( $wildcard->grant_priv( 'siteadmin', '*' ), 'grant the wildcard edit privilege' );
post_entryprops( $wildcard, url => $entry_url, _save => 1, prop_current_music => '' );
is( persisted_music(), undef, 'an administrator with wildcard privileges can clear a property' );

done_testing;
