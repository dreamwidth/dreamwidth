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

package LJ::Console::Command::Print;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "print" }

sub desc { "This is a debugging function. Given any number of arguments, it'll print each one back to you. If an argument begins with a bang (!), then it'll be printed to the error stream instead. Requires priv: none." }

sub args_desc { [] }

sub usage { '...' }

sub requires_remote { 0 }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    $self->info("Welcome to 'print'!");

    foreach my $arg (@args) {
        if ($arg =~ /^\!/) {
            $self->error($arg);
        } else {
            $self->print($arg);
        }
    }

    return 1;
}

1;
