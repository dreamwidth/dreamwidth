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

package LJ::User;

use strict;
use LJ::Event::CommunityInvite;
use LJ::Event::CommunityJoinRequest;
use LJ::Event::CommunityJoinApprove;
use LJ::Event::CommunityJoinReject;

# des: Sends an invitation to a user to join a community with the passed abilities.
# args: user to invite, community u, u of maintainer doing the invite, attrs
# des-attrs: a hashref of abilities this user should have (e.g. member, post, unmoderated, ...)
# returns: 1 for success, undef if failure
sub send_comm_invite {
    my ( $u, $cu, $mu, $attrs ) = @_;
    $cu = LJ::want_user( $cu );
    $mu = LJ::want_user( $mu );
    return undef unless LJ::isu( $u ) && $cu && $mu;

    # step 1: if the user has banned the community, don't accept the invite
    return LJ::error('comm_user_has_banned') if $u->has_banned( $cu );

    # step 2: lazily clean out old community invites.
    return LJ::error('db') unless $u->writer;
    $u->do('DELETE FROM inviterecv WHERE userid = ? AND ' .
           'recvtime < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
           undef, $u->{userid});

    return LJ::error('db') unless $cu->writer;
    $cu->do('DELETE FROM invitesent WHERE commid = ? AND ' .
            'recvtime < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
            undef, $cu->{userid});

    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my $argstr = $dbcr->selectrow_array('SELECT args FROM inviterecv WHERE userid = ? AND commid = ?',
                                        undef, $u->{userid}, $cu->{userid});

    # step 4: exceeded outstanding invitation limit?  only if no outstanding invite
    unless ($argstr) {
        my $cdbcr = LJ::get_cluster_def_reader($cu);
        return LJ::error('db') unless $cdbcr;
        my $count = $cdbcr->selectrow_array("SELECT COUNT(*) FROM invitesent WHERE commid = ? " .
                                            "AND userid <> ? AND status = 'outstanding'",
                                            undef, $cu->{userid}, $u->{userid});

        # for now, limit to 500 outstanding invitations per community.  if this is not enough
        # it can be raised or put back to the old system of using community size as an indicator
        # of how many people to allow.
        return LJ::error('comm_invite_limit') if $count > 500;
    }

    # step 5: setup arg string as url-encoded string
    my $newargstr = join('=1&', map { LJ::eurl($_) } @$attrs) . '=1';

    # step 6: branch here to update or insert
    if ($argstr) {
        # merely an update, so just do it quietly
        $u->do("UPDATE inviterecv SET args = ? WHERE userid = ? AND commid = ?",
               undef, $newargstr, $u->{userid}, $cu->{userid});

        $cu->do("UPDATE invitesent SET args = ?, status = 'outstanding' WHERE commid = ? AND userid = ?",
                undef, $newargstr, $cu->{userid}, $u->{userid});
    } else {
         # insert new data, as this is a new invite
         $u->do("INSERT INTO inviterecv VALUES (?, ?, ?, UNIX_TIMESTAMP(), ?)",
                undef, $u->{userid}, $cu->{userid}, $mu->{userid}, $newargstr);

         $cu->do("REPLACE INTO invitesent VALUES (?, ?, ?, UNIX_TIMESTAMP(), 'outstanding', ?)",
                 undef, $cu->{userid}, $u->{userid}, $mu->{userid}, $newargstr);
    }

    # Fire community invite event
    LJ::Event::CommunityInvite->new($u, $mu, $cu)->fire if LJ::is_enabled('esn');

    # step 7: error check database work
    return LJ::error('db') if $u->err || $cu->err;

    # success
    return 1;
}

