#!/usr/bin/perl
#
# Plack::Middleware::DW::ConcatRes
#
# Handles concatenated static resource requests (CSS/JS combo handler).
# URLs like /stc/css/??a.css,b.css?v=123 get multiple files concatenated
# into a single response.
#
# Ported from Apache::LiveJournal::send_concat_res_response.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::ConcatRes;

use strict;
use v5.10;

use parent qw/ Plack::Middleware /;

use Fcntl ':mode';
use HTTP::Date qw/ time2str /;

sub call {
    my ( $self, $env ) = @_;

    my $query = $env->{QUERY_STRING} // '';

    # Concat requests have a query string starting with '?' (making the URL ??...)
    return $self->app->($env)
        unless $query =~ /^\?/;

    my $uri     = $env->{PATH_INFO};
    my $docroot = $LJ::STATDOCS // $LJ::HTDOCS;
    my $dir     = $docroot . $uri;
    my $maxdir  = $docroot . '/max' . $uri;

    return _404()
        unless -d $dir || -d $maxdir;

    # Strip cache buster ?v=... suffix
    $query =~ s/\?v=.*$//;

    # Collect each file
    my ( $body, $size, $mtime, $mime ) = ( '', 0, 0, undef );
    foreach my $file ( split /,/, substr( $query, 1 ) ) {
        my $res = _load_file("$dir$file") // _load_file("$maxdir$file");
        return _404()
            unless defined $res;

        $body .= $res->[0];
        $size += $res->[1];
        $mtime = $res->[2]
            if $res->[2] > $mtime;
        $mime //= $res->[3];

        # Reject mixed file types
        return _404()
            if $mime ne $res->[3];
    }

    return _404()
        unless $body;

    my @headers = (
        'Content-Type'   => $mime,
        'Content-Length' => $size,
        'Last-Modified'  => time2str($mtime),
    );

    # Support HEAD requests
    my $response_body = $env->{REQUEST_METHOD} eq 'HEAD' ? '' : $body;

    return [ 200, \@headers, [$response_body] ];
}

sub _404 {
    return [ 404, [ 'Content-Type' => 'text/plain' ], ['Not Found'] ];
}

sub _load_file {
    my $fn = $_[0];

    # No path traversal
    return undef if $fn =~ /\.\./;

    # Specific types only
    my $mime;
    if ( $fn =~ /\.([a-z]+)$/ ) {
        $mime = {
            css => 'text/css; charset=utf-8',
            js  => 'application/javascript; charset=utf-8',
        }->{$1};
    }
    return undef unless $mime;

    # Verify exists and is regular file
    my @stat = stat($fn);
    return undef
        unless scalar @stat > 0
        && S_ISREG( $stat[2] );

    my $contents;
    open my $fh, '<', $fn
        or return undef;
    { local $/ = undef; $contents = <$fh>; }
    close $fh;

    # Remove UTF-8 byte-order mark
    $contents =~ s/\A\x{ef}\x{bb}\x{bf}//;

    # Add a newline for safety
    $contents .= "\n";

    my $size = length($contents);

    return [ $contents, $size, $stat[9], $mime ];
}

1;
