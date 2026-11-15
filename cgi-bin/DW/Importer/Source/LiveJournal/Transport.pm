#!/usr/bin/perl
#
# DW::Importer::Source::LiveJournal::Transport
#
# The real network access for the LiveJournal source adapter.
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

package DW::Importer::Source::LiveJournal::Transport;

=head1 NAME

DW::Importer::Source::LiveJournal::Transport - XML-RPC and HTTP for LiveJournal imports

=head1 DESCRIPTION

The source adapter (L<DW::Importer::Source::LiveJournal>) does no I/O of its own: it asks
its transport. This is the transport that talks to the real site. Tests, and anything
else that wants to replay or fake a site, provide an object with the same three methods
instead:

=over

=item C<< xmlrpc( $mode, $hash ) >>

Calls C<LJ.XMLRPC.$mode>, authenticated as the import's user, and returns the result
hashref, or C<< { fault => 1, faultString => '...' } >> if the call failed.

=item C<< get( $url, %agent_options ) >>

Fetches a page. Returns an L<HTTP::Response>.

=item C<< comment_export( $mode, $startid, $numitems, $log ) >>

Fetches one window of the comment export (C<$mode> is C<comment_meta> or
C<comment_body>) and returns its XML, or undef if it could not be fetched.

=back

A transport belongs to one job: it keeps the login session it makes for the comment
export.

=cut

use strict;
use warnings;

use Digest::MD5 qw( md5_hex );
use LWP::UserAgent;
use XMLRPC::Lite;

=head2 C<< DW::Importer::Source::LiveJournal::Transport->new( data => $import_data, [ dry_run => 1 ] ) >>

In a dry run the transport reads the comment export cache if there is one but never writes
it: a cache file made by a dry run would be trusted by the real import that follows.

=cut

sub new {
    my ( $class, %args ) = @_;
    return bless { data => $args{data}, dry_run => $args{dry_run} }, $class;
}

# XML-RPC ---------------------------------------------------------------------------

# runs the actual request and checks for errors, as well as handling the cases where
# we hit a problem and need to do something about it.  (abort or retry.)
sub _call_helper {
    my ( $self, $xmlrpc, $method, $req, $mode, $hash, $depth ) = @_;

    # bail if depth is 4, obviously something is going terribly wrong
    if ( $depth >= 4 ) {
        return {
            fault       => 1,
            faultString => 'Failed to connect to the server too many times.',
        };
    }

    # call out
    my $res;
    eval { $res = $xmlrpc->call( $method, $req ); };
    if ( $res && $res->fault ) {
        return {
            fault       => 1,
            faultString => $res->fault->{faultString} || 'Unknown error.',
        };
    }

    # Typically this is timeouts; but since we probably need a new challenge we have to
    # call the xmlrpc method to do the retry. However, if we're actually trying to
    # get a challenge we should call ourselves.
    unless ($res) {
        if ( $method eq 'LJ.XMLRPC.getchallenge' ) {
            return $self->_call_helper( $xmlrpc, $method, $req, $mode, $hash, $depth + 1 );
        }
        else {
            return $self->xmlrpc( $mode, $hash, $depth + 1 );
        }
    }

    return $res->result;
}

# does the challenge response stuff so we never send the user's password or md5 digest
# over the internet.
sub xmlrpc {
    my ( $self, $mode, $hash, $depth ) = @_;
    my $opts = $self->{data};
    $depth ||= 0;

    my $xmlrpc = XMLRPC::Lite->new;
    $xmlrpc->proxy(
        "https://" . ( $opts->{server} || $opts->{hostname} ) . "/interface/xmlrpc",
        agent    => "$LJ::SITENAME Content Importer ($LJ::ADMIN_EMAIL)",
        ssl_opts => {

            # TLS 1.3 handshakes hang under IO::Socket::SSL 2.098 + OpenSSL 3.0
            # due to session ticket handling (see openssl/openssl#7967). Force
            # TLS 1.2 as a workaround.
            SSL_version => 'TLSv1_2',
        },
    );

    my $chal;
    while ( !$chal ) {
        my $res =
            $self->_call_helper( $xmlrpc, 'LJ.XMLRPC.getchallenge', undef, undef, undef, $depth );
        if ( $res && $res->{fault} ) {
            return $res;
        }
        $chal = $res->{challenge};
    }

    my $response = md5_hex(
        $chal . ( $opts->{md5password} || $opts->{password_md5} || md5_hex( $opts->{password} ) ) );

    # we have to do this like this so that we don't send the argument if it's not valid
    my %usejournal;
    $usejournal{usejournal} = $opts->{usejournal} if $opts->{usejournal};

    return $self->_call_helper(
        $xmlrpc,
        "LJ.XMLRPC.$mode",
        {
            username       => $opts->{user} || $opts->{username},
            auth_method    => 'challenge',
            auth_challenge => $chal,
            auth_response  => $response,
            %usejournal,
            %{ $hash || {} },
        },
        $mode, $hash, $depth
    );
}

