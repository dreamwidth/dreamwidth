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

package LJ::User;
use strict;
no warnings 'uninitialized';

########################################################################
### 9. Logging and Recording Actions

=head2 Logging and Recording Actions
=cut

# <LJFUNC>
# name: LJ::User::dudata_set
# class: logging
# des: Record or delete disk usage data for a journal.
# args: u, area, areaid, bytes
# des-area: One character: "L" for log, "T" for talk, "B" for bio, "P" for pic.
# des-areaid: Unique ID within $area, or '0' if area has no ids (like bio)
# des-bytes: Number of bytes item takes up.  Or 0 to delete record.
# returns: 1.
# </LJFUNC>
sub dudata_set {
    my ($u, $area, $areaid, $bytes) = @_;
    $bytes += 0; $areaid += 0;
    if ($bytes) {
        $u->do("REPLACE INTO dudata (userid, area, areaid, bytes) ".
               "VALUES (?, ?, $areaid, $bytes)", undef,
               $u->userid, $area);
    } else {
        $u->do("DELETE FROM dudata WHERE userid=? AND ".
               "area=? AND areaid=$areaid", undef,
               $u->userid, $area);
    }
    return 1;
}


# <LJFUNC>
# name: LJ::User::infohistory_add
# des: Add a line of text to the [[dbtable[infohistory]] table for an account.
# args: uuid, what, value, other?
# des-uuid: User id or user object to insert infohistory for.
# des-what: What type of history is being inserted (15 chars max).
# des-value: Value for the item (255 chars max).
# des-other: Optional. Extra information / notes (30 chars max).
# returns: 1 on success, 0 on error.
# </LJFUNC>
sub infohistory_add {
    my ( $u, $what, $value, $other ) = @_;
    my $uuid = LJ::want_userid( $u );
    return unless $uuid && $what && $value;

    # get writer and insert
    my $dbh = LJ::get_db_writer();
    my $gmt_now = LJ::mysql_time(time(), 1);
    $dbh->do("INSERT INTO infohistory (userid, what, timechange, oldvalue, other) VALUES (?, ?, ?, ?, ?)",
             undef, $uuid, $what, $gmt_now, $value, $other);
    return $dbh->err ? 0 : 1;
}


# log a line to our userlog
sub log_event {
    my ( $u, $type, $info ) = @_;
    return undef unless $type;
    $info ||= {};

    # now get variables we need; we use delete to remove them from the hash so when we're
    # done we can just encode what's left
    my $ip = delete($info->{ip}) || LJ::get_remote_ip() || undef;
    my $uniq = delete $info->{uniq};
    unless ($uniq) {
        eval {
            $uniq = BML::get_request()->notes->{uniq};
        };
    }
    my $remote = delete($info->{remote}) || LJ::get_remote() || undef;
    my $targetid = (delete($info->{actiontarget})+0) || undef;
    my $extra = %$info ? join('&', map { LJ::eurl($_) . '=' . LJ::eurl($info->{$_}) } sort keys %$info) : undef;

    # now insert the data we have
    $u->do("INSERT INTO userlog (userid, logtime, action, actiontarget, remoteid, ip, uniq, extra) " .
           "VALUES (?, UNIX_TIMESTAMP(), ?, ?, ?, ?, ?, ?)", undef, $u->userid, $type,
           $targetid, $remote ? $remote->userid : undef, $ip, $uniq, $extra);
    return undef if $u->err;
    return 1;
}