# des: Accepts an invitation a user has received.  This does all the work to make the
#      user join the community as well as sets up privileges.
# args: user accepting invite, community the user is joining
# returns: 1 for success, undef if failure
sub accept_comm_invite {
    my ( $u, $cu ) = @_;
    $cu = LJ::want_user( $cu );
    return undef unless LJ::isu( $u ) && $cu;

    # get their invite to make sure they have one
    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my $argstr = $dbcr->selectrow_array('SELECT args FROM inviterecv WHERE userid = ? AND commid = ? ' .
                                        'AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
                                        undef, $u->{userid}, $cu->{userid});
    return undef unless $argstr;

    # decode to find out what they get
    my $args = {};
    LJ::decode_url_string($argstr, $args);

    # valid invite.  let's accept it as far as the community listing us goes.
    # 1, 0 means add comm to user's read list, but don't auto-add P edge.
    my $joined = 0;
    $joined = $u->join_community( $cu, 1, 0, moderated_add => 1 ) or return undef
        if $args->{member};

    # now grant necessary abilities
    my %edgelist = (
        post => 'P',
        preapprove => 'N',
        moderate => 'M',
        admin => 'A',
    );
    foreach (keys %edgelist) {
        LJ::set_rel($cu->{userid}, $u->{userid}, $edgelist{$_}) if $args->{$_};
    }

    # now we can delete the invite and update the status on the other side
    return LJ::error('db') unless $u->writer;
    $u->do("DELETE FROM inviterecv WHERE userid = ? AND commid = ?",
           undef, $u->{userid}, $cu->{userid});

    return LJ::error('db') unless $cu->writer;
    $cu->do("UPDATE invitesent SET status = 'accepted' WHERE commid = ? AND userid = ?",
            undef, $cu->{userid}, $u->{userid});

    # done
    return 1;
}

# des: Rejects an invitation a user has received.
# args: user rejecting invite, community the user is not joining
# returns: 1 for success, undef if failure
sub reject_comm_invite {
    my ( $u, $cu ) = @_;
    $cu = LJ::want_user( $cu );
    return undef unless LJ::isu( $u ) && $cu;

    # get their invite to make sure they have one
    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my $test = $dbcr->selectrow_array('SELECT userid FROM inviterecv WHERE userid = ? AND commid = ? ' .
                                      'AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
                                      undef, $u->{userid}, $cu->{userid});
    return undef unless $test;

    # now just reject it
    return LJ::error('db') unless $u->writer;
    $u->do("DELETE FROM inviterecv WHERE userid = ? AND commid = ?",
              undef, $u->{userid}, $cu->{userid});

    return LJ::error('db') unless $cu->writer;
    $cu->do("UPDATE invitesent SET status = 'rejected' WHERE commid = ? AND userid = ?",
            undef, $cu->{userid}, $u->{userid});

    # done
    return 1;
}

# des: Get a list of sent invitations from the past 30 days for given comm.
# returns: hashref of arrayrefs with keys userid, maintid, recvtime, status, args (itself
#          a hashref of what abilities the user would be given)
sub get_sent_invites {
    my ( $cu)  = @_;
    return undef unless LJ::isu( $cu );

    # now hit the database for their recent invites
    my $dbcr = LJ::get_cluster_def_reader($cu);
    return LJ::error('db') unless $dbcr;
    my $data = $dbcr->selectall_arrayref('SELECT userid, maintid, recvtime, status, args FROM invitesent ' .
                                         'WHERE commid = ? AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
                                          undef, $cu->{userid});

    # now break data down into usable format for caller
    my @res;
    foreach my $row (@{$data || []}) {
        my $temp = {};
        LJ::decode_url_string($row->[4], $temp);
        push @res, {
            userid => $row->[0]+0,
            maintid => $row->[1]+0,
            recvtime => $row->[2],
            status => $row->[3],
            args => $temp,
        };
    }

    # all done
    return \@res;
}

# des: Gets a list of pending community invitations for a user.
# returns: [ [ commid, maintainerid, time, args(url encoded) ], [ ... ], ... ] or
#          undef if failure
sub get_pending_invites {
    my ( $u)  = @_;
    return undef unless LJ::isu( $u );

    # hit up database for invites and return them
    my $dbcr = LJ::get_cluster_def_reader($u);
    return LJ::error('db') unless $dbcr;
    my $pending = $dbcr->selectall_arrayref('SELECT commid, maintid, recvtime, args FROM inviterecv WHERE userid = ? ' .
                                            'AND recvtime > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))',
                                            undef, $u->{userid});
    return undef if $dbcr->err;
    return $pending;
}

# des: Revokes a list of outstanding invitations to a community.
# args: community user object, list of userids to revoke invitations for
# returns: 1 if success, undef if error
sub revoke_invites {
    my ( $cu, @uids ) = @_;
    return undef unless LJ::isu( $cu ) && @uids;

    foreach my $uid (@uids) {
        return undef unless int($uid) > 0;
    }
    my $in = join(',', @uids);

    return LJ::error('db') unless $cu->writer;
    $cu->do("DELETE FROM invitesent WHERE commid = ? AND " .
            "userid IN ($in)", undef, $cu->{userid});
    return LJ::error('db') if $cu->err;

    # remove from inviterecv also,
    # otherwise invite cannot be resent for over 30 days
    foreach my $uid (@uids) {
        my $u =  LJ::want_user($uid);
        $u->do("DELETE FROM inviterecv WHERE userid = ? AND " .
               "commid = ?", undef, $uid, $cu->{userid});
    }

    # success
    return 1;
}

