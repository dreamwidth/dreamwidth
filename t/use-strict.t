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
use File::Find;

my %check;

# Walk the tree for Perl source instead of asking git. This has to run in any
# checkout, including devcontainer worktrees where $LJHOME/.git is a pointer file
# to a path that doesn't exist inside the container -- there git ls-tree fails, we
# find zero files, and the test dies on an empty plan.
find(
    {
        no_chdir => 1,
        wanted   => sub {
            my $path = $File::Find::name;

            # Prune trees we don't own or care about; also keeps us out of the
            # extlib symlink and other large vendored/generated directories.
            if ( -d $path ) {
                $File::Find::prune = 1
                    if $path =~
                    m!/(?:\.git|\.claude|node_modules|extlib|build|_build|logs|var|locks|temp)$!;
                return;
            }

            return unless $path =~ /\.(pl|pm)$/;

            # skip stuff we're less concerned about or don't control
            return if $path =~ m:\b(doc|etc|fck|miscperl|src|s2|extlib)/:;
            return if $path =~ m/config-test\.pl$/;
            return if $path =~ m/config-test-private\.pl$/;

            $check{$path} = 1;
        },
    },
    $ENV{LJHOME}
);

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