# returns 1 if action is permitted.  0 if above rate or fail.
sub rate_check {
    my ($u, $ratename, $count, $opts) = @_;

    my $rateperiod = $u->get_cap( "rateperiod-$ratename" );
    return 1 unless $rateperiod;

    my $rp = defined $opts->{'rp'} ? $opts->{'rp'}
             : LJ::get_prop("rate", $ratename);
    return 0 unless $rp;

    my $now = defined $opts->{'now'} ? $opts->{'now'} : time();
    my $beforeperiod = $now - $rateperiod;

    # check rate.  (okay per period)
    my $opp = $u->get_cap( "rateallowed-$ratename" );
    return 1 unless $opp;

    # check memcache, except in the case of rate limiting by ip
    my $memkey = $u->rate_memkey($rp);
    unless ($opts->{limit_by_ip}) {
        my $attempts = LJ::MemCache::get($memkey);
        if ($attempts) {
            my $num_attempts = 0;
            foreach my $attempt (@$attempts) {
                next if $attempt->{evttime} < $beforeperiod;
                $num_attempts += $attempt->{quantity};
            }

            return $num_attempts + $count > $opp ? 0 : 1;
        }
    }

    return 0 unless $u->writer;

    # delete inapplicable stuff (or some of it)
    my $userid = $u->userid;
    $u->do("DELETE FROM ratelog WHERE userid=$userid AND rlid=$rp->{'id'} ".
           "AND evttime < $beforeperiod LIMIT 1000");

    my $udbr = LJ::get_cluster_reader($u);
    my $ip = defined $opts->{'ip'}
             ? $opts->{'ip'}
             : $udbr->quote($opts->{'limit_by_ip'} || "0.0.0.0");
    my $sth = $udbr->prepare("SELECT evttime, quantity FROM ratelog WHERE ".
                             "userid=$userid AND rlid=$rp->{'id'} ".
                             "AND ip=INET_ATON($ip) ".
                             "AND evttime > $beforeperiod");
    $sth->execute;

    my @memdata;
    my $sum = 0;
    while (my $data = $sth->fetchrow_hashref) {
        push @memdata, $data;
        $sum += $data->{quantity};
    }

    # set memcache, except in the case of rate limiting by ip
    unless ($opts->{limit_by_ip}) {
        LJ::MemCache::set( $memkey => \@memdata || [] );
    }

    # would this transaction go over the limit?
    if ($sum + $count > $opp) {
        # FIXME: optionally log to rateabuse, unless caller is doing it
        # themselves somehow, like with the "loginstall" table.
        return 0;
    }

    return 1;
}


# returns 1 if action is permitted.  0 if above rate or fail.
# action isn't logged on fail.
#
# opts keys:
#   -- "limit_by_ip" => "1.2.3.4"  (when used for checking rate)
#   --
sub rate_log {
    my ($u, $ratename, $count, $opts) = @_;
    my $rateperiod = $u->get_cap( "rateperiod-$ratename" );
    return 1 unless $rateperiod;

    return 0 unless $u->writer;

    my $rp = LJ::get_prop("rate", $ratename);
    return 0 unless $rp;
    $opts->{'rp'} = $rp;

    my $now = time();
    $opts->{'now'} = $now;
    my $udbr = LJ::get_cluster_reader($u);
    my $ip = $udbr->quote($opts->{'limit_by_ip'} || "0.0.0.0");
    $opts->{'ip'} = $ip;
    return 0 unless $u->rate_check( $ratename, $count, $opts );

    # log current
    $count = $count + 0;
    my $userid = $u->userid;
    $u->do("INSERT INTO ratelog (userid, rlid, evttime, ip, quantity) VALUES ".
           "($userid, $rp->{'id'}, $now, INET_ATON($ip), $count)");

    # delete memcache, except in the case of rate limiting by ip
    unless ($opts->{limit_by_ip}) {
        LJ::MemCache::delete($u->rate_memkey($rp));
    }

    return 1;
}


########################################################################
### 10. Banning-Related Functions

=head2 Banning-Related Functions
=cut

sub banned_userids {
    my ( $u ) = @_;
    return LJ::load_rel_user( $u, 'B' );
}

sub ban_note {
    my ( $u, $ban_u, $text ) = @_;
    my @banned;

    if ( ref $ban_u eq 'ARRAY' ) {
        @banned = @$ban_u;  # array of userids
    } elsif ( LJ::isu( $ban_u ) ) {
        @banned = ( $ban_u->id );
    } elsif ( defined $ban_u ) {
        my $uid = LJ::want_userid( $ban_u );
        @banned = ( $uid ) if defined $uid;
    }
    return unless @banned;

    if ( defined $text ) {
        my $dbh = LJ::get_db_writer();
        my $remote = LJ::get_remote();
        my $remote_id = $remote ? $remote->id : 0;
        my @data = map { ( $u->id, $_, $remote_id, $text ) } @banned;
        my $qps = join( ', ', map { '(?,?,?,?)' } @banned );

        $dbh->do( "REPLACE INTO bannotes (journalid, banid, remoteid, notetext) "
                . "VALUES $qps", undef, @data );
        die $dbh->errstr if $dbh->err;
        return 1;

    } else {
        my $dbr = LJ::get_db_reader();
        my $qs = join( ', ', map { '?' } @banned );
        my $data = $dbr->selectall_arrayref(
            "SELECT banid, remoteid, notetext FROM bannotes " .
            "WHERE journalid=? AND banid IN ($qs)", undef, $u->id, @banned );
        die $dbr->errstr if $dbr->err;

        my ( %rows, %rus );
        foreach ( @$data ) {
            my ( $bid, $rid, $note ) = @$_;
            if ( $note && $rid && $rid != $u->id ) {
                # display the author of the note
                if ( $rus{$rid} ||= LJ::load_userid( $rid ) ) {
                    my $username = $rus{$rid}->user;
                    $note = "<user name=$username>: $note";
                }
            }
            $rows{$bid} = $note;
        }

        return \%rows;
    }
}