# des: Makes a user leave a community.  Takes care of all [special[reluserdefs]] and friend stuff.
# args: u doing the leaving, comm being left, unwatch (boolean)
# returns: 1 if success, undef if error of some sort (cu not a comm, u not in
#          comm, db error, etc)
sub leave_community {
    my ( $u, $cu, $unwatch ) = @_;
    $cu = LJ::want_user( $cu );

    return LJ::error( 'comm_not_found' ) unless LJ::isu( $u ) && $cu;
    return LJ::error( 'comm_not_comm' ) unless $cu->is_community;

    # log to userlog if remote is a maintainer
    $cu->log_event( 'maintainer_remove', { actiontarget => $u->id, remote => $u } )
            if $u->can_manage( $cu );

    # remove community membership
    return undef
        unless $u->remove_edge( $cu, member => {} );

    # clear edges that effect this relationship
    foreach my $edge (qw(P N A M)) {
        LJ::clear_rel($cu->{userid}, $u->{userid}, $edge);
    }

    # unwatch user -> comm?
    return 1 unless $unwatch;
    $u->remove_edge( $cu, watch => {} );

    # don't care if we failed the removal of comm from user's friends list...
    return 1;
}

# des: Makes a user join a community.  Takes care of all [special[reluserdefs]] and watch stuff.
# args: u joining, u of comm, watch?, noauto?
# des-watch: 1 to add this comm to user's watch list, else not
# des-noauto: if defined, 1 adds P edge, 0 does not; else, base on community postlevel
# returns: 1 if success, undef if error of some sort (ucommid not a comm, uuserid already in
#          comm, db error, etc)
sub join_community {
    my ( $u, $cu, $watch, $canpost, %opts ) = @_;
    $cu = LJ::want_user( $cu );
    return LJ::error( 'comm_not_found' ) unless LJ::isu( $u ) && $cu;
    return LJ::error( 'comm_not_comm' ) unless $cu->is_community;

    # try to join the community, and return if it didn't work
    $u->add_edge( $cu, member => {
        moderated_add => $opts{moderated_add} ? 1 : 0,
    } ) or return LJ::error('db');

    # add edges that effect this relationship... if the user sent a fourth
    # argument, use that as a bool.  else, load commrow and use the postlevel.
    my $addpostacc = 0;
    # only person users can post
    if ( $u->is_personal ) {
        if ( defined $canpost ) {
            $addpostacc = $canpost ? 1 : 0;
        } else {
            my $crow = $cu->get_community_row;
            $addpostacc = $crow->{postlevel} eq 'members'
                    || ( $crow->{postlevel} eq "select" && $cu->prop( 'comm_postlevel_new' ) );
        }
    }

    LJ::set_rel( $cu->{userid}, $u->{userid}, 'P' ) if $addpostacc;

    # user should watch comm?
    return 1 unless $watch;

    # don't do the work if they already watch the comm
    return 1 if $u->watches( $cu );

    # watch the comm
    $u->add_edge( $cu, watch => {} );

    # also automatically add to default view, as most useful behavior
    # this only applies if we are doing a quick / easy join, so it won't affect
    # things if the user is joining + watching communities the long way
    $u->add_to_default_filters( $cu );

    # done
    return 1;
}

# des: Gets data relevant to a community such as their membership level and posting access.
# returns: a hashref with user, userid, name, membership, and postlevel data from the
#          user and community tables; undef if error.
sub get_community_row {
    my ( $cu ) = @_;
    return unless LJ::isu( $cu );

    # hit up database
    my $dbr = LJ::get_db_reader() or return;
    my ($membership, $postlevel) =
        $dbr->selectrow_array('SELECT membership, postlevel FROM community WHERE userid=?',
                              undef, $cu->{userid});
    return if $dbr->err;
    return unless $membership;

    # return result hashref
    my $row = {
        user => $cu->{user},
        userid => $cu->{userid},
        name => $cu->{name},
        membership => $membership,
        postlevel => $postlevel,
    };
    return $row;
}

