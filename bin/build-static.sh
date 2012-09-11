#!/bin/bash
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


buildroot="$LJHOME/build/static";
mkdir -p $buildroot;

# check the relevant paths using the same logic as the codebase
perl -e '
use strict;

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require "ljlib.pl"; }
use LJ::Directories;

# look up all instances of the directory in various subfolders
# then add trailing slashes so that rsync will treat these as directories
printf( "htdocs/img:%s/\n", join( "/ ",LJ::get_all_directories( "htdocs/img", home_first => 1 ) ) );
printf( "htdocs/stc:%s/\n", join( "/ ",LJ::get_all_directories( "htdocs/stc", home_first => 1 ) ) );
printf( "htdocs/js:%s/\n",  join( "/ ",LJ::get_all_directories( "htdocs/js",  home_first => 1 ) ) );' | while read -r line
do
    to="$buildroot/"`echo $line | cut -d ":" -f 1`
    mkdir -p "$to"

    from=`echo $line | cut -d ":" -f 2`

    echo "* Syncing to $to..."
    rsync --archive --out-format="%n%L" --delete $from $to
done


