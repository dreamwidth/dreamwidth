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
#
# This is now just a wrapper around the non-LJ-specific multicvs.pl
#

use strict;

die "\$LJHOME not set.\n"
    unless -d $ENV{'LJHOME'};

# check to see if we want only stable releases
eval { require LJ::Config; };
LJ::Config->load unless $@;  # only load config if available
my @stable = $LJ::USE_STABLE_CODE ? ( '--stable' ) : ();

# strip off paths beginning with LJHOME
# (useful if you tab-complete filenames)
$_ =~ s!\Q$ENV{'LJHOME'}\E/?!! foreach (@ARGV);

my $vcv_exe = "multicvs.pl";
if (-e "$ENV{LJHOME}/bin/vcv") {
    $vcv_exe = "vcv";
}

exec("$ENV{'LJHOME'}/bin/$vcv_exe",
     "--conf=$ENV{'LJHOME'}/cvs/multicvs.conf",
     @stable,
     @ARGV);
