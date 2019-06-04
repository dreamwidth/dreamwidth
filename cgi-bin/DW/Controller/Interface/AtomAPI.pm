#!/usr/bin/perl
#
# DW::Controller::Interface::AtomAPI
#
# This controller is for the Atom Publishing Protocol interface
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Interface::AtomAPI;

use strict;
use DW::Routing;
use LJ::ParseFeed;

use XML::Atom::Entry;
use XML::Atom::Category;
use Digest::SHA1;
use MIME::Base64;

use HTTP::Status qw( :constants );

use LJ::Protocol;

use DW::Auth;

# service document URL is the same for all users
DW::Routing->register_string(
    "/interface/atom", \&service_document,
    app     => 1,
    format  => "atom",
    methods => { GET => 1 }
);

# note: safe to put these pages in the user subdomain even if they modify data
# because we don't use cookies (so even if a user's cookies are stolen...)
DW::Routing->register_string(
    "/interface/atom/entries", \&entries_handler,
    user    => 1,
    format  => "atom",
    methods => { POST => 1, GET => 1 }
);
DW::Routing->register_string(
    "/interface/atom/entries/tags", \&categories_document,
    user    => 1,
    format  => "atom",
    methods => { GET => 1 }
);
DW::Routing->register_regex(
    qr#^/interface/atom/entries/(\d+)$#, \&entry_handler,
    user    => 1,
    format  => "atom",
    methods => { GET => 1, PUT => 1, DELETE => 1 }
);

sub ok {
    my ( $message, $status, $content_type ) = @_;

    my $r = DW::Request->get;
    $r->status( $status || HTTP_OK );
    $r->content_type( $content_type || "application/atom+xml" );

    $r->print($message);

    return $r->OK;
}

sub err {
    my ( $message, $status ) = @_;

    my $r = DW::Request->get;
    $r->status( $status || HTTP_NOT_FOUND );
    $r->content_type('text/plain');

    $r->print($message);

    return $r->OK;
}

sub check_enabled {
    return ( 0, err ("This server does not support the Atom API.") )
        unless LJ::ModuleCheck->have_xmlatom;

    return (1);
}

sub authenticate {
    my (%opts) = @_;
    my $r = DW::Request->get;

    my ($remote) = DW::Auth->authenticate(
        wsse   => { allow_duplicate_nonce => $opts{allow_duplicate_nonce} || 0 },
        digest => 1
    );
    my $u = LJ::load_user( $opts{journal} ) || $remote;

    return ( 0, err ( "Authentication failed for this AtomAPI request.", $r->HTTP_UNAUTHORIZED ) )
        if !$remote;

    return (
        0,
            err
            (
            "User $remote->{user} has no posting access to account $u->{user}.",
            $r->HTTP_UNAUTHORIZED
            )
    ) if !$remote->can_post_to($u);

    return ( 1, { u => $u, remote => $remote } );
}

sub _create_workspace {
    my ($u) = @_;

    my $atom_base = $u->atom_base;
    my $title     = LJ::exml( $u->prop("journaltitle") || $u->user );

    my $ret = qq{
    <workspace>
    <atom:title>$title</atom:title>
    };

    # entries
    $ret .= qq{<collection href="$atom_base/entries">
    <atom:title>Entries</atom:title>
    <accept>application/atom+xml;type=entry</accept>
    <categories href="$atom_base/entries/tags" />
    </collection>
    };

    # add media, etc collections when available

    $ret .= "</workspace>";

    return $ret;
}

sub service_document {
    my ($call_info) = @_;

    my ( $ok, $rv ) = check_enabled();
    return $rv unless $ok;

    # detect the user's journal based on the account they log in as
    # not based on the journal subdomain they are currently trying to view
    # (since we're not on a subdomain)
    ( $ok, $rv ) = authenticate();
    return $rv unless $ok;

    my $r = DW::Request->get;

    # FIXME: use XML::Atom::Service?
    my $ret = qq{<?xml version="1.0"?>};
    $ret .=
        qq{<service xmlns="http://www.w3.org/2007/app" xmlns:atom="http://www.w3.org/2005/Atom">};

    $ret .= _create_workspace( $rv->{u} );

    my @comms = $rv->{u}->posting_access_list;
    $ret .= _create_workspace($_) foreach @comms;

    $ret .= "</service>";

    return ok( $ret, $r->OK, "application/atomsvc+xml; charset=utf-8" );
}

