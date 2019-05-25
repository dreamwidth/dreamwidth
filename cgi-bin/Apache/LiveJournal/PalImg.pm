#!/usr/bin/perl
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

package Apache::LiveJournal::PalImg;

use strict;
use Apache2::Const qw(:common REDIRECT HTTP_NOT_MODIFIED);
use PaletteModify;

# for callers to 'ping' as a class method for Class::Autouse to lazily load
sub load { 1 }

# URLs of form /palimg/somedir/file.gif[extra]
# where extras can be:
#   /p...    - palette modify

sub handler {
    my $apache_r = shift;
    my $uri      = $apache_r->uri;

    my ( $base, $ext, $extra ) = $uri =~ m!^/palimg/(.+)\.(\w+)(.*)$!;
    $apache_r->notes->{codepath} = "img.palimg";
    return 404 unless $base && $base !~ m!\.\.!;

    my $disk_file = "$LJ::HTDOCS/palimg/$base.$ext";
    return 404 unless -e $disk_file;

    my @st      = stat(_);
    my $size    = $st[7];
    my $modtime = $st[9];
    my $etag    = "$modtime-$size";

    my $mime = {
        'gif' => 'image/gif',
        'png' => 'image/png',
    }->{$ext};

    my $palspec;
    if ($extra) {
        if ( $extra =~ m!^/p(.+)$! ) {
            $palspec = $1;
        }
        else {
            return 404;
        }
    }

    return send_file(
        $apache_r,
        $disk_file,
        {
            'mime'    => $mime,
            'etag'    => $etag,
            'palspec' => $palspec,
            'size'    => $size,
            'modtime' => $modtime,
        }
    );
}

sub parse_hex_color {
    my $color = shift;
    return [ map { hex( substr( $color, $_, 2 ) ) } ( 0, 2, 4 ) ];
}

sub send_file {
    my ( $apache_r, $disk_file, $opts ) = @_;

    my $etag = $opts->{'etag'};

    # palette altering
    my %pal_colors;
    if ( my $pals = $opts->{'palspec'} ) {
        my $hx = "[0-9a-f]";
        if ( $pals =~ /^g($hx{2,2})($hx{6,6})($hx{2,2})($hx{6,6})$/ ) {

            # gradient from index $1, color $2, to index $3, color $4
            my $from = hex($1);
            my $to   = hex($3);
            return 404 if $from == $to;
            my $fcolor = parse_hex_color($2);
            my $tcolor = parse_hex_color($4);
            if ( $to < $from ) {
                ( $from, $to, $fcolor, $tcolor ) = ( $to, $from, $tcolor, $fcolor );
            }
            $etag .= ":pg$pals";
            for ( my $i = $from ; $i <= $to ; $i++ ) {
                $pal_colors{$i} = [
                    map {
                        int( $fcolor->[$_] +
                                ( $tcolor->[$_] - $fcolor->[$_] ) *
                                ( $i - $from ) /
                                ( $to - $from ) )
                    } ( 0 .. 2 )
                ];
            }
        }
        elsif ( $pals =~ /^t($hx{6,6})($hx{6,6})?$/ ) {

            # tint everything towards color
            my ( $t, $td ) = ( $1, $2 );
            $pal_colors{'tint'}      = parse_hex_color($t);
            $pal_colors{'tint_dark'} = $td ? parse_hex_color($td) : [ 0, 0, 0 ];
        }
        elsif ( length($pals) > 42 || $pals =~ /[^0-9a-f]/ ) {
            return 404;
        }
        else {
            my $len = length($pals);
            return 404 if $len % 7;    # must be multiple of 7 chars
            for ( my $i = 0 ; $i < $len / 7 ; $i++ ) {
                my $palindex = hex( substr( $pals, $i * 7, 1 ) );
                $pal_colors{$palindex} = [
                    hex( substr( $pals, $i * 7 + 1, 2 ) ),
                    hex( substr( $pals, $i * 7 + 3, 2 ) ),
                    hex( substr( $pals, $i * 7 + 5, 2 ) ),
                    substr( $pals, $i * 7 + 1, 6 ),
                ];
            }
            $etag .= ":p$_($pal_colors{$_}->[3])" for ( sort keys %pal_colors );
        }
    }

    $etag = '"' . $etag . '"';
    my $ifnonematch = $apache_r->headers_in->{'If-None-Match'};
    return HTTP_NOT_MODIFIED
        if defined $ifnonematch && $etag eq $ifnonematch;

    # send the file
    $apache_r->content_type( $opts->{'mime'} );
    $apache_r->headers_out->{'Content-length'} = $opts->{'size'};
    $apache_r->headers_out->{ETag}             = $etag;
    if ( $opts->{'modtime'} ) {
        $apache_r->update_mtime( $opts->{'modtime'} );
        $apache_r->set_last_modified();
    }

    # HEAD request?
    return OK if $apache_r->method eq "HEAD";

    open my ($fh), $disk_file;
    return 404 unless $fh;

    binmode($fh);

    my $palette;
    if (%pal_colors) {
        if ( $opts->{'mime'} eq "image/gif" ) {
            $palette = PaletteModify::new_gif_palette( $fh, \%pal_colors );
        }
        elsif ( $opts->{'mime'} == "image/png" ) {
            $palette = PaletteModify::new_png_palette( $fh, \%pal_colors );
        }
        unless ($palette) {
            return 404;    # image isn't palette changeable?
        }
    }

    $apache_r->print($palette) if $palette;    # when palette modified.

    # now read the rest of the file, but let's max on a 1MB image for sanity
    read $fh, my $buf, 1024 * 1024;
    $apache_r->print($buf) if $buf;

    $fh->close();
    return OK;
}

1;

