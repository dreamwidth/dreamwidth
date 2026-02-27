#!/usr/bin/perl
#
# DW::Controller::PalImg
#
# Serves palette-modified images. Replaces Apache::LiveJournal::PalImg for use
# under both Plack and mod_perl via DW::Routing.
#
# URLs of form /palimg/somedir/file.gif[/pSPEC] where SPEC can be:
#   gFFCOLORTTCOLOR  - gradient from palette index FF to TT
#   tCOLOR[DARK]     - tint towards COLOR (optional dark tint)
#   IRRGGBB...       - set specific palette indices (I=index, RRGGBB=color)
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

package DW::Controller::PalImg;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Request;
use DW::Routing;
use PaletteModify;

DW::Routing->register_regex(
    qr!^/palimg/(.+)$!, \&palimg_handler,
    app     => 1,
    formats => 1,
);

sub palimg_handler {
    my ($opts) = @_;
    my $r = DW::Request->get;

    # DW::Routing strips file extensions as "formats" when the URL ends with .ext.
    # For plain images like /palimg/solid.png, we get subpattern="solid" and format="png".
    # For palette URLs like /palimg/solid.png/pSPEC, the extension is NOT stripped
    # because the URL doesn't end with .ext, so we parse it from the subpattern.
    my ($rest) = @{ $opts->subpatterns };
    my ( $base, $ext, $extra );

    my $format = $opts->format;
    if ( $format && $format =~ /^(gif|png)$/ ) {

        # Extension was stripped by routing
        $ext   = $format;
        $base  = $rest;
        $extra = '';
    }
    else {
        # Extension still in the path — parse it out
        ( $base, $ext, $extra ) = $rest =~ m!^(.+)\.(gif|png)(.*)$!;
    }

    return $r->NOT_FOUND unless $base && $ext && $base !~ m!\.\.!;

    my $disk_file = "$LJ::HTDOCS/palimg/$base.$ext";
    return $r->NOT_FOUND unless -e $disk_file;

    my @st      = stat(_);
    my $size    = $st[7];
    my $modtime = $st[9];
    my $etag    = "$modtime-$size";

    my $mime = { gif => 'image/gif', png => 'image/png' }->{$ext};
    return $r->NOT_FOUND unless $mime;

    my %pal_colors;
    if ($extra) {
        return $r->NOT_FOUND unless $extra =~ m!^/p(.+)$!;
        my $pals = $1;

        return $r->NOT_FOUND
            unless _parse_palspec( $pals, \%pal_colors, \$etag );
    }

    $etag = qq{"$etag"};
    my $ifnonematch = $r->header_in('If-None-Match');
    if ( defined $ifnonematch && $etag eq $ifnonematch ) {
        $r->status(304);
        return $r->OK;
    }

    $r->content_type($mime);
    $r->header_out( 'Content-Length' => $size );
    $r->header_out( 'ETag'           => $etag );
    $r->header_out( 'Last-Modified'  => LJ::time_to_http($modtime) );

    return $r->OK if $r->method eq 'HEAD';

    open my $fh, '<', $disk_file or return $r->NOT_FOUND;
    binmode $fh;

    my $palette;
    if (%pal_colors) {
        if ( $mime eq 'image/gif' ) {
            $palette = PaletteModify::new_gif_palette( $fh, \%pal_colors );
        }
        elsif ( $mime eq 'image/png' ) {
            $palette = PaletteModify::new_png_palette( $fh, \%pal_colors );
        }
        unless ($palette) {
            close $fh;
            return $r->NOT_FOUND;
        }
    }

    my $body = '';
    $body .= $palette if $palette;
    read $fh, my $buf, 1024 * 1024;
    $body .= $buf if $buf;
    close $fh;

    $r->header_out( 'Content-Length' => length $body );
    $r->print($body);

    return $r->OK;
}

# Parse a palette spec string into the %pal_colors hash.
# Returns true on success, false on invalid spec.
sub _parse_palspec {
    my ( $pals, $pal_colors, $etag_ref ) = @_;

    my $hx = '[0-9a-f]';

    # Gradient: gFFCOLORTTCOLOR
    if ( $pals =~ /^g($hx{2})($hx{6})($hx{2})($hx{6})$/ ) {
        my $from   = hex($1);
        my $to     = hex($3);
        my $fcolor = _parse_hex_color($2);
        my $tcolor = _parse_hex_color($4);
        return 0 if $from == $to;

        ( $from, $to, $fcolor, $tcolor ) = ( $to, $from, $tcolor, $fcolor )
            if $to < $from;

        $$etag_ref .= ":pg$pals";
        for ( my $i = $from ; $i <= $to ; $i++ ) {
            $pal_colors->{$i} = [
                map {
                    int( $fcolor->[$_] +
                            ( $tcolor->[$_] - $fcolor->[$_] ) * ( $i - $from ) / ( $to - $from ) )
                } ( 0 .. 2 )
            ];
        }
    }

    # Tint: tCOLOR or tCOLORDARK
    elsif ( $pals =~ /^t($hx{6})($hx{6})?$/ ) {
        my ( $t, $td ) = ( $1, $2 );
        $pal_colors->{tint}      = _parse_hex_color($t);
        $pal_colors->{tint_dark} = $td ? _parse_hex_color($td) : [ 0, 0, 0 ];
    }

    # Direct palette index colors: IRRGGBB repeated
    elsif ( length($pals) <= 42 && $pals !~ /[^0-9a-f]/ ) {
        my $len = length($pals);
        return 0 if $len % 7;
        for ( my $i = 0 ; $i < $len / 7 ; $i++ ) {
            my $palindex = hex( substr( $pals, $i * 7, 1 ) );
            $pal_colors->{$palindex} = [
                hex( substr( $pals, $i * 7 + 1, 2 ) ),
                hex( substr( $pals, $i * 7 + 3, 2 ) ),
                hex( substr( $pals, $i * 7 + 5, 2 ) ),
                substr( $pals, $i * 7 + 1, 6 ),
            ];
        }
        $$etag_ref .= ":p$_($pal_colors->{$_}->[3])" for sort keys %$pal_colors;
    }
    else {
        return 0;
    }

    return 1;
}

sub _parse_hex_color {
    return [ map { hex( substr( $_[0], $_, 2 ) ) } ( 0, 2, 4 ) ];
}

1;