sub categories_document {
    my ($call_info) = @_;

    my ( $ok, $rv ) = check_enabled();
    return $rv unless $ok;

    ( $ok, $rv ) = authenticate( journal => $call_info->username );
    return $rv unless $ok;

    my $u      = $rv->{u};
    my $remote = $rv->{remote};

    my $r = DW::Request->get;

    my $ret = qq{<?xml version="1.0"?>};
    $ret .=
qq{<categories xmlns="http://www.w3.org/2007/app" xmlns:atom="http://www.w3.org/2005/Atom">};

    my $tags = LJ::Tags::get_usertags( $u, { remote => $remote } ) || {};
    foreach ( sort { $a->{name} cmp $b->{name} } values %$tags ) {
        my $name = LJ::exml( $_->{name} );
        $ret .= qq{<atom:category term="$name" />};
    }

    $ret .= '</categories>';

    return ok( $ret, $r->OK, "application/atomcat+xml; charset=utf-8" );
}

sub entries_handler {
    my ($call_info) = @_;

    my ( $ok, $rv ) = check_enabled();
    return $rv unless $ok;

    ( $ok, $rv ) = authenticate( allow_duplicate_nonce => 1, journal => $call_info->username );
    return $rv unless $ok;

    my $r = DW::Request->get;
    return _create_entry(%$rv) if $r->method eq "POST";
    return _list_entries(%$rv) if $r->method eq "GET";
}

sub _create_entry {
    my (%opts) = @_;
    my $u      = $opts{u};
    my $remote = $opts{remote};

    my $r = DW::Request->get;

    my ( $buff, $len, $entry );

    unless ($buff) {

        # check length
        $len = $r->header_in("Content-length");
        return err ( "Content is too long", $r->HTTP_BAD_REQUEST )
            if $len > $LJ::MAX_ATOM_UPLOAD;

        # read the content
        $r->read( $buff, $len );
    }

    # try parsing
    eval { $entry = XML::Atom::Entry->new( \$buff ); };
    return err ("Could not parse the entry due to invalid markup.\n\n $@")
        if $@;

    # remove the SvUTF8 flag. See same code in LJ::SynSuck for
    # an explanation
    $entry->title( LJ::no_utf8_flag( $entry->title ) );
    $entry->link( LJ::no_utf8_flag( $entry->link ) );
    $entry->content( LJ::no_utf8_flag( $entry->content->body ) )
        if $entry->content;

    # extract the list of tags from the provided categories
    my @tags = map { LJ::no_utf8_flag( $_->term ) } $entry->category;

    # post to the protocol
    # we ignore some things provided by the user,
    # such as the entry id, and the update time
    # FIXME: use an XML::Atom extension to add security options
    my $req = {
        ver         => 1,
        username    => $remote->user,
        usejournal  => !$remote->equals($u) ? $u->user : undef,
        lineendings => 'unix',
        subject     => $entry->title,
        event       => $entry->content->body,
        props       => { taglist => \@tags, },
        tz          => 'guess',
    };

    $req->{props}->{interface} = "atom";

    my $err;
    my $res = LJ::Protocol::do_request( "postevent", $req, \$err, { noauth => 1 } );
    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return err ( "Unable to post new entry. Protocol error: $errstr", $r->HTTP_SERVER_ERROR );
    }

    my $entry_obj  = LJ::Entry->new( $u, jitemid => $res->{itemid} );
    my $atom_reply = $entry_obj->atom_entry( apilinks => 1, synlevel => 'full' );

    $r->header_out( "Location", $entry_obj->atom_url );
    return ok( $atom_reply->as_xml, $r->HTTP_CREATED );
}

