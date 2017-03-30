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
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger( __PACKAGE__ );

use Carp qw/ confess /;
use LJ::Identity;

use DW::Pay;
use DW::User::OpenID;
use DW::InviteCodes::Promo;

########################################################################
### 1. Creating and Deleting Accounts

=head1 LJ::User Methods

=head2 Creating and Deleting Accounts
=cut

sub can_expunge {
    my $u = shift;

    # must be already deleted
    return 0 unless $u->is_deleted;

    # and deleted 30 days ago
    my $expunge_days = LJ::conf_test($LJ::DAYS_BEFORE_EXPUNGE) || 30;
    return 0 unless $u->statusvisdate_unix < time() - 86400*$expunge_days;

    my $hook_rv = 0;
    if (LJ::Hooks::are_hooks("can_expunge_user", $u)) {
        $hook_rv = LJ::Hooks::run_hook("can_expunge_user", $u);
        return $hook_rv ? 1 : 0;
    }

    return 1;
}


# class method to create a new account.
sub create {
    my ($class, %opts) = @_;

    my $err = sub {
        $log->warn( @_ );
        return undef;
    };

    my $username = LJ::canonical_username($opts{user}) or return;

    my $cluster     = $opts{cluster} || LJ::DB::new_account_cluster();
    my $caps        = $opts{caps} || $LJ::NEWUSER_CAPS;
    my $journaltype = $opts{journaltype} || "P";

    # non-clustered accounts aren't supported anymore
    return $err->( 'Invalid cluster: ', $cluster )
        unless $cluster;

    my $dbh = LJ::get_db_writer();

    $dbh->do('INSERT INTO user (user, clusterid, dversion, caps, journaltype) ' .
             'VALUES (?, ?, ?, ?, ?)', undef,
             $username, $cluster, $LJ::MAX_DVERSION, $caps, $journaltype);
    return $err->( 'Database error: ', $dbh->errstr ) if $dbh->err;

    my $userid = $dbh->{'mysql_insertid'};
    return $err->( 'Failed to get userid' ) unless $userid;

    $dbh->do('INSERT INTO useridmap (userid, user) VALUES (?, ?)',
             undef, $userid, $username);
    return $err->( 'Database error: ', $dbh->errstr ) if $dbh->err;

    $dbh->do('INSERT INTO userusage (userid, timecreate) VALUES (?, NOW())',
             undef, $userid);
    return $err->( 'Database error: ', $dbh->errstr ) if $dbh->err;

    my $u = LJ::load_userid( $userid, 'force' ) or return;
    DW::Stats::increment( 'dw.action.account.create', 1,
            [ 'journal_type:' . $u->journaltype_readable ] );

    my $status   = $opts{status}   || ($LJ::EVERYONE_VALID ? 'A' : 'N');
    my $name     = $opts{name}     || $username;
    my $bdate    = $opts{bdate}    || '0000-00-00';
    my $email    = $opts{email}    || '';
    my $password = $opts{password} || '';

    $u->update_self( { status => $status, name => $name, bdate => $bdate,
                       email => $email, password => $password, %LJ::USER_INIT } );

    my $remote = LJ::get_remote();
    $u->log_event('account_create', { remote => $remote });

    # only s2 is supported
    $u->set_prop( stylesys => 2 );

    while (my ($name, $val) = each %LJ::USERPROP_INIT) {
        $u->set_prop($name, $val);
    }

    if ($opts{extra_props}) {
        while (my ($key, $value) = each( %{$opts{extra_props}} )) {
            $u->set_prop( $key => $value );
        }
    }

    if ($opts{status_history}) {
        my $system = LJ::load_user( 'system' );
        if ($system) {
            while (my ($key, $value) = each( %{$opts{status_history}} )) {
                LJ::statushistory_add($u, $system, $key, $value);
            }
        }
    }

    LJ::Hooks::run_hooks(
        'post_create',
        {
            userid => $userid,
            user   => $username,
            code   => undef,
            news   => $opts{get_news},
        }
    );

    return $u;
}


sub create_community {
    my ($class, %opts) = @_;

    $opts{journaltype} = "C";
    my $u = LJ::User->create(%opts) or return;

    $u->set_prop("nonmember_posting", $opts{nonmember_posting}+0);
    $u->set_prop("moderated", $opts{moderated}+0);
    $u->set_prop("adult_content", $opts{journal_adult_settings}) if LJ::is_enabled( 'adult_content' );
    $u->set_default_style unless $LJ::_T_CONFIG;

    my $admin = $opts{admin_userid} ?
        LJ::load_userid( $opts{admin_userid} ) :
        LJ::get_remote();

    if ( $admin ) {
        LJ::set_rel($u, $admin, "A");  # maintainer
        LJ::set_rel($u, $admin, "M") if $opts{moderated}; # moderator if moderated
        $admin->join_community( $u, 1, 1 ); # member

        $u->set_comm_settings( $admin, { membership => $opts{membership},
                                         postlevel => $opts{postlevel} } )
            if exists $opts{membership} && exists $opts{postlevel};
    }
    return $u;
}


