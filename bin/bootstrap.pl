#!/usr/bin/perl

use strict;

# check for svn in a known place
die "Expected hg in /usr/bin ... not found!\n"
    unless -e '/usr/bin/hg';

# get the right directory
my $LJHOME = $ENV{'LJHOME'};
die "Must set the \$LJHOME environment variable before running this.\n"
    unless -d $LJHOME;
chdir( $LJHOME )
    or die "Couldn't chdir to \$LJHOME directory.\n";

# more than likely we don't have vcv, so let's get it
die "Did you already bootstrap?  cvs/vcv exists.\n"
    if -d "$LJHOME/cvs/vcv";

# so now get it
system( '/usr/bin/hg -q clone http://hg.dwscoalition.org/vcv cvs/vcv' );
die "Unable to checkout vcv from DWS Coalition repository.\n"
    unless -d "$LJHOME/cvs/vcv" && -e "$LJHOME/cvs/vcv/bin/vcv";

# now get vcv to do the rest for us
system( 'cvs/vcv/bin/vcv --conf=cvs/multicvs.conf --checkout' );

# finished :-)
print "Done!  We hope.  :-)\n";