# des: Gets a list of userids for people that have requested to be added to a community
#      but have not yet actually been approved or rejected.
# returns: an arrayref of userids of people with pending membership requests
sub get_pending_members {
    my ( $cu ) = @_;
    return unless LJ::isu( $cu );

    # database request
    my $dbr = LJ::get_db_reader() or return;
    my $args = $dbr->selectcol_arrayref('SELECT arg1 FROM authactions WHERE userid = ? ' .
                                        "AND action = 'comm_join_request' AND used = 'N'",
                                        undef, $cu->{userid}) || [];

    # parse out the args
    my @list;
    foreach (@$args) {
        push @list, $1+0 if $_ =~ /^targetid=(\d+)$/;
    }

    return \@list;
}

# des: Approves someone's request to join a community.  This updates the [dbtable[authactions]] table
#      as appropriate as well as does the regular join logic.  This also generates an e-mail to
#      be sent to the user notifying them of the acceptance.
# args: community user object, userid to approve
# returns: 1 on success, 0/undef on error
sub approve_pending_member {
    my ( $cu, $userid ) = @_;
    my $u = LJ::want_user($userid);
    return unless LJ::isu( $cu ) && $u;

    # step 1, update authactions table
    my $dbh = LJ::get_db_writer();
    my $count = $dbh->do("UPDATE authactions SET used = 'Y' WHERE userid = ? AND arg1 = ?",
                         undef, $cu->{userid}, "targetid=$u->{userid}");
    return unless $count;

    # step 2, make user join the community
    # 1 means "add community to user's friends list"
    return unless $u->join_community( $cu, 1, undef, moderated_add => 1 );

    # step 3, email the user
    my %params = (event => 'CommunityJoinApprove', journal => $u);
    unless ($u->has_subscription(%params)) {
        $u->subscribe(%params, method => 'Email');
    }
    LJ::Event::CommunityJoinApprove->new($u, $cu)->fire if LJ::is_enabled('esn');

    $cu->memc_delete( "pendingmemct" );

    return 1;
}

# des: Rejects someone's request to join a community.
#      Updates [dbtable[authactions]] and generates an e-mail to the user.
# args: community user object, userid to reject
# returns: 1 on success, 0/undef on error
sub reject_pending_member {
    my ( $cu, $u ) = @_;
    $u = LJ::want_user( $u );
    return unless LJ::isu( $cu ) && $u;

    # step 1, update authactions table
    my $dbh = LJ::get_db_writer() or return;
    my $count = $dbh->do("UPDATE authactions SET used = 'Y' WHERE userid = ? AND arg1 = ?",
                         undef, $cu->{userid}, "targetid=$u->{userid}");
    return unless $count;

    # step 2, email the user
    my %params = (event => 'CommunityJoinReject', journal => $u);
    unless ($u->has_subscription(%params)) {
        $u->subscribe(%params, method => 'Email');
    }
    LJ::Event::CommunityJoinReject->new($u, $cu)->fire if LJ::is_enabled('esn');

    $cu->memc_delete( "pendingmemct" );

    return 1;
}

# des: Registers an authaction to add a user to a
#      community and sends an approval email to the maintainers
# returns: Hashref; output of LJ::register_authaction()
#          includes datecreate of old row if no new row was created
# args: comm user object, user object to add
sub comm_join_request {
    my ( $comm, $u ) = @_;
    return undef unless LJ::isu( $comm ) && LJ::isu( $u );

    my $arg = "targetid=" . $u->id;
    my $dbh = LJ::get_db_writer() or return undef;

    # check for duplicates within the same hour (to prevent spamming)
    my $oldaa = $dbh->selectrow_hashref("SELECT aaid, authcode, datecreate FROM authactions " .
                                        "WHERE userid=? AND arg1=? " .
                                        "AND action='comm_join_request' AND used='N' " .
                                        "AND NOW() < datecreate + INTERVAL 1 HOUR " .
                                        "ORDER BY 1 DESC LIMIT 1",
                                        undef, $comm->id, $arg);

    return $oldaa if $oldaa;

    # insert authactions row
    my $aa = LJ::register_authaction($comm->id, 'comm_join_request', $arg);
    return undef unless $aa;

    # if there are older duplicates, invalidate any existing unused authactions of this type
    $dbh->do("UPDATE authactions SET used='Y' WHERE userid=? AND aaid<>? AND arg1=? " .
             "AND action='comm_invite' AND used='N'",
             undef, $comm->id, $aa->{'aaid'}, $arg);

    # get maintainers of community
    my $adminids = LJ::load_rel_user($comm->{userid}, 'A') || [];
    my $admins = LJ::load_userids(@$adminids);

    # now prepare the emails
    foreach my $au (values %$admins) {
        next unless $au && !$au->is_expunged;

        # unless it's a hyphen, we need to migrate
        my $prop = $au->prop("opt_communityjoinemail");
        if ($prop ne "-") {
            if ($prop ne "N") {
                my %params = (event => 'CommunityJoinRequest', journal => $au);
                unless ($au->has_subscription(%params)) {
                    $au->subscribe(%params, method => $_) foreach qw(Inbox Email);
                }
            }

            $au->set_prop("opt_communityjoinemail", "-");
        }

        LJ::Event::CommunityJoinRequest->new($au, $u, $comm)->fire;
    }

    $comm->memc_delete( 'pendingmemct' );

    return $aa;
}