# HTTP ------------------------------------------------------------------------------

sub get {
    my ( $self, $url, %agent ) = @_;

    my $ua = LJ::get_useragent(%agent);
    return $ua->get($url);
}

# comment export --------------------------------------------------------------------

# a login session for the export pages, made once per job
sub session {
    my ($self) = @_;

    return $self->{session} if defined $self->{session};

    my $r = $self->xmlrpc( 'sessiongenerate', { expiration => 'short' } );
    return $self->{session} = ( $r && !$r->{fault} ) ? $r->{ljsession} : undef;
}

sub comment_export {
    my ( $self, $mode, $startid, $numitems, $log ) = @_;
    my $data   = $self->{data};
    my $authas = $data->{usejournal} ? "&authas=$data->{usejournal}" : '';
    my $url =
"https://www.$data->{hostname}/export_comments.bml?get=$mode&startid=$startid&numitems=$numitems&props=1$authas";

    # clear "request" cache of db handles to force revalidation, whenever fetching a block
    # of comments, to avoid possibly using one that was idle too long without testing it.
    $LJ::DBIRole->clear_req_cache();

    # see if the file is cached. the cache belongs to one import (import_data_id is part of the
    # key): retries of a job reuse what was already downloaded, which stops a stuck job from
    # hammering the target, but a new import always fetches fresh data.
    my $md5 =
        md5_hex( $url
            . ( $data->{user} || $data->{username} )
            . ( $data->{usejournal} || '' ) . '#'
            . ( $data->{import_data_id} // 0 ) );
    my $fn = "$LJ::HOME/logs/imports/$data->{userid}/$md5.xml";
    if ( open my $cache, '<', $fn ) {
        $log->( 'Using cached file %s.xml', $md5 );

        local $/ = undef;
        my $ret = <$cache>;
        close $cache;
        return $ret;
    }

    # hit up the server with the specified information and return the raw content.
    # don't auto-follow redirects: a successful export returns XML directly, so any
    # 3xx means we were bounced (typically to login.bml when the source rejects our
    # session) -- we want to see that explicitly rather than silently fetching the
    # login page and failing the is-it-XML check below.
    my $session = $self->session;
    my $ua      = LWP::UserAgent->new;
    $ua->max_redirect(0);
    my $request = HTTP::Request->new( GET => $url );
    $request->push_header( Cookie => "ljsession=$session" );

    # try to get the response
    my $response = $ua->request($request);

    # a redirect almost always means the source didn't accept our session and is
    # bouncing us to login -- log where it sent us so this is diagnosable from the logs.
    if ( $response->is_redirect ) {
        my $location = $response->header('Location') || '';
        $log->(
            'comment fetch (%s, startid=%d) from %s redirected: HTTP %s -> %s%s',
            $mode,
            $startid,
            $data->{hostname},
            $response->code,
            $location,
            ( $location =~ m!/login\.bml! ? ' (session not accepted)' : '' )
        );
        return undef;
    }

    # HTTP-level failure (4xx/5xx): log the status and any throttling hint so blocks
    # or rate-limiting on the bulk export endpoint are visible in the import logs.
    if ( $response->is_error ) {
        my $retry = $response->header('Retry-After') || '';
        $log->(
            'comment fetch (%s, startid=%d) from %s failed: HTTP %s %s%s', $mode,
            $startid,                                                      $data->{hostname},
            $response->code,                                               $response->message,
            ( length $retry ? " (Retry-After: $retry)" : '' )
        );
        return undef;
    }

    # now get the content, ensure it's actually XML
    my $xml = $response->content;
    if ( $xml && $xml =~ m!^<\?xml ! ) {
        if ( $self->{dry_run} ) {
            $log->( 'Not writing cache file %s.xml in a dry run', $md5 );
        }
        elsif ( open my $cache, '>', $fn ) {
            $log->( 'Writing cache file %s.xml', $md5 );
            print $cache $xml;
            close $cache or $log->( 'Could not finish cache file %s.xml: %s', $md5, $! );
        }
        else {
            $log->( 'Could not write cache file %s.xml: %s', $md5, $! );
        }
        return $xml;
    }

    # 2xx but the body isn't XML (e.g. an error or login page) -- log enough to tell
    # what came back instead of comment metadata.
    my $snippet = substr( $xml || '', 0, 200 );
    $snippet =~ s/\s+/ /g;
    $log->(
'comment fetch (%s, startid=%d) from %s returned non-XML: HTTP %s, ctype=%s, %d bytes; starts: %s',
        $mode,
        $startid,
        $data->{hostname},
        $response->code,
        $response->content_type || '?',
        length( $xml || '' ),
        $snippet
    );
    return undef;
}

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
