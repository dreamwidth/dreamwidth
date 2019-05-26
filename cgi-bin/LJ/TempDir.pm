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

package LJ::TempDir;

# little OO-wrapper around File::Temp::tempdir, so when object
# DESTROYs, things get cleaned.

use strict;
use File::Temp ();
use File::Path ();

# returns either $obj or ($obj->dir, $obj), when in list context.
# when $obj goes out of scope, all temp directory contents are wiped.
sub new {
    my ($class) = @_;
    my $dir = File::Temp::tempdir()
        or die "Failed to create temp directory: $!\n";
    my $obj = bless { dir => $dir, }, $class;
    return wantarray ? ( $dir, $obj ) : $obj;
}

sub directory { $_[0]{dir} }

sub DESTROY {
    my $self = shift;
    File::Path::rmtree( $self->{dir} ) if $self->{dir} && -d $self->{dir};
}

1;
