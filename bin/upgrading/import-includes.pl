#!/usr/bin/perl
# This script goes through all of the files in your include directory
# (LJHOME/htdocs/inc) and then imports ones that are specified by your
# ljconfig.pl file (%LJ::FILEEDIT_VIA_DB) into your database if the file
# on disk is newer than the one in the database.

use strict;
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

# create list of files to check
my $dir = "$ENV{'LJHOME'}/htdocs/inc";
print "searching for files to check against database...";
opendir DIR, $dir 
    or die "Unable to open $ENV{'LJHOME'}/htdocs/inc for searching.\n";
my @files = grep { $LJ::FILEEDIT_VIA_DB || 
                   $LJ::FILEEDIT_VIA_DB{$_} } readdir(DIR);
my $count = scalar(@files);
print $count+0 . " found.\n";

# now iterate through and check times
my $dbh = LJ::get_db_writer();
foreach my $file (@files) {
    my $path = "$dir/$file";
    next unless -f $path;

    # now get filetime
    my $ftimedisk = (stat($path))[9];
    my $ftimedb = $dbh->selectrow_array("SELECT updatetime
                    FROM includetext WHERE incname=?", undef, $file)+0;
    
    # check
    if ($ftimedisk > $ftimedb) {
        # load file
        open FILE, "<$path";
        my $content = join("", <FILE>);
        close FILE;
    
        # now do SQL
        print "$file newer on disk...updating database...";
        $dbh->do("REPLACE INTO includetext (incname, inctext, updatetime)" .
                 "VALUES (?,?,UNIX_TIMESTAMP())", undef, $file, $content);
        print $dbh->err ? "error: " . $dbh->errstr . ".\n" : "done.\n";
    } else {
        print "$file newer in database, ignored.\n";
    }
}

print "all done.\n";
