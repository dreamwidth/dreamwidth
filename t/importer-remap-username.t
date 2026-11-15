# t/importer-remap-username.t
#
# Tests how the LiveJournal importer maps remote usernames onto local
# (OpenID or real) accounts. The remote site is replaced by a canned user
# agent, so nothing here touches the network.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );

use HTTP::Response;
use DW::Importer::Context;
use DW::Worker::ContentImporter::LiveJournal;

my $class = 'DW::Worker::ContentImporter::LiveJournal';
my $host  = 'remote.example';

# A user agent that answers from a table. Anything not in the table is a 404, so an
# unexpected request cannot reach out.
{

    package Test::CannedUA;

    our %RESPONSES;

    sub new { return bless {}, shift }

    sub get {
        my ( $self, $url ) = @_;
        my $body = $RESPONSES{$url};
        return HTTP::Response->new( 404, 'Not Found' ) unless defined $body;
        my $r = HTTP::Response->new( 200, 'OK' );
        $r->content($body);
        return $r;
    }
}

{
    no warnings 'redefine';
    *LJ::get_useragent = sub { return Test::CannedUA->new };
}

sub foaf {
    my ($openid) = @_;
    return qq{<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:foaf="http://xmlns.com/foaf/0.1/">
<foaf:Person><foaf:name>Someone</foaf:name><foaf:openid rdf:resource="$openid"/></foaf:Person>
</rdf:RDF>};
}

sub opml {
    my ($owner) = @_;
    return
qq{<?xml version="1.0"?><opml version="1.0"><head><ownerName>$owner</ownerName></head></opml>};
}

sub remap {
    my ($username) = @_;
    my $ctx = DW::Importer::Context->new( data => { hostname => $host } );
    return $class->remap_username_friend( $ctx, $username );
}

sub identity_of {
    my ($uid) = @_;
    my $u = LJ::load_userid($uid) or return undef;
    return $u->openid_identity;
}

# a normal account takes the identity URL published in its FOAF data
{
    local %Test::CannedUA::RESPONSES =
        ( "http://$host/~foafuser/data/foaf" => foaf('http://foafuser.remote.example/') );
    my $uid = remap('foafuser');
    ok( $uid, 'got a local userid' );
    is( identity_of($uid), 'http://foafuser.remote.example/', 'the identity is the FOAF openid' );
    is( remap('foafuser'), $uid, 'mapping the same remote user again reuses the account' );
}

# when the FOAF data cannot be loaded, the identity is guessed from the username
{
    local %Test::CannedUA::RESPONSES = ();
    my $uid = remap('under_score');
    ok( $uid, 'got a local userid' );
    is( identity_of($uid), "http://under-score.$host/",
        'underscores become hyphens in the guessed URL' );
}

# dashes and underscores in remote names are the same user
{
    local %Test::CannedUA::RESPONSES = ();
    is( remap('dash-user'), remap('dash_user'), 'dash-user and dash_user map to one account' );
}

# remote OpenID accounts (ext_NNN) use the OPML ownerName when there is one...
{
    local %Test::CannedUA::RESPONSES =
        ( "http://$host/tools/opml.bml?user=ext_1001" => opml('someone.example.org/blog') );
    my $uid = remap('ext_1001');
    is(
        identity_of($uid),
        'http://someone.example.org/blog/',
        'the OPML owner is used as the identity URL'
    );
}

# ...and fall back to ext-NNN.<remote host> when there is not
{
    local %Test::CannedUA::RESPONSES = ();
    my $uid = remap('ext_1002');
    is( identity_of($uid), "http://ext-1002.$host/", 'ext_ users fall back to ext-NNN.host' );
}

# an ext_ account whose identity is really a local user maps to that user, never to a new OpenID
{
    local $LJ::DOMAIN      = 'local.test';
    local $LJ::USER_DOMAIN = 'local.test';
    my $local = temp_user();

    local %Test::CannedUA::RESPONSES =
        ( "http://$host/tools/opml.bml?user=ext_1003" => opml( $local->user . '.local.test' ) );
    is( remap('ext_1003'), $local->id, 'the identity resolves to the existing local account' );
}

# an ext_ account pointing at a local name that does not exist stays anonymous instead of
# becoming an OpenID account for an OpenID account
{
    local $LJ::DOMAIN      = 'local.test';
    local $LJ::USER_DOMAIN = 'local.test';

    local %Test::CannedUA::RESPONSES =
        ( "http://$host/tools/opml.bml?user=ext_1004" => opml('nobody-by-this-name.local.test') );
    is( remap('ext_1004'), undef, 'an unmappable local identity yields no user' );
}

# when the identity is the old name of a renamed local user, the mapping returns that user's id
{
    local $LJ::DOMAIN      = 'local.test';
    local $LJ::USER_DOMAIN = 'local.test';
    my $new = temp_user();
    my $old = 'old_' . lc LJ::rand_chars(8);

    my $dbh = LJ::get_db_writer();
    $dbh->do(
        'INSERT INTO renames (auth, ownerid, renuserid, fromuser, touser, rendate, status) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
        undef, 'abcdefghijklm', $new->id, $new->id, $old, $new->user, time(), 'A'
    );
    my $renid = $dbh->{mysql_insertid};

    local %Test::CannedUA::RESPONSES =
        ( "http://$host/tools/opml.bml?user=ext_1005" => opml("$old.local.test") );
    my $got = remap('ext_1005');
    $dbh->do( 'DELETE FROM renames WHERE renid = ?', undef, $renid );

    ok( !ref $got, 'a userid, not an object' );
    is( $got, $new->id, 'the renamed user is found through the rename history' );
}

done_testing();
