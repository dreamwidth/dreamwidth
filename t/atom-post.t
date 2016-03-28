# t/atom-post.t
#
# Test post via ATOM protocol.
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test;

if ( LJ::Test::check_memcache ) {
    plan tests => 103;
} else {
    plan skip_all => "Memcache configured but not active."
}

use XML::Atom::Client;
use XML::Atom::Entry;
use XML::Atom::Category;
use XML::Atom::Feed;
use DW::Routing;

# so that entries can be posted to community journals
$LJ::EVERYONE_VALID = 1;

$LJ::USE_SSL = 1 if $LJ::USE_HTTPS_EVERYWHERE && $LJ::SSLROOT;

my $u = temp_user();
my $pass = "foopass";
$u->set_password( $pass );

my $api = XML::Atom::Client->new( Version => 1 );

my $r;
sub do_request {
    my ( $method, $uri, %opts ) = @_;

    my $authenticate = delete $opts{authenticate};
    my $data = delete $opts{data} || {};
    my $remote = delete $opts{remote} || $u;
    my $password = delete $opts{password} || $remote->password;

    $uri =~ m!https?://([^.]+)!;
    my $user_subdomain = $1 eq "www" ? "" : $1;

    my %routing_data = ();
    $routing_data{username} = $user_subdomain if $user_subdomain;
    $routing_data{ssl} = 1 if $LJ::USE_SSL;

    my $input = delete $data->{input};

    $r = routing_request( $uri,
        method => $method,
        content => $input,
        setup_http_request => sub {
            if ( $authenticate ) {
                $api->username( $remote->username );
                $api->password( $password );
                $api->munge_request( $_[0] );
            }
        },
        setup_dw_request => sub {
            $_[0]->pnote( $_ => $data->{$_} ) foreach %$data;
        },
        routing_data => \%routing_data,
    );
}

# check subject, etc
# items that are not defined in the hash to be checked against are ignored
sub check_entry {
    my ( $atom_entry, $entry_info, $journal ) = @_;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    subtest "check_entry $entry_info->{id} - $entry_info->{title}"  => sub {
        ok( $atom_entry, "Got an atom entry back from the server" );
        is( $atom_entry->title, $entry_info->{title}, "atom entry has right title" )
            if defined $entry_info->{title};

        # having the content body be of type HTML
        # causes newlines to appear for some reason when we try to extract the content as a string
        # so let's just work around it; it should be harmless (as_xml doesn't contain the extra newlines)
        my $event_raw = $entry_info->{content};
        like( $atom_entry->content->body, qr/\s*$event_raw\s*/, "atom entry has right content" )
            if defined $entry_info->{content};

        is( $atom_entry->id, $entry_info->{atom_id}, "atom id" )
            if defined $entry_info->{atom_id};

        is( $atom_entry->author->name, $entry_info->{author}, "atom entry author" )
            if defined $entry_info->{author};

        if ( defined $entry_info->{url} ) {
            my @links = $atom_entry->link;
            is( scalar @links, 2, "got back two links" );
            foreach my $link( @links ) {
                if ( $link->rel eq "edit" ) {
                    is( $link->href, $journal->atom_base . "/entries/$entry_info->{id}", "edit link" );
                } else { # alternate
                    is( $link->href, $entry_info->{url}, "entry link" );
                }
            }
        }

        if ( defined $entry_info->{categories} ) {
            my %tags = map { $_ => 1 } @{ $entry_info->{categories} || [] };
            my %categories = map { $_->term => 1 } $atom_entry->category;
            is( scalar keys %categories, 2, "got back multiple categories" );
            is_deeply( { %categories }, { %tags }, "got back the categories we sent in" );
        }
    };
}


note( "Authentication" );
do_request( GET => $u->atom_service_document );
is( $r->status, $r->HTTP_UNAUTHORIZED, "Did not pass any authorization information." );
is( $r->content_type, "text/plain", "Error content type" );

# intentionally break authorization
do_request( GET => $u->atom_service_document, authenticate => 1, password => $u->password x 3 );
is( $r->status, $r->HTTP_UNAUTHORIZED, "Passed wrong authorization information." );

do_request( GET => $u->atom_service_document, authenticate => 1 );
is( $r->status, $r->HTTP_OK, "Successful authentication." );


note( "Service document introspection." );
do_request( POST => $u->atom_service_document ); 
is( $r->status, $r->HTTP_METHOD_NOT_ALLOWED, "Service document needs GET (even unauthorized)" );

do_request( POST => $u->atom_service_document, authenticate => 1 );
is( $r->status, $r->HTTP_METHOD_NOT_ALLOWED, "Service document needs GET." );