sub create_personal {
    my ($class, %opts) = @_;

    my $u = LJ::User->create(%opts) or return;

    $u->set_prop("init_bdate", $opts{bdate});

    # so birthday notifications get sent
    $u->set_next_birthday;

    # Set the default style
    $u->set_default_style;

    if ( $opts{inviter} ) {
        # store inviter, if there was one
        my $inviter = LJ::load_user( $opts{inviter} );
        if ( $inviter ) {
            LJ::set_rel( $u, $inviter, 'I' );
            LJ::statushistory_add( $u, $inviter, 'create_from_invite', "Created new account." );
            if ( $inviter->is_individual ) {
                LJ::Event::InvitedFriendJoins->new( $inviter, $u )->fire;
            }
        }
    }
    # if we have initial subscriptions for new accounts, add them.
    foreach my $user ( @LJ::INITIAL_SUBSCRIPTIONS ) {
        my $userid = LJ::get_userid( $user )
            or next;
        $u->add_edge( $userid, watch => {} );
    }

    # apply any paid time that this account should get
    if ( $opts{code} ) {
        my $code = $opts{code};
        my $itemidref;
        my $promo_code = $LJ::USE_ACCT_CODES ? DW::InviteCodes::Promo->load( code => $code ) : undef;
        if ( $promo_code ) {
            $promo_code->apply_for_user( $u );
        } elsif ( my $cart = DW::Shop::Cart->get_from_invite( $code, itemidref => \$itemidref ) ) {
            my $item = $cart->get_item( $itemidref );
            if ( $item && $item->isa( 'DW::Shop::Item::Account' ) ) {
                # first update the item's target user and the cart
                $item->t_userid( $u->id );
                $cart->save( no_memcache => 1 );

                # now add paid time to the user
                my $from_u = $item->from_userid ? LJ::load_userid( $item->from_userid ) : undef;
                if ( DW::Pay::add_paid_time( $u, $item->class, $item->months ) ) {
                    LJ::statushistory_add( $u, $from_u, 'paid_from_invite',
                            sprintf( "Created new '%s' from order #%d.", $item->class, $item->cartid ) );
                } else {
                    my $paid_error = DW::Pay::error_text() || $@ || 'unknown error';
                    LJ::statushistory_add( $u, $from_u, 'paid_from_invite',
                            sprintf( "Failed to create new '%s' account from order #%d: %s",
                                $item->class, $item->cartid, $paid_error ) );
                }
            }
        }
    }

    # populate some default friends groups
    # FIXME(mark): this should probably be removed or refactored, especially
    # since editfriendgroups is dying/dead
#    LJ::do_request(
#                   {
#                       'mode'           => 'editfriendgroups',
#                       'user'           => $u->user,
#                       'ver'            => $LJ::PROTOCOL_VER,
#                       'efg_set_1_name' => 'Family',
#                       'efg_set_2_name' => 'Local Friends',
#                       'efg_set_3_name' => 'Online Friends',
#                       'efg_set_5_name' => 'Work',
#                       'efg_set_6_name' => 'Mobile View',
#                   }, \%res, { 'u' => $u, 'noauth' => 1, }
#                   );
#
    # subscribe to default events
    $u->subscribe( event => 'OfficialPost', method => 'Inbox' );
    $u->subscribe( event => 'OfficialPost', method => 'Email' ) if $opts{get_news};
    $u->subscribe( event => 'JournalNewComment', journal => $u, method => 'Inbox' );
    $u->subscribe( event => 'JournalNewComment', journal => $u, method => 'Email' );
    $u->subscribe( event => 'AddedToCircle', journal => $u, method => 'Inbox' );
    $u->subscribe( event => 'AddedToCircle', journal => $u, method => 'Email' );
    # inbox notifications for PMs are on for everyone automatically
    $u->subscribe( event => 'UserMessageRecvd', journal => $u, method => 'Email' );
    $u->subscribe( event => 'InvitedFriendJoins', journal => $u, method => 'Inbox' );
    $u->subscribe( event => 'InvitedFriendJoins', journal => $u, method => 'Email' );
    $u->subscribe( event => 'CommunityInvite', journal => $u, method => 'Inbox' );
    $u->subscribe( event => 'CommunityInvite', journal => $u, method => 'Email' );
    $u->subscribe( event => 'CommunityJoinRequest', journal => $u, method => 'Inbox' );
    $u->subscribe( event => 'CommunityJoinRequest', journal => $u, method => 'Email' );

    return $u;
}


sub create_syndicated {
    my ($class, %opts) = @_;

    return unless $opts{feedurl};

    $opts{caps}        = $LJ::SYND_CAPS;
    $opts{cluster}     = $LJ::SYND_CLUSTER;
    $opts{journaltype} = "Y";

    my $u = LJ::User->create(%opts) or return;

    my $dbh = LJ::get_db_writer();
    $dbh->do("INSERT INTO syndicated (userid, synurl, checknext) VALUES (?, ?, NOW())",
             undef, $u->id, $opts{feedurl});
    die $dbh->errstr if $dbh->err;

    my $remote = LJ::get_remote();
    LJ::statushistory_add( $u, $remote, "synd_create", "acct: " . $u->user );

    return $u;
}


sub delete_and_purge_completely {
    my $u = shift;
    # FIXME: delete from user tables
    # FIXME: delete from global tables
    my $dbh = LJ::get_db_writer();

    my @tables = qw(user useridmap reluser priv_map infohistory email password);
    foreach my $table (@tables) {
        $dbh->do("DELETE FROM $table WHERE userid=?", undef, $u->id);
    }

    $dbh->do("DELETE FROM wt_edges WHERE from_userid = ? OR to_userid = ?", undef, $u->id, $u->id);
    $dbh->do("DELETE FROM reluser WHERE targetid=?", undef, $u->id);
    $u->delete_email_alias;

    $dbh->do("DELETE FROM community WHERE userid=?", undef, $u->id)
        if $u->is_community;
    $dbh->do("DELETE FROM syndicated WHERE userid=?", undef, $u->id)
        if $u->is_syndicated;

    return 1;
}


# checks against the file containing our regular expressions to determine if a
# given username is disallowed
sub is_protected_username {
    my ( $class, $username ) = @_;

    # site admins (people with siteadmin:usernames) can override this check and
    # create any account they want
    my $remote = LJ::get_remote();
    return 0 if $remote && $remote->has_priv( siteadmin => 'usernames' );

    my @res = grep { $_ } split( /\r?\n/, LJ::load_include( 'reserved-usernames' ) );
    foreach my $re ( @res ) {
        return 1 if $username =~ /$re/;
    }

    return 0;
}


sub who_invited {
    my $u = shift;
    my $inviterid = LJ::load_rel_user($u, 'I');

    return LJ::load_userid($inviterid);
}


########################################################################
###  2. Statusvis and Account Types

=head2 Statusvis and Account Types
=cut

sub get_previous_statusvis {
    my $u = shift;

    my $extra = $u->selectcol_arrayref(
        "SELECT extra FROM userlog WHERE userid=? AND action='accountstatus' ORDER BY logtime DESC",
        undef, $u->userid );
    my @statusvis;
    foreach my $e (@$extra) {
        my %fields;
        LJ::decode_url_string($e, \%fields, []);
        push @statusvis, $fields{old};
    }
    return @statusvis;
}

sub is_deleted {
    my $u = shift;
    return $u->statusvis eq 'D';
}


sub is_expunged {
    my $u = shift;
    return $u->statusvis eq 'X' || $u->clusterid == 0;
}

sub is_inactive {
    my $u = shift;
    my $statusvis = $u->statusvis;
    # true if deleted, expunged or suspended
    return $statusvis eq 'D' || $statusvis eq 'X' || $statusvis eq 'S';
}

sub is_locked {
    my $u = shift;
    return $u->statusvis eq 'L';
}


sub is_memorial {
    my $u = shift;
    return $u->statusvis eq 'M';
}


sub is_readonly {
    my $u = shift;
    return $u->statusvis eq 'O' || $u->get_cap( 'readonly' );
}


sub is_renamed {
    my $u = shift;
    return $u->statusvis eq 'R';
}

sub is_rp_account {
    my $u = shift;
    return $u->prop( 'opt_rpacct' );
}

sub is_suspended {
    my $u = shift;
    return $u->statusvis eq 'S';
}


# returns if this user is considered visible
sub is_visible {
    my $u = shift;
    return $u->statusvis eq 'V';
}


sub set_deleted {
    my $u = shift;
    my $res = $u->set_statusvis('D');

    # run any account cancellation hooks
    LJ::Hooks::run_hooks("account_delete", $u);
    return $res;
}


