# t/use-strict.t
#
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

use strict;
use warnings;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Test::More;
use LJ::Directories;

my %check;

# bit of a hack. We assume that everything we care about is in a git repo
# which could be under $LJHOME, or $LJHOME/ext
foreach my $repo ( LJ::get_all_directories(".git") ) {
    my @files =
        eval { split( /\n/, qx`git --git-dir "$repo" ls-tree -r --full-tree --name-only HEAD` ) };
    next unless @files;

    $repo =~ s!/\.git!!;
    foreach my $line (@files) {
        chomp $line;
        $line =~ s!//!/!g;
        my $path = "$repo/$line";
        next unless $path =~ /\.(pl|pm)$/;

        # skip stuff we're less concerned about or don't control
        next if $path =~ m:\b(doc|etc|fck|miscperl|src|s2|extlib)/:;
        next if $path =~ m/config-test\.pl$/;
        next if $path =~ m/config-test-private\.pl$/;
        $check{$path} = 1;
    }
}
plan tests => scalar keys %check;

my @bad;
foreach my $f ( sort keys %check ) {
    my $strict = 0;
    open( my $fh, $f ) or die "Could not open $f: $!";
    while (<$fh>) {
        if (/^use strict;/) {
            $strict = 1;
            last;
        }
    }
    close $fh;
    ok( $strict, "strict in $f" );
    push @bad, $f unless $strict;
}

foreach my $bad (@bad) {
    diag("Missing strict: $bad");
}

