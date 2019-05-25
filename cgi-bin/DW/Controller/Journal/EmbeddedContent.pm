#!/usr/bin/perl
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2014 by Dreamwidth Studios, LLC.

package DW::Controller::EmbeddedContent;

use strict;
use DW::Controller;
use DW::Routing;

use LJ::Auth;
use LJ::EmbedModule;

=head1 NAME

DW::Controller::EmbeddedContent - Show embedded content in an iframe

=cut

DW::Routing->register_string( "/journal/embedcontent", \&embedcontent_handler, app => 1 );

sub embedcontent_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1, skip_domsess => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    my $print = sub {
        $r->print( $_[0] );
        return $r->OK;
    };

    # this can only be accessed from the embed module subdomain
    return $print->("This page cannot be viewed from $LJ::DOMAIN")
        unless $r->header_in("Host") =~ /.*$LJ::EMBED_MODULE_DOMAIN$/i;

    # we should have three GET params: journalid, moduleid, auth_token
    my $get       = $r->get_args;
    my $journalid = $get->{journalid} + 0 or return $print->("No journalid specified");

    my $moduleid = $get->{moduleid};
    return $print->("No module id specified") unless defined $moduleid;
    $moduleid += 0;

    my $preview = $get->{preview};

    return $print->("Invalid auth string")
        unless LJ::Auth->check_sessionless_auth_token( 'embedcontent', %$get );

    # ok we're cool, return content
    my $content = LJ::EmbedModule->module_content(
        journalid          => $journalid,
        moduleid           => $moduleid,
        preview            => $preview,
        display_as_content => 1,
    )->{content};

    $r->print(
qq{<html><head><style type="text/css">html, body { background-color:transparent; padding:0; margin:0; border:0; overflow:hidden; } iframe, object, embed { width: 100%; height: 100%;}</style></head><body>$content</body></html>}
    );
    return $r->OK;
}

1;