sub set_expunged {
    my $u = shift;
    return $u->set_statusvis('X');
}


sub set_locked {
    my $u = shift;
    return $u->set_statusvis('L');
}


sub set_memorial {
    my $u = shift;
    return $u->set_statusvis('M');
}


sub set_readonly {
    my $u = shift;
    return $u->set_statusvis('O');
}


sub set_renamed {
    my $u = shift;
    return $u->set_statusvis('R');
}


# set_statusvis only change statusvis parameter, all accompanied actions are done in set_* methods
sub set_statusvis {
    my ($u, $statusvis) = @_;

    Carp::croak "Invalid statusvis: $statusvis"
        unless $statusvis =~ /^(?:
            V|       # visible
            D|       # deleted
            X|       # expunged
            S|       # suspended
            L|       # locked
            M|       # memorial
            O|       # read-only
            R        # renamed
                                )$/x;

    # log the change to userlog
    $u->log_event('accountstatus', {
            # remote looked up by log_event
            old => $u->statusvis,
            new => $statusvis,
        });

    # do update
    return $u->update_self( { statusvis => $statusvis,
                              raw => 'statusvisdate=NOW()' } );
}


sub set_suspended {
    my ($u, $who, $reason, $errref) = @_;
    die "Not enough parameters for LJ::User::set_suspended call" unless $who and $reason;

    my $res = $u->set_statusvis('S');
    unless ($res) {
        $$errref = "DB error while setting statusvis to 'S'" if ref $errref;
        return $res;
    }

    LJ::statushistory_add($u, $who, "suspend", $reason);

    LJ::Hooks::run_hooks("account_cancel", $u);

    if (my $err = LJ::Hooks::run_hook("cdn_purge_userpics", $u)) {
        $$errref = $err if ref $errref and $err;
        return 0;
    }

    return $res; # success
}


# sets a user to visible, but also does all of the stuff necessary when a suspended account is unsuspended
# this can only be run on a suspended account
sub set_unsuspended {
    my ($u, $who, $reason, $errref) = @_;
    die "Not enough parameters for LJ::User::set_unsuspended call" unless $who and $reason;

    unless ($u->is_suspended) {
        $$errref = "User isn't suspended" if ref $errref;
        return 0;
    }

    my $res = $u->set_visible;
    unless ($res) {
        $$errref = "DB error while setting statusvis to 'V'" if ref $errref;
        return $res;
    }

    LJ::statushistory_add($u, $who, "unsuspend", $reason);

    return $res; # success
}


sub set_visible {
    my $u = shift;

    my $old_statusvis = $u->statusvis;
    my $ret = $u->set_statusvis('V');

    LJ::Hooks::run_hooks( "account_makevisible", $u, old_statusvis => $old_statusvis );

    return $ret;
}


sub statusvis {
    my $u = shift;
    return $u->{statusvis};
}


sub statusvisdate {
    my $u = shift;
    return $u->{statusvisdate};
}


sub statusvisdate_unix {
    my $u = shift;
    return LJ::mysqldate_to_time( $u->statusvisdate );
}


########################################################################
### 3. Working with All Types of Account

=head2 Working with All Types of Account
=cut

# this will return a hash of information about this user.
# this is useful for JavaScript endpoints which need to dump
# JSON data about users.
sub info_for_js {
    my $u = shift;

    my %ret = (
               username         => $u->user,
               display_username => $u->display_username,
               display_name     => $u->display_name,
               userid           => $u->userid,
               url_journal      => $u->journal_base,
               url_profile      => $u->profile_url,
               url_allpics      => $u->allpics_base,
               ljuser_tag       => $u->ljuser_display,
               is_comm          => $u->is_comm,
               is_person        => $u->is_person,
               is_syndicated    => $u->is_syndicated,
               is_identity      => $u->is_identity,
               );

    LJ::Hooks::run_hook("extra_info_for_js", $u, \%ret);

    my $up = $u->userpic;

    if ($up) {
        $ret{url_userpic} = $up->url;
        $ret{userpic_w}   = $up->width;
        $ret{userpic_h}   = $up->height;
    }

    return %ret;
}


sub is_community {
    return $_[0]->{journaltype} eq "C";
}
*is_comm = \&is_community;


sub is_identity {
    return $_[0]->{journaltype} eq "I";
}


# return true if the user is either a personal journal or an identity journal
sub is_individual {
    my $u = shift;
    return $u->is_personal || $u->is_identity ? 1 : 0;
}


sub is_official {
    my $u = shift;
    return $LJ::OFFICIAL_JOURNALS{$u->username} ? 1 : 0;
}


sub is_paid {
    my $u = shift;
    return 0 if $u->is_identity || $u->is_syndicated;
    return DW::Pay::get_account_type( $u ) ne 'free' ? 1 : 0;
}


sub is_perm {
    my $u = shift;
    return 0 if $u->is_identity || $u->is_syndicated;
    return DW::Pay::get_account_type( $u ) eq 'seed' ? 1 : 0;
}


sub is_person {
    return $_[0]->{journaltype} eq "P";
}
*is_personal = \&is_person;


sub is_redirect {
    return $_[0]->{journaltype} eq "R";
}


sub is_syndicated {
    return $_[0]->{journaltype} eq "Y";
}


sub journal_base {
    return LJ::journal_base( @_ );
}


sub journaltype {
    return $_[0]->{journaltype};
}


# return the journal type as a name
sub journaltype_readable {
    my $u = shift;

    return {
        R => 'redirect',
        I => 'identity',
        P => 'personal',
        Y => 'syndicated',
        C => 'community',
    }->{$u->journaltype};
}

sub last_updated {
    # Given a user object, returns a string detailing when that journal
    # was last updated, or "never" if never updated.

    my ( $u ) = @_;

    return undef unless $u -> is_person || $u->is_community;

    my $lastupdated = substr( LJ::mysql_time( $u->timeupdate ), 0, 10 );
    my $ago_text = LJ::diff_ago_text( $u->timeupdate );

    if ( $u->timeupdate ) {
        return LJ::Lang::ml( 'lastupdated.ago',
            { timestamp => $lastupdated, agotext => $ago_text });
    } else {
        return LJ::Lang::ml ( 'lastupdated.never' );
    }
}

