#!/bin/bash
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
