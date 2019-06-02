#!/usr/bin/perl
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

# This script goes through all of the files in your include directory
# (LJHOME/htdocs/inc) and then imports them into the database if
# they're newer on disk.

use strict;

BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

# create list of files to check
my $dir = "$ENV{'LJHOME'}/htdocs/inc";
print "searching for files to check against database...";
opendir DIR, $dir
    or die "Unable to open $ENV{'LJHOME'}/htdocs/inc for searching.\n";
my @files = readdir(DIR);
my $count = scalar(@files);
print $count+ 0 . " found.\n";

# now iterate through and check times
my $dbh = LJ::get_db_writer();
foreach my $file (@files) {
    my $path = "$dir/$file";
    next unless -f $path;

    # now get filetime
    my $ftimedisk = ( stat($path) )[9];
    my $ftimedb   = $dbh->selectrow_array(
        "SELECT updatetime
                    FROM includetext WHERE incname=?", undef, $file
    ) + 0;

    # check
    if ( $ftimedisk > $ftimedb ) {

        # load file
        open FILE, "<$path";
        my $content = join( "", <FILE> );
        close FILE;

        # now do SQL
        print "$file newer on disk...updating database...";
        $dbh->do(
            "REPLACE INTO includetext (incname, inctext, updatetime)"
                . "VALUES (?,?,UNIX_TIMESTAMP())",
            undef, $file, $content
        );
        print $dbh->err ? "error: " . $dbh->errstr . ".\n" : "done.\n";
    }
    else {
        print "$file newer in database, ignored.\n";
    }
}

print "all done.\n";