# returns LJ::User class of a random user, undef if we couldn't get one
#   my $random_u = LJ::User->load_random_user(type);
# If type is null, assumes a person.
sub load_random_user {
    my $class = shift;
    my $type = shift || 'P';

    # get a random database, but make sure to try them all if one is down or not
    # responding or similar
    my $dbcr;
    foreach (List::Util::shuffle(@LJ::CLUSTERS)) {
        $dbcr = LJ::get_cluster_reader($_);
        last if $dbcr;
    }
    die "Unable to get database cluster reader handle\n" unless $dbcr;

    # get a selection of users around a random time
    my $when = time() - int(rand($LJ::RANDOM_USER_PERIOD * 24 * 60 * 60)); # days -> seconds
    my $uids = $dbcr->selectcol_arrayref(qq{
            SELECT userid FROM random_user_set
            WHERE posttime > $when
            AND journaltype = ?
            ORDER BY posttime
            LIMIT 10
        }, undef, $type);
    die "Failed to execute query: " . $dbcr->errstr . "\n" if $dbcr->err;
    return undef unless $uids && @$uids;

    # try the users we got
    foreach my $uid (@$uids) {
        my $u = LJ::load_userid($uid)
            or next;

        # situational checks to ensure this user is a good one to show
        next unless $u->is_visible;        # no suspended/deleted/etc users
        next if $u->prop('latest_optout'); # they have chosen to be excluded

        # they've passed the checks, return this user
        return $u;
    }

    # must have failed
    return undef;
}


# des: Given a user hashref, loads the values of the given named properties
#      into that user hashref.
# args: u, opts?, propname*
# des-opts: hashref of opts.  set key 'use_master' to use cluster master.
# des-propname: the name of a property from the [dbtable[userproplist]] table.
#               leave undef to preload all userprops
sub preload_props {
    my $u = shift;
    return unless LJ::isu($u);
    return if $u->is_expunged;

    my $opts = ref $_[0] ? shift : {};
    my (@props) = @_;

    my ($sql, $sth);
    LJ::load_props("user");

    ## user reference
    my $uid = $u->userid + 0;
    $uid = LJ::get_userid( $u->user ) unless $uid;

    my $mem = {};
    my $use_master = 0;
    my $used_slave = 0;  # set later if we ended up using a slave

    if (@LJ::MEMCACHE_SERVERS) {
        my @keys;
        foreach (@props) {
            next if exists $u->{$_};
            my $p = LJ::get_prop("user", $_);
            die "Invalid userprop $_ passed to preload_props." unless $p;
            push @keys, [$uid,"uprop:$uid:$p->{'id'}"];
        }
        $mem = LJ::MemCache::get_multi(@keys) || {};
        $use_master = 1;
    }

    $use_master = 1 if $opts->{'use_master'};

    my @needwrite;  # [propid, propname] entries we need to save to memcache later

    my %loadfrom;
    my %multihomed; # ( $propid => 0/1 ) # 0 if we haven't loaded it, 1 if we have
    unless (@props) {
        # case 1: load all props for a given user.
        # multihomed props are stored on userprop and userproplite2, but since they
        # should always be in sync, it doesn't matter which gets loaded first, the
        # net results should be the same.  see doc/server/lj.int.multihomed_userprops.html
        # for more information.
        $loadfrom{'userprop'} = 1;
        $loadfrom{'userproplite'} = 1;
        $loadfrom{'userproplite2'} = 1;
        $loadfrom{'userpropblob'} = 1;
    } else {
        # case 2: load only certain things
        foreach (@props) {
            next if exists $u->{$_};
            my $p = LJ::get_prop("user", $_);
            die "Invalid userprop $_ passed to preload_props." unless $p;
            if (defined $mem->{"uprop:$uid:$p->{'id'}"}) {
                $u->{$_} = $mem->{"uprop:$uid:$p->{'id'}"};
                next;
            }
            push @needwrite, [ $p->{'id'}, $_ ];
            my $source = $p->{'indexed'} ? "userprop" : "userproplite";
            if ($p->{datatype} eq 'blobchar') {
                $source = "userpropblob"; # clustered blob
            }
            elsif ( $p->{'cldversion'} && $u->dversion >= $p->{'cldversion'} ) {
                $source = "userproplite2";  # clustered
            }
            elsif ($p->{multihomed}) {
                $multihomed{$p->{id}} = 0;
                $source = "userproplite2";
            }
            push @{$loadfrom{$source}}, $p->{'id'};
        }
    }

    foreach my $table (qw{userproplite userproplite2 userpropblob userprop}) {
        next unless exists $loadfrom{$table};
        my $db;
        if ($use_master) {
            $db = ($table =~ m{userprop(lite2|blob)}) ?
                LJ::get_cluster_master($u) :
                LJ::get_db_writer();
        }
        unless ($db) {
            $db = ($table =~ m{userprop(lite2|blob)}) ?
                LJ::get_cluster_reader($u) :
                LJ::get_db_reader();
            $used_slave = 1;
        }
        confess "No database handle available" unless $db;

        $sql = "SELECT upropid, value FROM $table WHERE userid=$uid";
        if (ref $loadfrom{$table}) {
            $sql .= " AND upropid IN (" . join(",", @{$loadfrom{$table}}) . ")";
        }
        die "No db\n" unless $db;

        $sth = $db->prepare($sql);
        $sth->execute;
        while (my ($id, $v) = $sth->fetchrow_array) {
            delete $multihomed{$id} if $table eq 'userproplite2';
            $u->{$LJ::CACHE_PROPID{'user'}->{$id}->{'name'}} = $v;
        }

        # push back multihomed if necessary
        if ($table eq 'userproplite2') {
            push @{$loadfrom{userprop}}, $_ foreach keys %multihomed;
        }
    }

    # see if we failed to get anything above and need to hit the master.
    # this usually happens the first time a multihomed prop is hit.  this
    # code will propagate that prop down to the cluster.
    if (%multihomed) {

        # verify that we got the database handle before we try propagating data
        if ($u->writer) {
            my @values;
            foreach my $id (keys %multihomed) {
                my $pname = $LJ::CACHE_PROPID{user}{$id}{name};
                if (defined $u->{$pname} && $u->{$pname}) {
                    push @values, "($uid, $id, " . $u->quote($u->{$pname}) . ")";
                } else {
                    push @values, "($uid, $id, '')";
                }
            }
            $u->do("REPLACE INTO userproplite2 VALUES " . join ',', @values);
        }
    }

    # Add defaults to user object.

    # If this was called with no @props, then the function tried
    # to load all metadata.  but we don't know what's missing, so
    # try to apply all defaults.
    unless (@props) { @props = keys %LJ::USERPROP_DEF; }

    foreach my $prop (@props) {
        next if (defined $u->{$prop});
        $u->{$prop} = $LJ::USERPROP_DEF{$prop};
    }

    unless ($used_slave) {
        my $expire = time() + 3600*24;
        foreach my $wr (@needwrite) {
            my ($id, $name) = ($wr->[0], $wr->[1]);
            LJ::MemCache::set([$uid,"uprop:$uid:$id"], $u->{$name} || "", $expire);
        }
    }
}


# class method.  returns remote (logged in) user object.  or undef if
# no session is active.
sub remote {
    my ($class, $opts) = @_;
    return LJ::get_remote($opts);
}


