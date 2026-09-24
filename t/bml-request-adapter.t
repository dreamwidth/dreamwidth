#!/usr/bin/perl
# Regression coverage for DW::BML::RequestAdapter's class name, isa, and
# method surface after its move out of DW::BML.pm into its own file
# (cgi-bin/DW/BML/RequestAdapter.pm). No behavior change is intended by
# that move; this proves it against a real DW::Request under test_psgi.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use Test::More;
use HTTP::Request::Common qw(GET);
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::BML::RequestAdapter;
use DW::Request;
use DW::Request::Plack;

test_psgi(
    app => sub {
        my $env = shift;
        DW::Request->reset;
        my $r = DW::Request->get( plack_env => $env );

        my $adapter = DW::BML::RequestAdapter->new($r);

        is( ref $adapter, 'DW::BML::RequestAdapter', 'new() returns the exact class name' );
        isa_ok( $adapter, 'DW::BML::RequestAdapter' );

        is( $adapter->uri, '/bml-request-adapter-marker', 'uri delegates to DW::Request::uri' );

        is( $adapter->connection->client_ip,
            $r->get_remote_ip, 'connection->client_ip delegates to DW::Request::get_remote_ip' );

        # headers_in: tied-hash FETCH reads through DW::Request::header_in
        is( $adapter->headers_in->{'X-Test-Header'},
            'incoming-value', 'headers_in FETCH reads the real incoming request header' );

        # notes: tied-hash STORE/FETCH round-trips through DW::Request::note
        $adapter->notes->{adapter_note_key} = 'adapter-note-value';
        is( $r->note('adapter_note_key'),
            'adapter-note-value', 'notes STORE writes through to the real DW::Request note' );
        is( $adapter->notes->{adapter_note_key},
            'adapter-note-value', 'notes FETCH reads back the same value' );

        # headers_out: tied-hash STORE/FETCH round-trips through DW::Request::header_out
        $adapter->headers_out->{'X-Adapter-Out'} = 'adapter-out-value';
        is( $r->header_out('X-Adapter-Out'),
            'adapter-out-value',
            'headers_out STORE writes through to the real DW::Request header_out' );
        is( $adapter->headers_out->{'X-Adapter-Out'},
            'adapter-out-value', 'headers_out FETCH reads back the same value' );

        # err_headers_out: ->add() writes through the same header_out path
        $adapter->err_headers_out->add( 'X-Adapter-Err', 'adapter-err-value' );
        is( $r->header_out('X-Adapter-Err'),
            'adapter-err-value',
            'err_headers_out->add writes through to the real DW::Request header_out' );

        is( $adapter->status(202), 202, 'status(val) sets and returns the status' );
        is( $r->status,            202, 'status(val) writes through to the real DW::Request' );
        is( $adapter->status,      202, 'status() with no args reads back the same status' );

        $adapter->content_type('text/x-adapter-test');

        is( $adapter->OK,        0,   'OK constant is 0' );
        is( $adapter->NOT_FOUND, 404, 'NOT_FOUND constant is 404' );

        $adapter->print('adapter print output');

        # Finalize through the real DW::Request, exactly as production code
        # does, so print()/status()/content_type() are all verified
        # end-to-end via the actual PSGI response below.
        return $r->res;
    },
    client => sub {
        my $cb  = shift;
        my $res = $cb->( GET '/bml-request-adapter-marker', 'X-Test-Header' => 'incoming-value' );
        is( $res->code, 202, 'status(val) reaches the real finalized response' );
        is( $res->content_type, 'text/x-adapter-test',
            'content_type(val) reaches the real finalized response' );
        is(
            $res->content,
            'adapter print output',
            'print() writes through to the real DW::Request response body'
        );
    },
);
DW::Request->reset;

done_testing;
