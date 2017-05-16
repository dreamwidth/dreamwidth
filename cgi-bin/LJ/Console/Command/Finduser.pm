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

package LJ::Console::Command::Finduser;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "finduser" }

sub desc { "Finds all accounts matching a certain criterion. Requires priv: finduser." }

sub args_desc { [
                 'criteria' => "One of: 'user', 'userid', 'email', 'openid', or 'timeupdate'.",
                 'data' => "Either a username or email address, or a userid when using 'userid'," .
                           " or a URL when using 'openid'.",
                 ] }

sub usage { '<criteria> <data>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "finduser" );
}

sub execute {
    my ($self, @args) = @_;

    return $self->error( "No arguments given" ) unless @args;

    my ( $crit, $data );
    my $use_timeupdate = 0;

    if (scalar(@args) == 1) {
        # we can auto-detect emails easy enough
        $data = $args[0];
        $crit = ( $data =~ /@/ ) ? 'email' : 'user';
    } else {
        # old format...but new variations
        $crit = $args[0];
        $data = $args[1];

        # if they gave us the timeupdate flag as the criterion,
        # rewrite as a regular finduser, but display last update time, too
        if ($crit eq 'timeupdate') {
            $use_timeupdate = 1;
            $crit = ( $data =~ /@/ ) ? 'email' : 'user';
        }

        # if they gave us a username and want to search by email, instead find
        # all users with that email address
        if ($crit eq 'email' && $data !~ /@/) {
            my $u = LJ::load_user($data)
                or return $self->error("User $data doesn't exist.");
            $data = $u->email_raw
                or return $self->error($u->user . " does not have an email address.");
        }

        if ( $crit eq 'openid' ) {
            if ( $data =~ m!^[^/]+$! ) {
                # (a) given host.domain (no slashes)
                $data = "//$data/";  # add slashes to indicate start and end
            } elsif ( $data =~ s/^https?:// || $data =~ m!^//! ) {
                # (b) convert HTTP(S) link to protocol-neutral URL;
                #     add trailing slash if we aren't using a host/page URL
                $data .= '/' if $data =~ m!^//[^/]+$!;
            } else {
                return $self->error( "Doesn't look like a valid web URL: $data" );
            }
            # URL should now be of the form //host.domain/ or //host.domain/page
        }
    }

    my $dbh = LJ::get_db_reader();
    my $userlist;
    my %idmap;  # for identity accounts

    if ($crit eq 'email') {
        $userlist = $dbh->selectcol_arrayref("SELECT userid FROM email WHERE email = ?", undef, $data);
    } elsif ($crit eq 'userid') {
        $userlist = $dbh->selectcol_arrayref("SELECT userid FROM user WHERE userid = ?", undef, $data);
    } elsif ($crit eq 'user') {
        $data = LJ::canonical_username($data);
        $userlist = $dbh->selectcol_arrayref("SELECT userid FROM user WHERE user = ?", undef, $data);
    } elsif ( $crit eq 'openid' ) {
        # Use wildcard search to match either HTTP or HTTPS entries.
        my $rows = $dbh->selectcol_arrayref(
            "SELECT userid, identity FROM identitymap WHERE idtype='O' AND identity LIKE ?",
            { Columns => [1,2] }, "%$data" );
        %idmap = @$rows;
        $userlist = [ keys %idmap ];
    } else {
        return $self->error("Unknown criterion. Consult the reference.");
    }

    return $self->error("Error in database query.")
        if $dbh->err;

    my $userids = [];
    push @$userids, @{$userlist || []};

    return $self->error("No matches")
        unless @$userids;

    my $us = LJ::load_userids(@$userids);

    my $timeupdate;
    $timeupdate = LJ::get_timeupdate_multi({}, @$userids)
        if $use_timeupdate;

    foreach my $u (sort { $a->id <=> $b->id } values %$us) {
        next unless $u;
        my $userid = $u->id;

        $self->info("User: " . $u->user . " (" . $u->id . "), journaltype: " . $u->journaltype . ", statusvis: " .
                    $u->statusvis . ", email: (" . $u->email_status . ") " . $u->email_raw);

        $self->info("  URL: $idmap{$userid}") if $crit eq 'openid';

        $self->info("  User is currently in read-only mode.")
            if $u->readonly;

        $self->info("  Last updated: " . ($timeupdate->{$userid} ? LJ::time_to_http($timeupdate->{$userid}) : "Never"))
            if $use_timeupdate;

        foreach (LJ::Hooks::run_hooks("finduser_extrainfo", $u)) {
            next unless $_->[0];
            $self->info($_) foreach (split(/\n/, $_->[0]));
        }
    }

    return 1;
}

1;
