#!/bin/bash
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


buildroot="$LJHOME/build/static"
mkdir -p $buildroot

compressor="$LJHOME/ext/yuicompressor/yuicompressor.jar"
uncompressed_dir="/max"
if [ ! -e $compressor ]
then
    echo "Warning: No compressor found ($compressor)" >&2
    compressor=""
    uncompressed_dir=""
fi

# check the relevant paths using the same logic as the codebase
perl -e '
use strict;

use lib "$ENV{LJHOME}/extlib/lib/perl5";
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require "ljlib.pl"; }
use LJ::Directories;

# look up all instances of the directory in various subfolders
# then add trailing slashes so that rsync will treat these as directories
printf( ":img:%s/\n", join( "/ ",LJ::get_all_directories( "htdocs/img", home_first => 1 ) ) );
printf( "compress:stc:%s/\n", join( "/ ",LJ::get_all_directories( "htdocs/stc", home_first => 1 ) ) );
printf( "compress:js:%s/\n",  join( "/ ",LJ::get_all_directories( "htdocs/js",  home_first => 1 ) ) );' | while read -r line
do
    compress=`echo $line | cut -d ":" -f 1`

    to_dir=`echo $line | cut -d ":" -f 2`
    final="$buildroot/$to_dir"                           # directory we serve files from, if minifying

    if [[ -n "$compressor" && -n "$compress" ]]; then
        sync_to="$buildroot$uncompressed_dir/$to_dir"    # directory we're copying files to
    else
        sync_to=$final
    fi

    if [[ ! -e $sync_to ]]; then mkdir -p "$sync_to"; fi
    if [[ ! -e $final ]];   then mkdir -p "$final"; fi

    from=`echo $line | cut -d ":" -f 3`

    echo "* Syncing to $sync_to..."
    rsync --archive --out-format="%n" --delete $from $sync_to | while read -r modified_file
    do
        echo " > $modified_file"
        if [[ -n "$compressor" && -n "$compress" ]]
        then
            base=$(basename "$modified_file")
            ext=${base##*.}
            dir=$(dirname "$modified_file")
            synced_file="$sync_to/$modified_file"
            if [[ -f "$synced_file" ]]; then

                # remove the old one so that we don't have a stale version
                # in case minifying fails for any reason
                if [[ -f "$final/$modified_file" ]]; then
                    rm "$final/$modified_file"
                fi

                mkdir -p "$final/$dir"
                if [[ "$ext" = "js" || "$ext" = "css" ]]; then
                    java -jar $compressor "$synced_file" -o "$final/$modified_file"
                else
                    cp -p "$synced_file" "$final/$modified_file"
                fi
            else
                # we're deleting rather than copying
                # only need this for compressed files
                # rsync handles the uncompressed ones
                deleting=${modified_file#deleting }
                if [[ "$deleting" != "$modified_file" ]]; then
                    rm "$final/$deleting"
                fi
            fi
        fi
    done
done

if [[ -n $compressor ]]; then
    escaped=$( echo $buildroot | sed 's/\//\\\//g' )
    find $buildroot/js $buildroot/max/js   | sed "s/$escaped\/\(max\/\)\?//" | sort | uniq -c | sort -n   | grep '^[[:space:]]\+1'
    find $buildroot/stc $buildroot/max/stc | sed "s/$escaped\/\(max\/\)\?//" | sort | uniq -c | sort -n   | grep '^[[:space:]]\+1'
fi