# Get membership and posting level settings for a community
sub get_comm_settings {
    my ( $c ) = @_;
    return undef unless LJ::isu( $c );

    my $cid = $c->userid;
    my ($membership, $postlevel);
    my $memkey = [ $cid, "commsettings:$cid" ];

    my $memval = LJ::MemCache::get($memkey);
    ( $membership, $postlevel ) = @$memval if $memval;
    return ( $membership, $postlevel )
        if ( $membership && $postlevel );

    my $dbr = LJ::get_db_reader() or return undef;
    ( $membership, $postlevel ) =
        $dbr->selectrow_array("SELECT membership, postlevel FROM community WHERE userid=?", undef, $cid);

    LJ::MemCache::set($memkey, [$membership,$postlevel] ) if ( $membership && $postlevel );

    return ($membership, $postlevel);
}

# Set membership and posting level settings for a community
sub set_comm_settings {
    my ( $c, $u, $opts ) = @_;

    die "Invalid users passed to set_comm_settings"
        unless LJ::isu( $c ) && LJ::isu( $u );

    die "User cannot modify this community"
        unless $u->can_manage_other( $c );

    my @settings = qw/membership postlevel/;
    my $updates = join(', ', map { $opts->{$_} ? "$_=?" : () } @settings);
    my @update_values = map { $opts->{$_} || () } @settings;

    die "Membership or posting level is not available"
        unless @update_values;

    my $cid = $c->userid;

    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT INTO community (userid, membership, postlevel) VALUES (?,?,?) ON DUPLICATE KEY UPDATE $updates" , undef, $cid, $opts->{membership} || 'open', $opts->{postlevel} || 'members', @update_values);

    my $memkey = [ $cid, "commsettings:$cid" ];
    LJ::MemCache::delete($memkey);

    return;
}

sub maintainer_linkbar {
    my ( $comm, $page, $in_foundation_page ) = @_;
    die "Invalid arguments passed to maintainer_linkbar"
        unless LJ::isu( $comm ) and defined $page;

    my $username = $comm->user;
    my @links;

    if ( LJ::Hooks::are_hooks( 'community_manage_link_info' ) ) {
        my %manage_link_info = LJ::Hooks::run_hook( 'community_manage_link_info', $username );
        if (keys %manage_link_info) {
            push @links, $page eq "account" ?
                "<strong>$manage_link_info{text}</strong>" :
                "<a href='$manage_link_info{url}'>$manage_link_info{text}</a>";
        }
    }

    push @links, (
        $page eq "profile" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actinfo2') . "</strong>" :
            "<a href='$LJ::SITEROOT/manage/profile/?authas=$username'>" . LJ::Lang::ml('/community/manage.bml.commlist.actinfo2') . "</a>",
        $page eq "customize" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.customize2') . "</strong>" :
            "<a href='$LJ::SITEROOT/customize/?authas=$username'>" . LJ::Lang::ml('/community/manage.bml.commlist.customize2') . "</a>",
        $page eq "settingsaccount" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actsettingsaccount') . "</strong>" :
            "<a href='$LJ::SITEROOT/manage/settings/?authas=$username&cat=community'>" . LJ::Lang::ml('/community/manage.bml.commlist.actsettingsaccount') . "</a>",
        $page eq "invites" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actinvites') . "</strong>" :
            "<a href='$LJ::SITEROOT/communities/$username/members/new'>" . LJ::Lang::ml('/community/manage.bml.commlist.actinvites') . "</a>",
        $page eq "members" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.actmembers2') . "</strong>" :
            "<a href='" . $comm->community_manage_members_url . "'>" . LJ::Lang::ml('/community/manage.bml.commlist.actmembers2') . "</a>",
        $page eq "queue" ?
            "<strong>" . LJ::Lang::ml('/community/manage.bml.commlist.queue') . "</strong>" :
            "<a href='" . $comm->moderation_queue_url . "'>" . LJ::Lang::ml('/community/manage.bml.commlist.queue' ) . "</a>",

    );

    my $ret .= "<strong>" . LJ::Lang::ml('/community/manage.bml.managelinks', { user => $comm->ljuser_display }) . "</strong> ";
    $ret .= join(" | ", @links);

    return $in_foundation_page ? $ret : "<p style='margin-bottom: 20px;'>$ret</p>";
}