sub ban_notes {
    my ( $u ) = @_;
    my $banned = LJ::load_rel_user( $u, 'B' );
    return $u->ban_note( $banned );
}

sub ban_user {
    my ($u, $ban_u) = @_;

    my $remote = LJ::get_remote();
    $u->log_event('ban_set', { actiontarget => $ban_u->id, remote => $remote });

    return LJ::set_rel($u->id, $ban_u->id, 'B');
}


sub ban_user_multi {
    my ($u, @banlist) = @_;

    LJ::set_rel_multi(map { [$u->id, $_, 'B'] } @banlist);

    my $us = LJ::load_userids(@banlist);
    foreach my $banuid (@banlist) {
        $u->log_event('ban_set', { actiontarget => $banuid, remote => LJ::get_remote() });
        LJ::Hooks::run_hooks('ban_set', $u, $us->{$banuid}) if $us->{$banuid};
    }

    return 1;
}

# return if $target is banned from $u's journal
sub has_banned {
    my ( $u, $target ) = @_;

    my $uid = LJ::want_userid( $u );
    my $jid = LJ::want_userid( $target );
    return 1 unless $uid && $jid;
    return 0 if $uid == $jid;  # can't ban yourself

    return LJ::check_rel( $uid, $jid, 'B' );
}


sub unban_user_multi {
    my ($u, @unbanlist) = @_;

    LJ::clear_rel_multi(map { [$u->id, $_, 'B'] } @unbanlist);
    $u->ban_note( \@unbanlist, '' );

    my $us = LJ::load_userids(@unbanlist);
    foreach my $banuid (@unbanlist) {
        $u->log_event('ban_unset', { actiontarget => $banuid, remote => LJ::get_remote() });
        LJ::Hooks::run_hooks('ban_unset', $u, $us->{$banuid}) if $us->{$banuid};
    }

    return 1;
}


########################################################################
### Selective Screening functions

# return if $target's comments will automatically be screened in $u's journal
sub has_autoscreen {
    my ( $u, $target ) = @_;

    my $uid = LJ::want_userid( $u );
    my $jid = LJ::want_userid( $target );
    return 0 unless $uid && $jid;  #can't autoscreen anons ($jid == 0)
    return 0 if $uid == $jid;  # can't autoscreen yourself

    return LJ::check_rel( $uid, $jid, 'S' );
}


########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

########################################################################
###  9. Logging and Recording Actions

=head2 Logging and Recording Actions (LJ)
=cut

# <LJFUNC>
# class: logging
# name: LJ::statushistory_add
# des: Adds a row to a user's statushistory
# info: See the [dbtable[statushistory]] table.
# returns: boolean; 1 on success, 0 on failure
# args: userid, adminid, shtype, notes?
# des-userid: The user being acted on.
# des-adminid: The site admin doing the action.
# des-shtype: The status history type code.
# des-notes: Optional notes associated with this action.
# </LJFUNC>
sub statushistory_add {
    my ( $userid, $actid, $shtype, $notes ) = @_;
    my $dbh = LJ::get_db_writer();

    $userid = LJ::want_userid( $userid ) + 0;
    $actid  = LJ::want_userid( $actid ) + 0;

    my $qshtype = $dbh->quote( $shtype );
    my $qnotes  = $dbh->quote( $notes );

    $dbh->do( "INSERT INTO statushistory (userid, adminid, shtype, notes) ".
              "VALUES ($userid, $actid, $qshtype, $qnotes)" );
    return $dbh->err ? 0 : 1;
}


1;
