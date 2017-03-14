#!/usr/bin/perl
#
# mood-maker.pl -- Given a new moodset, outputs what should be placed into mood.dat
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use Getopt::Long;

# parse input options
my ( $dir, $name, $description );
exit 1 unless GetOptions(
                         'dir=s' => \$dir,
                         'name=s' => \$name,
                         'desc=s' => \$description,
                         );

if ( !( $dir =~ m#^[\w-]+$# ) || ( $name =~ /:/ ) ) {
    die "Usage: mood-maker.pl [opts]\n\n" .
      "--dir   The directory within htdocs/img/mood/ the images are stored in\n" .
      "        (that is, if images are in htdocs/img/mood/x/, should be 'x')\n" .
      "--name  The name of the theme (no colons allowed)\n" .
      "--desc  A description for the theme\n\n";
}

# now load in the beast
BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

use File::Basename;
use Image::Size;
use DW::Mood;

my %moods; # { name => id }

foreach ( values %{ DW::Mood->get_moods() } ) {
    $moods{$_->{name}} = $_->{id};
}

print "MOODTHEME $name : $description\n";
foreach my $path ( glob( $LJ::HOME.'/htdocs/img/mood/'.$dir."/*" ) ) {
    my $url = $path;
    $url =~ s#\Q$LJ::HOME\E/htdocs##;
    my ( $mood ) = fileparse( $path, qr/\.[^.]*/ );
    die "Mood $mood does not exist!" unless exists $moods{$mood};
    my ( $w, $h ) = Image::Size::imgsize( $path );
    die "Could not get image dimensions of $path" unless $w && $h;
    print $moods{$mood}, " ", $url, " ", $w, " ", $h, "\n";
}