# class method.  set the remote user ($u or undef) for the duration of this request.
# once set, it'll never be reloaded, unless "unset_remote" is called to forget it.
sub set_remote {
    my ($class, $remote) = @_;
    $LJ::CACHED_REMOTE = 1;
    $LJ::CACHE_REMOTE = $remote;
    1;
}


# when was this account created?
# returns unixtime
sub timecreate {
    my $u = shift;

    return $u->{_cache_timecreate} if $u->{_cache_timecreate};

    my $memkey = [$u->id, "tc:" . $u->id];
    my $timecreate = LJ::MemCache::get($memkey);
    if ($timecreate) {
        $u->{_cache_timecreate} = $timecreate;
        return $timecreate;
    }

    my $dbr = LJ::get_db_reader() or die "No db";
    my $when = $dbr->selectrow_array("SELECT timecreate FROM userusage WHERE userid=?", undef, $u->id);

    $timecreate = LJ::mysqldate_to_time($when);
    $u->{_cache_timecreate} = $timecreate;
    LJ::MemCache::set($memkey, $timecreate, 60*60*24);

    return $timecreate;
}


# when was last time this account updated?
# returns unixtime
sub timeupdate {
    my $u = shift;
    my $timeupdate = LJ::get_timeupdate_multi($u->id);
    return $timeupdate->{$u->id};
}


# class method.  forgets the cached remote user.
sub unset_remote {
    my $class = shift;
    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE = undef;
    1;
}


########################################################################
###  19. OpenID and Identity Users

=head2 OpenID and Identity Users
=cut

# returns a true value if user has a reserved 'ext' name.
sub external {
    my $u = shift;
    return $u->user =~ /^ext_/;
}


# returns LJ::Identity object
sub identity {
    my $u = shift;
    return $u->{_identity} if $u->{_identity};
    return undef unless $u->is_identity;

    my $memkey = [$u->userid, "ident:" . $u->userid];
    my $ident = LJ::MemCache::get($memkey);
    if ($ident) {
        my $i = LJ::Identity->new(
                                  typeid => $ident->[0],
                                  value  => $ident->[1],
                                  );

        return $u->{_identity} = $i;
    }

    my $dbh = LJ::get_db_writer();
    $ident = $dbh->selectrow_arrayref( "SELECT idtype, identity FROM identitymap ".
                                       "WHERE userid=? LIMIT 1", undef, $u->userid );
    if ($ident) {
        LJ::MemCache::set($memkey, $ident);
        my $i = LJ::Identity->new(
                                  typeid => $ident->[0],
                                  value  => $ident->[1],
                                  );
        return $i;
    }
    return undef;
}


# class function - load an identity user, but only if they're already known to us
sub load_existing_identity_user {
    my ($type, $ident) = @_;

    my $dbh = LJ::get_db_reader();
    my $uid;

    # if given an https URL, also look for existing http account
    # (we should have stripped the protocol before storing these, sigh)
    if ( $ident =~ s/^https:// ) {
        my $secure_ident= "https:$ident";
        $ident = "http:$ident";

        # do the secure lookup first; if it fails, try the fallback below
        $uid = $dbh->selectrow_array( "SELECT userid FROM identitymap WHERE " .
                                      "idtype=? AND identity=?",
                                      undef, $type, $secure_ident );
    }

    unless ( $uid ) {
        $uid = $dbh->selectrow_array( "SELECT userid FROM identitymap WHERE " .
                                      "idtype=? AND identity=?",
                                      undef, $type, $ident );
    }

    return $uid ? LJ::load_userid($uid) : undef;
}


# class function - load an identity user, and if we've never seen them before create a user account for them
sub load_identity_user {
    my ($type, $ident, $vident) = @_;

    my $u = load_existing_identity_user($type, $ident);

    # If the user is marked as expunged, move identity mapping aside
    # and continue to create new account.
    # Otherwise return user if it exists.
    if ($u) {
        if ($u->is_expunged) {
            return undef unless ($u->rename_identity);
        } else {
            return $u;
        }
    }

    # increment ext_ counter until we successfully create an LJ
    # account.  hard cap it at 10 tries. (arbitrary, but we really
    # shouldn't have *any* failures here, let alone 10 in a row)

    for (1..10) {
        my $extuser = 'ext_' . LJ::alloc_global_counter('E');

        my $name = $extuser;
        if ($type eq "O" && ref $vident) {
            $name = $vident->display;
        }

        $u = LJ::User->create(
            caps => undef,
            user => $extuser,
            name => $ident,
            journaltype => 'I',
        );
        last if $u;
        select undef, undef, undef, .10;  # lets not thrash over this
    }

    return undef unless $u;

    my $dbh = LJ::get_db_writer();
    return undef unless
        $dbh->do( "INSERT INTO identitymap (idtype, identity, userid) VALUES (?,?,?)",
                  undef, $type, $ident, $u->id );

    # set default style
    $u->set_default_style;

    # record create information
    my $remote = LJ::get_remote();
    $u->log_event('account_create', { remote => $remote });

    return $u;
}

# class function - refactoring verification of Net::OpenID::Consumer object
# returns the associated user object, or undef on failure
sub load_from_consumer {
    my ( $csr, $errorref ) = @_;

    my $err = sub { $$errorref = LJ::Lang::ml( @_ ) if defined $errorref && ref $errorref };

    my $vident = eval { $csr->verified_identity; };

    unless ( $vident ) {
        my $msg = $@ ? $@ : $csr->err;
        $err->( '/openid/login.bml.error.notverified', { error => $msg } );
        return;
    }

    my $url = $vident->url;

    if ( $url =~ /[\<\>\s]/ ) {
        $err->( '/openid/login.bml.error.invalidcharacters' );
        return;
    }

    my $u = load_identity_user( "O", $url, $vident );

    unless ( $u ) {
        $err->( '/openid/login.bml.error.notvivified', { url => LJ::ehtml( $url ) } );
        return;
    }

    return $u;
}

# journal_base replacement for OpenID accounts. since they don't have
# a journal, redirect to /read.
sub openid_journal_base {
    return $_[0]->journal_base . "/read";
}

# returns a URL if account is an OpenID identity.  undef otherwise.
sub openid_identity {
    my $u = shift;
    my $ident = $u->identity;
    return undef unless $ident && $ident->typeid eq 'O';
    return $ident->value;
}


# prepare OpenId part of html-page, if needed
sub openid_tags {
    my $u = shift;

    my $head = '';

    # OpenID Server and Yadis
    if (LJ::OpenID->server_enabled and defined $u) {
        my $journalbase = $u->journal_base;
        $head .= qq{<link rel="openid.server" href="$LJ::OPENID_SERVER" />\n};
        $head .= qq{<meta http-equiv="X-XRDS-Location" content="$journalbase/data/yadis" />\n};
    }

    return $head;
}


