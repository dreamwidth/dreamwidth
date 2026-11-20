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
use Encode qw(encode_utf8);
use File::Temp qw(tempdir);
use HTTP::Request::Common;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Controller::Admin::Props;
use DW::External::Account;
use DW::Request::Standard;
use LJ::Test qw(temp_user);

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'adminEntryProps';
$LJ::TASK_QUEUE_LOCAL_PATH = tempdir( CLEANUP => 1 );

my $owner = temp_user();
my $entry = $owner->t_post_fake_entry;
END { LJ::delete_entry( $owner, $entry->jitemid, 0, $entry->anum ) if $entry; }
$entry->set_prop( current_music    => 'Original music' );
$entry->set_prop( current_location => 'Original location' );
$entry->set_prop( current_coords   => '45.0,-123.0' );
$entry->set_prop( adult_content    => 'concepts' );
$entry->set_prop( revnum           => 1 );
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

sub persisted_prop {
    my ($name) = @_;
    my $prop = LJ::get_prop( 'log', $name );
    return $owner->selectrow_array(
        'SELECT value FROM logprop2 WHERE journalid = ? AND jitemid = ? AND propid = ?',
        undef, $owner->id, $entry->jitemid, $prop->{id} );
}

sub persisted_music { return persisted_prop('current_music'); }

sub baseline {
    my ( $form, $name ) = @_;
    my ($original) = $form =~ /name=['"]baseline_$name['"][^>]*value=['"]([^'"]*)/;
    return ( "baseline_$name" => $original // '' );
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

foreach my $invalid (
    [ adult_content  => 'invalid',     'concepts',       qr/none, concepts, or explicit/ ],
    [ current_coords => '91.0,-123.0', '45.0,-123.0',    qr/valid coordinates/ ],
    [ current_music  => '0',           'Original music', qr/Literal 0/ ],
    [ current_music  => 'a' x 101,     'Original music', qr/100 characters/ ],
    [ current_music => encode_utf8( chr(0x20ac) x 86 ), 'Original music', qr/255 bytes/ ],
    )
{
    my ( $name, $input, $original, $message ) = @$invalid;
    my $response = post_entryprops(
        $admin,
        url   => $entry_url,
        _save => 1,
        baseline( $form, $name ),
        "prop_$name" => $input,
        baseline( $form, 'current_location' ), prop_current_location => 'Do not save',
    );
    like( $response, $message, "$name: invalid value is rejected" );
    is( persisted_prop($name), $original, "$name: invalid value is not stored" );
    is( persisted_prop('current_location'), 'Original location', 'validation prevents all writes' );

    $entry->set_prop( $name, $original );
    $entry->set_prop( current_location => 'Original location' );
}

my $music = '<em>Updated</em> & saved';
post_entryprops(
    $admin,
    url          => $entry_url,
    _save        => 1,
    lj_form_auth => $auth // '',
    baseline( $form, 'current_music' ),
    prop_current_music => $music,
);
is( persisted_music(), $music, 'the authorized edit persists the raw value' );
is(
    scalar LJ::get_db_writer()->selectrow_array(
        'SELECT notes FROM statushistory WHERE userid = ? AND adminid = ? AND shtype = ?',
        undef, $owner->id, $admin->id, 'entryprops'
    ),
    'Entry ' . $entry->ditemid . ': current_music',
    'audit record identifies the actor, entry, and changed property without its value'
);

my $updated = post_entryprops( $viewer, url => $entry_url );
like( $updated, qr/&lt;em&gt;Updated&lt;\/em&gt; &amp; saved/,
    'viewer sees escaped updated value' );

my $wildcard = temp_user();
ok( $wildcard->grant_priv( 'canview',   '*' ), 'grant the wildcard view privilege' );
ok( $wildcard->grant_priv( 'siteadmin', '*' ), 'grant the wildcard edit privilege' );

my $first_form  = post_entryprops( $admin,    url => $entry_url );
my $second_form = post_entryprops( $wildcard, url => $entry_url );
my $first_save  = post_entryprops(
    $admin,
    url   => $entry_url,
    _save => 1,
    baseline( $first_form, 'current_music' ), prop_current_music => 'New music',
);
like( $first_save, qr/Changes saved/, 'first editor saves their change' );
my $second_save = post_entryprops(
    $wildcard,
    url   => $entry_url,
    _save => 1,
    baseline( $second_form, 'current_music' ),
    prop_current_music => $music,
    baseline( $second_form, 'current_location' ), prop_current_location => 'New location',
);
like( $second_save, qr/Changes saved/, 'stale form can still save an unrelated change' );
is( persisted_music(), 'New music', 'untouched stale field does not overwrite the first edit' );
is( persisted_prop('current_location'),
    'New location', 'second editor saves their disjoint change' );

my $conflict = post_entryprops(
    $wildcard,
    url   => $entry_url,
    _save => 1,
    baseline( $second_form, 'current_music' ),
    prop_current_music => 'Conflicting music',
    baseline( $second_form, 'adult_content' ), prop_adult_content => 'explicit',
);
like( $conflict, qr/changed since you opened/, 'an intended change to a stale field is rejected' );
unlike( $conflict, qr/Changes saved/, 'a conflict is not reported as saved' );
is( persisted_music(),               'New music', 'same-field conflict preserves the first edit' );
is( persisted_prop('adult_content'), 'concepts',  'a conflicting save leaves other fields alone' );

my $clear_form = post_entryprops( $wildcard, url => $entry_url );
my $cleared    = post_entryprops(
    $wildcard,
    url   => $entry_url,
    _save => 1,
    baseline( $clear_form, 'current_music' ),
    prop_current_music => '',
    baseline( $clear_form, 'adult_content' ),
    prop_adult_content => 'explicit',
    baseline( $clear_form, 'current_coords' ), prop_current_coords => '20.0,30.0',
);
like( $cleared, qr/Changes saved/, 'valid enum and coordinate edits can be saved with a clear' );
is( persisted_music(), undef, 'a blank clears the property for a wildcard editor' );
is( persisted_prop('adult_content'),  'explicit',  'valid enum is stored' );
is( persisted_prop('current_coords'), '20.0,30.0', 'valid coordinates are stored' );

$entry->set_prop( statusvis     => 'S' );
$entry->set_prop( opt_backdated => 1 );
DW::External::Account->record_xpost( $entry, { 1 => 123 } );
DW::External::Account->record_xpost_detail( $entry,
    { 1 => { itemid => 123, url => 'https://example.test/123' } } );
my $suspended_form = post_entryprops( $admin, url => $entry_url );
foreach my $protected (qw(statusvis opt_backdated revnum xpost xpostdetail replycount)) {
    like(
        $suspended_form,
        qr/<strong>\Q$protected\E:<\/strong>/,
        "the suspended entry's $protected is shown read-only"
    );
    unlike(
        $suspended_form,
        qr/\bname=['"]prop_\Q$protected\E['"]/,
        "$protected has no edit control"
    );
}
unlike(
    $suspended_form,
    qr/\bname=['"]prop_current_music['"]/,
    'a cleared property cannot be added back through the editor'
);

done_testing;
