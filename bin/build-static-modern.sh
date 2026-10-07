#!/bin/bash
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

# Parse flags. If no step flags are specified, run everything appropriate for
# the build mode. The rsync to build/static always runs since all steps feed
# into it.
do_sass=0
do_compress=0
force=0

# Build mode: dev builds are unminified to aid debugging, prod builds are
# minified. Dev mode follows LJ_IS_DEV_SERVER (with the same truthiness that
# ljlib.pl uses); --dev and --prod override it.
mode=prod
if [[ -n "$LJ_IS_DEV_SERVER" && "$LJ_IS_DEV_SERVER" != "0" ]]; then
    mode=dev
fi

for arg in "$@"; do
    case "$arg" in
        --sass)     do_sass=1 ;;
        --compress) do_compress=1 ;;
        --dev)      mode=dev ;;
        --prod)     mode=prod ;;
        --force)    force=1 ;;
        --help|-h)
            echo "Usage: $0 [--sass] [--compress] [--dev|--prod] [--force]"
            echo "  --sass       Compile SCSS files with Dart Sass"
            echo "  --compress   Minify JS and CSS with esbuild (even in dev mode)"
            echo "  --dev        Dev mode: expanded CSS, no minification by default"
            echo "               (the default if LJ_IS_DEV_SERVER is set)"
            echo "  --prod       Prod mode: compressed CSS, minified JS and CSS"
            echo "               (the default otherwise; overrides LJ_IS_DEV_SERVER)"
            echo "  --force      Wipe the build directory and rebuild everything"
            echo "  (no step flags runs SCSS compilation, plus minification in prod mode)"
            echo ""
            echo "  Asset sync (rsync to build/static/) always runs. A full rebuild also"
            echo "  happens automatically when this script, the tool versions, or the"
            echo "  build mode change."
            exit 0
            ;;
        *)
            echo "$0: unknown option -- $arg" >&2
            exit 1
            ;;
    esac
done

# No step flags = run everything; only minify by default in prod
if [[ $do_sass -eq 0 && $do_compress -eq 0 ]]; then
    do_sass=1
    if [[ $mode = "prod" ]]; then
        do_compress=1
    fi
fi

# Dart Sass writes source maps next to the compiled CSS by default; we never
# want those, since they'd end up synced into build/static
if [[ $mode = "prod" ]]; then
    sass_options="--style=compressed --no-source-map"
else
    sass_options="--style=expanded --no-source-map"
fi

if [[ -z "$LJHOME" ]]; then
    echo "Error: LJHOME is not set" >&2
    exit 1
fi

buildroot="$LJHOME/build/static"
mkdir -p $buildroot

sass=$(which sass)

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

# --- Full rebuild check ---
# Incremental syncs only reprocess files whose source changed, so if anything
# that affects the output changes (this script, the tool versions, or the build
# mode) everything needs to be rebuilt. Record those in a stamp file and wipe
# the build directory when they differ, or when --force is given.
stamp_file="$buildroot/.build-stamp"
stamp=$(
    echo "script: $(sha256sum < "${BASH_SOURCE[0]}" | cut -d ' ' -f 1)"
    echo "esbuild: $( [ -n "$compressor" ] && $compressor --version )"
    echo "sass: $( [ -n "$sass" ] && $sass --version )"
    echo "mode: $mode"
    echo "minify: $( [ -n "$compressor" ] && echo 1 || echo 0 )"
)

if [[ $force -eq 1 ]]; then
    echo "* Forced full rebuild"
elif [[ ! -f "$stamp_file" ]]; then
    echo "* No build stamp found, doing a full rebuild"
    force=1
elif [[ "$(cat "$stamp_file")" != "$stamp" ]]; then
    echo "* Build script, tools or mode changed, doing a full rebuild"
    force=1
fi

if [[ $force -eq 1 ]]; then
    # Remove the contents rather than the directory itself, which may be a
    # symlink (e.g. in the dev container)
    find -H "$buildroot" -mindepth 1 -delete
fi

# --- SCSS compilation ---
if [[ $do_sass -eq 1 ]]; then
    if [ "$sass" != "" ]; then
        echo "* Building SCSS..."
        if ! $sass $sass_options \
            --load-path=$LJHOME/htdocs/scss \
            $LJHOME/htdocs/scss:$LJHOME/htdocs/stc/css; then
            echo "Error: Sass compilation failed" >&2
            exit 1
        fi
        if [ -d "$LJHOME/ext/dw-nonfree/htdocs/scss" ]; then
            if ! $sass $sass_options \
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

                if [[ "$ext" = "js" || "$ext" = "css" ]]; then
                    # Minify JS and CSS with esbuild (Dart Sass output is
                    # already compressed in prod, but plain CSS is not)
                    $compressor --target=es6 --minify "$synced_file" --outfile="$final/$modified_file" 2>/dev/null \
                        || cp -p "$synced_file" "$final/$modified_file"
                else
                    # other files copy as-is
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

# Only record the stamp once the build has finished, so an interrupted build
# gets redone from scratch next time
echo "$stamp" > "$stamp_file"

exit 0