sub get_mod_queue_count {
    my ( $cu ) = @_;
    return 0 unless LJ::isu( $cu ) && $cu->is_community;

    my $mqcount = $cu->memc_get( 'mqcount' );
    return $mqcount if defined $mqcount;

    # if it's not in memcache, hit the db
    my $dbr = LJ::get_cluster_reader( $cu );
    my $sql = "SELECT COUNT(*) FROM modlog WHERE journalid=" . $cu->id;
    $mqcount = $dbr->selectrow_array( $sql ) || 0;

    # store in memcache for 10 minutes
    $cu->memc_set( 'mqcount' => $mqcount, 600 );
    return $mqcount;
}

sub get_pending_members_count {
    my ( $cu ) = @_;
    return 0 unless LJ::isu( $cu ) && $cu->is_community;

    my $pending_count = $cu->memc_get( 'pendingmemct' );
    return $pending_count if defined $pending_count;

    # seems to be doing some additional parsing, which would make this
    # number potentially incorrect if you just do SELECT COUNT
    # so grab the parsed list and count it
    $pending_count = scalar @{ $cu->get_pending_members };
    $cu->memc_set( 'pendingmemct' => $pending_count, 600 );

    return $pending_count;
}

# returns the membership level of a community
sub membership_level {
    my ( $u ) = @_;

    return undef unless $u->is_community;

    my ( $membership_level ) = $u->get_comm_settings;
    return $membership_level || '';
}

# returns the post level of a community
sub post_level {
    my $u = $_[0];
    return undef unless $u->is_community;

    my ( $membership_level, $post_level ) = $u->get_comm_settings;
    return $post_level || '';
}
# helper methods for checking some values about communities
sub is_closed_membership    { $_[0]->membership_level eq 'closed' ? 1 : 0;    }
sub is_moderated_membership { $_[0]->membership_level eq 'moderated' ? 1 : 0; }
sub is_open_membership      { $_[0]->membership_level eq 'open' ? 1 : 0;      }
sub has_moderated_posting   { $_[0]->prop( 'moderated' );                     }
sub has_open_posting        { $_[0]->prop( 'nonmember_posting' ) ? 1 : 0;     }

# returns an array of maintainer userids
sub maintainer_userids {
    my ( $u ) = @_;

    return () unless $u->is_community;
    return @{LJ::load_rel_user_cache( $u->id, 'A' )};
}

# returns an array of moderator userids
sub moderator_userids {
    my ( $u ) = @_;

    return () unless $u->is_community && $u->has_moderated_posting;
    return @{LJ::load_rel_user_cache( $u->id, 'M' )};
}

# accepts (optionally) a list of roles to filter by
# returns two hashrefs:
#   { userid => { "userid" => userid, "name" => username, "A" => 1, "P" => 1 ... }, ... }
#   { "M" => count, "P" => count, ... }
#
# not cached
sub get_members_by_role {
    my ( $cu, $types ) = @_;

    my @all_types = qw ( A P M N E );
    my @filter_by_types = scalar @$types ? @$types : @all_types;
    my %filter_by = map { $_ => 1 } @filter_by_types;
    my $type_in = join ", ", map { qq('$_') } @all_types;

    # need a dbr now
    my $dbr = LJ::get_db_reader();

    # get all community edges
    my $sth = $dbr->prepare("SELECT r.targetid, r.type, u.user FROM reluser r, useridmap u " .
                            "WHERE r.targetid = u.userid AND r.userid=? AND r.type IN ( $type_in )");
    $sth->execute( $cu->userid );

    my %userinfo;       # contains the data that we fetched
    my %users;          # the users we return / are interested in
    my %count;
    while ( my ( $id, $type, $user ) = $sth->fetchrow_array ) {
        $userinfo{$id}->{userid} = $id;
        $userinfo{$id}->{name} = $user;
        $userinfo{$id}->{$type} = 1;

        # filter down to just the roles we are interested in
        if ( $filter_by{$type} ) {
            $users{$id} = $userinfo{$id};

            # only count if we actually include in the final results
            $count{$type}++;
        }
    }

    return ( \%users, \%count );
}

