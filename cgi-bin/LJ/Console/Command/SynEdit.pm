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

package LJ::Console::Command::SynEdit;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_editurl" }

sub desc { "Changes the source feed URL for a syndicated account. Requires priv: syn_edit." }

sub args_desc {
    [
        'user'   => "The username of the syndicated account.",
        'newurl' => "The new source feed URL.",
    ]
}

sub usage { '<user> <newurl>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("syn_edit");
}

sub execute {
    my ( $self, $user, $newurl, @args ) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $user && $newurl && scalar(@args) == 0;

    my $u = LJ::load_user($user);

    return $self->error("Invalid user $user")
        unless $u;
    return $self->error("Not a syndicated account")
        unless $u->is_syndicated;
    return $self->error("Invalid URL")
        unless $newurl =~ m!^https?://(.+?)/!;

    my $dbh = LJ::get_db_writer();
    my $oldurl =
        $dbh->selectrow_array( "SELECT synurl FROM syndicated WHERE userid=?", undef, $u->id );
    $dbh->do( "UPDATE syndicated SET synurl=?, checknext=NOW() WHERE userid=?",
        undef, $newurl, $u->id );

    if ( $dbh->err ) {
        my $acct =
            $dbh->selectrow_array( "SELECT userid FROM syndicated WHERE synurl=?", undef, $newurl );
        my $oldu = LJ::load_userid($acct);
        return $self->error( "URL for account $user not changed: URL in use by " . $oldu->user );
    }
    else {
        my $remote = LJ::get_remote();
        LJ::statushistory_add( $u, $remote, 'synd_edit', "URL changed: $oldurl => $newurl" );
        return $self->print("URL for account $user changed: $oldurl => $newurl");
    }
}

1;