sub _list_entries {
    my (%opts) = @_;
    my $u      = $opts{u};
    my $remote = $opts{remote};

    my $r = DW::Request->get;

    # simulate a call to the S1 data view creator, with appropriate options
    my %op = (
        pathextra => "/atom",
        apilinks  => 1,
    );
    my $ret = LJ::Feed::make_feed( $r, $u, $remote, \%op );

    unless ( defined $ret ) {
        if ( $op{redir} ) {

            # this happens if the account was renamed or a syn account.
            # the redir URL is wrong because LJ::Feed is too
            # dataview-specific. Since this is an admin interface, we can
            # just fail.
            return err
                (
qq{The account "$u->{user}" is of a wrong type and does not allow AtomAPI administration.},
                $r->NOT_FOUND
                );
        }
        if ( $op{handler_return} ) {

            # this could be a conditional GET shortcut, honor it
            $r->status( $op{handler_return} );
            return $r->OK;
        }

        # should never get here
        return err ( "Unknown error", $r->NOT_FOUND );
    }

    return ok($ret);
}

sub entry_handler {
    my ( $call_info, $jitemid ) = @_;

    my ( $ok, $rv ) = check_enabled();
    return $rv unless $ok;

    ( $ok, $rv ) = authenticate( journal => $call_info->username, allow_duplicate_nonce => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;

    my $u      = $rv->{u};
    my $remote = $rv->{remote};

    $jitemid = int( $jitemid || 0 );

    my $req = {
        ver        => 1,
        username   => $remote->user,
        usejournal => !$remote->equals($u) ? $u->user : undef,
        itemid     => $jitemid,
        selecttype => 'one'
    };

    my $err;
    my $olditem = LJ::Protocol::do_request( "getevents", $req, \$err, { noauth => 1 } );

    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return err
            ( "Unable to retrieve the item requested for editing. Protocol error: $errstr",
            $r->NOT_FOUND );
    }

    return err ( "No entry found.", $r->NOT_FOUND )
        unless scalar @{ $olditem->{events} };

    my $entry_obj = LJ::Entry->new( $u, jitemid => $jitemid );
    return err ( "You aren't authorize to view this entry.", $r->HTTP_UNAUTHORIZED )
        unless $entry_obj && $entry_obj->visible_to($remote);

    return _retrieve_entry( %$rv, item => $olditem->{events}->[0], entry_obj => $entry_obj )
        if $r->method eq "GET";
    return _edit_entry( %$rv, item => $olditem->{events}->[0], entry_obj => $entry_obj )
        if $r->method eq "PUT";
    return _delete_entry( %$rv, item => $olditem->{events}->[0], entry_obj => $entry_obj )
        if $r->method eq "DELETE";
}

sub _retrieve_entry {
    my (%opts) = @_;

    my $u       = $opts{u};
    my $remote  = $opts{remote};
    my $olditem = $opts{item};
    my $e       = $opts{entry_obj};

    my $r = DW::Request->get;

    return ( 0, err ( "You aren't authorized to retrieve this entry.", $r->HTTP_UNAUTHORIZED ) )
        unless $e->poster->equals($remote) || $remote->can_manage($u);

    return ok( $e->atom_entry( apilinks => 1, synlevel => 'full' )->as_xml, );
}