do_request( GET => $u->atom_service_document, authenticate => 1 );
is( $r->status, $r->HTTP_OK, "Got service document." );
like( $r->content_type, qr#^\Qapplication/atomsvc+xml\E#, "Service content type" );
my $service_document_xml = $r->response_content;

note( "Categories document." );
# populate journal with some tags
my @journal_tags = qw( a b c );
LJ::Tags::create_usertag( $u, join( ", ", @journal_tags ), { display => 1 } );

do_request( GET => $u->atom_base . "/entries/tags" );
is( $r->status, $r->HTTP_UNAUTHORIZED, "Categories document protected by authorization." );

do_request( POST => $u->atom_base . "/entries/tags", authenticate => 1 );
is( $r->status, $r->HTTP_METHOD_NOT_ALLOWED, "Categories document needs GET." );

do_request( GET => $u->atom_base . "/entries/tags", authenticate => 1 );
is( $r->status, $r->HTTP_OK, "Got categories document." );
like( $r->content_type, qr#^\Qapplication/atomcat+xml\E#, "Categories document type" );
my $categories_document_xml = $r->response_content;

SKIP: {
    skip "No XML::Atom::Service/XML::Atom::Categories module installed.", 10
        unless eval "use XML::Atom::Service; use XML::Atom::Categories; 1;";

    my $service = XML::Atom::Service->new( \ $service_document_xml );
    ok( $service, "Got service document." );

    my @workspaces = $service->workspace;
    is( scalar @workspaces, 1, "One workspace" );
    is( $workspaces[0]->title, $u->user, "Workspace title" );

    my @collections = $workspaces[0]->collections;
    is( scalar @collections, 1, "One collection" );
    is( $collections[0]->title, "Entries", "Entries collection title" );
    is( $collections[0]->href, $u->atom_base . "/entries", "Entries collection uri" );

    my @categories = $collections[0]->categories;
    is( scalar @categories, 1, "One categories link" );
    is( $categories[0]->href, $u->atom_base . "/entries/tags", "Categories collection uri" );


    my $categories = XML::Atom::Categories->new( \$ categories_document_xml );
    @categories = $categories->category;
    is( scalar @categories, 3, "three existing categories" );
    is_deeply( { map { $_->term => 1 } @categories }, { map { $_ => 1 } @journal_tags }, "Journal tags match fetched categories" );
}

my $atom_entry; # an XML::Atom::Entry object
my $entry_obj;  # an LJ::Entry object
my $atom_entry_server;  # an XML::Atom::Entry object retrieved from the server

$atom_entry = XML::Atom::Entry->new( Version => 1 );
my $title = "New Post";
my $content = "Content of my post at " . rand();
my @tags = qw( foo bar );
$atom_entry->title( $title );
$atom_entry->content( $content );
foreach my $tag ( @tags ) {
    my $category = XML::Atom::Category->new( Version => 1 );
    $category->term( $tag );
    $atom_entry->add_category( $category );
}

note( "Create an entry." );
do_request( POST => $u->atom_base . "/entries", data => { input => $atom_entry->as_xml } );
is( $r->status, $r->HTTP_UNAUTHORIZED, "Entry creation protected by authorization." );

do_request( POST => $u->atom_base . "/entries", authenticate => 1, data => { input => $atom_entry->as_xml } );
is( $r->status, $r->HTTP_CREATED, "POSTed new entry" );
is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

note( "Double-check posted entry." );
$entry_obj = LJ::Entry->new( $u, jitemid => 1 );
ok( $entry_obj, "got entry" );
ok( $entry_obj->valid, "entry is valid" );
is( $entry_obj->subject_raw, $title, "item has right title" );
is( $entry_obj->event_raw, $content, "item has right content" );

$atom_entry_server = XML::Atom::Entry->new( \ $r->response_content );
check_entry( $atom_entry_server, {
            id      => $entry_obj->jitemid,
            title   => $atom_entry_server->title,
            content => $atom_entry_server->content->body,
            url     => $entry_obj->url,
            author  => $u->name_orig,
            categories => \@tags,
         },
         $u );

ok( $atom_entry_server->published eq $atom_entry_server->updated, "same publish and edit date" );
ok( ! $atom_entry_server->summary, "no summary; we have the content." );

note( "List entries" );
do_request( GET => $u->atom_base . "/entries" );
is( $r->status, $r->HTTP_UNAUTHORIZED, "Entries feed needs authorization." );

do_request( GET => $u->atom_base . "/entries", authenticate => 1 );
is( $r->status, $r->HTTP_OK, "Retrieved entry list" );
is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

my $feed = XML::Atom::Feed->new( \ $r->response_content );
my @entries = $feed->entries;
is( scalar @entries, 1, "Got entry from feed." );

note( "Retrieve entry" );
do_request( GET => $u->atom_base . "/entries/1" );
is( $r->status, $r->HTTP_UNAUTHORIZED, "Retrieving entry needs authorization." );

do_request( GET => $u->atom_base . "/entries/12345", authenticate => 1 );
is( $r->status, $r->NOT_FOUND, "No such entry" );
is( $r->content_type, "text/plain", "AtomAPI entry content type" );

do_request( POST => $u->atom_base . "/entries/1", authenticate => 1 );
is( $r->status, $r->HTTP_METHOD_NOT_ALLOWED, $u->atom_base . "/entries/1 does not support POST." );

do_request( GET => $u->atom_base . "/entries/1", authenticate => 1 );
is( $r->status, $r->HTTP_OK, "Retrieved entry" );
is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

$atom_entry_server = XML::Atom::Entry->new( \ $r->response_content );
check_entry( $atom_entry_server, {
                id      => $entry_obj->jitemid,
                title   => $entry_obj->subject_raw,
                content => $entry_obj->event_raw,
                atom_id => $entry_obj->atom_id,
                url     => $entry_obj->url,
                author  => $u->name_orig,
                categories => \@tags
             },
            $u );
ok( $atom_entry_server->published eq $atom_entry_server->updated, "same publish and edit date" );
ok( ! $atom_entry_server->summary, "no summary; we have the content." );


note( "Edit entry" );
do_request( PUT => $u->atom_base . "/entries/1" );
is( $r->status, $r->HTTP_UNAUTHORIZED, "Retrieving entry needs authorization." );

do_request( PUT => $u->atom_base . "/entries/12345", authenticate => 1 );
is( $r->status, $r->NOT_FOUND, "No such entry" );
is( $r->content_type, "text/plain", "AtomAPI entry content type" );


$atom_entry = XML::Atom::Entry->new( Version => 1 );
$title = "Edited Post";
$content = "Content of my post at " . rand();
@tags = qw( foo2 bar2 );
$atom_entry->id( $atom_entry_server->id );
$atom_entry->title( $title );
$atom_entry->content( $content );
foreach my $tag ( @tags ) {
    my $category = XML::Atom::Category->new( Version => 1 );
    $category->term( $tag );
    $atom_entry->add_category( $category );
}

# put a little bit of time between publish and update
sleep( 1 );
do_request( PUT => $u->atom_base . "/entries/1", authenticate => 1, data => { input => $atom_entry->as_xml } );
is( $r->status, $r->HTTP_OK, "Edited entry" );
is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

do_request( GET => $u->atom_base . "/entries/1", authenticate => 1 );
$atom_entry_server = XML::Atom::Entry->new( \ $r->response_content );
check_entry( $atom_entry_server, {
                id      => $entry_obj->jitemid,
                title   => $title,
                content => $content,
                atom_id => $entry_obj->atom_id,
                url     => $entry_obj->url,
                author  => $u->name_orig,
                categories => \@tags
             },
            $u );
ok( $atom_entry_server->published ne $atom_entry_server->updated, "different publish and edit date" );


$atom_entry_server->id( "123" );
do_request( PUT => $u->atom_base . "/entries/1", authenticate => 1, data => { input => $atom_entry_server->as_xml } );
is( $r->status, $r->HTTP_BAD_REQUEST, "Mismatched ids" );


do_request( DELETE => $u->atom_base . "/entries/1", authenticate => 1 );
is( $r->status, $r->HTTP_OK, "Deleted entry" );
$entry_obj = LJ::Entry->new( $u, jitemid => 1 );
isnt( $entry_obj->valid, "Entry confirmed deleted" );


do_request( PUT => $u->atom_base . "/entries/1", authenticate => 1 );
is( $r->status, $r->NOT_FOUND, "Trying to edit deleted entry" );


note( "Checking community functionality." );
{
    my $memberof_cu = temp_comm();
    my $nonmemberof_cu = temp_comm();
    $u->join_community( $memberof_cu, 1, 1 );

    my $another_u = temp_user(); # another member of the community
    $another_u->set_password( $pass );
    $another_u->join_community( $memberof_cu, 1, 1 );

    my $admin_u = temp_user();   # an administrator of the community
    $admin_u->set_password( $pass );
    $admin_u->join_community( $memberof_cu, 1, 1 );
    LJ::set_rel( $memberof_cu->userid, $admin_u->userid, "A" );


    note( "Service document introspection (community)." );
    # unauthenticated to community
    do_request( GET => $memberof_cu->atom_service_document );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "Service document protected by authorization." );

    # community you aren't a member of
    do_request( GET => $nonmemberof_cu->atom_service_document, authenticate => 1 );
    is( $r->status, $r->HTTP_OK, "Not a member of the community, but we still get the service document for the user (which doesn't contain the community)." );

    SKIP: {
        skip "No XML::Atom::Service/XML::Atom::Categories module installed.", 3
            unless eval "use XML::Atom::Service; use XML::Atom::Categories; 1;";

        my $service_document_xml = $r->response_content;

        my $service = XML::Atom::Service->new( \ $service_document_xml );
        ok( $service, "Got service document." );

        my @workspaces = $service->workspace;
        is( scalar @workspaces, 2, "One workspace" );
        isnt( $_->title, $nonmemberof_cu->user, "Community you're not a member of doesn't appear in the service document." ) foreach @workspaces;
    }


    # community you are a member of
    do_request( GET => $memberof_cu->atom_service_document, authenticate => 1 );
    is( $r->status, $r->HTTP_OK, "Got service document." );
    like( $r->content_type, qr#^\Qapplication/atomsvc+xml\E#, "Service content type" );

    SKIP: {
        skip "No XML::Atom::Service/XML::Atom::Categories module installed.", 8
            unless eval "use XML::Atom::Service; use XML::Atom::Categories; 1;";

        my $service_document_xml = $r->response_content;

        my $service = XML::Atom::Service->new( \ $service_document_xml );
        ok( $service, "Got service document." );

        my @workspaces = $service->workspace;
        is( scalar @workspaces, 2, "Personal journal and community as separate workspaces" );

        # making assumptions that the second workspace is our community
        my $memberof_cu_workspace = $workspaces[1];
        is( $memberof_cu_workspace->title, $memberof_cu->user, "Workspace title" );

        my @collections = $memberof_cu_workspace->collections;
        is( scalar @collections, 1, "One collection" );
        is( $collections[0]->title, "Entries", "Entries collection title" );
        is( $collections[0]->href, $memberof_cu->atom_base . "/entries", "Entries collection uri" );

        my @categories = $collections[0]->categories;
        is( scalar @categories, 1, "One categories link" );
        is( $categories[0]->href, $memberof_cu->atom_base . "/entries/tags", "Categories collection uri" );
    }


    note( "Create an entry (community)." );
    my $title = "Community entry";
    my $content = "Community entry content " . rand();
    my $atom_entry = XML::Atom::Entry->new( Version => 1 );
    $atom_entry->title( $title );
    $atom_entry->content( $content );

    # unauthenticated to community
    do_request( POST => $memberof_cu->atom_base . "/entries", data => { input => $atom_entry->as_xml } );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "Trying to post to community while unauthenticated." );

    # community you don't have posting access to
    do_request( POST => $nonmemberof_cu->atom_base . "/entries", authenticate => 1, data => { input => $atom_entry->as_xml } );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "Trying to post to community, but don't have posting access." );

    # community you have posting access to
    do_request( POST => $memberof_cu->atom_base . "/entries", authenticate => 1, data => { input => $atom_entry->as_xml } );
    is( $r->status, $r->HTTP_CREATED, "POSTed new entry" );
    is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

    note( "Double-check posted entry (community)." );
    $entry_obj = LJ::Entry->new( $memberof_cu, jitemid => 1 );
    ok( $entry_obj, "got entry" );
    ok( $entry_obj->valid, "entry is valid" );
    is( $entry_obj->subject_raw, $title, "item has right title" );
    is( $entry_obj->event_raw, $content, "item has right content" );

    $atom_entry_server = XML::Atom::Entry->new( \ $r->response_content );
    check_entry( $atom_entry_server, {
                id      => $entry_obj->jitemid,
                title   => $atom_entry_server->title,
                content => $atom_entry_server->content->body,
                url     => $entry_obj->url,
                author  => $u->name_orig,
             },
            $memberof_cu );


    note( "List entries (community)." );
    # unauthenticated to community
    do_request( GET => $memberof_cu->atom_base . "/entries" );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "Entries feed needs authorization." );

    # community you don't have posting access to
    do_request( GET => $nonmemberof_cu->atom_base . "/entries", authenticate => 1 );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "Entries feed needs authorization." );

    # community you have posting access to
    do_request( GET => $memberof_cu->atom_base . "/entries", authenticate => 1 );
    is( $r->status, $r->HTTP_OK, "Retrieved entry list" );
    is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

    my $feed = XML::Atom::Feed->new( \ $r->response_content );
    my @entries = $feed->entries;
    is( scalar @entries, 1, "Got entry from feed." );


    note( "Retrieve entry (community)" );
    # unauthenticated to community
    do_request( GET => $memberof_cu->atom_base . "/entries/1" );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "Retrieving entry needs authorization." );

    # community you don't have posting access to
    do_request( GET => $nonmemberof_cu->atom_base . "/entries/1", authenticate => 1 );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "Retrieving entry needs authorization." );


    # community you have posting access to
    # retrieve (should succeed)
    # edit (should succeed)
    # delete (should succeed)
    do_request( GET => $memberof_cu->atom_base . "/entries/1", authenticate => 1 );
    is( $r->status, $r->HTTP_OK, "Retrieved entry" );
    is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

    $atom_entry_server = XML::Atom::Entry->new( \ $r->response_content );
    check_entry( $atom_entry_server, {
                    id      => $entry_obj->jitemid,
                    title   => $entry_obj->subject_raw,
                    content => $entry_obj->event_raw,
                    atom_id => $entry_obj->atom_id,
                    url     => $entry_obj->url,
                    author  => $u->name_orig
                 },
                $memberof_cu );

    $atom_entry = XML::Atom::Entry->new( Version => 1 );
    $title = "Edited Post";
    $content = "Content of my post at " . rand();
    $atom_entry->id( $atom_entry_server->id );
    $atom_entry->title( $title );
    $atom_entry->content( $content );

    do_request( PUT => $memberof_cu->atom_base . "/entries/1", authenticate => 1, data => { input => $atom_entry->as_xml } );

    is( $r->status, $r->HTTP_OK, "Edited entry" );
    is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

    do_request( GET => $memberof_cu->atom_base . "/entries/1", authenticate => 1 );
    $atom_entry_server = XML::Atom::Entry->new( \ $r->response_content );
    check_entry( $atom_entry_server, {
                id      => $entry_obj->jitemid,
                title   => $title,
                content => $content,
                atom_id => $entry_obj->atom_id,
                url     => $entry_obj->url,
                author  => $u->name_orig,
             },
            $memberof_cu );


    do_request( DELETE => $memberof_cu->atom_base . "/entries/1", authenticate => 1 );
    is( $r->status, $r->HTTP_OK, "Deleted entry" );
    $entry_obj = LJ::Entry->new( $memberof_cu, jitemid => 1 );
    isnt( $entry_obj->valid, "Entry confirmed deleted" );


    note( "Check what other people can do." );
    # make another entry that other people can view/manipulate
    do_request( POST => $memberof_cu->atom_base . "/entries", authenticate => 1, data => { input => $atom_entry->as_xml } );
    $atom_entry_server = XML::Atom::Entry->new( \ $r->response_content );
    $atom_entry = XML::Atom::Entry->new( Version => 1 );
    $title = "Edited Post";
    $content = "Content of my post at " . rand();
    $atom_entry->id( $atom_entry_server->id );
    $atom_entry->title( $title );
    $atom_entry->content( $content );

    # another community member
    # retrieve (should fail)
    # edit (should fail)
    # delete (should fail)
    do_request( GET => $memberof_cu->atom_base . "/entries/2", authenticate => 1, remote => $another_u );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "You don't own this entry (another_u, get)" );

    do_request( PUT => $memberof_cu->atom_base . "/entries/2", authenticate => 1, remote => $another_u, data => { input => $atom_entry->as_xml } );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "You don't own this entry (another_u, edit)" );

    do_request( DELETE => $memberof_cu->atom_base . "/entries/2", authenticate => 1, remote => $another_u );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "You don't own this entry (another_u, delete)" );


    # community admin
    # retrieve (should succeed)
    # edit (should fail)
    # delete (should succeed)
    do_request( GET => $memberof_cu->atom_base . "/entries/2", authenticate => 1, remote => $admin_u );
    is( $r->status, $r->HTTP_OK, "Retrieved entry" );
    is( $r->content_type, "application/atom+xml", "AtomAPI entry content type" );

    do_request( PUT => $memberof_cu->atom_base . "/entries/2", authenticate => 1, remote => $admin_u, data => { input => $atom_entry->as_xml } );
    is( $r->status, $r->HTTP_UNAUTHORIZED, "You don't own this entry (admin_u, edit)" );

    do_request( DELETE => $memberof_cu->atom_base . "/entries/2", authenticate => 1, remote => $admin_u );
    is( $r->status, $r->HTTP_OK, "Deleted entry (admin_u, delete)" );
    $entry_obj = LJ::Entry->new( $memberof_cu, jitemid => 2 );
    isnt( $entry_obj->valid, "Entry confirmed deleted" );
}


done_testing();
