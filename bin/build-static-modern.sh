#!/bin/bash
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

# Parse flags. If none specified, run everything.
# The rsync to build/static always runs since all steps feed into it.
do_sass=0
do_compress=0

for arg in "$@"; do
    case "$arg" in
        --sass)     do_sass=1 ;;
        --compress) do_compress=1 ;;
        --help|-h)
            echo "Usage: $0 [--sass] [--compress]"
            echo "  --sass       Compile SCSS files with Dart Sass"
            echo "  --compress   Minify JS with esbuild"
            echo "  (no flags runs all steps)"
            echo ""
            echo "  Asset sync (rsync to build/static/) always runs."
            exit 0
            ;;
        *)
            echo "$0: unknown option -- $arg" >&2
            exit 1
            ;;
    esac
done

# No flags = run everything
if [[ $do_sass -eq 0 && $do_compress -eq 0 ]]; then
    do_sass=1
    do_compress=1
fi

buildroot="$LJHOME/build/static"
mkdir -p $buildroot

# --- SCSS compilation ---
if [[ $do_sass -eq 1 ]]; then
    sass=$(which sass)
    if [ "$sass" != "" ]; then
        echo "* Building SCSS..."
        if ! $sass --style=compressed --no-source-map \
            --load-path=$LJHOME/htdocs/scss \
            $LJHOME/htdocs/scss:$LJHOME/htdocs/stc/css; then
            echo "Error: Sass compilation failed" >&2
            exit 1
        fi
        if [ -d "$LJHOME/ext/dw-nonfree/htdocs/scss" ]; then
            if ! $sass --style=compressed --no-source-map \
                --load-path=$LJHOME/htdocs/scss \
                --load-path=$LJHOME/ext/dw-nonfree/htdocs/scss \
                $LJHOME/ext/dw-nonfree/htdocs/scss:$LJHOME/ext/dw-nonfree/htdocs/stc/css; then
                echo "Error: Sass compilation failed (dw-nonfree)" >&2
                exit 1
            fi
        fi
    else
        echo "Error: No sass command found" >&2
        exit 1
    fi
fi

# --- Asset sync (always runs) and optional compression ---
compressor=""
uncompressed_dir=""
if [[ $do_compress -eq 1 ]]; then
    compressor=$(which esbuild)
    uncompressed_dir="/max"
    if [ -z "$compressor" ]; then
        echo "Warning: No esbuild command found" >&2
        uncompressed_dir=""
    fi
fi

# check the relevant paths using the same logic as the codebase
perl -e '
use strict;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
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

                if [[ "$ext" = "js" ]]; then
                    # Minify JS with esbuild
                    $compressor --minify "$synced_file" --outfile="$final/$modified_file" 2>/dev/null \
                        || cp -p "$synced_file" "$final/$modified_file"
                else
                    # CSS is already minified by Dart Sass; other files copy as-is
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

exit 0