# <LJFUNC>
# name: LJ::User::rename_identity
# des: Change an identity user's 'identity', update DB,
#      clear memcache and log change.
# args: user
# returns: Success or failure.
# </LJFUNC>
sub rename_identity {
    my $u = shift;
    return 0 unless ($u && $u->is_identity && $u->is_expunged);

    my $id = $u->identity;
    return 0 unless $id;

    my $dbh = LJ::get_db_writer();

    # generate a new identity value that looks like ex_oldidvalue555
    my $tempid = sub {
        my ( $ident, $idtype ) = @_;
        my $temp = (length($ident) > 249) ? substr($ident, 0, 249) : $ident;
        my $exid;

        for (1..10) {
            $exid = "ex_$temp" . int(rand(999));

            # check to see if this identity already exists
            unless ($dbh->selectrow_array("SELECT COUNT(*) FROM identitymap WHERE identity=? AND idtype=? LIMIT 1", undef, $exid, $idtype)) {
                # name doesn't already exist, use this one
                last;
            }
            # name existed, try and get another

            if ($_ >= 10) {
                return 0;
            }
        }
        return $exid;
    };

    my $from = $id->value;
    my $to = $tempid->($id->value, $id->typeid);

    return 0 unless $to;

    $dbh->do("UPDATE identitymap SET identity=? WHERE identity=? AND idtype=?",
             undef, $to, $from, $id->typeid);

    LJ::memcache_kill($u, "userid");

    $u->infohistory_add( 'identity', $from );

    return 1;
}

########################################################################
### 26. Syndication-Related Functions

=head2 Syndication-Related Functions
=cut

# generate tag URI for user's atom id (RFC 4151)
sub atomid {
    my ( $u ) = @_;
    my $journalcreated = LJ::mysql_date( $u->timecreate, 1 );
    return "tag:$LJ::DOMAIN,$journalcreated:$u->{userid}";
}

sub atom_service_document {
    return "$LJ::SITEROOT/interface/atom";
}

sub atom_base {
    my ( $u ) = @_;
    return $u->journal_base . "/interface/atom";
}

# retrieve hash of basic syndicated info
sub get_syndicated {
    my $u = shift;

    return unless $u->is_syndicated;
    my $userid = $u->userid;
    my $memkey = [$userid, "synd:$userid"];

    my $synd = {};
    $synd = LJ::MemCache::get($memkey);
    unless ($synd) {
        my $dbr = LJ::get_db_reader();
        return unless $dbr;
        $synd = $dbr->selectrow_hashref( "SELECT * FROM syndicated WHERE userid=$userid" );
        LJ::MemCache::set($memkey, $synd, 60 * 30) if $synd;
    }

    return $synd;
}


########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

use Carp;

########################################################################
###  3. Working with All Types of Accounts

=head2 Working with All Types of Accounts (LJ)
=cut

# <LJFUNC>
# name: LJ::canonical_username
# des: normalizes username.
# info:
# args: user
# returns: the canonical username given, or blank if the username is not well-formed
# </LJFUNC>
sub canonical_username {
    my $input = lc( $_[0] // '' );
    my $user = "";
    if ( $input =~ /^\s*([a-z0-9_\-]{1,25})\s*$/ ) {  # good username
        $user = $1;
        $user =~ s/-/_/g;
    }
    return $user;
}


# <LJFUNC>
# name: LJ::get_userid
# des: Returns a userid given a username.
# info: Results cached in memory.  On miss, does DB call.  Not advised
#       to use this many times in a row... only once or twice perhaps
#       per request.  Tons of serialized db requests, even when small,
#       are slow.  Opposite of [func[LJ::get_username]].
# args: dbarg?, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_userid {
    my $user = LJ::canonical_username( $_[0] );

    if ($LJ::CACHE_USERID{$user}) { return $LJ::CACHE_USERID{$user}; }

    my $userid = LJ::MemCache::get("uidof:$user");
    return $LJ::CACHE_USERID{$user} = $userid if $userid;

    my $dbr = LJ::get_db_reader();
    $userid = $dbr->selectrow_array("SELECT userid FROM useridmap WHERE user=?", undef, $user);

    if ($userid) {
        $LJ::CACHE_USERID{$user} = $userid;
        LJ::MemCache::set("uidof:$user", $userid);
    }

    return ($userid+0);
}


# <LJFUNC>
# name: LJ::get_username
# des: Returns a username given a userid.
# info: Results cached in memory.  On miss, does DB call.  Not advised
#       to use this many times in a row... only once or twice perhaps
#       per request.  Tons of serialized db requests, even when small,
#       are slow.  Opposite of [func[LJ::get_userid]].
# args: dbarg?, user
# des-user: Username whose userid to look up.
# returns: Userid, or 0 if invalid user.
# </LJFUNC>
sub get_username {
    my $userid = $_[0] + 0;

    # Checked the cache first.
    if ($LJ::CACHE_USERNAME{$userid}) { return $LJ::CACHE_USERNAME{$userid}; }

    # if we're using memcache, it's faster to just query memcache for
    # an entire $u object and just return the username.  otherwise, we'll
    # go ahead and query useridmap
    if (@LJ::MEMCACHE_SERVERS) {
        my $u = LJ::load_userid($userid);
        return undef unless $u;

        $LJ::CACHE_USERNAME{$userid} = $u->user;
        return $u->user;
    }

    my $dbr = LJ::get_db_reader();
    my $user = $dbr->selectrow_array("SELECT user FROM useridmap WHERE userid=?", undef, $userid);

    # Fall back to master if it doesn't exist.
    unless (defined $user) {
        my $dbh = LJ::get_db_writer();
        $user = $dbh->selectrow_array("SELECT user FROM useridmap WHERE userid=?", undef, $userid);
    }

    return undef unless defined $user;

    $LJ::CACHE_USERNAME{$userid} = $user;
    return $user;
}


# is a user object (at least a hashref)
sub isu {
    return unless ref $_[0];
    return 1 if UNIVERSAL::isa($_[0], "LJ::User");

    if (ref $_[0] eq "HASH" && $_[0]->{userid}) {
        carp "User HASH objects are deprecated from use." if $LJ::IS_DEV_SERVER;
        return 1;
    }
}

