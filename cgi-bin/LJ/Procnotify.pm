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

package LJ::Procnotify;

use strict;
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";


# <LJFUNC>
# name: LJ::Procnotify::add
# des: Sends a message to all other processes on all clusters.
# info: You'll probably never use this yourself.
# args: cmd, args?
# des-cmd: Command name.  Currently recognized: "DBI::Role::reload" and "rename_user"
# des-args: Hashref with key/value arguments for the given command.
#           See relevant parts of [func[LJ::Procnotify::callback]], for
#           required args for different commands.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub add {
    my ($cmd, $argref) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    my $args = join('&', map { LJ::eurl($_) . "=" . LJ::eurl($argref->{$_}) }
                    sort keys %$argref);
    $dbh->do("INSERT INTO procnotify (cmd, args) VALUES (?,?)",
             undef, $cmd, $args);

    return 0 if $dbh->err;
    return $dbh->{'mysql_insertid'};
}

# <LJFUNC>
# name: LJ::Procnotify::callback
# des: Call back function process notifications.
# info: You'll probably never use this yourself.
# args: cmd, argstring
# des-cmd: Command name.
# des-argstring: String of arguments.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub callback {
    my ($cmd, $argstring) = @_;
    my $arg = {};
    LJ::decode_url_string($argstring, $arg);

    if ($cmd eq "rename_user") {
        # this looks backwards, but the cache hash names are just odd:
        delete $LJ::CACHE_USERNAME{$arg->{'userid'}};
        delete $LJ::CACHE_USERID{$arg->{'user'}};
        return;
    }

    # ip/uniq/spamreport bans
    my %ban_types = (
                     ip         => \%LJ::IP_BANNED,
                     uniq       => \%LJ::UNIQ_BANNED,
                     spamreport => \%LJ::SPAMREPORT_BANNED,
                    );

    if ( $cmd =~ /^ban_(\w+)$/ && exists $ban_types{$1} ) {
        my $banarg = $arg->{$1};
        $ban_types{$1}->{$banarg} = $arg->{exptime};
        return;
    }

    if ( $cmd =~ /^unban_(\w+)$/ && exists $ban_types{$1} ) {
        my $banarg = $arg->{$1};
        delete $ban_types{$1}->{$banarg};
        return;
    }

    # cluster switchovers
    if ($cmd eq 'cluster_switch') {
        $LJ::CLUSTER_PAIR_ACTIVE{ $arg->{'cluster'} } = $arg->{ 'role' };
        return;
    }
}


# each server process runs this to periodically check for new actions

sub check {
    my $now = time;
    return if $LJ::CACHE_PROCNOTIFY_CHECK &&
              $LJ::CACHE_PROCNOTIFY_CHECK + 30 > $now;
    $LJ::CACHE_PROCNOTIFY_CHECK = $now;

    my $dbr = LJ::get_db_reader();
    my $max = $dbr->selectrow_array("SELECT MAX(nid) FROM procnotify");
    return unless defined $max;
    my $old = $LJ::CACHE_PROCNOTIFY_MAX;
    if (defined $old && $max > $old) {
        my $sth = $dbr->prepare("SELECT cmd, args FROM procnotify ".
                                "WHERE nid > ? AND nid <= $max ORDER BY nid");
        $sth->execute($old);
        while (my ($cmd, $args) = $sth->fetchrow_array) {
            LJ::Procnotify::callback( $cmd, $args );
        }
    }
    $LJ::CACHE_PROCNOTIFY_MAX = $max;
}


1;
