#!/bin/bash

#
# Disable directory listing by creating in it empty index.bml file.
#

PREFIX=${LJHOME}/htdocs
DIRSLIST="inc preview rte temp"

for d in $DIRSLIST; do
    p=$PREFIX/$d
    if [ -d $p ]; then
        subs=`find $p -type d`
        for s in $subs; do
            [ -f $s/index.* ] || touch "$s/index.html"
        done
    else
        echo "$0: Directory '$p' does not exist."
    fi
done