# <LJFUNC>
# name: LJ::journal_base
# des: Returns URL of a user's journal.
# info: The tricky thing is that users with underscores in their usernames
#       can't have some_user.example.com as a hostname, so that's changed into
#       some-user.example.com.
# args: uuser, vhost?
# des-uuser: User hashref or username of user whose URL to make.
# des-vhost: What type of URL.  Acceptable options: "users", to make a
#            http://user.example.com/ URL; "tilde" for http://example.com/~user/;
#            "community" for http://example.com/community/user; or the default
#            will be http://example.com/users/user.  If unspecified and uuser
#            is a user hashref, then the best/preferred vhost will be chosen.
# returns: scalar; a URL.
# </LJFUNC>
sub journal_base {
    my ($user, %opts) = @_;
    my $vhost = $opts{vhost};
    my $protocol = ( $LJ::USE_HTTPS_EVERYWHERE || $LJ::IS_SSL ) ? "https" : "http";

    my $u = LJ::isu( $user ) ? $user : LJ::load_user( $user );
    $user = $u->user if $u;

    if ( $u && LJ::Hooks::are_hooks("journal_base") ) {
        my $hookurl = LJ::Hooks::run_hook("journal_base", $u, $vhost);
        return $hookurl if $hookurl;

        unless (defined $vhost) {
            if ($LJ::FRONTPAGE_JOURNAL eq $user) {
                $vhost = "front";
            } elsif ( $u->is_person ) {
                $vhost = "";
            } elsif ( $u->is_community ) {
                $vhost = "community";
            }
        }
    }

    if ( $LJ::ONLY_USER_VHOSTS ) {
        my $rule = $u ? $LJ::SUBDOMAIN_RULES->{$u->journaltype} : undef;
        $rule ||= $LJ::SUBDOMAIN_RULES->{P};

        # if no rule, then we don't have any idea what to do ...
        die "Site misconfigured, no %LJ::SUBDOMAIN_RULES."
            unless $rule && ref $rule eq 'ARRAY';

        if ( $rule->[0] && $user !~ /^\_/ && $user !~ /\_$/ ) {
            $user =~ s/_/-/g;
            return "$protocol://$user.$LJ::DOMAIN";
        } else {
            return "$protocol://$rule->[1]/$user";
        }
    }

    if ($vhost eq "users") {
        my $he_user = $user;
        $he_user =~ s/_/-/g;
        return "$protocol://$he_user.$LJ::USER_DOMAIN";
    } elsif ($vhost eq "tilde") {
        return "$LJ::SITEROOT/~$user";
    } elsif ($vhost eq "community") {
        return "$LJ::SITEROOT/community/$user";
    } elsif ($vhost eq "front") {
        return $LJ::SITEROOT;
    } elsif ($vhost =~ /^other:(.+)/) {
        return "$protocol://$1";
    } else {
        return "$LJ::SITEROOT/users/$user";
    }
}


# <LJFUNC>
# name: LJ::load_user
# des: Loads a user record, from the [dbtable[user]] table, given a username.
# args: dbarg?, user, force?
# des-user: Username of user to load.
# des-force: if set to true, won't return cached user object and will
#            query a dbh.
# returns: Hashref, with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_user {
    my ($user, $force) = @_;

    $user = LJ::canonical_username($user);
    return undef unless length $user;

    my $get_user = sub {
        my $use_dbh = shift;
        my $db = $use_dbh ? LJ::get_db_writer() : LJ::get_db_reader();
        my $u = _load_user_raw($db, "user", $user)
            or return undef;

        # set caches since we got a u from the master
        LJ::memcache_set_u($u) if $use_dbh;

        return _set_u_req_cache($u);
    };

    # caller is forcing a master, return now
    return $get_user->("master") if $force || $LJ::_PRAGMA_FORCE_MASTER;

    my $u;

    # return process cache if we have one
    if ($u = $LJ::REQ_CACHE_USER_NAME{$user}) {
        $u->selfassert;
        return $u;
    }

    # check memcache
    {
        my $uid = LJ::MemCache::get("uidof:$user");
        $u = LJ::memcache_get_u([$uid, "userid:$uid"]) if $uid;
        return _set_u_req_cache($u) if $u;
    }

    # try to load from master if using memcache, otherwise from slave
    $u = $get_user->(scalar @LJ::MEMCACHE_SERVERS);
    return $u if $u;

    return undef;
}


sub load_user_or_identity {
    my $arg = shift;

    my $user = LJ::canonical_username($arg);
    return LJ::load_user($user) if $user;

    # return undef if not dot in arg (can't be a URL)
    return undef unless $arg =~ /\./;

    my $url = lc($arg);
    $url = "http://$url" unless $url =~ m!^https?://!;
    $url .= "/" unless $url =~ m!/$!;

    # get from memcache
    {
        # overload the uidof memcache key to accept both display name and name
        my $uid = LJ::MemCache::get( "uidof:$url" );
        my $u = $uid ? LJ::memcache_get_u( [ $uid, "userid:$uid" ] ) : undef;
        return _set_u_req_cache( $u ) if $u;
    }

    my $u = LJ::User::load_existing_identity_user( 'O', $url );

    # set user in memcache
    if ( $u ) {
        # memcache URL-to-userid for identity users
        LJ::MemCache::set( "uidof:$url", $u->id, 1800 );
        LJ::memcache_set_u( $u );
        return _set_u_req_cache( $u );
    }

    return undef;
}


# <LJFUNC>
# name: LJ::load_userid
# des: Loads a user record, from the [dbtable[user]] table, given a userid.
# args: dbarg?, userid, force?
# des-userid: Userid of user to load.
# des-force: if set to true, won't return cached user object and will
#            query a dbh
# returns: LJ::User object.
# </LJFUNC>
sub load_userid {
    my ($userid, $force) = @_;
    return undef unless $userid;

    my $get_user = sub {
        my $use_dbh = shift;
        my $db = $use_dbh ? LJ::get_db_writer() : LJ::get_db_reader();
        my $u = _load_user_raw($db, "userid", $userid)
            or return undef;

        LJ::memcache_set_u($u) if $use_dbh;
        return _set_u_req_cache($u);
    };

    # user is forcing master, return now
    return $get_user->("master") if $force || $LJ::_PRAGMA_FORCE_MASTER;

    my $u;

    # check process cache
    $u = $LJ::REQ_CACHE_USER_ID{$userid};
    if ($u) {
        $u->selfassert;
        return $u;
    }

    # check memcache
    $u = LJ::memcache_get_u([$userid,"userid:$userid"]);
    return _set_u_req_cache($u) if $u;

    # get from master if using memcache
    return $get_user->("master") if @LJ::MEMCACHE_SERVERS;

    # check slave
    $u = $get_user->();
    return $u if $u;

    # if we didn't get a u from the reader, fall back to master
    return $get_user->("master");
}


# <LJFUNC>
# name: LJ::load_userids
# des: Simple interface to [func[LJ::load_userids_multiple]].
# args: userids
# returns: hashref with keys ids, values $u refs.
# </LJFUNC>
sub load_userids {
    my %u;
    LJ::load_userids_multiple([ map { $_ => \$u{$_} } @_ ]);
    return \%u;
}