# Perhaps check If-Match and If-Unmodified-Since?
sub _edit_entry {
    my (%opts) = @_;

    my $u         = $opts{u};
    my $remote    = $opts{remote};
    my $olditem   = $opts{item};
    my $entry_obj = $opts{entry_obj};

    my $r = DW::Request->get;

    return ( 0, err ( "You aren't authorized to edit this entry.", $r->HTTP_UNAUTHORIZED ) )
        unless $entry_obj->poster->equals($remote);

    return ( 0, err ( "Can't edit entry: journal is readonly.", $r->BAD_REQUEST ) )
        if $u->is_readonly || $remote->is_readonly;

    my ( $buff, $len, $atom_entry );

    unless ($buff) {

        # check length
        $len = $r->header_in("Content-length");
        return err ( "Content is too long", $r->HTTP_BAD_REQUEST )
            if $len > $LJ::MAX_ATOM_UPLOAD;

        # read the content
        $r->read( $buff, $len );
    }

    # try parsing
    eval { $atom_entry = XML::Atom::Entry->new( \$buff ); };
    return err ("Could not parse the entry due to invalid markup.\n\n $@")
        if $@;

    # the AtomEntry must include <id> which must match the one we sent
    # on GET

    return err ( "Incorrect id field for entry in this request.", $r->HTTP_BAD_REQUEST )
        unless $atom_entry->id eq $entry_obj->atom_id;

    # remove the SvUTF8 flag. See same code in LJ::SynSuck for
    # an explanation
    $atom_entry->title( LJ::no_utf8_flag( $atom_entry->title ) );
    $atom_entry->link( LJ::no_utf8_flag( $atom_entry->link ) );
    $atom_entry->content( LJ::no_utf8_flag( $atom_entry->content->body ) )
        if $atom_entry->content;

    # extract the list of tags from the provided categories
    my @tags = map { LJ::no_utf8_flag( $_->term ) } $atom_entry->category;

    # build an edit event request. Preserve fields that aren't being
    # changed by this item (perhaps the AtomEntry isn't carrying the
    # complete information).

    my $props = $olditem->{props};
    delete $props->{revnum};
    delete $props->{revtime};
    $props->{taglist} = join( ", ", @tags ) if @tags;

    my $req = {
        ver         => 1,
        username    => $remote->user,
        usejournal  => !$remote->equals($u) ? $u->user : undef,
        itemid      => $olditem->{itemid},
        lineendings => 'unix',
        subject     => $atom_entry->title || $olditem->{subject},
        event       => $atom_entry->content->body || $olditem->{event},
        props       => $props,
        security    => $olditem->{security},
        allowmask   => $olditem->{allowmask},
    };

    my $err = undef;
    my $res = LJ::Protocol::do_request( "editevent", $req, \$err, { noauth => 1 } );
    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return err ( "Unable to edit entry. Protocol error: $errstr", $r->HTTP_SERVER_ERROR );
    }

    return ok( "The entry was succesfully updated.", $r->OK );
}

sub _delete_entry {

    # build an edit event request to delete the entry.
    my (%opts) = @_;

    my $u         = $opts{u};
    my $remote    = $opts{remote};
    my $olditem   = $opts{item};
    my $entry_obj = $opts{entry_obj};

    my $r = DW::Request->get;

    return ( 0, err ( "You aren't authorized to delete this entry.", $r->HTTP_UNAUTHORIZED ) )
        unless $entry_obj->poster->equals($remote) || $remote->can_manage($u);

    my $req = {
        usejournal  => !$remote->equals($u) ? $u->user : undef,
        ver         => 1,
        username    => $remote->user,
        itemid      => $olditem->{itemid},
        lineendings => 'unix',
        event       => '',
    };

    my $err = undef;
    my $res = LJ::Protocol::do_request( "editevent", $req, \$err, { noauth => 1 } );

    if ($err) {
        my $errstr = LJ::Protocol::error_message($err);
        return err ( "Unable to delete entry. Protocol error: $errstr", $r->HTTP_SERVER_ERROR );
    }

    return ok( "Entry was succesfully deleted.", $r->OK );
}

# old URL format, retaining for compatibility with old simple clients like LoudTwitter, which don't support service discovery
DW::Routing->register_string(
    "/interface/atom/post", \&post_entry_compat,
    app    => 1,
    format => "atom"
);

sub post_entry_compat {
    my ($call_info) = @_;

    my ( $ok, $rv ) = check_enabled();
    return $rv unless $ok;

    ( $ok, $rv ) = authenticate( allow_duplicate_nonce => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;
    return _create_entry(%$rv) if $r->method eq "POST";
    return ok("The method at this URL is deprecated. Use the service document URL, "
            . $rv->{u}->atom_service_document
            . ",  when setting up your client." )
        if $r->method eq "GET";

    return err ( "URI scheme /interface/atom/entries is incompatible with " . $r->method );
}

1;