# accepts a user object to fetch member data of
# returns same as get_members_by_role
sub get_member {
    my ( $cu, $u ) = @_;

    return ( {}, {} ) unless LJ::isu( $u );

    my $dbr = LJ::get_db_reader();

    # get all community edges
    my $results = $dbr->selectall_arrayref("SELECT r.targetid, r.type, u.user FROM reluser r, useridmap u " .
                            "WHERE r.targetid = u.userid AND r.userid=? AND r.targetid=?", undef, $cu->userid, $u->userid );

    my %userinfo;
    my %count;
    foreach ( @$results ) {
        my ( $id, $type, $user ) = @$_;

        $userinfo{$id}->{userid} = $id;
        $userinfo{$id}->{name} = $user;
        $userinfo{$id}->{$type} = 1;

        $count{$type}++;
    }

    return ( \%userinfo, \%count );
}



=head2 C<< $cu->notify_administrator_remove( $admin_u_del, $remote ) >>

Notify a user when they've been removed from being admin for a community.
$admin_u_del is the user to be removed; $remote is the user doing the removing

=cut
sub notify_administrator_remove {
    my ( $cu, $admin_u_del, $remote ) = @_;
    $cu->_notify_administrator( $admin_u_del, $remote, "maintainer_remove" )
}


=head2 C<< $cu->notify_administrator_add( $admin_u_new, $remote ) >>

Notify a user when they've been added as an admin to a community.
$admin_u_new is the user to be added; $remote is the user doing the adding.

=cut
sub notify_administrator_add {
    my ( $cu, $admin_u_new, $remote ) = @_;
    $cu->_notify_administrator( $admin_u_new, $remote, "maintainer_add" );
}

# TODO: check if user wants to receive emails?
sub _notify_administrator {
    my ( $cu, $target_u, $remote, $action ) = @_;
    $cu->log_event( $action, { actiontarget => $target_u->id, remote => $remote } );

    return if ! $target_u || $target_u->is_expunged;

    my $email_body;
    my $email_subject;
    my $ml_scope = "/communities/members/edit.tt";
    if ( $action eq "maintainer_add" ) {
        $email_body = LJ::Lang::ml( "$ml_scope.email.admin.add.body", {
                comm => $cu->name_raw,
                community_url => $cu->journal_base,

                community_management_url => "$LJ::SITEROOT/communities/list"
            } );
        $email_subject = LJ::Lang::ml( "$ml_scope.email.admin.add.subject", { comm => $cu->name_raw } );
    } else {
        $email_body = LJ::Lang::ml( "$ml_scope.email.admin.delete.body", {
                admin => $remote->user,

                comm => $cu->name_raw,
                community_url => $cu->journal_base,
            });
        $email_subject = LJ::Lang::ml( "$ml_scope.email.admin.delete.subject", { comm => $cu->name_raw } );
    }

    LJ::send_formatted_mail(
            to => $target_u->email_raw,
            greeting_user => $target_u->user,

            from => $LJ::BOGUS_EMAIL,
            fromname => qq{"$LJ::SITENAME"},

            subject => $email_subject,
            body => $email_body,
    );
}

=head2 C<< $cu->get_mod_queue >>

Get entries pending moderation

=cut
sub get_mod_queue {
    my ( $cu ) = @_;

    my $dbcr = LJ::get_cluster_def_reader( $cu );

    my @entries;
    my $sth = $dbcr->prepare( "SELECT * FROM modlog WHERE journalid=?" );
    $sth->execute( $cu->userid );

    while ($_ = $sth->fetchrow_hashref) {
        push @entries, $_;
    }

    return sort { $a->{logtime} lt $b->{logtime} } @entries;
}
1;
