#!/usr/bin/perl
#
# DW::Controller::RPC::CutExpander
#
# AJAX endpoint that returns the expanded text for a cut tag.
#
# Author:
#      Allen Petersen
#
# Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::RPC::CutExpander;

use strict;
use DW::Routing;
use LJ::JSON;

DW::Routing->register_rpc( "cuttag", \&cutexpander_handler, format => 'json' );

sub cutexpander_handler {
    my $opts = shift;

    # gets the request and args
    my $r    = DW::Request->get;
    my $args = $r->get_args;

    my $remote = LJ::get_remote();

    # error handler
    my $error_out = sub {
        my ( $code, $message ) = @_;
        $r->status($code);
        $r->print( to_json( { error => $message } ) );

        return $r->OK;
    };

    if ( $args->{ditemid} && $args->{journal} && $args->{cutid} ) {

        # all parameters are included; get the entry.
        my $ditemid = $args->{ditemid};
        my $uid     = LJ::get_userid( $args->{journal} );
        my $entry   = $uid ? LJ::Entry->new( $uid, ditemid => $ditemid ) : undef;

        # FIXME: This returns 200 due to old library, Make return proper when we are jQuery only.
        return $error_out->( 200, BML::ml("error.nopermission") ) unless $entry;

        # make sure the user can read the entry
        if ( $entry->visible_to($remote) ) {
            my $text = load_cuttext( $entry, $remote, $args->{cutid} );

            # FIXME: temporary fix.
            # remove some unicode characters that could cause the returned JSON to break
            # like in LJ::ejs, but we don't need to escape quotes, etc (to_json does that)
            $text =~ s/\xE2\x80[\xA8\xA9]//gs;
            $r->print( to_json( { text => $text } ) );
            return $r->OK;
        }
    }

    # FIXME: This returns 200 due to old library, Make return proper when we are jQuery only.
    return $error_out->( 200, BML::ml("error.nopermission") );
}

# loads the cutttext for the given entry
sub load_cuttext {
    my ( $entry_obj, $remote, $cutid ) = @_;

    # most of this is taken from S2->Entry_from_entryobj, modified for this
    # more limited purpose.
    my $get     = {};
    my $subject = "";

    my $anum    = $entry_obj->anum;
    my $jitemid = $entry_obj->jitemid;
    my $ditemid = $entry_obj->ditemid;

    # $journal: journal posted to
    my $journalid = $entry_obj->journalid;
    my $journal   = LJ::load_userid($journalid);

    #load and prepare text of entry
    my $text = LJ::CleanHTML::quote_html( $entry_obj->event_raw, $get->{nohtml} );
    LJ::item_toutf8( $journal, \$subject, \$text ) if $entry_obj->props->{unknown8bit};

    my $suspend_msg    = $entry_obj && $entry_obj->should_show_suspend_msg_to($remote) ? 1 : 0;
    my $cleanhtml_opts = {
        cuturl              => $entry_obj->url,
        journal             => $journal->username,
        ditemid             => $ditemid,
        suspend_msg         => $suspend_msg,
        unsuspend_supportid => $suspend_msg ? $entry_obj->prop('unsuspend_supportid') : 0,
        preformatted        => $entry_obj->prop("opt_preformatted"),
        cut_retrieve        => $cutid,
    };

    LJ::CleanHTML::clean_event( \$text, $cleanhtml_opts );

    LJ::expand_embedded( $journal, $jitemid, $remote, \$text );

    return $text;
}

1;
