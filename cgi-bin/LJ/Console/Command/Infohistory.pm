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

package LJ::Console::Command::Infohistory;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "infohistory" }

sub desc { "Retrieve info history of a given account. Requires priv: finduser:infohistory." }

sub args_desc { [
                 'user' => "The username of the account whose infohistory to retrieve.",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "finduser", "infohistory" );
}

sub execute {
    my ($self, $user, @args) = @_;

    return $self->error("This command takes exactly one argument. Consult the reference.")
        unless $user && !@args;

    my $u = LJ::load_user($user);

    return $self->error("Invalid user $user")
        unless $u;

    my $dbh = LJ::get_db_reader();
    my $sth = $dbh->prepare("SELECT * FROM infohistory WHERE userid=?");
    $sth->execute($u->id);

    return $self->error("No matches.")
        unless $sth->rows;

    $self->info("Infohistory of user: $user");
    while (my $info = $sth->fetchrow_hashref) {
        $info->{'oldvalue'} ||= '(none)';
        $self->info("Changed $info->{'what'} at $info->{'timechange'}.");
        $self->info("Old value of $info->{'what'} was $info->{'oldvalue'}.");
        $self->info("Other information recorded: $info->{'other'}")
            if $info->{'other'};
    }

    return 1;
}

1;