# <LJFUNC>
# name: LJ::load_userids_multiple
# des: Loads a number of users at once, efficiently.
# info: loads a few users at once, their userids given in the keys of $map
#       listref (not hashref: can't have dups).  values of $map listref are
#       scalar refs to put result in.  $have is an optional listref of user
#       object caller already has, but is too lazy to sort by themselves.
#       <strong>Note</strong>: The $have parameter is deprecated,
#       as is $memcache_only; but it is still preserved for now.
#       Really, this whole API (i.e. LJ::load_userids_multiple) is clumsy.
#       Use [func[LJ::load_userids]] instead.
# args: dbarg?, map, have, memcache_only?
# des-map: Arrayref of pairs (userid, destination scalarref).
# des-have: Arrayref of user objects caller already has.
# des-memcache_only: Flag to only retrieve data from memcache.
# returns: Nothing.
# </LJFUNC>
sub load_userids_multiple {
    # the $have parameter is deprecated, as is $memcache_only, but it's still preserved for now.
    # actually this whole API is crap.  use LJ::load_userids() instead.
    my ($map, undef, $memcache_only) = @_;

    my $sth;
    my @have;
    my %need;
    while (@$map) {
        my $id = shift @$map;
        my $ref = shift @$map;
        next unless int($id);
        push @{$need{$id}}, $ref;

        if ($LJ::REQ_CACHE_USER_ID{$id}) {
            push @have, $LJ::REQ_CACHE_USER_ID{$id};
        }
    }

    my $satisfy = sub {
        my $u = shift;
        next unless ref $u eq "LJ::User";

        # this could change the $u returned to an
        # existing one we already have loaded in memory,
        # once it's been upgraded.  then everybody points
        # to the same one.
        $u = _set_u_req_cache($u);

        foreach ( @{$need{$u->userid}} ) {
            # check if existing target is defined and not what we already have.
            if (my $eu = $$_) {
                LJ::assert_is( $u->userid, $eu->userid );
            }
            $$_ = $u;
        }

        delete $need{$u->userid};
    };

    unless ($LJ::_PRAGMA_FORCE_MASTER) {
        foreach my $u (@have) {
            $satisfy->($u);
        }

        if (%need) {
            foreach (LJ::memcache_get_u(map { [$_,"userid:$_"] } keys %need)) {
                $satisfy->($_);
            }
        }
    }

    if (%need && ! $memcache_only) {
        my $db = @LJ::MEMCACHE_SERVERS || $LJ::_PRAGMA_FORCE_MASTER ?
            LJ::get_db_writer() : LJ::get_db_reader();

        _load_user_raw($db, "userid", [ keys %need ], sub {
            my $u = shift;
            LJ::memcache_set_u($u);
            $satisfy->($u);
        });
    }
}


# <LJFUNC>
# name: LJ::make_user_active
# des:  Record user activity per cluster, on [dbtable[clustertrack2]], to
#       make per-activity cluster stats easier.
# args: userid, type
# des-userid: source userobj ref
# des-type: currently unused
# </LJFUNC>
sub mark_user_active {
    my ($u, $type) = @_;  # not currently using type
    return 0 unless $u;   # do not auto-vivify $u
    my $uid = $u->userid;
    return 0 unless $uid && $u->clusterid;
    # FIXME: return 1 instead? Callers don't use the return value, so I'm not
    # sure whether 0 means "some error happened" or just "nothing done"
    return 0 unless $u->is_personal || $u->is_community || $u->is_identity;

    # Update the clustertrack2 table, but not if we've done it for this
    # user in the last hour.  if no memcache servers are configured
    # we don't do the optimization and just always log the activity info
    if (@LJ::MEMCACHE_SERVERS == 0 ||
        LJ::MemCache::add("rate:tracked:$uid", 1, 3600)) {

        return 0 unless $u->writer;
        my $active = time();
        $u->do( qq{ REPLACE INTO clustertrack2
                        SET userid=?, timeactive=?, clusterid=?,
                        accountlevel=?, journaltype=? },
                undef, $uid, $active, $u->clusterid,
                DW::Pay::get_current_account_status( $uid ), $u->journaltype )
            or return 0;

        my $memkey = [$u->userid, "timeactive:" . $u->userid];
        LJ::MemCache::set($memkey, $active, 86400);
    }
    return 1;
}


# <LJFUNC>
# name: LJ::want_user
# des: Returns user object when passed either userid or user object. Useful to functions that
#      want to accept either.
# args: user
# des-user: Either a userid or a user hash with the userid in its 'userid' key.
# returns: The user object represented by said userid or username.
# </LJFUNC>
sub want_user {
    my $uuid = shift;
    return undef unless $uuid;
    return $uuid if ref $uuid;
    return LJ::load_userid($uuid) if $uuid =~ /^\d+$/;
    Carp::croak("Bogus caller of LJ::want_user with non-ref/non-numeric parameter");
}


# <LJFUNC>
# name: LJ::want_userid
# des: Returns userid when passed either userid or the user hash. Useful to functions that
#      want to accept either. Forces its return value to be a number (for safety).
# args: userid
# des-userid: Either a userid, or a user hash with the userid in its 'userid' key.
# returns: The userid, guaranteed to be a numeric value.
# </LJFUNC>
sub want_userid {
    my $uuserid = shift;
    return ($uuserid->{userid} + 0) if ref $uuserid;
    return ($uuserid + 0);
}


########################################################################
###  19. OpenID and Identity Functions

=head2 OpenID and Identity Functions (LJ)
=cut

# given a LJ userid/u, return a hashref of:
# type, extuser, extuserid
# returns undef if user isn't an externally mapped account.
sub get_extuser_map {
    my $uid = LJ::want_userid(shift);
    return undef unless $uid;

    my $dbr = LJ::get_db_reader();
    return undef unless $dbr;

    my $sql = "SELECT * FROM extuser WHERE userid=?";
    my $ret = $dbr->selectrow_hashref($sql, undef, $uid);
    return undef unless $ret;

    my $type = 'unknown';
    foreach ( keys %LJ::EXTERNAL_NAMESPACE ) {
        $type = $_ if $LJ::EXTERNAL_NAMESPACE{$_}->{id} == $ret->{siteid};
    }

    $ret->{type} = $type;
    return $ret;
}


# given an extuserid or extuser, return the LJ uid.
# return undef if there is no mapping.
sub get_extuser_uid {
    my ($type, $opts, $force) = @_;
    return undef unless $type && $LJ::EXTERNAL_NAMESPACE{$type}->{id};
    return undef unless ref $opts &&
        ($opts->{extuser} || defined $opts->{extuserid});

    my $dbh = $force ? LJ::get_db_writer() : LJ::get_db_reader();
    return undef unless $dbh;

    my $sql = "SELECT userid FROM extuser WHERE siteid=?";
    my @bind = ($LJ::EXTERNAL_NAMESPACE{$type}->{id});

    if ($opts->{extuser}) {
        $sql .= " AND extuser=?";
        push @bind, $opts->{extuser};
    }

    if ($opts->{extuserid}) {
        $sql .= $opts->{extuser} ? ' OR ' : ' AND ';
        $sql .= "extuserid=?";
        push @bind, $opts->{extuserid}+0;
    }

    return $dbh->selectrow_array($sql, undef, @bind);
}


1;
