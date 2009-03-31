#!/usr/bin/perl

# LastFM - API to LastFM
package LJ::LastFM;

use strict;
use warnings;

# FIXME: this can be simplified, if not completely removed, but it's used in
# LJ::S2, talkread.bml, and talkpost.bml, all of which are (I think) having
# surgery of their own, so leaving it as is until someone can look at how they
# use it in more detail.
sub format_current_music_string {
    my $string = shift;

    if ($string =~ $LJ::LAST_FM_SIGN_RE) {

        my ($artist, $track) = $string =~ /^\s*(.*)\s{1}-\s{1}(.*)$LJ::LAST_FM_SIGN_RE/;

        if ($artist && $track) {
            $string = $artist ne 'Unknown artist' ? qq{<a href='$LJ::LAST_FM_ARTIST_URL'>$artist</a>} : $artist;
            $string .= ' - ';
            $string .= $track ne 'Unknown track' ? qq{<a href='$LJ::LAST_FM_TRACK_URL'>$track</a>} : $track;

            $string .= " $LJ::LAST_FM_SIGN_TEXT";

            $string =~ s/%artist%/$artist/g;
            $artist =  LJ::eurl($artist);
            $string =~ s/%artist_esc%/$artist/g;

            $string =~ s/%track%/$track/g;
            $track  =  LJ::eurl($track);
            $string =~ s/%track_esc%/$track/g;
        }

        $string =~ s!Last\.fm!$LJ::LAST_FM_SIGN_URL!;

    }

    return $string;
}

1;
