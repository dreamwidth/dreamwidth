#
# NOTE: This module now requires Perl 5.10 or greater.
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

#
# LiveJournal user object
#
# 2004-07-21: we're transitioning from $u hashrefs to $u objects, currently
#             backed by hashrefs, to ease migration.  in the future,
#             more methods from ljlib.pl and other places will move here,
#             and the representation of a $u object will change to 'fields'.
#             at present, the motivation to moving to $u objects is to do
#             all database access for a given user through his/her $u object
#             so the queries can be tagged for use by the star replication
#             daemon.

use strict;
no warnings 'uninitialized';

########################################################################
### Begin LJ::User functions

package LJ::User;
use Carp;
use Storable;
use List::Util qw/ min /;
use lib "$LJ::HOME/cgi-bin";
use LJ::Global::Constants;
use LJ::MemCache;
use LJ::Session;

use DW::Logic::ProfilePage;
use DW::Pay;
use DW::User::ContentFilters;
use DW::User::Edges;
use DW::User::OpenID;
use DW::InviteCodes::Promo;
use DW::SiteScheme;
use DW::Template;

use LJ::Community;
use LJ::Subscription;
use LJ::Identity;
use LJ::Auth;
use LJ::Jabber::Presence;
use LJ::S2;
use IO::Socket::INET;
use Time::Local;
use LJ::BetaFeatures;
use LJ::S2Theme;
use LJ::Customize;
use LJ::Keywords;

########################################################################
### Please keep these categorized and alphabetized for ease of use.
### If you need a new category, add it at the end, BEFORE category 99.
### Categories kinda fuzzy, but better than nothing.
###
### Categories:
###  1. Creating and Deleting Accounts
###  2. Statusvis and Account Types
###  3. Working with All Types of Account
###  4. Login, Session, and Rename Functions
###  5. Database and Memcache Functions
###  6. What the App Shows to Users
###  7. Userprops, Caps, and Displaying Content to Others
###  8. Formatting Content Shown to Users
###  9. Logging and Recording Actions
###  10. Banning-Related Functions
###  11. Birthdays and Age-Related Functions
###  12. Comment-Related Functions
###  13. Community-Related Functions and Authas
###  14. Adult Content Functions
###  15. Email-Related Functions
###  16. (( there is no section 16 ))
###  18. Jabber-Related Functions
###  19. OpenID and Identity Functions
###  20. Page Notices Functions
###  21. Password Functions
###  22. Priv-Related Functions
###  24. Styles and S2-Related Functions
###  25. Subscription, Notifiction, and Messaging Functions
###  26. Syndication-Related Functions
###  27. Tag-Related Functions
###  28. Userpic-Related Functions
###  99. Miscellaneous Legacy Items


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

    my $username = LJ::canonical_username($opts{user}) or return;

    my $cluster     = $opts{cluster} || LJ::DB::new_account_cluster();
    my $caps        = $opts{caps} || $LJ::NEWUSER_CAPS;
    my $journaltype = $opts{journaltype} || "P";

    # non-clustered accounts aren't supported anymore
    return unless $cluster;

    my $dbh = LJ::get_db_writer();

    $dbh->do("INSERT INTO user (user, clusterid, dversion, caps, journaltype) " .
             "VALUES (?, ?, ?, ?, ?)", undef,
             $username, $cluster, $LJ::MAX_DVERSION, $caps, $journaltype);
    return if $dbh->err;

    my $userid = $dbh->{'mysql_insertid'};
    return unless $userid;

    $dbh->do("INSERT INTO useridmap (userid, user) VALUES (?, ?)",
             undef, $userid, $username);
    $dbh->do("INSERT INTO userusage (userid, timecreate) VALUES (?, NOW())",
             undef, $userid);

    my $u = LJ::load_userid( $userid, "force" ) or return;

    my $status   = $opts{status}   || ($LJ::EVERYONE_VALID ? 'A' : 'N');
    my $name     = $opts{name}     || $username;
    my $bdate    = $opts{bdate}    || "0000-00-00";
    my $email    = $opts{email}    || "";
    my $password = $opts{password} || "";

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
        my $system = LJ::load_user("system");
        if ($system) {
            while (my ($key, $value) = each( %{$opts{status_history}} )) {
                LJ::statushistory_add($u, $system, $key, $value);
            }
        }
    }

    LJ::Hooks::run_hooks("post_create", {
        'userid' => $userid,
        'user'   => $username,
        'code'   => undef,
        'news'   => $opts{get_news},
    });

    return $u;
}


sub create_community {
    my ($class, %opts) = @_;

    $opts{journaltype} = "C";
    my $u = LJ::User->create(%opts) or return;

    $u->set_prop("nonmember_posting", $opts{nonmember_posting}+0);
    $u->set_prop("moderated", $opts{moderated}+0);
    $u->set_prop("adult_content", $opts{journal_adult_settings}) if LJ::is_enabled( 'adult_content' );
    $u->set_default_style;

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
    $dbh->do("DELETE FROM email_aliases WHERE alias=?", undef, $u->site_email_alias);

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

    croak "Invalid statusvis: $statusvis"
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
        $sql = "SELECT upropid, value FROM $table WHERE userid=$uid";
        if (ref $loadfrom{$table}) {
            $sql .= " AND upropid IN (" . join(",", @{$loadfrom{$table}}) . ")";
        }
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
sub set_remote
{
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
sub unset_remote
{
    my $class = shift;
    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE = undef;
    1;
}


########################################################################
### 4. Login, Session, and Rename Functions

=head2 Login, Session, and Rename Functions
=cut

# returns a new LJ::Session object, or undef on failure
sub create_session
{
    my ($u, %opts) = @_;
    return LJ::Session->create($u, %opts);
}


#<LJFUNC>
# name: LJ::User::get_renamed_user
# des: Get the actual user of a renamed user
# args: user
# returns: user
# </LJFUNC>
sub get_renamed_user {
    my $u = shift;
    my %opts = @_;
    my $hops = $opts{hops} || 5;
    my $username;

    # Traverse the renames to the final journal
    if ($u) {
        while ( $u->is_redirect && $hops-- > 0 ) {
            my $rt = $u->prop("renamedto");
            last unless length $rt;

            $username = $rt;
            $u = LJ::load_user( $rt );

            # the username we renamed to is no longer a valid user
            last unless LJ::isu( $u );
        }
    }

    # return both the user object, and the last known renamedto username
    # in case the user object isn't valid
    return wantarray ? ( $u, $username ) : $u;
}


# name: LJ::User->get_timeactive
# des:  retrieve last active time for user from [dbtable[clustertrack2]] or
#       memcache
sub get_timeactive {
    my ($u) = @_;
    my $memkey = [$u->userid, "timeactive:" . $u->userid];
    my $active;
    unless (defined($active = LJ::MemCache::get($memkey))) {
        # FIXME: die if unable to get handle? This was left verbatim from
        # refactored code.
        my $dbcr = LJ::get_cluster_def_reader($u) or return 0;
        $active = $dbcr->selectrow_array("SELECT timeactive FROM clustertrack2 ".
                                         "WHERE userid=?", undef, $u->userid);
        LJ::MemCache::set($memkey, $active, 86400);
    }
    return $active;
}


sub kill_all_sessions {
    my $u = shift
        or return 0;

    LJ::Session->destroy_all_sessions($u)
        or return 0;

    # forget this user, if we knew they were logged in
    if ( $LJ::CACHE_REMOTE && $u->equals( $LJ::CACHE_REMOTE ) ) {
        LJ::Session->clear_master_cookie;
        LJ::User->set_remote(undef);
    }

    return 1;
}


# $u->kill_session(@sessids)
sub kill_session {
    my $u = shift
        or return 0;
    my $sess = $u->session
        or return 0;

    $sess->destroy;

    if ( $LJ::CACHE_REMOTE && $u->equals( $LJ::CACHE_REMOTE ) ) {
        LJ::Session->clear_master_cookie;
        LJ::User->set_remote(undef);
    }

    return 1;
}


sub kill_sessions {
    return LJ::Session->destroy_sessions( @_ );
}


sub logout {
    my $u = shift;
    if (my $sess = $u->session) {
        $sess->destroy;
    }
    $u->_logout_common;
}


sub logout_all {
    my $u = shift;
    LJ::Session->destroy_all_sessions($u)
        or die "Failed to logout all";
    $u->_logout_common;
}

sub make_fake_login_session {
    return $_[0]->make_login_session( 'once', undef, 1 );
}

sub make_login_session {
    my ( $u, $exptype, $ipfixed, $fake_login ) = @_;
    $exptype ||= 'short';
    return 0 unless $u;

    eval { BML::get_request()->notes->{ljuser} = $u->user; };

    # create session and log user in
    my $sess_opts = {
        'exptype' => $exptype,
        'ipfixed' => $ipfixed,
    };
    $sess_opts->{nolog} = 1 if $fake_login;

    my $sess = LJ::Session->create($u, %$sess_opts);
    $sess->update_master_cookie;

    LJ::User->set_remote($u);

    unless ( $fake_login ) {
        # add a uniqmap row if we don't have one already
        my $uniq = LJ::UniqCookie->current_uniq;
        LJ::UniqCookie->save_mapping($uniq => $u);
    }

    # restore scheme and language
    my $bl = LJ::Lang::get_lang($u->prop('browselang'));
    BML::set_language($bl->{'lncode'}) if $bl;

    # don't set/force the scheme for this page if we're on SSL.
    # we'll pick it up from cookies on subsequent pageloads
    # but if their scheme doesn't have an SSL equivalent,
    # then the post-login page throws security errors
    BML::set_scheme($u->prop('schemepref'))
        unless $LJ::IS_SSL;

    # run some hooks
    my @sopts;
    LJ::Hooks::run_hooks("login_add_opts", {
        "u" => $u,
        "form" => {},
        "opts" => \@sopts
    });
    my $sopts = @sopts ? ":" . join('', map { ".$_" } @sopts) : "";
    $sess->flags($sopts);

    my $etime = $sess->expiration_time;
    LJ::Hooks::run_hooks("post_login", {
        "u" => $u,
        "form" => {},
        "expiretime" => $etime,
    });

    unless ( $fake_login ) {
        # activity for cluster usage tracking
        LJ::mark_user_active($u, 'login');

        # activity for global account number tracking
        $u->note_activity('A');
    }

    return 1;
}


# We have about 10 million different forms of activity tracking.
# This one is for tracking types of user activity on a per-hour basis
#
#    Example: $u had login activity during this out
#
sub note_activity {
    my ($u, $atype) = @_;
    croak ("invalid user") unless ref $u;
    croak ("invalid activity type") unless $atype;

    # If we have no memcache servers, this function would trigger
    # an insert for every logged-in pageview.  Probably not a problem
    # load-wise if the site isn't using memcache anyway, but if the
    # site is that small active user tracking probably doesn't matter
    # much either.  :/
    return undef unless @LJ::MEMCACHE_SERVERS;

    # Also disable via config flag
    return undef unless LJ::is_enabled('active_user_tracking');

    my $now    = time();
    my $uid    = $u->userid;   # yep, lazy typist w/ rsi
    my $explen = 1800;         # 30 min, same for all types now

    my $memkey = [ $uid, "uactive:$atype:$uid" ];

    # get activity key from memcache
    my $atime = LJ::MemCache::get($memkey);

    # nothing to do if we got an $atime within the last hour
    return 1 if $atime && $atime > $now - $explen;

    # key didn't exist due to expiration, or was too old,
    # means we need to make an activity entry for the user
    my ($hr, $dy, $mo, $yr) = (gmtime($now))[2..5];
    $yr += 1900; # offset from 1900
    $mo += 1;    # 0-based

    # delayed insert in case the table is currently locked due to an analysis
    # running.  this way the apache won't be tied up waiting
    $u->do("INSERT IGNORE INTO active_user " .
           "SET year=?, month=?, day=?, hour=?, userid=?, type=?",
           undef, $yr, $mo, $dy, $hr, $uid, $atype);

    # set a new memcache key good for $explen
    LJ::MemCache::set($memkey, $now, $explen);

    return 1;
}


sub record_login {
    my ($u, $sessid) = @_;

    my $too_old = time() - 86400 * 30;
    $u->do("DELETE FROM loginlog WHERE userid=? AND logintime < ?",
           undef, $u->userid, $too_old);

    my $r  = DW::Request->get;
    my $ip = LJ::get_remote_ip();
    my $ua = $r->header_in('User-Agent');

    return $u->do("INSERT INTO loginlog SET userid=?, sessid=?, logintime=UNIX_TIMESTAMP(), ".
                  "ip=?, ua=?", undef, $u->userid, $sessid, $ip, $ua);
}


sub redirect_rename {
    my ( $u, $uri ) = @_;
    return undef unless $u->is_redirect;
    my $renamedto = $u->prop( 'renamedto' ) or return undef;
    my $ru = LJ::load_user( $renamedto ) or return undef;
    $uri ||= '';
    return BML::redirect( $ru->journal_base . $uri );
}


# my $sess = $u->session           (returns current session)
# my $sess = $u->session($sessid)  (returns given session id for user)
sub session {
    my ($u, $sessid) = @_;
    $sessid = $sessid + 0;
    return $u->{_session} unless $sessid;  # should be undef, or LJ::Session hashref
    return LJ::Session->instance($u, $sessid);
}


# in list context, returns an array of LJ::Session objects which are active.
# in scalar context, returns hashref of sessid -> LJ::Session, which are active
sub sessions {
    my $u = shift;
    my @sessions = LJ::Session->active_sessions($u);
    return @sessions if wantarray;
    my $ret = {};
    foreach my $s (@sessions) {
        $ret->{$s->id} = $s;
    }
    return $ret;
}


sub _logout_common {
    my $u = shift;
    my $r = DW::Request->get;
    LJ::Session->clear_master_cookie;
    LJ::User->set_remote( undef );
    $r->delete_cookie(
        name    => 'BMLschemepref',
        domain  => ".$LJ::DOMAIN",
    );
    eval { BML::set_scheme( undef ); };
}


########################################################################
### 5. Database and Memcache Functions

=head2 Database and Memcache Functions
=cut

sub begin_work {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->begin_work;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}


# front-end to LJ::cmd_buffer_add, which has terrible interface
#   cmd: scalar
#   args: hashref
sub cmd_buffer_add {
    my ($u, $cmd, $args) = @_;
    $args ||= {};
    return LJ::cmd_buffer_add( $u->clusterid, $u->userid, $cmd, $args );
}


sub commit {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->commit;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}


# $u->do("UPDATE foo SET key=?", undef, $val);
sub do {
    my $u = shift;
    my $query = shift;

    my $uid = $u->userid + 0
        or croak "Database update called on null user object";

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    $query =~ s!^(\s*\w+\s+)!$1/* uid=$uid */ !;

    my $rv = $dbcm->do($query, @_);
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    $u->{_mysql_insertid} = $dbcm->{'mysql_insertid'} if $dbcm->{'mysql_insertid'};

    return $rv;
}


sub dversion {
    my $u = shift;
    return $u->{dversion};
}


sub err {
    my $u = shift;
    return $u->{_dberr};
}


sub errstr {
    my $u = shift;
    return $u->{_dberrstr};
}


sub is_innodb {
    my $u = shift;
    my $cluid = $u->clusterid;
    return $LJ::CACHE_CLUSTER_IS_INNO{$cluid}
        if defined $LJ::CACHE_CLUSTER_IS_INNO{$cluid};

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;
    my (undef, $ctable) = $dbcm->selectrow_array("SHOW CREATE TABLE log2");
    die "Failed to auto-discover database type for cluster \#$cluid: [$ctable]"
        unless $ctable =~ /^CREATE TABLE/;

    my $is_inno = ($ctable =~ /=InnoDB/i ? 1 : 0);
    return $LJ::CACHE_CLUSTER_IS_INNO{$cluid} = $is_inno;
}


sub last_transition {
    # FIXME: this function is unused as of Aug 2009 - kareila
    my ($u, $what) = @_;
    croak "invalid user object" unless LJ::isu($u);

    $u->transition_list($what)->[-1];
}


# log2_do
# see comments for talk2_do
sub log2_do {
    my ($u, $errref, $sql, @args) = @_;
    return undef unless $u->writer;

    my $dbcm = $u->{_dbcm};

    my $memkey = [$u->userid, "log2lt:" . $u->userid];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    my $ret = $u->do($sql, undef, @args);
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    LJ::MemCache::delete($memkey, 0) if int($ret);
    return $ret;
}


# simple function for getting something from memcache; this assumes that the
# item being gotten follows the standard format [ $userid, "item:$userid" ]
sub memc_get {
    return LJ::MemCache::get( [$_[0]->userid, "$_[1]:" . $_[0]->userid] );
}


# sets a predictably named item. usage:
#   $u->memc_set( key => 'value', [ $timeout ] );
sub memc_set {
    return LJ::MemCache::set( [$_[0]->userid, "$_[1]:" . $_[0]->userid], $_[2], $_[3] || 1800 );
}


# deletes a predictably named item. usage:
#   $u->memc_delete( key );
sub memc_delete {
    return LJ::MemCache::delete( [$_[0]->userid, "$_[1]:" . $_[0]->userid] );
}


sub mysql_insertid {
    my $u = shift;
    if ($u->isa("LJ::User")) {
        return $u->{_mysql_insertid};
    } elsif ( LJ::DB::isdb( $u ) ) {
        my $db = $u;
        return $db->{'mysql_insertid'};
    } else {
        die "Unknown object '$u' being passed to LJ::User::mysql_insertid.";
    }
}


sub nodb_err {
    my $u = shift;
    return "Database handle unavailable [user: " . $u->user . "; cluster: " . $u->clusterid . ", errstr: $DBI::errstr]";
}


sub note_transition {
    # FIXME: this function is unused as of Aug 2009 - kareila
    my ($u, $what, $from, $to) = @_;
    croak "invalid user object" unless LJ::isu($u);

    return 1 unless LJ::is_enabled('user_transitions');

    # we don't want to insert if the requested transition is already
    # the last noted one for this user... in that case there has been
    # no transition at all
    my $last = $u->last_transition($what);
    return 1 if
        $last->{before} eq $from &&
        $last->{after}  eq $to;

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master";

    # bleh, need backticks on the 'before' and 'after' columns since those
    # are MySQL reserved words
    $dbh->do("INSERT INTO usertrans " .
             "SET userid=?, time=UNIX_TIMESTAMP(), what=?, " .
             "`before`=?, `after`=?",
             undef, $u->{userid}, $what, $from, $to);
    die $dbh->errstr if $dbh->err;

    # also log account changes to statushistory
    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "account_level_change", "$from -> $to")
        if $what eq "account";

    return 1;
}


# get an $sth from the writer
sub prepare {
    my $u = shift;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->prepare(@_);
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}


sub quote {
    my ( $u, $text ) = @_;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    return $dbcm->quote($text);
}


# memcache key that holds the number of times a user performed one of the rate-limited actions
sub rate_memkey {
    my ($u, $rp) = @_;

    return [$u->id, "rate:" . $u->id . ":$rp->{id}"];
}


sub readonly {
    my $u = shift;
    return LJ::get_cap($u, "readonly");
}


sub rollback {
    my $u = shift;
    return 1 unless $u->is_innodb;

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->rollback;
    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }
    return $rv;
}


sub selectall_arrayref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectall_arrayref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}


sub selectall_hashref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectall_hashref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}


sub selectcol_arrayref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectcol_arrayref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}


sub selectrow_array {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $set_err = sub {
        if ($u->{_dberr} = $dbcm->err) {
            $u->{_dberrstr} = $dbcm->errstr;
        }
    };

    if (wantarray()) {
        my @rv = $dbcm->selectrow_array(@_);
        $set_err->();
        return @rv;
    }

    my $rv = $dbcm->selectrow_array(@_);
    $set_err->();
    return $rv;
}


sub selectrow_hashref {
    my $u = shift;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;

    my $rv = $dbcm->selectrow_hashref(@_);

    if ($u->{_dberr} = $dbcm->err) {
        $u->{_dberrstr} = $dbcm->errstr;
    }

    return $rv;
}


# do some internal consistency checks on self.  die if problems,
# else returns 1.
sub selfassert {
    my $u = shift;
    LJ::assert_is( $u->userid, $u->{_orig_userid} )
        if $u->{_orig_userid};
    LJ::assert_is( $u->user, $u->{_orig_user} )
        if $u->{_orig_user};
    return 1;
}


# this is for debugging/special uses where you need to instruct
# a user object on what database handle to use.  returns the
# handle that you gave it.
sub set_dbcm {
    my $u = shift;
    return $u->{'_dbcm'} = shift;
}


# class method, returns { clusterid => [ uid, uid ], ... }
sub split_by_cluster {
    my $class = shift;

    my @uids = @_;
    my $us = LJ::load_userids(@uids);

    my %clusters;
    foreach my $u (values %$us) {
        next unless $u;
        push @{$clusters{$u->clusterid}}, $u->id;
    }

    return \%clusters;
}


# all reads/writes to talk2 must be done inside a lock, so there's
# no race conditions between reading from db and putting in memcache.
# can't do a db write in between those 2 steps.  the talk2 -> memcache
# is elsewhere (LJ::Talk), but this $dbh->do wrapper is provided
# here because non-talklib things modify the talk2 table, and it's
# nice to centralize the locking rules.
#
# return value is return of $dbh->do.  $errref scalar ref is optional, and
# if set, gets value of $dbh->errstr
#
# write:  (LJ::talk2_do)
#   GET_LOCK
#    update/insert into talk2
#   RELEASE_LOCK
#    delete memcache
#
# read:   (LJ::Talk::get_talk_data)
#   try memcache
#   GET_LOCk
#     read db
#     update memcache
#   RELEASE_LOCK

sub talk2_do {
    my ($u, $nodetype, $nodeid, $errref, $sql, @args) = @_;
    return undef unless $nodetype =~ /^\w$/;
    return undef unless $nodeid =~ /^\d+$/;
    return undef unless $u->writer;

    my $dbcm = $u->{_dbcm};
    my $userid = $u->userid;

    my $memkey = [$userid, "talk2:$userid:$nodetype:$nodeid"];
    my $lockkey = $memkey->[1];

    $dbcm->selectrow_array("SELECT GET_LOCK(?,10)", undef, $lockkey);
    my $ret = $u->do($sql, undef, @args);
    $$errref = $u->errstr if ref $errref && $u->err;
    $dbcm->selectrow_array("SELECT RELEASE_LOCK(?)", undef, $lockkey);

    LJ::MemCache::delete($memkey, 0) if int($ret);
    return $ret;
}


sub transition_list {
    # FIXME: this function is unused as of Aug 2009 - kareila
    my ($u, $what) = @_;
    croak "invalid user object" unless LJ::isu($u);

    my $dbh = LJ::get_db_writer()
        or die "unable to contact global db master";

    # FIXME: return list of transition object singleton instances?
    my @list = ();
    my $sth = $dbh->prepare("SELECT time, `before`, `after` " .
                            "FROM usertrans WHERE userid=? AND what=?");
    $sth->execute($u->{userid}, $what);
    die $dbh->errstr if $dbh->err;

    while (my $trans = $sth->fetchrow_hashref) {

        # fill in a couple of properties here rather than
        # sending over the network from db
        $trans->{userid} = $u->{userid};
        $trans->{what}   = $what;

        push @list, $trans;
    }

    return wantarray() ? @list : \@list;
}


sub uncache_prop {
    my ($u, $name) = @_;
    my $prop = LJ::get_prop("user", $name) or die; # FIXME: use exceptions
    my $userid = $u->userid;
    LJ::MemCache::delete( [$userid, "uprop:$userid:$prop->{id}"] );
    delete $u->{$name};
    return 1;
}


sub update_self {
    my ( $u, $ref ) = @_;
    return LJ::update_user( $u, $ref );
}


# returns self (the $u object which can be used for $u->do) if
# user is writable, else 0
sub writer {
    my $u = shift;
    return $u if $u->{'_dbcm'} ||= LJ::get_cluster_master($u);
    return 0;
}


########################################################################
### 6. What the App Shows to Users

=head2 What the App Shows to Users
=cut

# format unixtimestamp according to the user's timezone setting
sub format_time {
    # FIXME: this function is unused as of Aug 2009 - kareila
    my $u = shift;
    my $time = shift;

    return undef unless $time;

    return eval { DateTime->from_epoch(epoch=>$time, time_zone=>$u->prop("timezone"))->ymd('-') } ||
                  DateTime->from_epoch(epoch => $time)->ymd('-');
}


sub is_in_beta {
    my ($u, $key) = @_;
    return LJ::BetaFeatures->user_in_beta( $u => $key );
}


# sometimes when the app throws errors, we want to display "nice"
# text to end-users, while allowing admins to view the actual error message
sub show_raw_errors {
    my $u = shift;

    return 1 if $LJ::IS_DEV_SERVER;
    return 1 if $LJ::ENABLE_BETA_TOOLS;

    return 0 unless LJ::isu( $u );
    return 1 if $u->has_priv( "supporthelp" );
    return 1 if $u->has_priv( "supportviewscreened" );
    return 1 if $u->has_priv( "siteadmin" );

    return 0;
}


# returns a DateTime object corresponding to a user's "now"
sub time_now {
    my $u = shift;

    my $now = DateTime->now;

    # if user has timezone, use it!
    my $tz = $u->prop("timezone");
    return $now unless $tz;

    $now = eval { DateTime->from_epoch(
                                       epoch => time(),
                                       time_zone => $tz,
                                       );
              };

    return $now;
}


# return the user's timezone based on the prop if it's defined, otherwise best guess
sub timezone {
    my $u = shift;

    my $offset = 0;
    LJ::get_timezone($u, \$offset);
    return $offset;
}


########################################################################
### 7. Userprops, Caps, and Displaying Content to Others

=head2 Userprops, Caps, and Displaying Content to Others
=cut

sub add_to_class {
    my ($u, $class) = @_;
    my $bit = LJ::Capabilities::class_bit( $class );
    die "unknown class '$class'" unless defined $bit;

    # call add_to_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs the new we say we'll be adding
    if (LJ::Hooks::are_hooks('add_to_class')) {
        LJ::Hooks::run_hooks('add_to_class', $u, $class);
    }

    return $u->modify_caps( [$bit], [] );
}


# 1/0 whether the argument is allowed to search this journal
sub allow_search_by {
    my ( $u, $by ) = @_;
    return 0 unless LJ::isu( $u ) && LJ::isu( $by );

    # the person doing the search has to be an individual
    return 0 unless $by->is_individual;

    # someone in the equation has to be a paid account
    return 0 unless $u->is_paid || $by->is_paid;

    # allow searches if this is a community or it's us
    return 1 if $u->is_community || $u->equals( $by );

    # check the userprop for security access
    my $whocan = $u->prop( 'opt_allowsearchby' ) || 'F';
    return 1 if $whocan eq 'A';
    return 1 if $whocan eq 'F' && $u->trusts( $by );
    return 1 if $whocan eq 'N' && $u->equals( $by );

    # failing the above, sorry, no search for you
    return 0;
}


sub caps {
    my $u = shift;
    return $u->{caps};
}


sub can_be_text_messaged_by {
    my ($u, $sender) = @_;

    return 0 unless $u->get_cap("textmessaging");

    # check for valid configuration
    my $tminfo = LJ::TextMessage->tm_info( $u );
    return 0 unless $tminfo->{provider} && $tminfo->{number};

    my $security = LJ::TextMessage->tm_security($u);

    return 0 if $security eq "none";
    return 1 if $security eq "all";

    if ($sender) {
        return 1 if $security eq "reg";
        return 1 if $security eq "friends" && $u->trusts( $sender );
    }

    return 0;
}

sub can_beta_payments {
    return $_[0]->get_cap( 'beta_payments' ) ? 1 : 0;
}

sub can_buy_icons {
    return $_[0]->get_cap( 'bonus_icons' ) ? 1 : 0;
}

sub can_create_feeds {
    return $_[0]->get_cap( 'synd_create' ) ? 1 : 0;
}

sub can_create_moodthemes {
    return $_[0]->get_cap( 'moodthemecreate' ) ? 1 : 0;
}

sub can_create_polls {
    return $_[0]->get_cap( 'makepoll' ) ? 1 : 0;
}

sub can_create_s2_props {
    return $_[0]->get_cap( 's2props' ) ? 1 : 0;
}

sub can_create_s2_styles {
    return $_[0]->get_cap( 's2styles' ) ? 1 : 0;
}

sub can_edit_comments {
    return $_[0]->get_cap( 'edit_comments' ) ? 1 : 0;
}

sub can_emailpost {
    return $_[0]->get_cap( 'emailpost' ) ? 1 : 0;
}

sub can_find_similar {
    return $_[0]->get_cap( 'findsim' ) ? 1 : 0;
}

sub can_get_comments {
    return $_[0]->get_cap( 'get_comments' ) ? 1 : 0;
}

sub can_get_self_email {
    return $_[0]->get_cap( 'getselfemail' ) ? 1 : 0;
}

sub can_have_email_alias {
    return 0 unless $LJ::USER_EMAIL;
    return $_[0]->get_cap( 'useremail' ) ? 1 : 0;
}

sub can_leave_comments {
    return $_[0]->get_cap( 'leave_comments' ) ? 1 : 0;
}

sub can_manage_invites_light {
    my $u = $_[0];

    return 1 if $u->has_priv( "payments" );
    return 1 if $u->has_priv( "siteadmin", "invites" );

    return 0;
}

sub can_map_domains {
    return $_[0]->get_cap( 'domainmap' ) ? 1 : 0;
}

sub can_post {
    return $_[0]->get_cap( 'can_post' ) ? 1 : 0;
}

sub can_post_disabled {
    return $_[0]->get_cap( 'disable_can_post' ) ? 1 : 0;
}

sub can_import_comm {
    return $_[0]->get_cap( 'import_comm' ) ? 1 : 0;
}

sub can_receive_vgifts_from {
    my ( $u, $remote, $is_anon ) = @_;
    $remote ||= LJ::get_remote();
    my $valid_remote = LJ::isu( $remote ) ? 1 : 0;

    # check for shop status
    return 0 unless exists $LJ::SHOP{vgifts};

    # check for anonymous
    return 0 if $is_anon && $u->prop( 'opt_anonvgift_optout' );

    # if the prop isn't set, default to true
    my $prop = $u->prop( 'opt_allowvgiftsfrom' );
    return 1 unless $prop;

    # all: always true; none: always false
    return 1 if $prop eq 'all';
    return 0 if $prop eq 'none';

    # registered: must have $remote
    return $valid_remote if $prop eq 'registered';
    return 0 unless $valid_remote;  # shortcut: skip remaining tests

    # access: anyone on trust/membership list
    return $u->trusts_or_has_member( $remote ) if $prop eq 'access';

    # remaining options not allowed for communities
    return 0 if $u->is_community;

    # circle: also includes watch list
    return $u->watches( $remote ) || $u->trusts( $remote )
        if $prop eq 'circle';

    # only remaining valid option: trust group, which must be numeric.
    # if it's not a valid value, assume false
    return 0 unless $prop =~ /^\d+$/;

    # check the trustmask
    my $mask = 1 << $prop;
    return ( $u->trustmask( $remote ) & $mask );
}

sub can_show_location {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);
    my $remote = LJ::get_remote();

    return 0 if $u->opt_showlocation eq 'N';
    return 0 if $u->opt_showlocation eq 'R' && !$remote;
    return 0 if $u->opt_showlocation eq 'F' && !$u->trusts( $remote );
    return 1;
}


sub can_show_onlinestatus {
    # FIXME: this function is unused as of Aug 2009 - kareila
    my $u = shift;
    my $remote = shift;
    croak "invalid user object passed"
        unless LJ::isu($u);

    # Nobody can see online status of $u
    return 0 if $u->opt_showonlinestatus eq 'N';

    # Everybody can see online status of $u
    return 1 if $u->opt_showonlinestatus eq 'Y';

    # Only mutually trusted people of $u can see online status
    if ($u->opt_showonlinestatus eq 'F') {
        return 0 unless $remote;
        return 1 if $u->mutually_trusts( $remote );
        return 0;
    }
    return 0;
}

# The option to track all comments is available to:
# -- community admins for any community they manage
# -- all users if community's seed or premium paid
# -- members only if community's paid
sub can_track_all_community_comments {
    my ( $remote, $journal ) = @_;
     return 1 if LJ::isu( $journal ) && $journal->is_community
                 && ( $remote->can_manage_other( $journal )
                    || $journal->get_cap( 'track_all_comments' )
                    || $journal->is_paid && $remote->member_of( $journal ) );
}

sub can_track_defriending {
    return $_[0]->get_cap( 'track_defriended' ) ? 1 : 0;
}

sub can_track_new_userpic {
    return $_[0]->get_cap( 'track_user_newuserpic' ) ? 1 : 0;
}

sub can_track_pollvotes {
    return $_[0]->get_cap( 'track_pollvotes' ) ? 1 : 0;
}

sub can_track_thread {
    return $_[0]->get_cap( 'track_thread' ) ? 1 : 0;
}

sub can_use_checkforupdates {
    return $_[0]->get_cap( 'checkfriends' ) ? 1 : 0;
}

sub can_use_daily_readpage {
    return $_[0]->get_cap( 'friendspage_per_day' ) ? 1 : 0;
}

sub can_use_directory {
    return $_[0]->get_cap( 'directory' ) ? 1 : 0;
}

sub can_use_fastlane {
    return $_[0]->get_cap( 'fastserver' ) ? 1 : 0;
}

sub can_use_full_rss {
    return $_[0]->get_cap( 'full_rss' ) ? 1 : 0;
}

sub can_use_google_analytics {
    return $_[0]->get_cap( 'google_analytics' ) ? 1 : 0;
}

sub can_use_latest_comments_rss {
    return $_[0]->get_cap( 'latest_comments_rss' ) ? 1 : 0;
}

sub can_use_mass_privacy {
    return $_[0]->get_cap( 'mass_privacy' ) ? 1 : 0;
}

sub can_use_popsubscriptions {
    return $_[0]->get_cap( 'popsubscriptions' ) ? 1 : 0;
}

sub can_use_network_page {
    return 0 unless $_[0]->get_cap( 'friendsfriendsview' ) && $_[0]->is_person;
}


sub can_use_active_entries {
    return $_[0]->get_cap( 'activeentries' ) ? 1 : 0;
}

# Check if the user can use *any* page statistic module for their own journal.
sub can_use_page_statistics {
    return $_[0]->can_use_google_analytics;
}

sub can_use_textmessaging {
    return $_[0]->get_cap( 'textmessaging' ) ? 1 : 0;
}

sub can_use_userpic_select {
    return 0 unless LJ::is_enabled( 'userpicselect' );
    return $_[0]->get_cap( 'userpicselect' ) ? 1 : 0;
}

sub can_view_mailqueue {
    return $_[0]->get_cap( 'viewmailqueue' ) ? 1 : 0;
}

sub captcha_type {
    my $u = $_[0];

    if ( defined $_[1] ) {
        $u->set_prop( captcha => $_[1] );
    }

    return $_[1] || $u->prop( 'captcha' ) || $LJ::DEFAULT_CAPTCHA_TYPE;
}

sub cc_msg {
    my ( $u, $value ) = @_;
    if ( defined $value && $value=~ /[01]/ ) {
       $u->set_prop( cc_msg => $value );
       return $value;
    }

    return $u->prop( 'cc_msg' ) ? 1 : 0;
}

sub clear_prop {
    my ($u, $prop) = @_;
    $u->set_prop($prop, undef);
    return 1;
}

=head3 C<< $self->clear_daycounts( @security ) >>

Clears the day counts relevant to the entry security

security is an array of strings: "public", a number (allowmask), "private"

=cut

sub clear_daycounts
{
    my ( $u, @security ) = @_;

    return undef unless LJ::isu( $u );
    # if old and new security are equal, don't clear the day counts
    return undef if scalar @security == 2 && $security[0] eq $security[1];

    # memkind can be one of:
    #  a = all entries in this journal
    #  g# = access or groupmask
    #  p = only public entries
    my @memkind;
    my $access = 0;
    foreach my $security ( @security )
    {
        push @memkind, "p" if $security eq 'public'; # public
        push @memkind, "g$security" if $security =~ /^\d+/;

        $access++ if $security eq 'public' || ( $security != 1 &&  $security =~ /^\d+/ );
    }
    # clear access only security, but does not cover custom groups
    push @memkind, "g1" if $access;

    # any change to any entry security means this must be expired
    push @memkind, "a";

    foreach my $memkind ( @memkind )
    {
        LJ::MemCache::delete( [ $u->userid, "dayct2:" . $u->userid . ":$memkind" ] );
    }
}

sub optout_community_promo {
    my ( $u, $val ) = @_;

    if ( defined $val && $val =~ /^[01]$/ ) {
        $u->set_prop( optout_community_promo => $val );
        return $val;
    }

    return $u->prop( 'optout_community_promo' ) ? 1 : 0;
}

sub control_strip_display {
    my $u = shift;

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'control_strip_display' );
    return 0 if $prop_val eq 'none';
    return $prop_val if $prop_val =~ /^\d+$/;

    # otherwise, return the default: all options checked
    my $ret;
    my @pageoptions = LJ::Hooks::run_hook( 'page_control_strip_options' );
    for ( my $i = 0; $i < scalar @pageoptions; $i++ ) {
        $ret |= 1 << $i;
    }

    return $ret ? $ret : 0;
}

sub count_bookmark_max {
    return $_[0]->get_cap( 'bookmark_max' );
}

sub count_inbox_max {
    return $_[0]->get_cap( 'inbox_max' );
}

sub count_maxcomments {
    return $_[0]->get_cap( 'maxcomments' );
}

sub count_maxcomments_before_captcha {
    return $_[0]->get_cap( 'maxcomments-before-captcha' );
}

sub count_maxfriends {
    return $_[0]->get_cap( 'maxfriends' );
}

sub count_max_interests {
    return $_[0]->get_cap( 'interests' );
}

sub count_max_mod_queue {
    return $_[0]->get_cap( 'mod_queue' );
}

sub count_max_mod_queue_per_poster {
    return $_[0]->get_cap( 'mod_queue_per_poster' );
}

sub count_max_subscriptions {
    return $_[0]->get_cap( 'subscriptions' );
}

sub count_max_userlinks {
    return $_[0]->get_cap( 'userlinks' );
}

sub count_max_userpics {
    return $_[0]->userpic_quota;
}

sub count_max_xpost_accounts {
    return $_[0]->get_cap( 'xpost_accounts' );
}

sub count_recent_comments_display {
    return $_[0]->get_cap( 'tools_recent_comments_display' );
}

sub count_s2layersmax {
    return $_[0]->get_cap( 's2layersmax' );
}

sub count_s2stylesmax {
    return $_[0]->get_cap( 's2stylesmax' );
}

sub count_tags_max {
    return $_[0]->get_cap( 'tags_max' );
}

sub count_usermessage_length {
    return $_[0]->get_cap( 'usermessage_length' );
}

# returns the country specified by the user
sub country {
    return $_[0]->prop( 'country' );
}

sub disable_auto_formatting {
    my ( $u, $value ) = @_;
    if ( defined $value && $value =~ /[01]/ ) {
        $u->set_prop( disable_auto_formatting => $value );
        return $value;
    }

    return $u->prop( 'disable_auto_formatting' ) ? 1 : 0;
}

sub exclude_from_own_stats {
    my $u = shift;

    if ( defined $_[0] && $_[0] =~ /[01]/ ) {
        $u->set_prop( exclude_from_own_stats => $_[0] );
        return $_[0];
    }

    return $u->prop( 'exclude_from_own_stats' ) eq "1" ? 1 : 0;
}

# returns the max capability ($cname) for all the classes
# the user is a member of
sub get_cap {
    my ( $u, $cname ) = @_;

    # turn on all caps for tests, except the read-only cap
    return 1 if $LJ::T_HAS_ALL_CAPS && $cname ne "readonly";
    return LJ::get_cap( $u, $cname );
}

# returns the gift shop URL to buy a gift for that user
sub gift_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/shop/account?for=gift&user=" . $u->user;
}


# returns the gift shop URL to buy points for that user
sub gift_points_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/shop/points?for=" . $u->user;
}

# returns the gift shop URL to transfer your own points to that user
sub transfer_points_url {
    my ( $u ) = @_;
    return "$LJ::SITEROOT/shop/transferpoints?for=" . $u->user;
}

=head3 C<< $self->give_shop_points( %options ) >>

The options hash MUST contain the following keys:

=over 4

=item amount

How many points to give the user.  May be positive or negative, s
use a negative number to deduct points from a user's balance.  Will not allow
a user's balance to go negative.

=item reason

A short description of why this transaction is happening.  For
example: 'purchase of cart 9883463'.

=back

The options hash MAY contain these keys, as well:

=over 4

=item admin

If this action was being done by an administrator, pass their userid
or user object here.  This helps us record when admins make things happen.

=back

Example usage:

C<<   $self->give_shop_points( amount => 50, reason => 'purchased' ); >>

This gives 50 points to the user as a routine purchase.

C<<   $self->give_shop_points( amount => -100, reason => 'refund', admin => $remote ); >>

Admin processed refund, remove 100 points from the user's balance.

Returns a true value on success, undef on error.

=cut

sub give_shop_points {
    my ( $self, %opts ) = @_;
    return unless LJ::isu( $self );

    # do some cleanup on our input parameters
    $opts{amount} += 0;
    $opts{reason} = LJ::trim( $opts{reason} );
    return unless $opts{amount} && $opts{reason};

    # ensure we're not going negative ...
    my $old = $self->shop_points;
    die "Unable to set points balance to negative value.\n"
        if $old + $opts{amount} < 0;

    # log the change first so we know what's going on
    my $admin = $opts{admin} ? LJ::want_user( $opts{admin} ) : undef;
    my $msg = sprintf( 'old balance: %d, adjust amount: %d, reason: %s', $old, $opts{amount}, $opts{reason} );
    LJ::statushistory_add( $self->id, $admin ? $admin->id : undef, 'shop_points', $msg);

    # finally set the value
    $self->set_prop( shop_points => $old + $opts{amount } );
    return 1;
}


# get/set the Google Analytics ID
sub google_analytics {
    my $u = shift;

    if ( defined $_[0] ) {
        $u->set_prop( google_analytics => $_[0] );
        return $_[0];
    }

    return $u->prop( 'google_analytics' );
}


# get/set post to community link visibility
sub hide_join_post_link {
    my $u = $_[0];

    if ( defined $_[1] ) {
        $u->set_prop( hide_join_post_link => $_[1] );
        return $_[1];
    }

    return $u->prop( 'hide_join_post_link' );
}

=head3 C<< $self->iconbrowser_metatext( [ $arg ] ) >>

If no argument, returns whether to show meta text in the icon browser or not.
Default is to show meta text (true)

If argument is passed in, acts as setter. Argument can be "Y" / "N"

=cut

sub iconbrowser_metatext {
    my $u = $_[0];

    if ( $_[1] ) {
        my $newval = $_[1] eq "N" ? "N": undef;
        $u->set_prop( iconbrowser_metatext => $newval );
    }

    return  ( $_[1] || $u->prop( 'iconbrowser_metatext' ) || "Y" ) eq 'Y' ? 1 : 0;
}


=head3 C<< $self->iconbrowser_smallicons( [ $small_icons ] ) >>

If no argument, returns whether to show small icons in the icon browser or large.
Default is large.

If argument is passed in, acts as setter. Argument can be "Y" / "N"

=cut

sub iconbrowser_smallicons {
    my $u = $_[0];

    if ( $_[1] ) {
        my $newval = $_[1] eq "Y" ? "Y" : undef;
        $u->set_prop( iconbrowser_smallicons => $newval );
    }

    return  ( $_[1] || $u->prop( 'iconbrowser_smallicons' ) || "N" ) eq 'Y' ? 1 : 0;
}

# whether to respect cut tags in the inbox
sub cut_inbox {
    my $u = $_[0];

    if ( defined $_[1] ) {
        $u->set_prop( cut_inbox => $_[1] );
    }

    return  ( $_[1] || $u->prop( 'cut_inbox' ) || "N" ) eq 'Y' ? 1 : 0;
}

# tests to see if a user is in a specific named class. class
# names are site-specific.
sub in_class {
    my ($u, $class) = @_;
    return LJ::Capabilities::caps_in_group( $u->{caps}, $class );
}


# 1/0; whether or not this account should be included in the global search
# system.  this is used by the bin/worker/sphinx-copier mostly.
sub include_in_global_search {
    my $u = $_[0];

    # only P/C accounts should be globally searched
    return 0 unless $u->is_person || $u->is_community;

    # default) check opt_blockglobalsearch and use that if it's defined
    my $bgs = $u->prop( 'opt_blockglobalsearch' );
    return $bgs eq 'Y' ? 0 : 1 if defined $bgs && length $bgs;

    # fallback) use their robot blocking value if it's set
    my $br = $u->prop( 'opt_blockrobots' );
    return $br ? 0 : 1 if defined $br && length $br;

    # allow search of this user's content
    return 1;
}


# whether this user wants to have their content included in the latest feeds or not
sub include_in_latest_feed {
    my $u = $_[0];
    return $u->prop( 'latest_optout' ) ? 0 : 1;
}


# must be called whenever birthday, location, journal modtime, journaltype, etc.
# changes.  see LJ/Directory/PackedUserRecord.pm
sub invalidate_directory_record {
    my $u = shift;

    # Future: ?
    # LJ::try_our_best_to("invalidate_directory_record", $u->id);
    # then elsewhere, map that key to subref.  if primary run fails,
    # put in schwartz, then have one worker (misc-deferred) to
    # redo...

    my $dbs = defined $LJ::USERSEARCH_DB_WRITER ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER) : LJ::get_db_writer();
    $dbs->do("UPDATE usersearch_packdata SET good_until=0 WHERE userid=?",
             undef, $u->id);
}


# <LJFUNC>
# name: LJ::User::large_journal_icon
# des: get the large icon by journal type.
# returns: HTML to display large journal icon.
# </LJFUNC>
sub large_journal_icon {
    my $u = shift;
    croak "invalid user object"
        unless LJ::isu($u);

    my $wrap_img = sub {
        my $type = $_[0];
        return LJ::img( "id_$type-24", "",
                        { border => 0, style => 'padding: 0px 2px 0px 0px' } );
    };

    return $wrap_img->( "community" ) if $u->is_comm;

    return $wrap_img->( "feed" ) if $u->is_syndicated;

    return $wrap_img->( "openid" ) if $u->is_identity;

    # personal or unknown fallthrough
    return $wrap_img->( "user" );
}


# des: Given a list of caps to add and caps to remove, updates a user's caps.
# args: cap_add, cap_del, res
# des-cap_add: arrayref of bit numbers to turn on
# des-cap_del: arrayref of bit numbers to turn off
# des-res: hashref returned from 'modify_caps' hook
# returns: updated u object, retrieved from $dbh, then 'caps' key modified
#          otherwise, returns 0 unless all hooks run properly.
sub modify_caps {
    my ( $argu, $cap_add, $cap_del, $res ) = @_;
    my $userid = LJ::want_userid( $argu );
    return undef unless $userid;

    $cap_add ||= [];
    $cap_del ||= [];
    my %cap_add_mod = ();
    my %cap_del_mod = ();

    # convert capnames to bit numbers
    if ( LJ::Hooks::are_hooks( "get_cap_bit" ) ) {
        foreach my $bit ( @$cap_add, @$cap_del ) {
            next if $bit =~ /^\d+$/;

            # bit is a magical reference into the array
            $bit = LJ::Hooks::run_hook( "get_cap_bit", $bit );
        }
    }

    # get a u object directly from the db
    my $u = LJ::load_userid( $userid, "force" ) or return;

    # add new caps
    my $newcaps = int( $u->{caps} );
    foreach ( @$cap_add ) {
        my $cap = 1 << $_;

        # about to turn bit on, is currently off?
        $cap_add_mod{$_} = 1 unless $newcaps & $cap;
        $newcaps |= $cap;
    }

    # remove deleted caps
    foreach ( @$cap_del ) {
        my $cap = 1 << $_;

        # about to turn bit off, is it currently on?
        $cap_del_mod{$_} = 1 if $newcaps & $cap;
        $newcaps &= ~$cap;
    }

    # run hooks for modified bits
    if ( LJ::Hooks::are_hooks( "modify_caps" ) ) {
        $res = LJ::Hooks::run_hook( "modify_caps",
             { u => $u,
               newcaps => $newcaps,
               oldcaps => $u->{caps},
               cap_on_req  => { map { $_ => 1 } @$cap_add },
               cap_off_req => { map { $_ => 1 } @$cap_del },
               cap_on_mod  => \%cap_add_mod,
               cap_off_mod => \%cap_del_mod } );

        # hook should return a status code
        return undef unless defined $res;
    }

    # update user row
    return 0 unless $u->update_self( { caps => $newcaps } );

    $u->{caps} = $newcaps;
    $argu->{caps} = $newcaps;
    return $u;
}


sub opt_logcommentips {
    my $u = shift;

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'opt_logcommentips' );
    return $prop_val if $prop_val =~ /^[NSA]$/;

    # otherwise, return the default: log for all comments
    return 'A';
}

sub opt_nctalklinks {
    my ( $u, $val ) = @_;

    if ( defined $val && $val =~ /^[01]$/ ) {
        $u->set_prop( opt_nctalklinks => $val );
        return $val;
    }

    return $u->prop( 'opt_nctalklinks' ) eq "1" ? 1 : 0;
}

sub opt_randompaidgifts {
    my $u = shift;

    return $u->prop( 'opt_randompaidgifts' ) eq 'N' ? 0 : 1;
}

sub opt_showcontact {
    my $u = shift;

    if ($u->{'allow_contactshow'} =~ /^(N|Y|R|F)$/) {
        return $u->{'allow_contactshow'};
    } else {
        return 'F' if $u->is_minor;
        return 'Y';
    }
}


sub opt_showlocation {
    my $u = shift;
    # option not set = "yes", set to N = "no"
    $u->_lazy_migrate_infoshow;

    # see comments for opt_showbday
    unless ( LJ::is_enabled('infoshow_migrate') || $u->{allow_infoshow} eq ' ' ) {
        return $u->{allow_infoshow} eq 'Y' ? undef : 'N';
    }
    if ($u->raw_prop('opt_showlocation') =~ /^(N|Y|R|F)$/) {
        return $u->raw_prop('opt_showlocation');
    } else {
        return 'F' if ($u->is_minor);
        return 'Y';
    }
}


# opt_showonlinestatus options
# F = Mutually Trusted
# Y = Everybody
# N = Nobody
sub opt_showonlinestatus {
    my $u = shift;

    if ($u->raw_prop('opt_showonlinestatus') =~ /^(F|N|Y)$/) {
        return $u->raw_prop('opt_showonlinestatus');
    } else {
        return 'F';
    }
}


sub opt_whatemailshow {
    my $u = $_[0];

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'opt_whatemailshow' );
    $prop_val =~ tr/BVL/ADN/ unless $u->can_have_email_alias;
    return $prop_val if $prop_val =~ /^[ALBNDV]$/;

    # otherwise, return the default: no email shown
    return 'N';
}


# get/set community's guidelines entry ditemid
sub posting_guidelines_entry {
    my ( $u, $args ) = @_;

    if ( defined $args ) {
        unless ( $args ) {
            $u->set_prop( posting_guidelines_entry => '' );
            return 1;
        }
        my $ditemid;
        if ( $args =~ m!/(\d+)\.html! ) {
            $ditemid = $1;
        } elsif ( $args =~ m!^(\d+)$! ) {
            $ditemid = $1;
        } else {
            return 0;
        }

        my $entry = LJ::Entry->new( $u, ditemid => $ditemid );
        return 0 unless $entry && $entry->valid;

        $u->set_prop( posting_guidelines_entry => $ditemid );
        return $ditemid;
    }

    return $u->prop( 'posting_guidelines_entry' );
}


# get community's guidelines entry as entry object
sub get_posting_guidelines_entry {
    my $u = shift;

    if ( my $ditemid = $u->posting_guidelines_entry ) {
        my $entry = LJ::Entry->new( $u, ditemid => $ditemid );
        return $entry if $entry->valid;
    }

    return undef;
}

sub posting_guidelines_url {
    my $u = $_[0];

    return "" unless $u->is_community;

    my $posting_guidelines = $u->posting_guidelines_entry;
    if ( $u->posting_guidelines_location eq "P" ) {
        return $u->profile_url;
    } elsif ( $u->posting_guidelines_location eq "N") {
        return "";
    }

    return "" unless $posting_guidelines;

    return $u->journal_base . "/guidelines";
}

# Where are a community's posting guidelines held?  Blank=Nowhere, P=Profile, E=Entry
sub posting_guidelines_location {
    my ( $u,  $value ) = @_;
    if ( defined $value && $value=~ /[PE]/ ) {
        $u->set_prop( posting_guidelines_location => $value );
        return $value;
    }
    # We store the "N=Nowhere" option in the database as a blank empty entry to
    # reduce space.  N should be returned whenever a blank entry is encountered.
    if ( defined $value && $value eq 'N' ) {
        $u->set_prop( posting_guidelines_location => '' );
        return $value;
    }
    $u->prop( 'posting_guidelines_location' ) || $LJ::DEFAULT_POSTING_GUIDELINES_LOC;
}


sub profile_url {
    my ( $u, %opts ) = @_;

    my $url;
    if ( $u->is_identity ) {
        $url = "$LJ::SITEROOT/profile?userid=" . $u->userid . "&t=I";
        $url .= "&mode=full" if $opts{full};
    } else {
        $url = $u->journal_base . "/profile";
        $url .= "?mode=full" if $opts{full};
    }
    return $url;
}


# get/set the displayed email on profile (if user has specified)
sub profile_email {
    my ( $u, $email ) = @_;

    if ( defined $email ) {
        $u->set_prop( opt_profileemail => $email );
        return $email;
    }

    return $u->prop( 'opt_profileemail' );
}


# instance method:  returns userprop for a user.  currently from cache with no
# way yet to force master.
sub prop {
    my ($u, $prop) = @_;

    # some props have accessors which do crazy things, if so they need
    # to be redirected from this method, which only loads raw values
    if ({ map { $_ => 1 }
          qw(opt_sharebday opt_showbday opt_showlocation opt_showmutualfriends
             view_control_strip show_control_strip opt_ctxpopup opt_embedplaceholders
             esn_inbox_default_expand)
        }->{$prop})
    {
        return $u->$prop;
    }

    return $u->raw_prop($prop);
}


# returns the user's public key
sub public_key {
    $_[0]->prop( 'public_key' );
}


sub raw_prop {
    my ($u, $prop) = @_;
    $u->preload_props($prop) unless exists $u->{$prop};
    return $u->{$prop};
}


sub remove_from_class {
    my ($u, $class) = @_;
    my $bit = LJ::Capabilities::class_bit( $class );
    die "unknown class '$class'" unless defined $bit;

    # call remove_from_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs what we'll be removing
    if (LJ::Hooks::are_hooks('remove_from_class')) {
        LJ::Hooks::run_hooks('remove_from_class', $u, $class);
    }

    return $u->modify_caps( [], [$bit] );
}


# Sets/deletes userprop(s) by name for a user.
# This adds or deletes from the [dbtable[userprop]]/[dbtable[userproplite]]
# tables, and also updates $u's cached version. Can set $prop => $value
# or also accepts a hashref of propname keys and corresponding values.
# Returns boolean indicating success or failure.
sub set_prop {
    my ( $u, $prop, $value, $opts ) = @_;
    my $userid = $u->userid + 0;
    my $hash = ref $prop eq "HASH" ? $prop : { $prop => $value };
    $opts ||= {};

    my %action;  # $table -> {"replace"|"delete"} -> [ "($propid, $qvalue)" | propid ]
    my %multihomed;  # { $propid => $value }
    my %propnames;   # { $propid => $propname }

    # enforce limits on data in the code
    # to make sure that memcache and db data are consistent after a save
    my %table_values_lengths = (
        userprop => 60,
        userproplite => 255,
        userproplite2 => 255,
        # userpropblob => ...,
    );

    # Accumulate prepared actions.
    foreach my $propname ( keys %$hash ) {
        $value = $hash->{$propname};

        # Call all hooks, since we don't look at the return values.
        # We expect anybody who uses this hook to do the extra work
        # a property needs when it is set.
        LJ::Hooks::run_hooks( 'setprop', prop => $propname, u => $u, value => $value );

        my $p = LJ::get_prop( "user", $propname ) or
            die "Attempted to set invalid userprop $propname.";
        $propnames{ $p->{id} } = $propname;

        if ( $p->{multihomed} ) {
            # collect into array for later handling
            $multihomed{ $p->{id} } = $value;
            next;
        }
        # if not multihomed, select appropriate table
        my $table = 'userproplite';  # default
        $table = 'userprop' if $p->{indexed};
        $table = 'userproplite2' if $p->{cldversion}
                                 && $u->dversion >= $p->{cldversion};
        $table = 'userpropblob' if $p->{datatype} eq 'blobchar';

        # only assign db for update action if value has changed
        unless ( $opts->{skip_db} && $value eq $u->{$propname} ) {
            my $db = $action{$table}->{db} ||= (
                $table !~ m{userprop(lite2|blob)}
                    ? LJ::get_db_writer()  # global
                    : $u->writer );        # clustered
            return 0 unless $db;  # failure to get db handle
        }

        # determine if this is a replacement or a deletion
        if ( defined $value && $value ) {
            $value = LJ::text_trim( $value, undef, $table_values_lengths{$table} )
                        if defined $table_values_lengths{$table};
            push @{ $action{$table}->{replace} }, [ $p->{id}, $value ];
        } else {
            push @{ $action{$table}->{delete} }, $p->{id};
        }
    }

    # keep in memcache for 24 hours and update user object in memory
    my $memc = sub {
        my ( $p, $v ) = @_;
        LJ::MemCache::set( [ $userid, "uprop:$userid:$p" ], $v, 3600 * 24 );
        $u->{ $propnames{$p} } = $v eq "" ? undef : $v;
    };

    # Execute prepared actions.
    foreach my $table ( keys %action ) {
        my $db = $action{$table}->{db};
        if ( my $list = $action{$table}->{replace} ) {
            if ( $db ) {
                my $vals = join( ',', map { "($userid,$_->[0]," . $db->quote( $_->[1] ) . ")" } @$list );
                $db->do( "REPLACE INTO $table (userid, upropid, value) VALUES $vals" );
                die $db->errstr if $db->err;
            }
            $memc->( $_->[0], $_->[1] ) foreach @$list;
        }
        if ( my $list = $action{$table}->{delete} ) {
            if ( $db ) {
                my $in = join( ',', @$list );
                $db->do( "DELETE FROM $table WHERE userid=$userid AND upropid IN ($in)" );
                die $db->errstr if $db->err;
            }
            $memc->( $_, "" ) foreach @$list;
        }
    }

    # if we had any multihomed props, set them here
    if ( %multihomed ) {
        my $dbh = LJ::get_db_writer();
        return 0 unless $dbh && $u->writer;

        while ( my ( $propid, $pvalue ) = each %multihomed ) {
            if ( defined $pvalue && $pvalue ) {
                my $uprop_pvalue = LJ::text_trim( $pvalue, undef, $table_values_lengths{userprop} );

                # replace data into master
                $dbh->do( "REPLACE INTO userprop VALUES (?, ?, ?)",
                          undef, $userid, $propid, $uprop_pvalue );
            } else {
                # delete data from master, but keep in cluster
                $dbh->do( "DELETE FROM userprop WHERE userid = ? AND upropid = ?",
                          undef, $userid, $propid );
            }

            # fail out?
            return 0 if $dbh->err;

            # put data in cluster
            $pvalue = $pvalue ? LJ::text_trim( $pvalue, undef, $table_values_lengths{userproplite2} ) : '';
            $u->do( "REPLACE INTO userproplite2 VALUES (?, ?, ?)",
                    undef, $userid, $propid, $pvalue );
            return 0 if $u->err;

            # set memcache and update user object
            $memc->( $propid, $pvalue );
        }
    }

    return 1;
}


sub share_contactinfo {
    my ($u, $remote) = @_;

    return 0 if $u->is_syndicated;
    return 0 if $u->opt_showcontact eq 'N';
    return 0 if $u->opt_showcontact eq 'R' && !$remote;
    return 0 if $u->opt_showcontact eq 'F' && !$u->trusts( $remote );
    return 1;
}


=head3 C<< $self->shop_points >>

Returns how many points this user currently has available for spending in the
shop.  For adjusting points on a user, please see C<<$self->give_shop_points>>.

=cut

sub shop_points {
    return $_[0]->prop( 'shop_points' ) // 0;
}


sub should_block_robots {
    my $u = shift;

    return 1 if $u->is_syndicated;
    return 1 if $u->is_identity;
    return 1 if $u->prop('opt_blockrobots');

    return 0 unless LJ::is_enabled( 'adult_content' );

    my $adult_content = $u->adult_content_calculated;

    return 1 if $LJ::CONTENT_FLAGS{$adult_content} && $LJ::CONTENT_FLAGS{$adult_content}->{block_robots};
    return 0;
}


sub support_points_count {
    my $u = shift;

    my $dbr = LJ::get_db_reader();
    my $userid = $u->id;
    my $count;

    $count = $u->{_supportpointsum};
    return $count if defined $count;

    my $memkey = [$userid, "supportpointsum:$userid"];
    $count = LJ::MemCache::get($memkey);
    if (defined $count) {
        $u->{_supportpointsum} = $count;
        return $count;
    }

    $count = $dbr->selectrow_array("SELECT totpoints FROM supportpointsum WHERE userid=?", undef, $userid) || 0;
    $u->{_supportpointsum} = $count;
    LJ::MemCache::set($memkey, $count, 60*5);

    return $count;
}


# should show the thread expander for this user/journal
sub show_thread_expander {
    my ( $u, $remote ) = @_;

    return 1 if $remote && $remote->get_cap( 'thread_expander' )
        || $u->get_cap( 'thread_expander' );

    return 0;
}

# should allow expand-all for this user/journal
sub thread_expand_all {
    my ( $u, $remote ) = @_;

    return 1 if $remote && $remote->get_cap( 'thread_expand_all' )
        || $u->get_cap( 'thread_expand_all' );

    return 0;
}

#get/set Sticky Entry parent ID for settings menu
sub sticky_entry {
    my ( $u, $input ) = @_;

    if ( defined $input ) {
        unless ( $input ) {
            $u->set_prop( sticky_entry => '' );
            return 1;
        }
        #also takes URL
        my $ditemid;
        if ( $input =~ m!/(\d+)\.html! ) {
            $ditemid = $1;
        } elsif ( $input =~ m!(\d+)! ) {
            $ditemid = $1;
        } else {
            return 0;
        }

        # Validate the entry
        my $item = LJ::Entry->new( $u, ditemid => $ditemid );
        return 0 unless $item && $item->valid;

        $u->set_prop( sticky_entry => $ditemid );
        return 1;
    }
    return $u->prop( 'sticky_entry' );
}

sub get_sticky_entry {
    my $u = shift;

    if ( my $ditemid = $u->sticky_entry ) {
        my $item = LJ::Entry->new( $u, ditemid => $ditemid );
        return $item if $item->valid;
    }
    return undef;
}

# should times be displayed in 24-hour time format?
sub use_24hour_time { $_[0]->prop( 'timeformat_24' ) ? 1 : 0; }

sub _lazy_migrate_infoshow {
    my ($u) = @_;
    return 1 unless LJ::is_enabled('infoshow_migrate');

    # 1) column exists, but value is migrated
    # 2) column has died from 'user')
    if ($u->{allow_infoshow} eq ' ' || ! $u->{allow_infoshow}) {
        return 1; # nothing to do
    }

    my $infoval = $u->{allow_infoshow} eq 'Y' ? undef : 'N';

    # need to migrate allow_infoshow => opt_showbday
    if ($infoval) {
        foreach my $prop (qw(opt_showbday opt_showlocation)) {
            $u->set_prop($prop => $infoval);
        }
    }

    # setting allow_infoshow to ' ' means we've migrated it
    $u->update_self( { allow_infoshow => ' ' } )
        or die "unable to update user after infoshow migration";
    $u->{allow_infoshow} = ' ';

    return 1;
}


########################################################################
### 8. Formatting Content Shown to Users

=head2 Formatting Content Shown to Users
=cut

sub ajax_auth_token {
    return LJ::Auth->ajax_auth_token( @_ );
}


# gets a user bio, from DB or memcache.
# optional argument: boolean, true to skip memcache and use cluster master.
sub bio {
    my ( $u, $force ) = @_;
    return unless $u && $u->has_bio;

    my $bio;

    $bio = $u->memc_get( 'bio' ) unless $force;
    return $bio if defined $bio;

    # not in memcache, fall back to disk
    my $db = @LJ::MEMCACHE_SERVERS || $force
             ? LJ::get_cluster_def_reader( $u )
             : LJ::get_cluster_reader( $u );
    return unless $db;
    $bio = $db->selectrow_array( "SELECT bio FROM userbio WHERE userid=?",
                                 undef, $u->userid );

    # set in memcache
    LJ::MemCache::add( [$u->id, "bio:" . $u->id], $bio );

    return $bio;
}


sub check_ajax_auth_token {
    return LJ::Auth->check_ajax_auth_token( @_ );
}


sub clusterid {
    return $_[0]->{clusterid};
}


# returns username or identity display name, not escaped
*display_username = \&display_name;
sub display_name {
    my $u = shift;
    return $u->user unless $u->is_identity;

    my $id = $u->identity;
    return "[ERR:unknown_identity]" unless $id;

    my ($url, $name);
    if ($id->typeid eq 'O') {
        $url = $id->value;

        # load the module conditionally
        $LJ::OPTMOD_OPENID_VERIFIED_IDENTITY = eval "use Net::OpenID::VerifiedIdentity; 1;"
            unless defined $LJ::OPTMOD_OPENID_VERIFIED_IDENTITY;
        $name = Net::OpenID::VerifiedIdentity::DisplayOfURL($url, $LJ::IS_DEV_SERVER)
            if $LJ::OPTMOD_OPENID_VERIFIED_IDENTITY;

        $name = LJ::Hooks::run_hook("identity_display_name", $name) || $name;

        ## Unescape %xx sequences
        $name =~ s/%([\dA-Fa-f]{2})/chr(hex($1))/ge;
    }
    return $name;
}


sub equals {
    my ($u1, $u2) = @_;
    return $u1 && $u2 && $u1->userid == $u2->userid;
}


sub has_bio {
    return $_[0]->{has_bio} eq "Y" ? 1 : 0;
}


# userid
*userid = \&id;
sub id {
    return $_[0]->{userid};
}


sub ljuser_display {
    my ( $u, $opts ) = @_;

    return LJ::ljuser( $u, $opts ) unless $u->is_identity;

    my $id = $u->identity;
    return "<b>????</b>" unless $id;

    # Mark accounts as deleted that aren't visible, memorial, locked, or
    # read-only
    $opts->{del} = 1 unless $u->is_visible || $u->is_memorial ||
            $u->is_locked || $u->is_readonly;

    my $andfull = $opts->{full} ? "&amp;mode=full" : "";
    my $img = $opts->{imgroot} || $LJ::IMGPREFIX;
    my $strike = $opts->{del} ? ' text-decoration: line-through;' : '';
    my $profile_url = $opts->{profile_url} || '';
    my $journal_url = $opts->{journal_url} || '';
    my $display_class = $opts->{no_ljuser_class} ? "" : " class='ljuser'";
    my $type = $u->journaltype_readable;

    my ($url, $name);

    if ($id->typeid eq 'O') {
        $url = $journal_url ne '' ? $journal_url : $id->value;
        $name = $u->display_name;

        $url ||= "about:blank";
        $name ||= "[no_name]";

        $url = LJ::ehtml($url);
        $name = LJ::ehtml($name);

        my ($imgurl, $width, $height);
        my $head_size = $opts->{head_size};
        if ($head_size) {
            $imgurl = "$img/silk/${head_size}/openid.png";
            $width = $head_size;
            $height = $head_size;
        } else {
            $imgurl = "$img/silk/identity/openid.png";
            $width = 16;
            $height = 16;
        }

        if (my $site = LJ::ExternalSite->find_matching_site($url)) {
            $imgurl = $site->icon_url;
        }

        my $profile = $profile_url ne '' ? $profile_url :
            "$LJ::SITEROOT/profile?userid=" . $u->userid . "&amp;t=I$andfull";

        my $lj_user = $opts->{no_ljuser_class} ? "" : " lj:user='$name'";
        return "<span$lj_user style='white-space: nowrap;$strike'$display_class><a href='$profile'>" .
            "<img src='$imgurl' alt='[$type profile] ' width='$width' height='$height'" .
            " style='vertical-align: text-bottom; border: 0; padding-right: 1px;' /></a>" .
            "<a href='$url' rel='nofollow'><b>$name</b></a></span>";

    } else {
        return "<b>????</b>";
    }
}


# returns the user-specified name of a journal in valid UTF-8
# and with HTML escaped
sub name_html {
    my $u = shift;
    return LJ::ehtml($u->name_raw);
}


# returns the user-specified name of a journal exactly as entered
sub name_orig {
    my $u = shift;
    return $u->{name};
}


# returns the user-specified name of a journal in valid UTF-8
sub name_raw {
    my $u = shift;
    LJ::text_out(\$u->{name});
    return $u->{name};
}


sub new_from_row {
    my ($class, $row) = @_;
    my $u = bless $row, $class;

    # for selfassert method below:
    $u->{_orig_userid} = $u->userid;
    $u->{_orig_user}   = $u->user;

    return $u;
}


sub new_from_url {
    my ($class, $url) = @_;

    # this doesn't seem to like URLs with ?...
    $url =~ s/\?.+$//;

    # /users, /community, or /~
    if ($url =~ m!^\Q$LJ::SITEROOT\E/(?:users/|community/|~)([\w-]+)/?!) {
        return LJ::load_user($1);
    }

    # user subdomains
    if ($LJ::USER_DOMAIN && $url =~ m!^http://([\w-]+)\.\Q$LJ::USER_DOMAIN\E/?$!) {
        return LJ::load_user($1);
    }

    # subdomains that hold a bunch of users (eg, users.siteroot.com/username/)
    if ($url =~ m!^http://\w+\.\Q$LJ::USER_DOMAIN\E/([\w-]+)/?$!) {
        return LJ::load_user($1);
    }

    return undef;
}


# if bio_absent is set to "yes", bio won't be updated
sub set_bio {
    my ( $u, $text, $bio_absent ) = @_;
    $bio_absent = "" unless $bio_absent;

    my $oldbio = $u->bio;
    my $newbio = $bio_absent eq "yes" ? $oldbio : $text;
    my $has_bio = ( $newbio =~ /\S/ ) ? "Y" : "N";

    $u->update_self( { has_bio => $has_bio } );

    # update their bio text
    return if ( $oldbio eq $text ) || ( $bio_absent eq "yes" );

    if ( $has_bio eq "N" ) {
        $u->do( "DELETE FROM userbio WHERE userid=?", undef, $u->id );
        $u->dudata_set( 'B', 0, 0 );
    } else {
        $u->do( "REPLACE INTO userbio (userid, bio) VALUES (?, ?)",
                undef, $u->id, $text );
        $u->dudata_set( 'B', 0, length( $text ) );
    }
    $u->memc_set( 'bio', $text );
}


sub url {
    my $u = shift;

    my $url;

    if ( $u->is_identity && ! $u->prop( 'url' ) ) {
        my $id = $u->identity;
        if ($id && $id->typeid eq 'O') {
            $url = $id->value;
            $u->set_prop("url", $url) if $url;
        }
    }

    # not openid, what does their 'url' prop say?
    $url ||= $u->prop( 'url' );
    return undef unless $url;

    $url = "http://$url" unless $url =~ m!^https?://!;

    return $url;
}


# returns username
*username = \&user;
sub user {
    return $_[0]->{user};
}


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
    my $extra = %$info ? join('&', map { LJ::eurl($_) . '=' . LJ::eurl($info->{$_}) } keys %$info) : undef;

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
        my @data = map { ( $u->id, $_, $remote->id, $text ) } @banned;
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
### 11. Birthdays and Age-Related Functions
###   FIXME: Some of these may be outdated when we remove under-13 accounts.

=head2 Birthdays and Age-Related Functions
=cut

# Users age based off their profile birthdate
sub age {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    my $bdate = $u->{bdate};
    return unless length $bdate;

    my ($year, $mon, $day) = $bdate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $age = LJ::calc_age($year, $mon, $day);
    return $age if $age > 0;
    return;
}


# This will format the birthdate based on the user prop
sub bday_string {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    my $bdate = $u->{'bdate'};
    my ($year,$mon,$day) = split(/-/, $bdate);
    my $bday_string = '';

    if ($u->can_show_full_bday && $day > 0 && $mon > 0 && $year > 0) {
        $bday_string = $bdate;
    } elsif ($u->can_show_bday && $day > 0 && $mon > 0) {
        $bday_string = "$mon-$day";
    } elsif ($u->can_show_bday_year && $year > 0) {
        $bday_string = $year;
    }
    $bday_string =~ s/^0000-//;
    return $bday_string;
}


# Returns the best guess age of the user, which is init_age if it exists, otherwise age
sub best_guess_age {
    my $u = shift;
    return 0 unless $u->is_person || $u->is_identity;
    return $u->init_age || $u->age;
}


# returns if this user can join an adult community or not
# adultref will hold the value of the community's adult content flag
sub can_join_adult_comm {
    my ($u, %opts) = @_;

    return 1 unless LJ::is_enabled( 'adult_content' );

    my $adultref = $opts{adultref};
    my $comm = $opts{comm} or croak "No community passed";

    my $adult_content = $comm->adult_content_calculated;
    $$adultref = $adult_content;

    return 0 if $adult_content eq "explicit" && ( $u->is_minor || !$u->best_guess_age );

    return 1;
}


# Birthday logic -- should a notification be sent?
# Currently the same logic as can_show_bday with an exception for
# journals that have memorial or deleted status.
sub can_notify_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu( $u );

    return 0 if $u->is_memorial;
    return 0 if $u->is_deleted;

    return $u->can_show_bday( %opts );
}


# Birthday logic -- can any of the birthday info be shown
# This will return true if any birthday info can be shown
sub can_share_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $with_u = $opts{with} || LJ::get_remote();

    return 0 if $u->opt_sharebday eq 'N';
    return 0 if $u->opt_sharebday eq 'R' && !$with_u;
    return 0 if $u->opt_sharebday eq 'F' && !$u->trusts( $with_u );
    return 1;
}


# Birthday logic -- show appropriate string based on opt_showbday
# This will return true if the actual birthday can be shown
sub can_show_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'D' || $u->opt_showbday eq 'F';
    return 1;
}


# This will return true if the actual birth year can be shown
sub can_show_bday_year {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'Y' || $u->opt_showbday eq 'F';
    return 1;
}


# This will return true if month, day, and year can be shown
sub can_show_full_bday {
    my ( $u, %opts ) = @_;
    croak "invalid user object passed" unless LJ::isu($u);

    my $to_u = $opts{to} || LJ::get_remote();

    return 0 unless $u->can_share_bday( with => $to_u );
    return 0 unless $u->opt_showbday eq 'F';
    return 1;
}


sub include_in_age_search {
    my $u = shift;

    # if they don't display the year
    return 0 if $u->opt_showbday =~ /^[DN]$/;

    # if it's not visible to registered users
    return 0 if $u->opt_sharebday =~ /^[NF]$/;

    return 1;
}


# This returns the users age based on the init_bdate (users coppa validation birthdate)
sub init_age {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    my $init_bdate = $u->prop('init_bdate');
    return unless $init_bdate;

    my ($year, $mon, $day) = $init_bdate =~ m/^(\d\d\d\d)-(\d\d)-(\d\d)/;
    my $age = LJ::calc_age($year, $mon, $day);
    return $age if $age > 0;
    return;
}


sub next_birthday {
    my $u = shift;
    return if $u->is_expunged;

    return $u->selectrow_array("SELECT nextbirthday FROM birthdays " .
                               "WHERE userid = ?", undef, $u->id)+0;
}


# class method, loads next birthdays for a bunch of users
sub next_birthdays {
    my $class = shift;

    # load the users we need, so we can get their clusters
    my $clusters = LJ::User->split_by_cluster(@_);

    my %bdays = ();
    foreach my $cid (keys %$clusters) {
        next unless $cid;

        my @users = @{$clusters->{$cid} || []};
        my $dbcr = LJ::get_cluster_def_reader($cid)
            or die "Unable to load reader for cluster: $cid";

        my $bind = join(",", map { "?" } @users);
        my $sth = $dbcr->prepare("SELECT * FROM birthdays WHERE userid IN ($bind)");
        $sth->execute(@users);
        while (my $row = $sth->fetchrow_hashref) {
            $bdays{$row->{userid}} = $row->{nextbirthday};
        }
    }

    return \%bdays;
}


# opt_showbday options
# F - Full Display of Birthday
# D - Only Show Month/Day       DEFAULT
# Y - Only Show Year
# N - Do not display
sub opt_showbday {
    my $u = shift;
    # option not set = "yes", set to N = "no"
    $u->_lazy_migrate_infoshow;

    # migrate above did nothing
    # -- if user was already migrated in the past, we'll
    #    fall through and show their prop value
    # -- if user not migrated yet, we'll synthesize a prop
    #    value from infoshow without writing it
    unless ( LJ::is_enabled('infoshow_migrate') || $u->{allow_infoshow} eq ' ' ) {
        return $u->{allow_infoshow} eq 'Y' ? undef : 'N';
    }
    if ($u->raw_prop('opt_showbday') =~ /^(D|F|N|Y)$/) {
        return $u->raw_prop('opt_showbday');
    } else {
        return 'D';
    }
}


# opt_sharebday options
# A - All people
# R - Registered Users
# F - Trusted Only
# N - Nobody
sub opt_sharebday {
    my $u = shift;

    if ($u->raw_prop('opt_sharebday') =~ /^(A|F|N|R)$/) {
        return $u->raw_prop('opt_sharebday');
    } else {
        return 'F' if $u->is_minor;
        return 'A';
    }
}


# this sets the unix time of their next birthday for notifications
sub set_next_birthday {
    my $u = shift;
    return if $u->is_expunged;

    my ($year, $mon, $day) = split(/-/, $u->{bdate});
    unless ($mon > 0 && $day > 0) {
        $u->do("DELETE FROM birthdays WHERE userid = ?", undef, $u->id);
        return;
    }

    my $as_unix = sub {
        return LJ::mysqldate_to_time(sprintf("%04d-%02d-%02d", @_));
    };

    my $curyear = (gmtime(time))[5]+1900;

    # Calculate the time of their next birthday.

    # Assumption is that birthday-notify jobs won't be backed up.
    # therefore, if a user's birthday is 1 day from now, but
    # we process notifications for 2 days in advance, their next
    # birthday is really a year from tomorrow.

    # We need to do calculate three possible "next birthdays":
    # Current Year + 0: For the case where we it for the first
    #   time, which could happen later this year.
    # Current Year + 1: For the case where we're setting their next
    #   birthday on (approximately) their birthday. Gotta set it for
    #   next year. This works in all cases but...
    # Current Year + 2: For the case where we're processing notifs
    #   for next year already (eg, 2 days in advance, and we do
    #   1/1 birthdays on 12/30). Year + 1 gives us the date two days
    #   from now! So, add another year on top of that.

    # We take whichever one is earliest, yet still later than the
    # window of dates where we're processing notifications.

    my $bday;
    for my $inc (0..2) {
        $bday = $as_unix->($curyear + $inc, $mon, $day);
        last if $bday > time() + $LJ::BIRTHDAY_NOTIFS_ADVANCE;
    }

    # up to twelve hours drift so we don't get waves
    $bday += int(rand(12*3600));

    $u->do("REPLACE INTO birthdays VALUES (?, ?)", undef, $u->id, $bday);
    die $u->errstr if $u->err;

    return $bday;
}


sub should_fire_birthday_notif {
    my $u = shift;

    return 0 unless $u->is_person;
    return 0 unless $u->is_visible;

    # if the month/day can't be shown
    return 0 if $u->opt_showbday =~ /^[YN]$/;

    # if the birthday isn't shown to anyone
    return 0 if $u->opt_sharebday eq "N";

    # note: this isn't intended to capture all cases where birthday
    # info is restricted. we want to pare out as much as possible;
    # individual "can user X see this birthday" is handled in
    # LJ::Event::Birthday->matches_filter

    return 1;
}


# data for generating packed directory records
sub usersearch_age_with_expire {
    my $u = shift;
    croak "Invalid user object" unless LJ::isu($u);

    # don't include their age in directory searches
    # if it's not publicly visible in their profile
    my $age = $u->include_in_age_search ? $u->age : 0;
    $age += 0;

    # no need to expire due to age if we don't have a birthday
    my $expire = $u->next_birthday || undef;

    return ($age, $expire);
}


########################################################################
### 12. Comment-Related Functions

=head2 Comment-Related Functions
=cut

# true if u1 restricts commenting to trusted and u2 is not trusted
sub does_not_allow_comments_from {
    my ( $u1, $u2 ) = @_;
    return unless LJ::isu( $u1 ) && LJ::isu( $u2 );
    return $u1->prop('opt_whocanreply') eq 'friends'
        && ! $u1->trusts_or_has_member( $u2 );
}


# get recent talkitems posted to this user
# args: maximum number of comments to retrieve
# returns: array of hashrefs with jtalkid, nodetype, nodeid, parenttalkid, posterid, state
sub get_recent_talkitems {
    my ($u, $maxshow, %opts) = @_;

    $maxshow ||= 15;
    my $max_fetch = int($LJ::TOOLS_RECENT_COMMENTS_MAX*1.5) || 150;
    # We fetch more items because some may be screened
    # or from suspended users, and we weed those out later

    my $remote   = $opts{remote} || LJ::get_remote();
    return undef unless LJ::isu($u);

    ## $raw_talkitems - contains DB rows that are not filtered
    ## to match remote user's permissions to see
    my $raw_talkitems;
    my $memkey = [$u->userid, 'rcntalk:' . $u->userid ];
    $raw_talkitems = LJ::MemCache::get($memkey);
    if (!$raw_talkitems) {
        my $sth = $u->prepare(
            "SELECT jtalkid, nodetype, nodeid, parenttalkid, ".
            "       posterid, UNIX_TIMESTAMP(datepost) as 'datepostunix', state ".
            "FROM talk2 ".
            "WHERE journalid=? AND state <> 'D' " .
            "ORDER BY jtalkid DESC ".
            "LIMIT $max_fetch"
        );
        $sth->execute( $u->userid );
        $raw_talkitems = $sth->fetchall_arrayref({});
        LJ::MemCache::set($memkey, $raw_talkitems, 60*5);
    }

    ## Check remote's permission to see the comment, and create singletons
    my @recv;
    foreach my $r (@$raw_talkitems) {
        last if @recv >= $maxshow;

        # construct an LJ::Comment singleton
        my $comment = LJ::Comment->new($u, jtalkid => $r->{jtalkid});
        $comment->absorb_row(%$r);
        next unless $comment->visible_to($remote);
        push @recv, $r;
    }

    # need to put the comments in order, with "oldest first"
    # they are fetched from DB in "recent first" order
    return reverse @recv;
}


# return the number of comments a user has posted
sub num_comments_posted {
    my $u = shift;
    my %opts = @_;

    my $dbcr = $opts{dbh} || LJ::get_cluster_reader($u);
    my $userid = $u->id;

    my $memkey = [$userid, "talkleftct:$userid"];
    my $count = LJ::MemCache::get($memkey);
    unless ($count) {
        my $expire = time() + 3600*24*2; # 2 days;
        $count = $dbcr->selectrow_array("SELECT COUNT(*) FROM talkleft " .
                                        "WHERE userid=?", undef, $userid);
        LJ::MemCache::set($memkey, $count, $expire) if defined $count;
    }

    return $count;
}


# return the number of comments a user has received
sub num_comments_received {
    my $u = shift;
    my %opts = @_;

    my $dbcr = $opts{dbh} || LJ::get_cluster_reader($u);
    my $userid = $u->id;

    my $memkey = [$userid, "talk2ct:$userid"];
    my $count = LJ::MemCache::get($memkey);
    unless ($count) {
        my $expire = time() + 3600*24*2; # 2 days;
        $count = $dbcr->selectrow_array("SELECT COUNT(*) FROM talk2 ".
                                        "WHERE journalid=?", undef, $userid);
        LJ::MemCache::set($memkey, $count, $expire) if defined $count;
    }

    return $count;
}


########################################################################
### 13. Community-Related Functions and Authas

=head2 Community-Related Functions and Authas
=cut

sub can_manage {
    # true if the first user is an admin for the target user.
    my ( $u, $target ) = @_;
    # backward compatibility: allow $target to be a userid
    $target = LJ::want_user( $target ) or return undef;

    # is same user?
    return 1 if $u->equals( $target );

    # people/syn/rename accounts can only be managed by the one account
    return 0 if $target->journaltype =~ /^[PYR]$/;

    # check for admin access
    return 1 if LJ::check_rel( $target, $u, 'A' );

    # failed checks, return false
    return 0;
}


sub can_manage_other {
    # true if the first user is an admin for the target user,
    # UNLESS the two users are the same.
    my ( $u, $target ) = @_;
    # backward compatibility: allow $target to be a userid
    $target = LJ::want_user( $target ) or return undef;

    return 0 if $u->equals( $target );
    return $u->can_manage( $target );
}


sub can_moderate {
    # true if the first user can moderate the target user.
    my ( $u, $target ) = @_;
    # backward compatibility: allow $target to be a userid
    $target = LJ::want_user( $target ) or return undef;

    return 1 if $u->can_manage_other( $target );
    return LJ::check_rel( $target, $u, 'M' );
}


# can $u post to $targetu?
sub can_post_to {
    my ( $u, $targetu ) = @_;
    croak "Invalid users passed to LJ::User->can_post_to."
        unless LJ::isu( $u ) && LJ::isu( $targetu );

    # if it's you, and you're a person, you can post to it
    return 1 if $u->is_person && $u->equals( $targetu );

    # else, you have to be an individual and the target has to be a comm
    return 0 unless $u->is_individual && $targetu->is_community;

    # check if user has access explicit posting access
    return 1 if LJ::check_rel( $targetu, $u, 'P' );

    # let's check if this community is allowing post access to non-members
    if ( $targetu->has_open_posting ) {
        my ( $ml, $pl ) = $targetu->get_comm_settings;
        return 1 if $pl eq 'members';
    }

    # is the poster an admin for this community?  admins can always post
    return 1 if $u->can_manage( $targetu );

    return 0;
}


# Get an array of usernames a given user can authenticate as.
# Valid keys for opts hashref:
#     - type: filter by given journaltype (P or C)
#     - cap:  filter by users who have given cap
#     - showall: override hiding of non-visible/non-read-only journals
sub get_authas_list {
    my ( $u, $opts ) = @_;

    # Two valid types, Personal or Community
    $opts->{type} = undef unless $opts->{type} =~ m/^[PC]$/;

    my $ids = LJ::load_rel_target( $u, 'A' );
    return undef unless $ids;
    my %users = %{ LJ::load_userids( @$ids ) };

    return map { $_->user }
           grep { ! $opts->{cap}  || $_->get_cap( $opts->{cap} ) }
           grep { ! $opts->{type} || $opts->{type} eq $_->journaltype }

           # unless overridden, hide non-visible/non-read-only journals.
           # always display the user's acct
           grep { $opts->{showall} || $_->is_visible || $_->is_readonly || $_->equals( $u ) }

           # can't work as an expunged account
           grep { ! $_->is_expunged && $_->clusterid > 0 }

           # put $u at the top of the list, then sort the rest
           ( $u,  sort { $a->user cmp $b->user } values %users );
}


# What journals can this user post to?
sub posting_access_list {
    my $u = shift;

    my @res;

    my $ids = LJ::load_rel_target($u, 'P');
    my $us = LJ::load_userids(@$ids);
    foreach (values %$us) {
        next unless $_->is_visible;
        push @res, $_;
    }

    return sort { $a->{user} cmp $b->{user} } @res;
}

# gets the relevant communities that the user is a member of
# used to suggest communities to a person who know the user
sub relevant_communities {
    my $u = shift;

    my %comms;
    my @ids = $u->member_of_userids;
    my $memberships = LJ::load_userids( @ids );

    # get all communities that $u is a member of that aren't closed membership
    # and that wish to be included in the community promo
    foreach my $membershipid ( keys %$memberships ) {
        my $membershipu = $memberships->{$membershipid};

        next unless $membershipu->is_community;
        next if $membershipu->optout_community_promo;
        next unless $membershipu->is_visible;
        next if $membershipu->is_closed_membership;

        $comms{$membershipid}->{u} = $membershipu;
        $comms{$membershipid}->{istatus} = 'normal';
    }

    # get usage information about comms
    if ( scalar keys %comms ) {
        my $comms_times = LJ::get_times_multi( keys %comms );
        foreach my $commid ( keys %comms ) {
            if ( $comms_times->{created} && defined $comms_times->{created}->{$commid} ) {
                $comms{$commid}->{created} = $comms_times->{created}->{$commid};
            }
            if ( $comms_times->{updated} && defined $comms_times->{updated}->{$commid} ) {
                $comms{$commid}->{updated} = $comms_times->{updated}->{$commid};
            }
        }
    }

    # prune the list of communities
    #
    # keep a community in the list if:
    # * it was created in the past 10 days OR
    # * $u is a maint or mod of it OR
    # * it was updated in the past 30 days
    my $over30 = 0;
    my $now = time();

    COMMUNITY:
        foreach my $commid ( sort { $comms{$b}->{updated} <=> $comms{$a}->{updated} } keys %comms ) {
            my $commu = $comms{$commid}->{u};

            if ( $now - $comms{$commid}->{created} <= 60*60*24*10 ) { # 10 days
                $comms{$commid}->{istatus} = 'new';
                next COMMUNITY;
            }

            my @maintainers = $commu->maintainer_userids;
            my @moderators  = $commu->moderator_userids;
            foreach my $mid ( @maintainers, @moderators ) {
                if ( $mid == $u->id ) {
                    $comms{$commid}->{istatus} = 'mm';
                    next COMMUNITY;
                }
            }

            if ( $over30 ) {
                delete $comms{$commid};
                next COMMUNITY;
            } else {
                if ( $now - $comms{$commid}->{updated} > 60*60*24*30 ) { # 30 days
                    delete $comms{$commid};

                    # since we're going through the communities in timeupdate order,
                    # we know every community in %comms after this one was updated
                    # more than 30 days ago
                    $over30 = 1;
                }
            }
        }

    # if we still have more than 20 comms, delete any with fewer than five members
    # as long as it's not new and $u isn't a maint/mod
    if ( scalar keys %comms > 20 ) {
        foreach my $commid ( keys %comms ) {
            my $commu = $comms{$commid}->{u};

            next unless $comms{$commid}->{istatus} eq 'normal';

            my @ids = $commu->member_userids;
            if ( scalar @ids < 5 ) {
                delete $comms{$commid};
            }
        }
    }

    return %comms;
}


sub trusts_or_has_member {
    my ( $u, $target_u ) = @_;
    $target_u = LJ::want_user( $target_u ) or return 0;

    return $target_u->member_of( $u ) ? 1 : 0
        if $u->is_community;

    return $u->trusts( $target_u ) ? 1 : 0;
}

########################################################################
### 14. Adult Content Functions

=head2 Adult Content Functions
=cut

# defined by the user
# returns 'none', 'concepts' or 'explicit'
sub adult_content {
    my $u = shift;

    my $prop_value = $u->prop('adult_content');

    return $prop_value ? $prop_value : "none";
}


# uses user-defined prop to figure out the adult content level
sub adult_content_calculated {
    my $u = shift;

    return $u->adult_content;
}


# returns who marked the entry as the 'adult_content_calculated' adult content level
sub adult_content_marker {
    my $u = shift;

    return "journal";
}


# defuned by the user
sub adult_content_reason {
    my $u = shift;

    return $u->prop('adult_content_reason');
}


sub hide_adult_content {
    my $u = shift;

    my $prop_value = $u->prop('hide_adult_content');

    if (!$u->best_guess_age) {
        return "concepts";
    }

    if ($u->is_minor && $prop_value ne "concepts") {
        return "explicit";
    }

    return $prop_value ? $prop_value : "none";
}


# returns a number that represents the user's chosen search filtering level
# 0 = no filtering
# 1-10 = moderate filtering
# >10 = strict filtering
sub safe_search {
    my $u = shift;

    my $prop_value = $u->prop('safe_search');

    # current user 18+ default is 0
    # current user <18 default is 10
    # new user default (prop value is "nu_default") is 10
    return 0 if $prop_value eq "none";
    return $prop_value if $prop_value && $prop_value =~ /^\d+$/;
    return 0 if $prop_value ne "nu_default" && $u->best_guess_age && !$u->is_minor;
    return 10;
}


# determine if the user in "for_u" should see $u in a search result
sub should_show_in_search_results {
    my ( $u, %opts ) = @_;

    # check basic user attributes first
    return 0 unless $u->is_visible;
    return 0 if $u->is_person && $u->age && $u->age < 14;

    # now check adult content / safe search
    return 1 unless LJ::is_enabled( 'adult_content' ) && LJ::is_enabled( 'safe_search' );

    my $adult_content = $u->adult_content_calculated;
    my $for_u = $opts{for};

    # only show accounts with no adult content to logged out users
    return $adult_content eq "none" ? 1 : 0
        unless LJ::isu( $for_u );

    my $safe_search = $for_u->safe_search;
    return 1 if $safe_search == 0;  # user wants to see everyone

    # calculate the safe_search level for this account
    my $adult_content_flag = $LJ::CONTENT_FLAGS{$adult_content};
    my $adult_content_flag_level = $adult_content_flag
                                 ? $adult_content_flag->{safe_search_level}
                                 : 0;

    # if the level is set, see if it exceeds the desired safe_search level
    return 1 unless $adult_content_flag_level;
    return ( $safe_search < $adult_content_flag_level ) ? 1 : 0;
}


########################################################################
###  15. Email-Related Functions

=head2 Email-Related Functions
=cut

sub accounts_by_email {
    my ( $u, $email ) = @_;
    $email ||= $u->email_raw if LJ::isu( $u );
    return undef unless $email;

    my $dbr = LJ::get_db_reader() or die "Couldn't get db reader";
    my $userids = $dbr->selectcol_arrayref(
                        "SELECT userid FROM email WHERE email=?",
                        undef, $email );
    die $dbr->errstr if $dbr->err;
    return $userids ? @$userids : ();
}


sub delete_email_alias {
    my $u = $_[0];

    my $dbh = LJ::get_db_writer();
    $dbh->do( "DELETE FROM email_aliases WHERE alias=?",
              undef, $u->site_email_alias );

    return 0 if $dbh->err;
    return 1;
}


sub email_for_feeds {
    my $u = shift;

    # don't display if it's mangled
    return if $u->prop("opt_mangleemail") eq "Y";

    my $remote = LJ::get_remote();
    return $u->email_visible($remote);
}


sub email_raw {
    my $u = shift;
    my $userid = $u->userid;
    $u->{_email} ||= LJ::MemCache::get_or_set( [$userid, "email:$userid"], sub {
        my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
        return $dbh->selectrow_array( "SELECT email FROM email WHERE userid=?",
                                      undef, $userid );
    } );
    return $u->{_email};
}


sub email_status {
    my $u = shift;
    return $u->{status};
}


# in scalar context, returns user's email address.  given a remote user,
# bases decision based on whether $remote user can see it.  in list context,
# returns all emails that can be shown
sub email_visible {
    my ($u, $remote) = @_;

    return scalar $u->emails_visible($remote);
}

# returns an array of emails based on the user's display prefs
# A: actual email address
# D: display email address
# L: local email address
# B: both actual + local email address
# V: both display + local email address

sub emails_visible {
    my ($u, $remote) = @_;

    return () if $u->is_identity || $u->is_syndicated;

    # security controls
    return () unless $u->share_contactinfo($remote);

    my $whatemail = $u->opt_whatemailshow;

    # some classes of users we want to have their contact info hidden
    # after so much time of activity, to prevent people from bugging
    # them for their account or trying to brute force it.
    my $hide_contactinfo = sub {
        return 0 if $LJ::IS_DEV_SERVER;
        my $hide_after = $u->get_cap( "hide_email_after" );
        return 0 unless $hide_after;
        my $active = $u->get_timeactive;
        return $active && (time() - $active) > $hide_after * 86400;
    };

    return () if $whatemail eq "N" || $hide_contactinfo->();

    my @emails = ();

    if ( $whatemail eq "A" || $whatemail eq "B" ) {
        push @emails, $u->email_raw if $u->email_raw;
    } elsif ( $whatemail eq "D" || $whatemail eq "V" ) {
        my $profile_email = $u->prop( 'opt_profileemail' );
        push @emails, $profile_email if $profile_email;
    }

    if ( $whatemail eq "B" || $whatemail eq "V" || $whatemail eq "L" ) {
        push @emails, $u->site_email_alias
            unless $u->prop( 'no_mail_alias' );
    }
    return wantarray ? @emails : $emails[0];
}


sub is_validated {
    my $u = shift;
    return $u->email_status eq "A";
}


# return user selected mail encoding or undef
sub mailencoding {
    my $u = shift;
    my $enc = $u->prop('mailencoding');

    return undef unless $enc;

    LJ::load_codes({ "encoding" => \%LJ::CACHE_ENCODINGS } )
        unless %LJ::CACHE_ENCODINGS;
    return $LJ::CACHE_ENCODINGS{$enc}
}


# return the setting indicating how a user can be found by their email address
# Y - Findable, N - Not findable, H - Findable but identity hidden
sub opt_findbyemail {
    my $u = shift;

    if ($u->raw_prop('opt_findbyemail') =~ /^(N|Y|H)$/) {
        return $u->raw_prop('opt_findbyemail');
    } else {
        return undef;
    }
}


# initiate reset of user's email
# newemail: the new address provided (not validated?)
# err: reference for error messages
# emailsucc: send email if defined, report success if reference
# update_opts: additional options for the update_user call
sub reset_email {
    my ( $u, $newemail, $err, $emailsucc, $update_opts ) = @_;
    my $errsub = sub { $$err = $_[0] if ref $err; return undef };

    my $dbh = LJ::get_db_writer();
    $dbh->do( "UPDATE infohistory SET what='emailreset'" .
              " WHERE userid=? AND what='email'", undef, $u->id ) or
        return $errsub->( LJ::Lang::ml( "error.dberror" ) . $dbh->errstr );

    $u->infohistory_add( 'emailreset', $u->email_raw, $u->email_status )
        if $u->email_raw ne $newemail; # record only if it changed

    $update_opts ||= { status => 'T' };
    $update_opts->{email} = $newemail;
    $u->update_self( $update_opts ) or
        return $errsub->( LJ::Lang::ml( "email.emailreset.error",
                                        { user => $u->user } ) );

    if ( $LJ::T_SUPPRESS_EMAIL ) {
        $$emailsucc = 1 if ref $emailsucc;  # pretend we sent it
    } elsif ( defined $emailsucc ) {
        my $aa = LJ::register_authaction( $u->id, "validateemail", $newemail );
        my $auth = "$aa->{aaid}.$aa->{authcode}";
        my $sent = LJ::send_mail( {
            to => $newemail,
            from => $LJ::ADMIN_EMAIL,
            subject => LJ::Lang::ml( "email.emailreset.subject" ),
            body => LJ::Lang::ml( "email.emailreset.body",
                                  { user => $u->user,
                                    sitename => $LJ::SITENAME,
                                    siteroot => "$LJ::SITEROOT/",
                                    auth => $auth } ),
        } );
        $$emailsucc = $sent if ref $emailsucc;
    }
}


sub set_email {
    my ($u, $email) = @_;
    return LJ::set_email($u->id, $email);
}


sub site_email_alias {
    my $u = $_[0];
    my $alias = $u->user . "\@$LJ::USER_DOMAIN";
    return $alias;
}


sub update_email_alias {
    my $u = $_[0];

    return unless $u && $u->can_have_email_alias;
    return if $u->prop("no_mail_alias");
    return unless $u->is_validated;

    my $dbh = LJ::get_db_writer();
    $dbh->do( "REPLACE INTO email_aliases (alias, rcpt) VALUES (?,?)",
              undef, $u->site_email_alias, $u->email_raw );

    return 0 if $dbh->err;
    return 1;
}


sub validated_mbox_sha1sum {
    my $u = shift;

    # must be validated
    return undef unless $u->is_validated;

    # must have one on file
    my $email = $u->email_raw;
    return undef unless $email;

    # return SHA1, which does not disclose the actual value
    return Digest::SHA1::sha1_hex('mailto:' . $email);
}


########################################################################
###  16. Entry-Related Functions

=head2 Entry-Related Functions
=cut

# front-end to recent_entries, which forces the remote user to be
# the owner, so we get everything.
sub all_recent_entries {
    my ( $u, %opts ) = @_;
    $opts{filtered_for} = $u;
    return $u->recent_entries(%opts);
}


sub draft_text {
    my ($u) = @_;
    return $u->prop('entry_draft');
}

sub entryform_width {
    my ( $u ) = @_;

    if ( $u->raw_prop( 'entryform_width' ) =~ /^(F|P)$/ ) {
        return $u->raw_prop( 'entryform_width' )
    } else {
        return 'F';
    }
}

# getter/setter
sub entryform_panels {
    my ( $u, $val ) = @_;

    if ( defined $val ) {
        $u->set_prop( entryform_panels => Storable::nfreeze( $val ) );
        return $val;
    }

    my $prop = $u->prop( "entryform_panels" );
    my $default = {
        order => [ [ "tags", "displaydate" ],

                   # FIXME: should be [ "status"  "journal" "comments" "age_restriction" ] %]
                   [ "access", "journal", "currents", "comments", "age_restriction" ],

                   # FIXME: should be [ "icons" "crosspost" "scheduled" ]
                   [ "icons", "crosspost" ],
                ],
        show => {
            "tags"          => 1,
            "currents"      => 1,
            "displaydate"   => 0,
            "access"        => 1,
            "journal"       => 1,
            "comments"      => 0,
            "age_restriction" => 0,
            "icons"         => 1,
            "crosspost"     => 0,

            #"scheduled"     => 0,
            #"status"        => 1,
        },
        collapsed => {
        }
    };

    my %need_panels = map { $_ => 1 } keys %{$default->{show}};

    my $ret;
    $ret = Storable::thaw( $prop ) if $prop;

    if ( $ret ) {
        # fill in any modules that somehow are not in this list
        foreach my $column ( @{$ret->{order}} ) {
            foreach my $panel ( @{$column} ) {
                delete $need_panels{$panel};
            }
        }

        my @col = @{$ret->{order}->[2]};
        foreach ( keys %need_panels ) {
            # add back into last column, but respect user's option to show/not-show
            push @col, $_;
            $ret->{show}->{$_} = 0 unless defined $ret->{show}->{$_};
        }
        $ret->{order}->[2] = \@col;
    } else {
        $ret = $default;
    }

    return $ret;
}

sub entryform_panels_order {
    my ( $u, $val ) = @_;

    my $panels = $u->entryform_panels;

    if ( defined $val ) {
        $panels->{order} = $val;
        $panels = $u->entryform_panels( $panels );
    }

    return $panels->{order};
}

sub entryform_panels_visibility {
    my ( $u, $val ) = @_;

    my $panels = $u->entryform_panels;
    if ( defined $val ) {
        $panels->{show} = $val;
        $panels = $u->entryform_panels( $panels );
    }

    return $panels->{show};
}

sub entryform_panels_collapsed {
    my ( $u, $val ) = @_;

    my $panels = $u->entryform_panels;
    if ( defined $val ) {
        $panels->{collapsed} = $val;
        $panels = $u->entryform_panels( $panels );
    }

    return $panels->{collapsed};
}



# <LJFUNC>
# name: LJ::get_post_ids
# des: Given a user object and some options, return the number of posts or the
#      posts'' IDs (jitemids) that match.
# returns: number of matching posts, <strong>or</strong> IDs of
#          matching posts (default).
# args: u, opts
# des-opts: 'security' - [public|private|usemask]
#           'allowmask' - integer for friends-only or custom groups
#           'start_date' - UTC date after which to look for match
#           'end_date' - UTC date before which to look for match
#           'return' - if 'count' just return the count
#           FIXME: Add caching?
# </LJFUNC>
sub get_post_ids {
    my ($u, %opts) = @_;

    my $query = 'SELECT';
    my @vals; # parameters to query

    if ($opts{'start_date'} || $opts{'end_date'}) {
        croak "start or end date not defined"
            if (!$opts{'start_date'} || !$opts{'end_date'});

        if (!($opts{'start_date'} >= 0) || !($opts{'end_date'} >= 0) ||
            !($opts{'start_date'} <= $LJ::EndOfTime) ||
            !($opts{'end_date'} <= $LJ::EndOfTime) ) {
            return undef;
        }
    }

    # return count or jitemids
    if ($opts{'return'} eq 'count') {
        $query .= " COUNT(*)";
    } else {
        $query .= " jitemid";
    }

    # from the journal entries table for this user
    $query .= " FROM log2 WHERE journalid=?";
    push( @vals, $u->userid );

    # filter by security
    if ($opts{'security'}) {
        $query .= " AND security=?";
        push(@vals, $opts{'security'});
        # If friends-only or custom
        if ($opts{'security'} eq 'usemask' && $opts{'allowmask'}) {
            $query .= " AND allowmask=?";
            push(@vals, $opts{'allowmask'});
        }
    }

    # filter by date, use revttime as it is indexed
    if ($opts{'start_date'} && $opts{'end_date'}) {
        # revttime is reverse event time
        my $s_date = $LJ::EndOfTime - $opts{'start_date'};
        my $e_date = $LJ::EndOfTime - $opts{'end_date'};
        $query .= " AND revttime<?";
        push(@vals, $s_date);
        $query .= " AND revttime>?";
        push(@vals, $e_date);
    }

    # return count or jitemids
    if ($opts{'return'} eq 'count') {
        return $u->selectrow_array($query, undef, @vals);
    } else {
        my $jitemids = $u->selectcol_arrayref($query, undef, @vals) || [];
        die $u->errstr if $u->err;
        return @$jitemids;
    }
}


# Returns 'rich' or 'plain' depending on user's
# setting of which editor they would like to use
# and what they last used
sub new_entry_editor {
    my $u = shift;

    my $editor = $u->prop('entry_editor');
    return 'plain' if $editor eq 'always_plain'; # They said they always want plain
    return 'rich' if $editor eq 'always_rich'; # They said they always want rich
    return $editor if $editor =~ /(rich|plain)/; # What did they last use?
    return $LJ::DEFAULT_EDITOR; # Use config default
}

# What security level to use for new posts. This magic flag is used to give
# user's the ability to specify that "if I try to post public, don't let me".
# To override this, you have to go back and edit your post.
sub newpost_minsecurity {
    return $_[0]->prop( 'newpost_minsecurity' ) || 'public';
}

# This loads the user's specified post-by-email security. If they haven't
# set that up, then we fall back to the standard new post minimum security.
sub emailpost_security {
    return $_[0]->prop( 'emailpost_security' ) ||
        $_[0]->newpost_minsecurity;
}


*get_post_count = \&number_of_posts;
sub number_of_posts {
    my ($u, %opts) = @_;

    # to count only a subset of all posts
    if (%opts) {
        $opts{return} = 'count';
        return $u->get_post_ids(%opts);
    }

    my $userid = $u->userid;
    my $memkey = [$userid, "log2ct:$userid"];
    my $expire = time() + 3600*24*2; # 2 days
    return LJ::MemCache::get_or_set($memkey, sub {
        return $u->selectrow_array( "SELECT COUNT(*) FROM log2 WHERE journalid=?",
                                    undef, $userid );
    }, $expire);
}


# returns array of LJ::Entry objects, ignoring security
sub recent_entries {
    my ($u, %opts) = @_;
    my $remote = delete $opts{'filtered_for'} || LJ::get_remote();
    my $count  = delete $opts{'count'}        || 50;
    my $order  = delete $opts{'order'}        || "";
    die "unknown options" if %opts;

    my $err;
    my @recent = $u->recent_items(
        itemshow  => $count,
        err       => \$err,
        clusterid => $u->clusterid,
        remote    => $remote,
        order     => $order,
    );
    die "Error loading recent items: $err" if $err;

    my @objs;
    foreach my $ri (@recent) {
        my $entry = LJ::Entry->new($u, jitemid => $ri->{itemid});
        push @objs, $entry;
        # FIXME: populate the $entry with security/posterid/alldatepart/ownerid/rlogtime
    }
    return @objs;
}


sub security_group_display {
    my ( $u, $allowmask ) = @_;
    return '' unless LJ::isu( $u );
    return '' unless defined $allowmask;

    my $remote = LJ::get_remote() or return '';
    my $use_urls = $remote->get_cap( "security_filter" ) || $u->get_cap( "security_filter" );

    # see which group ids are in the security mask
    my %group_ids = ( map { $_ => 1 } grep { $allowmask & ( 1 << $_ ) } 1..60 );
    return '' unless scalar( keys %group_ids ) > 0;

    my @ret;

    my @groups = $u->trust_groups;
    foreach my $group ( @groups ) {
        next unless $group_ids{$group->{groupnum}};  # not in mask

        my $name = LJ::ehtml( $group->{groupname} );
        if ( $use_urls ) {
            my $url = LJ::eurl( $u->journal_base . "/security/group:$name" );
            push @ret, "<a href='$url'>$name</a>";
        } else {
            push @ret, $name;
        }
    }

    return join( ', ', @ret );
}



sub set_draft_text {
    my ($u, $draft) = @_;
    my $old = $u->draft_text;

    $LJ::_T_DRAFT_RACE->() if $LJ::_T_DRAFT_RACE;

    # try to find a shortcut that makes the SQL shorter
    my @methods;  # list of [ $subref, $cost ]

    # one method is just setting it all at once.  which incurs about
    # 75 bytes of SQL overhead on top of the length of the draft,
    # not counting the escaping
    push @methods, [ "set", sub { $u->set_prop('entry_draft', $draft); 1 },
                     75 + length $draft ];

    # stupid case, setting the same thing:
    push @methods, [ "noop", sub { 1 }, 0 ] if $draft eq $old;

    # simple case: appending
    if (length $old && $draft =~ /^\Q$old\E(.+)/s) {
        my $new = $1;
        my $appending = sub {
            my $prop = LJ::get_prop("user", "entry_draft") or die; # FIXME: use exceptions
            my $rv = $u->do("UPDATE userpropblob SET value = CONCAT(value, ?) WHERE userid=? AND upropid=? AND LENGTH(value)=?",
                            undef, $new, $u->userid, $prop->{id}, length $old);
            return 0 unless $rv > 0;
            $u->uncache_prop("entry_draft");
            return 1;
        };
        push @methods, [ "append", $appending, 40 + length $new ];
    }

    # FIXME: prepending/middle insertion (the former being just the latter), as
    # well as appending, wihch we could then get rid of

    # try the methods in increasing order
    foreach my $m (sort { $a->[2] <=> $b->[2] } @methods) {
        my $func = $m->[1];
        if ($func->()) {
            $LJ::_T_METHOD_USED->($m->[0]) if $LJ::_T_METHOD_USED; # for testing
            return 1;
        }
    }
    return 0;
}

sub third_party_notify_list {
    my $u = shift;

    my $val = $u->prop('third_party_notify_list');
    my @services = split(',', $val);

    return @services;
}


# Add a service to a user's notify list
sub third_party_notify_list_add {
    my ( $u, $svc ) = @_;
    return 0 unless $svc;

    # Is it already there?
    return 1 if $u->third_party_notify_list_contains($svc);

    # Create the new list of services
    my @cur_services = $u->third_party_notify_list;
    push @cur_services, $svc;
    my $svc_list = join(',', @cur_services);

    # Trim a service from the list if it is too long
    if (length $svc_list > 255) {
        shift @cur_services;
        $svc_list = join(',', @cur_services)
    }

    # Set it
    $u->set_prop('third_party_notify_list', $svc_list);
    return 1;
}


# Check if the user's notify list contains a particular service
sub third_party_notify_list_contains {
    my ( $u, $val ) = @_;

    return 1 if grep { $_ eq $val } $u->third_party_notify_list;

    return 0;
}


# Remove a service to a user's notify list
sub third_party_notify_list_remove {
    my ( $u, $svc ) = @_;
    return 0 unless $svc;

    # Is it even there?
    return 1 unless $u->third_party_notify_list_contains($svc);

    # Remove it!
    $u->set_prop('third_party_notify_list',
                 join(',',
                      grep { $_ ne $svc } $u->third_party_notify_list
                      )
                 );
    return 1;
}


########################################################################
###  18. Jabber-Related Functions

=head2 Jabber-Related Functions
=cut

# Hide the LJ Talk field on profile?  opt_showljtalk needs a value of 'N'.
sub hide_ljtalk {
    my $u = shift;
    croak "Invalid user object passed" unless LJ::isu($u);

    # ... The opposite of showing the field. :)
    return $u->show_ljtalk ? 0 : 1;
}


# returns whether or not the user is online on jabber
sub jabber_is_online {
    # FIXME: this function is unused as of Aug 2009 - kareila
    my $u = shift;

    return keys %{LJ::Jabber::Presence->get_resources($u)} ? 1 : 0;
}


sub ljtalk_id {
    my $u = shift;
    croak "Invalid user object passed" unless LJ::isu($u);

    return $u->site_email_alias;
}


# opt_showljtalk options based on user setting
# Y = Show the LJ Talk field on profile (default)
# N = Don't show the LJ Talk field on profile
sub opt_showljtalk {
    my $u = shift;

    # Check for valid value, or just return default of 'Y'.
    if ($u->raw_prop('opt_showljtalk') =~ /^(Y|N)$/) {
        return $u->raw_prop('opt_showljtalk');
    } else {
        return 'Y';
    }
}


# find what servers a user is logged in to, and send them an IM
# returns true if sent, false if failure or user not logged on
# Please do not call from web context
sub send_im {
    my ($self, %opts) = @_;

    croak "Can't call in web context" if LJ::is_web_context();

    my $from = delete $opts{from};
    my $msg  = delete $opts{message} or croak "No message specified";

    croak "No from or bot jid defined" unless $from || $LJ::JABBER_BOT_JID;

    my @resources = keys %{LJ::Jabber::Presence->get_resources($self)} or return 0;

    my $res = $resources[0] or return 0; # FIXME: pick correct server based on priority?
    my $pres = LJ::Jabber::Presence->new($self, $res) or return 0;
    my $ip = $LJ::JABBER_SERVER_IP || '127.0.0.1';

    my $sock = IO::Socket::INET->new(PeerAddr => "${ip}:5200")
        or return 0;

    my $vhost = $LJ::DOMAIN;

    my $to_jid   = $self->user   . '@' . $LJ::DOMAIN;
    my $from_jid = $from ? $from->user . '@' . $LJ::DOMAIN : $LJ::JABBER_BOT_JID;

    my $emsg = LJ::exml($msg);
    my $stanza = LJ::eurl(qq{<message to="$to_jid" from="$from_jid"><body>$emsg</body></message>});

    print $sock "send_stanza $vhost $to_jid $stanza\n";

    my $start_time = time();

    while (1) {
        my $rin = '';
        vec($rin, fileno($sock), 1) = 1;
        select(my $rout=$rin, undef, undef, 1);
        if (vec($rout, fileno($sock), 1)) {
            my $ln = <$sock>;
            return 1 if $ln =~ /^OK/;
        }

        last if time() > $start_time + 5;
    }

    return 0;
}


# Show LJ Talk field on profile?  opt_showljtalk needs a value of 'Y'.
sub show_ljtalk {
    my $u = shift;
    croak "Invalid user object passed" unless LJ::isu($u);

    # Fail if the user wants to hide the LJ Talk field on their profile,
    # or doesn't even have the ability to show it.
    return 0 unless $u->opt_showljtalk eq 'Y' && LJ::is_enabled('ljtalk') && $u->is_person;

    # User either decided to show LJ Talk field or has left it at the default.
    return 1 if $u->opt_showljtalk eq 'Y';
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
    my $uid = $dbh->selectrow_array("SELECT userid FROM identitymap WHERE idtype=? AND identity=?",
                                    undef, $type, $ident);
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
###  20. Page Notices Functions

=head2 Page Notices Functions
=cut

sub dismissed_page_notices {
    my $u = shift;

    my $val = $u->prop("dismissed_page_notices");
    my @notices = split(",", $val);

    return @notices;
}


# add a page notice to a user's dismissed page notices list
sub dismissed_page_notices_add {
    my ( $u, $notice_string ) = @_;

    return 0 unless $notice_string && $LJ::VALID_PAGE_NOTICES{$notice_string};

    # is it already there?
    return 1 if $u->has_dismissed_page_notice($notice_string);

    # create the new list of dismissed page notices
    my @cur_notices = $u->dismissed_page_notices;
    push @cur_notices, $notice_string;
    my $cur_notices_string = join(",", @cur_notices);

    # remove the oldest notice if the list is too long
    if (length $cur_notices_string > 255) {
        shift @cur_notices;
        $cur_notices_string = join(",", @cur_notices);
    }

    # set it
    $u->set_prop("dismissed_page_notices", $cur_notices_string);

    return 1;
}


# remove a page notice from a user's dismissed page notices list
sub dismissed_page_notices_remove {
    my ( $u, $notice_string ) = @_;

    return 0 unless $notice_string && $LJ::VALID_PAGE_NOTICES{$notice_string};

    # is it even there?
    return 0 unless $u->has_dismissed_page_notice($notice_string);

    # remove it
    $u->set_prop("dismissed_page_notices", join(",", grep { $_ ne $notice_string } $u->dismissed_page_notices));

    return 1;
}


sub has_dismissed_page_notice {
    my ( $u, $notice_string ) = @_;

    return 1 if grep { $_ eq $notice_string } $u->dismissed_page_notices;
    return 0;
}


########################################################################
###  21. Password Functions

=head2 Password Functions
=cut

sub can_receive_password {
    my ($u, $email) = @_;

    return 0 unless $u && $email;
    return 1 if lc($email) eq lc($u->email_raw);

    my $dbh = LJ::get_db_reader();
    return $dbh->selectrow_array("SELECT COUNT(*) FROM infohistory ".
                                 "WHERE userid=? AND what='email' ".
                                 "AND oldvalue=? AND other='A'",
                                 undef, $u->id, $email);
}


sub password {
    my $u = shift;
    return unless $u->is_person;
    my $userid = $u->userid;
    $u->{_password} ||= LJ::MemCache::get_or_set( [$userid, "pw:$userid"], sub {
        my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
        return $dbh->selectrow_array( "SELECT password FROM password WHERE userid=?",
                                      undef, $userid );
    } );
    return $u->{_password};
}


sub set_password {
    my ( $u, $password ) = @_;
    my $userid = $u->id;

    my $dbh = LJ::get_db_writer();
    if ( $LJ::DEBUG{'write_passwords_to_user_table'} ) {
        $dbh->do( "UPDATE user SET password=? WHERE userid=?", undef,
                  $password, $userid );
    }
    $dbh->do( "REPLACE INTO password (userid, password) VALUES (?, ?)",
              undef, $userid, $password );

    # update caches
    LJ::memcache_kill( $userid, "userid" );
    $u->memc_delete( 'pw' );
    my $cache = $LJ::REQ_CACHE_USER_ID{$userid} or return;
    $cache->{'_password'} = $password;
}


########################################################################
###  22. Priv-Related Functions


sub grant_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||= "";
    my $dbh = LJ::get_db_writer();

    return 1 if $u->has_priv( $priv, $arg );

    if ( $arg && $arg ne '*' && $priv !~ /^support/ ) {
        my $valid_args = LJ::list_valid_args( $priv );
        return 0 if $valid_args and not $valid_args->{$arg};
    }

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("INSERT INTO priv_map (userid, prlid, arg) VALUES (?, ?, ?)",
             undef, $u->id, $privid, $arg);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    return 1;
}

sub has_priv {
    my ( $u, $priv, $arg ) = @_;

    # check to see if the priv is packed, and unpack it if so, this allows
    # someone to call $u->has_priv( "foo:*" ) instead of $u->has_priv( foo => '*' )
    # which is helpful for some callers.
    ( $priv, $arg ) = ( $1, $2 )
        if $priv =~ /^(.+?):(.+)$/;

    # at this point, if they didn't provide us with a priv, bail out
    return 0 unless $priv;

    # load what privileges the user has, if we haven't
    $u->load_user_privs( $priv )
        unless $u->{'_privloaded'}->{$priv};

    # no access if they don't have the priv
    return 0 unless defined $u->{'_priv'}->{$priv};

    # at this point we know they have the priv
    return 1 unless defined $arg;

    # check if they have the right arguments
    return 1 if defined $u->{'_priv'}->{$priv}->{$arg};
    return 1 if defined $u->{'_priv'}->{$priv}->{"*"};

    # don't have the right argument
    return 0;
}

# des: loads all of the given privs for a given user into a hashref, inside
#      the user record.
# args: u, priv, arg?
# des-priv: Priv names to load (see [dbtable[priv_list]]).
# des-arg: Optional argument.
# returns: boolean
sub load_user_privs {
    my ( $remote, @privs ) = @_;
    return unless $remote and @privs;

    # return if we've already loaded these privs for this user.
    @privs = grep { ! $remote->{'_privloaded'}->{$_} } @privs;
    return unless @privs;

    my $dbr = LJ::get_db_reader() or return;
    $remote->{'_privloaded'}->{$_}++ foreach @privs;
    my $bind = join ',', map { '?' } @privs;
    my $sth = $dbr->prepare( "SELECT pl.privcode, pm.arg ".
                             "FROM priv_map pm, priv_list pl ".
                             "WHERE pm.prlid=pl.prlid AND ".
                             "pm.userid=? AND pl.privcode IN ($bind)" );
    $sth->execute( $remote->userid, @privs );
    while ( my ($priv, $arg) = $sth->fetchrow_array ) {
        $arg = "" unless defined $arg;  # NULL -> ""
        $remote->{'_priv'}->{$priv}->{$arg} = 1;
    }
}

sub priv_args {
    my ( $u, $priv ) = @_;
    return unless $priv && $u->has_priv( $priv );
    # returns hash of form { arg => 1 }
    return %{ $u->{'_priv'}->{$priv} };
}


sub revoke_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||="";
    my $dbh = LJ::get_db_writer();

    return 1 unless $u->has_priv( $priv, $arg );

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("DELETE FROM priv_map WHERE userid = ? AND prlid = ? AND arg = ?",
             undef, $u->id, $privid, $arg);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    undef $u->{'_priv'};
    return 1;
}

sub revoke_priv_all {
    my ($u, $priv) = @_;
    my $dbh = LJ::get_db_writer();

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("DELETE FROM priv_map WHERE userid = ? AND prlid = ?",
             undef, $u->id, $privid);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    undef $u->{'_priv'};
    return 1;
}

########################################################################
###  24. Styles and S2-Related Functions

=head2 Styles and S2-Related Functions
=cut

sub display_journal_deleted {
    my ( $u, $remote, %opts ) = @_;
    return undef unless LJ::isu( $u );

    my $r = DW::Request->get;
    $r->status( 404 );

    my $extra = {};
    if ( $opts{bml} ) {
        $extra->{scope} = 'bml';
        $extra->{scope_data} = $opts{bml};
    } elsif ( $opts{journal_opts} ) {
        $extra->{scope} = 'journal';
        $extra->{scope_data} = $opts{journal_opts};
    }

    my $data = {
        reason => $u->prop( 'delete_reason' ),
        u => $u,

        is_member_of => $u->is_community && $u->trusts_or_has_member( $remote ),
        is_protected => LJ::User->is_protected_username( $u->user ),
    };

    return DW::Template->render_template_misc( "journal/deleted.tt", $data, $extra );
}
# returns undef on error, or otherwise arrayref of arrayrefs,
# each of format [ year, month, day, count ] for all days with
# non-zero count.  examples:
#  [ [ 2003, 6, 5, 3 ], [ 2003, 6, 8, 4 ], ... ]
#
sub get_daycounts {
    my ( $u, $remote, $not_memcache ) = @_;
    return undef unless LJ::isu( $u );
    my $uid = $u->id;

    my $memkind = 'p'; # public only, changed below
    my $secwhere = "AND security='public'";
    my $viewall = 0;

    if ( LJ::isu( $remote ) ) {
        # do they have the viewall priv?
        my $r = DW::Request->get;
        my %getargs = %{ $r->get_args };
        if ( defined $getargs{'viewall'} and $getargs{'viewall'} eq '1' ) {
            $viewall = $remote->has_priv( 'canview', '*' );
            LJ::statushistory_add( $u->userid, $remote->userid,
                "viewall", "archive" ) if $viewall;
        }

        if ( $viewall || $remote->can_manage( $u ) ) {
            $secwhere = "";   # see everything
            $memkind = 'a'; # all
        } elsif ( $remote->is_individual ) {
            my $gmask = $u->is_community ? $remote->member_of( $u ) : $u->trustmask( $remote );
            if ( $gmask ) {
                $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))";
                $memkind = 'g' . $gmask; # friends case: allowmask == gmask == 1
            }
        }
    }

    my $memkey = [$uid, "dayct2:$uid:$memkind"];
    unless ($not_memcache) {
        my $list = LJ::MemCache::get($memkey);
        if ($list) {
            # this was an old version of the stored memcache value
            # where the first argument was the list creation time
            # so throw away the first argument
            shift @$list unless ref $list->[0];
            return $list;
        }
    }

    my $dbcr = LJ::get_cluster_def_reader($u) or return undef;
    my $sth = $dbcr->prepare("SELECT year, month, day, COUNT(*) ".
                             "FROM log2 WHERE journalid=? $secwhere GROUP BY 1, 2, 3");
    $sth->execute($uid);
    my @days;
    while (my ($y, $m, $d, $c) = $sth->fetchrow_array) {
        # we force each number from string scalars (from DBI) to int scalars,
        # so they store smaller in memcache
        push @days, [ int($y), int($m), int($d), int($c) ];
    }

    if ( $memkind ne "g1" && $memkind =~ /^g\d+$/ ) {
        # custom groups are cached for only 15 minutes
        LJ::MemCache::set( $memkey, [@days], 15 * 60 );
    } else {
        # all other security levels are cached indefinitely
        # because we clear them when there are updates
        LJ::MemCache::set( $memkey, [@days]  );
    }
    return \@days;
}


sub journal_base {
    return LJ::journal_base( @_ );
}


sub meta_discovery_links {
    my ( $u, %opts ) = @_;
    my $journalbase = $u->journal_base;

    my $ret = "";

    # Automatic Discovery of RSS/Atom
    if ( $opts{feeds} ) {
        if ( $opts{tags} && @{$opts{tags}||[]}) {
            my $taglist = join( ',', map( { LJ::eurl($_) } @{$opts{tags}||[]} ) );
            $ret .= qq{<link rel="alternate" type="application/rss+xml" title="RSS: filtered by selected tags" href="$journalbase/data/rss?tag=$taglist" />\n};
            $ret .= qq{<link rel="alternate" type="application/atom+xml" title="Atom: filtered by selected tags" href="$journalbase/data/atom?tag=$taglist" />\n};
        }

        $ret .= qq{<link rel="alternate" type="application/rss+xml" title="RSS: all entries" href="$journalbase/data/rss" />\n};
        $ret .= qq{<link rel="alternate" type="application/atom+xml" title="Atom: all entries" href="$journalbase/data/atom" />\n};
        $ret .= qq{<link rel="service" type="application/atomsvc+xml" title="AtomAPI service document" href="} . $u->atom_service_document . qq{" />\n};
    }

    # OpenID Server and Yadis
    $ret .= $u->openid_tags if $opts{openid};

    # FOAF autodiscovery
    if ( $opts{foaf} ) {
        my $foafurl = $u->{external_foaf_url} ? LJ::eurl( $u->{external_foaf_url} ) : "$journalbase/data/foaf";
        $ret .= qq{<link rel="meta" type="application/rdf+xml" title="FOAF" href="$foafurl" />\n};

        if ($u->email_visible($opts{remote})) {
            my $digest = Digest::SHA1::sha1_hex( 'mailto:' . $u->email_raw );
            $ret .= qq{<meta name="foaf:maker" content="foaf:mbox_sha1sum '$digest'" />\n};
        }
    }

    return $ret;
}


sub opt_ctxpopup {
    my $u = shift;

    # if unset, default to on
    my $prop = $u->raw_prop('opt_ctxpopup') || 'Y';

    return $prop;
}

# should contextual hover be displayed for icons
sub opt_ctxpopup_icons {
    return ( $_[0]->prop( 'opt_ctxpopup' ) eq "Y" || $_[0]->prop( 'opt_ctxpopup' ) eq "I" );
}

# should contextual hover be displayed for the graphical userhead
sub opt_ctxpopup_userhead {
    return ( $_[0]->prop( 'opt_ctxpopup' ) eq "Y" || $_[0]->prop( 'opt_ctxpopup' ) eq "U" );
}


sub opt_embedplaceholders {
    my $u = shift;

    my $prop = $u->raw_prop('opt_embedplaceholders');

    if (defined $prop) {
        return $prop;
    } else {
        my $imagelinks = $u->prop('opt_imagelinks');
        return $imagelinks;
    }
}

sub set_default_style {
    my $style = eval { LJ::Customize->verify_and_load_style( $_[0] ); };
    warn $@ if $@;

    return $style;
}

sub show_control_strip {
    my $u = shift;

    LJ::Hooks::run_hook('control_strip_propcheck', $u, 'show_control_strip') if LJ::is_enabled('control_strip_propcheck');

    my $prop = $u->raw_prop('show_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}


sub view_control_strip {
    my $u = shift;

    LJ::Hooks::run_hook('control_strip_propcheck', $u, 'view_control_strip') if LJ::is_enabled('control_strip_propcheck');

    my $prop = $u->raw_prop('view_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}


# BE VERY CAREFUL about the return values and arguments you pass to this
# method.  please understand the security implications of this, and how to
# properly and safely use it.
#
sub view_priv_check {
    my ( $remote, $u, $requested, $page, $itemid ) = @_;

    # $requested is set to the 'viewall' GET argument.  this should ONLY be on if the
    # user is EXPLICITLY requesting to view something they can't see normally.  most
    # of the time this is off, so we can bail now.
    return unless $requested;

    # now check the rest of our arguments for validity
    return unless LJ::isu( $remote ) && LJ::isu( $u );
    return if defined $page && $page !~ /^\w+$/;
    return if defined $itemid && $itemid !~ /^\d+$/;

    # viewsome = "this user can view suspended content"
    my $viewsome = $remote->has_priv( canview => 'suspended' );

    # viewall = "this user can view all content, even private"
    my $viewall = $viewsome && $remote->has_priv( canview => '*' );

    # make sure we log the content being viewed
    if ( $viewsome && $page ) {
        my $user = $u->user;
        $user .= ", itemid: $itemid" if defined $itemid;
        my $sv = $u->statusvis;
        LJ::statushistory_add( $u->userid, $remote->userid, 'viewall',
                               "$page: $user, statusvis: $sv");
    }

    return wantarray ? ( $viewall, $viewsome ) : $viewsome;
}

=head2 C<< $u->viewing_style( $view ) >>
Takes a user and a view argument and returns what that user's preferred
style is for a given view.
=cut
sub viewing_style {
    my ( $u, $view ) = @_;

    $view ||= 'entry';

    my %style_types = ( O => "original", M => "mine", S => "site", L => "light" );
    my %view_props = (
        entry => 'opt_viewentrystyle',
        reply => 'opt_viewentrystyle',
        icons => 'opt_viewiconstyle',
    );

    my $prop = $view_props{ $view } || 'opt_viewjournalstyle';
    return $style_types{ $u->prop( $prop ) } || 'original';
}

########################################################################
###  25. Subscription, Notifiction, and Messaging Functions

=head2 Subscription, Notifiction, and Messaging Functions
=cut

# this is the count used to check the maximum subscription count
sub active_inbox_subscription_count {
    my $u = shift;
    return scalar ( grep { $_->active && $_->enabled } $u->find_subscriptions(method => 'Inbox') );
}


sub can_add_inbox_subscription {
    my $u = shift;
    return $u->active_inbox_subscription_count >= $u->max_subscriptions ? 0 : 1;
}


# can this user use ESN?
sub can_use_esn {
    my $u = shift;
    return 0 if $u->is_community || $u->is_syndicated;
    return 0 unless LJ::is_enabled('esn');
    return LJ::is_enabled('esn_ui', $u);
}


# 1/0 if someone can send a message to $u
sub can_receive_message {
    my ($u, $sender) = @_;

    my $opt_usermsg = $u->opt_usermsg;
    return 0 if $opt_usermsg eq 'N' || !$sender;
    return 0 if $u->has_banned($sender);
    return 0 if $opt_usermsg eq 'M' && !$u->mutually_trusts($sender);
    return 0 if $opt_usermsg eq 'F' && !$u->trusts($sender);

    return 1;
}


# delete all of a user's subscriptions
sub delete_all_subscriptions {
    return LJ::Subscription->delete_all_subs( @_ );
}


# delete all of a user's subscriptions
sub delete_all_inactive_subscriptions {
    return LJ::Subscription->delete_all_inactive_subs( @_ );
}


# ensure that this user does not have more than the maximum number of subscriptions
# allowed by their cap, and enable subscriptions up to their current limit
sub enable_subscriptions {
    my $u = shift;

    # first thing, disable everything they don't have caps for
    # and make sure everything is enabled that should be enabled
    map { $_->available_for_user($u) ? $_->enable : $_->disable } $u->find_subscriptions(method => 'Inbox');

    my $max_subs = $u->get_cap('subscriptions');
    my @inbox_subs = grep { $_->active && $_->enabled } $u->find_subscriptions(method => 'Inbox');

    if ((scalar @inbox_subs) > $max_subs) {
        # oh no, too many subs.
        # disable the oldest subscriptions that are "tracking" subscriptions
        my @tracking = grep { $_->is_tracking_category } @inbox_subs;

        # oldest subs first
        @tracking = sort {
            return $a->createtime <=> $b->createtime;
        } @tracking;

        my $need_to_deactivate = (scalar @inbox_subs) - $max_subs;

        for (1..$need_to_deactivate) {
            my $sub_to_deactivate = shift @tracking;
            $sub_to_deactivate->deactivate if $sub_to_deactivate;
        }
    } else {
        # make sure all subscriptions are activated
        my $need_to_activate = $max_subs - (scalar @inbox_subs);

        # get deactivated subs
        @inbox_subs = grep { $_->active && $_->available_for_user } $u->find_subscriptions(method => 'Inbox');

        for (1..$need_to_activate) {
            my $sub_to_activate = shift @inbox_subs;
            $sub_to_activate->activate if $sub_to_activate;
        }
    }
}


sub esn_inbox_default_expand {
    my $u = shift;

    my $prop = $u->raw_prop('esn_inbox_default_expand');
    return $prop ne 'N';
}


# interim solution while legacy/ESN notifications are both happening:
# checks possible subscriptions to see if user will get an ESN notification
# THIS IS TEMPORARY. FIXME. Should only be called by talklib.
# params: journal, arg1 (entry ditemid), arg2 (comment talkid)
sub gets_notified {
    my ($u, %params) = @_;

    $params{event} = "LJ::Event::JournalNewComment";
    $params{method} = "LJ::NotificationMethod::Email";

    my $has_sub;

    # did they subscribe to the parent comment?
    $has_sub = LJ::Subscription->find($u, %params);
    return $has_sub if $has_sub;

    # remove the comment-specific parameter, then check for an entry subscription
    $params{arg2} = 0;
    $has_sub = LJ::Subscription->find($u, %params);
    return $has_sub if $has_sub;

    # remove the entry-specific parameter, then check if they're subscribed to the entire journal
    $params{arg1} = 0;
    $has_sub = LJ::Subscription->find($u, %params);
    return $has_sub;
}


# search for a subscription
*find_subscriptions = \&has_subscription;
sub has_subscription {
    my ($u, %params) = @_;
    croak "No parameters" unless %params;

    return LJ::Subscription->find($u, %params);
}


sub max_subscriptions {
    my $u = shift;
    return $u->get_cap('subscriptions');
}


# return the URL to the send message page
sub message_url {
    my $u = shift;
    croak "invalid user object passed" unless LJ::isu($u);

    return undef unless LJ::is_enabled('user_messaging');
    return "$LJ::SITEROOT/inbox/compose?user=" . $u->user;
}


sub new_message_count {
    my $u = shift;
    my $inbox = $u->notification_inbox;
    my $count = $inbox->unread_count;

    return $count || 0;
}


sub notification_archive {
    my $u = shift;
    return LJ::NotificationArchive->new($u);
}


# Returns the NotificationInbox for this user
*inbox = \&notification_inbox;
sub notification_inbox {
    my $u = shift;
    return LJ::NotificationInbox->new($u);
}


# opt_usermsg options
# Y - Registered Users
# F - Trusted Users
# M - Mutually Trusted Users
# N - Nobody
sub opt_usermsg {
    my $u = shift;

    if ($u->raw_prop('opt_usermsg') =~ /^(Y|F|M|N)$/) {
        return $u->raw_prop('opt_usermsg');
    } else {
        return 'M' if $u->is_minor;
        return 'Y';
    }
}


# subscribe to an event
sub subscribe {
    my ($u, %opts) = @_;
    croak "No subscription options" unless %opts;

    return LJ::Subscription->create($u, %opts);
}


sub subscription_count {
    my $u = shift;
    return scalar LJ::Subscription->subscriptions_of_user($u);
}


sub subscriptions {
    my $u = shift;
    return LJ::Subscription->subscriptions_of_user($u);
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
###  27. Tag-Related Functions

=head2 Tag-Related Functions
=cut

# can $u add existing tags to $targetu's entries?
sub can_add_tags_to {
    my ($u, $targetu) = @_;

    return LJ::Tags::can_add_tags($targetu, $u);
}

# can $u control (add, delete, edit) the tags of $targetu?
sub can_control_tags {
   my ($u, $targetu) = @_;

   return LJ::Tags::can_control_tags($targetu, $u);
}

# <LJFUNC>
# name: LJ::User::get_keyword_id
# class:
# des: Get the id for a keyword.
# args: uuid, keyword, autovivify?
# des-uuid: User object or userid to use.
# des-keyword: A string keyword to get the id of.
# returns: Returns a kwid into [dbtable[userkeywords]].
#          If the keyword doesn't exist, it is automatically created for you.
# des-autovivify: If present and 1, automatically create keyword.
#                 If present and 0, do not automatically create the keyword.
#                 If not present, default behavior is the old
#                 style -- yes, do automatically create the keyword.
# </LJFUNC>
sub get_keyword_id
{
    my ( $u, $kw, $autovivify ) = @_;
    $u = LJ::want_user( $u );
    return undef unless $u;
    $autovivify = 1 unless defined $autovivify;

    # setup the keyword for use
    return 0 unless $kw =~ /\S/;
    $kw = LJ::text_trim( $kw, LJ::BMAX_KEYWORD, LJ::CMAX_KEYWORD );

    # get the keyword and insert it if necessary
    my $kwid = $u->selectrow_array( 'SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                    undef, $u->userid, $kw ) + 0;
    if ( $autovivify && ! $kwid ) {
        # create a new keyword
        $kwid = LJ::alloc_user_counter( $u, 'K' );
        return undef unless $kwid;

        # attempt to insert the keyword
        my $rv = $u->do( "INSERT IGNORE INTO userkeywords (userid, kwid, keyword) VALUES (?, ?, ?)",
                         undef, $u->userid, $kwid, $kw ) + 0;
        return undef if $u->err;

        # at this point, if $rv is 0, the keyword is already there so try again
        unless ( $rv ) {
            $kwid = $u->selectrow_array( 'SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                         undef, $u->userid, $kw ) + 0;
        }

        # nuke cache
        $u->memc_delete( 'kws' );
    }
    return $kwid;
}


sub tags {
    my $u = shift;

    return LJ::Tags::get_usertags($u);
}


########################################################################
###  28. Userpic-Related Functions

=head2 Userpic-Related Functions

=head3 C<< $u->activate_userpics >>

Sets/unsets userpics as inactive based on account caps.

=cut
sub activate_userpics {
    my $u = shift;

    # this behavior is optional, but enabled by default
    return 1 if $LJ::ALLOW_PICS_OVER_QUOTA;

    return undef unless LJ::isu($u);

    # can't get a cluster read for expunged users since they are clusterid 0,
    # so just return 1 to the caller from here and act like everything went fine
    return 1 if $u->is_expunged;

    my $userid = $u->userid;
    my $have_mapid = $u->userpic_have_mapid;

    # active / inactive lists
    my @active = ();
    my @inactive = ();

    # get a database handle for reading/writing
    my $dbh = LJ::get_db_writer();
    my $dbcr = LJ::get_cluster_def_reader($u);

    # select all userpics and build active / inactive lists
    return undef unless $dbcr;
    my $sth = $dbcr->prepare( "SELECT picid, state FROM userpic2 WHERE userid=?" );
    $sth->execute($userid);
    while (my ($picid, $state) = $sth->fetchrow_array) {
        next if $state eq 'X'; # expunged, means userpic has been removed from site by admins
        if ($state eq 'I') {
            push @inactive, $picid;
        } else {
            push @active, $picid;
        }
    }

    # inactivate previously activated userpics
    my $allowed = $u->userpic_quota;
    if (scalar @active > $allowed) {
        my $to_ban = scalar @active - $allowed;

        # find first jitemid greater than time 2 months ago using rlogtime index
        # ($LJ::EndOfTime - UnixTime)
        my $jitemid = $dbcr->selectrow_array("SELECT jitemid FROM log2 USE INDEX (rlogtime) " .
                                             "WHERE journalid=? AND rlogtime > ? LIMIT 1",
                                             undef, $userid, $LJ::EndOfTime - time() + 86400*60);

        # query all pickws in logprop2 with jitemid > that value
        my %count_kw = ();
        my $propid;
        if ( $have_mapid ) {
            $propid = LJ::get_prop("log", "picture_mapid")->{id};
        } else {
            $propid = LJ::get_prop("log", "picture_keyword")->{id};
        }
        my $sth = $dbcr->prepare("SELECT value, COUNT(*) FROM logprop2 " .
                                 "WHERE journalid=? AND jitemid > ? AND propid=?" .
                                 "GROUP BY value");
        $sth->execute($userid, $jitemid || 0, $propid);
        while (my ($value, $ct) = $sth->fetchrow_array) {
            # keyword => count
            $count_kw{$value} = $ct;
        }

        my $values_in = join(",", map { $dbh->quote($_) } keys %count_kw);

        # map pickws to picids for freq hash below
        my %count_picid = ();
        if ( $values_in ) {
            if ( $have_mapid ) {
                foreach my $mapid ( keys %count_kw ) {
                    my $picid = $u->get_picid_from_mapid($mapid);
                    $count_picid{$picid} += $count_kw{$mapid} if $picid;
                }
            } else {
                my $sth = $dbcr->prepare( "SELECT k.keyword, m.picid FROM userkeywords k, userpicmap2 m ".
                                        "WHERE k.keyword IN ($values_in) AND k.kwid=m.kwid AND k.userid=m.userid " .
                                        "AND k.userid=?" );
                $sth->execute($userid);
                while (my ($keyword, $picid) = $sth->fetchrow_array) {
                    # keyword => picid
                    $count_picid{$picid} += $count_kw{$keyword};
                }
            }
        }

        # we're only going to ban the least used, excluding the user's default
        my @ban = (grep { $_ != $u->{defaultpicid} }
                   sort { $count_picid{$a} <=> $count_picid{$b} } @active);

        @ban = splice(@ban, 0, $to_ban) if @ban > $to_ban;
        my $ban_in = join(",", map { $dbh->quote($_) } @ban);
        $u->do( "UPDATE userpic2 SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                undef, $userid ) if $ban_in;
    }

    # activate previously inactivated userpics
    if (scalar @inactive && scalar @active < $allowed) {
        my $to_activate = $allowed - @active;
        $to_activate = @inactive if $to_activate > @inactive;

        # take the $to_activate newest (highest numbered) pictures
        # to reactivated
        @inactive = sort @inactive;
        my @activate_picids = splice(@inactive, -$to_activate);

        my $activate_in = join(",", map { $dbh->quote($_) } @activate_picids);
        if ( $activate_in ) {
            $u->do( "UPDATE userpic2 SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                    undef, $userid );
        }
    }

    # delete userpic info object from memcache
    LJ::Userpic->delete_cache($u);
    $u->clear_userpic_kw_map;

    return 1;
}


=head3 C<< $u->allpics_base >>

Return the base URL for the icons page.

=cut
sub allpics_base {
    return $_[0]->journal_base . "/icons";
}

=head3 C<< $u->clear_userpic_kw_map >>

Clears the internally cached mapping of userpics to keywords for this user.

=cut
sub clear_userpic_kw_map {
    $_[0]->{picid_kw_map} = undef;
}

=head3 C<< $u->expunge_userpic( $picid ) >>

Expunges a userpic so that the system will no longer deliver this userpic.

=cut
# If your site has off-site caching or something similar, you can also define
# a hook "expunge_userpic" which will be called with a picid and userid when
# a pic is expunged.
sub expunge_userpic {
    my ( $u, $picid ) = @_;
    $picid += 0;
    return undef unless $picid && LJ::isu( $u );

    # get the pic information
    my $state;

    my $dbcm = LJ::get_cluster_master( $u );
    return undef unless $dbcm && $u->writer;

    $state = $dbcm->selectrow_array( 'SELECT state FROM userpic2 WHERE userid = ? AND picid = ?',
                                     undef, $u->userid, $picid );
    return undef unless $state; # invalid pic
    return $u->userid if $state eq 'X'; # already expunged

    # else now mark it
    $u->do( "UPDATE userpic2 SET state='X' WHERE userid = ? AND picid = ?", undef, $u->userid, $picid );
    return LJ::error( $dbcm ) if $dbcm->err;

    # Since we don't clean userpicmap2 when we migrate to dversion 9, clean it here on expunge no matter the dversion.
    $u->do( "DELETE FROM userpicmap2 WHERE userid = ? AND picid = ?", undef, $u->userid, $picid );
    if ( $u->userpic_have_mapid ) {
        $u->do( "DELETE FROM userpicmap3 WHERE userid = ? AND picid = ? AND kwid=NULL", undef, $u->userid, $picid );
        $u->do( "UPDATE userpicmap3 SET picid = NULL WHERE userid = ? AND picid = ?", undef, $u->userid, $picid );
    }

    # now clear the user's memcache picture info
    LJ::Userpic->delete_cache( $u );

    # call the hook and get out of here
    my @rval = LJ::Hooks::run_hooks( 'expunge_userpic', $picid, $u->userid );
    return ( $u->userid, map {$_->[0]} grep {$_ && @$_ && $_->[0]} @rval );
}

=head3 C<< $u->get_keyword_from_mapid( $mapid, %opts ) >>

Returns the keyword for the given mapid or undef if the mapid doesn't exist.

Arguments:

=over 4

=item mapid

=back

Additional options:

=over 4

=item redir_callback

Called if the mapping is redirected to another mapping with the following arguments

( $u, $old_mapid, $new_mapid )

=back

=cut
sub get_keyword_from_mapid {
    my ( $u, $mapid, %opts ) = @_;
    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return undef unless $info;
    return undef unless $u->userpic_have_mapid;

    $mapid = $u->resolve_mapid_redirects($mapid,%opts);
    my $kw = $info->{mapkw}->{ $mapid };
    return $kw;
}

=head3 C<< $u->get_mapid_from_keyword( $kw, %opts ) >>

Returns the mapid for a given keyword.

Arguments:

=over 4

=item kw

The keyword.

=back

Additional options:

=over 4

=item create

Should a mapid be created if one does not exist.

Default: 0

=back

=cut
sub get_mapid_from_keyword {
    my ( $u, $kw, %opts ) = @_;
    return 0 unless $u->userpic_have_mapid;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return 0 unless $info;

    my $mapid = $info->{kwmap}->{$kw};
    return $mapid if $mapid;

    # the silly "pic#2343" thing when they didn't assign a keyword, if we get here
    # we need to create it.
    if ( $kw =~ /^pic\#(\d+)$/ ) {
        my $picid = $1;
        return 0 unless $info->{pic}{$picid};           # don't create rows for invalid pics
        return 0 unless $info->{pic}{$picid}{state} eq 'N'; # or inactive

        return $u->_create_mapid( undef, $picid )
    }

    return 0 unless $opts{create};

    return $u->_create_mapid( $u->get_keyword_id( $kw ), undef );
}

=head3 C<< $u->get_picid_from_keyword( $kw, $default ) >>

Returns the picid for a given keyword.

=over 4

=item kw

Keyword to look up.

=item default (optional)

Default: the users default userpic.

=back

=cut
sub get_picid_from_keyword {
    my ( $u, $kw, $default ) = @_;
    $default ||= ref $u ? $u->{defaultpicid} : 0;
    return $default unless $kw;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return $default unless $info;

    my $pr = $info->{kw}{$kw};
    # normal keyword
    return $pr->{picid} if $pr->{picid};

    # the silly "pic#2343" thing when they didn't assign a keyword
    if ( $kw =~ /^pic\#(\d+)$/ ) {
        my $picid = $1;
        return $picid if $info->{pic}{$picid};
    }

    return $default;
}

=head3 C<< $u->get_picid_from_mapid( $mapid, %opts ) >>

Returns the picid for a given mapid.

Arguments:

=over 4

=item mapid

=back

Additional options:

=over 4

=item default

Default: the users default userpic.

=item redir_callback

Called if the mapping is redirected to another mapping with the following arguments

( $u, $old_mapid, $new_mapid )

=back

=cut
sub get_picid_from_mapid {
    my ( $u, $mapid, %opts ) = @_;
    my $default = $opts{default} || ref $u ? $u->{defaultpicid} : 0;
    return $default unless $mapid;
    return $default unless $u->userpic_have_mapid;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return $default unless $info;

    $mapid = $u->resolve_mapid_redirects($mapid,%opts);
    my $pr = $info->{mapid}{$mapid};

    return $pr->{picid} if $pr->{picid};

    return $default;
}

=head3 C<< $u->get_userpic_count >>

Return the number of userpics.

=cut
sub get_userpic_count {
    my $u = shift or return undef;
    my $count = scalar LJ::Userpic->load_user_userpics($u);

    return $count;
}

=head3 C<< $u->get_userpic_info( $opts ) >>

Given a user, gets their userpic information

Arguments:

=over 4

=item opts

Hashref of options

Valid options:

=over 4

=item load_comments

=item load_urls

=item load_descriptions

=back

Returns a hashref with the following keys:

=over 4

=item comment

Maps a picid to a comment.
May not be present if load_comments was not specified.

=item description

Maps a picid to a description.
May not be present if load_descriptions was not specified.

=item kw

Maps a keyword to a pic hashref.

=item kwmap

Maps a keyword to a mapid.

=item map_redir

Maps a mapid to a diffrent mapid.

=item mapid

Maps a mapid to a pic hashref.

=item mapkw

Maps a mapid to a keyword.

=item pic

Maps a picid to a pic hashref.

=back

=back

=cut
# returns: hash of userpicture information;
#          for efficiency, we store the userpic structures
#          in memcache in a packed format.
# info: memory format:
#       [
#       version number of format,
#       userid,
#       "packed string", which expands to an array of {width=>..., ...}
#       "packed string", which expands to { 'kw1' => id, 'kw2' => id, ...}
#       series of 3 4-byte numbers, which expands to { mapid1 => id, mapid2 => id, ...}, as well as { mapid1 => mapid2 }
#       "packed string", which expands to { 'kw1' => mapid, 'kw2' => mapid, ...}
#       ]
sub get_userpic_info {
    my ( $u, $opts ) = @_;
    return undef unless LJ::isu( $u ) && $u->clusterid;
    my $mapped_icons = $u->userpic_have_mapid;

    # in the cache, cool, well unless it doesn't have comments or urls or descriptions
    # and we need them
    if (my $cachedata = $LJ::CACHE_USERPIC_INFO{ $u->userid }) {
        my $good = 1;
        $good = 0 if $opts->{load_comments} && ! $cachedata->{_has_comments};
        $good = 0 if $opts->{load_urls} && ! $cachedata->{_has_urls};
        $good = 0 if $opts->{load_descriptions} && ! $cachedata->{_has_descriptions};

        return $cachedata if $good;
    }

    my $VERSION_PICINFO = 4;

    my $memkey = [$u->userid,"upicinf:$u->{'userid'}"];
    my ($info, $minfo);

    if ($minfo = LJ::MemCache::get($memkey)) {
        # the pre-versioned memcache data was a two-element hash.
        # since then, we use an array and include a version number.

        if (ref $minfo eq 'HASH' ||
            $minfo->[0] != $VERSION_PICINFO) {
            # old data in the cache.  delete.
            LJ::MemCache::delete($memkey);
        } else {
            my (undef, $picstr, $kwstr, $picmapstr, $kwmapstr) = @$minfo;
            $info = {
                pic => {},
                kw => {}
            };
            while (length $picstr >= 7) {
                my $pic = { userid => $u->userid };
                ($pic->{picid},
                 $pic->{width}, $pic->{height},
                 $pic->{state}) = unpack "NCCA", substr($picstr, 0, 7, '');
                $info->{pic}->{$pic->{picid}} = $pic;
            }

            my ($pos, $nulpos);
            $pos = $nulpos = 0;
            while (($nulpos = index($kwstr, "\0", $pos)) > 0) {
                my $kw = substr($kwstr, $pos, $nulpos-$pos);
                my $id = unpack("N", substr($kwstr, $nulpos+1, 4));
                $pos = $nulpos + 5; # skip NUL + 4 bytes.
                $info->{kw}->{$kw} = $info->{pic}->{$id};
            }

            if ( $mapped_icons ) {
                if ( defined $picmapstr && defined $kwmapstr ) {
                    $pos =  0;
                    while ($pos < length($picmapstr)) {
                        my ($mapid, $id, $redir) = unpack("NNN", substr($picmapstr, $pos, 12));
                        $pos += 12; # 3 * 4 bytes.
                        $info->{mapid}->{$mapid} = $info->{pic}{$id} if $id;
                        $info->{map_redir}->{$mapid} = $redir if $redir;
                    }

                    $pos = $nulpos = 0;
                    while (($nulpos = index($kwmapstr, "\0", $pos)) > 0) {
                        my $kw = substr($kwmapstr, $pos, $nulpos-$pos);
                        my $id = unpack("N", substr($kwmapstr, $nulpos+1, 4));
                        $pos = $nulpos + 5; # skip NUL + 4 bytes.
                        $info->{kwmap}->{$kw} = $id;
                        $info->{mapkw}->{$id} = $kw || "pic#" . $info->{mapid}->{$id}->{picid};
                    }
                } else { # This user is on dversion 9, but the data isn't in memcache
                         # so force a db load
                    undef $info;
                }
            }
        }


        # Load picture comments
        if ( $opts->{load_comments} && $info ) {
            my $commemkey = [$u->userid, "upiccom:" . $u->userid];
            my $comminfo = LJ::MemCache::get( $commemkey );

            if ( defined( $comminfo ) ) {
                my ( $pos, $nulpos );
                $pos = $nulpos = 0;
                while ( ($nulpos = index( $comminfo, "\0", $pos )) > 0 ) {
                    my $comment = substr( $comminfo, $pos, $nulpos-$pos );
                    my $id = unpack( "N", substr( $comminfo, $nulpos+1, 4 ) );
                    $pos = $nulpos + 5; # skip NUL + 4 bytes.
                    $info->{pic}->{$id}->{comment} = $comment;
                    $info->{comment}->{$id} = $comment;
                }
                $info->{_has_comments} = 1;
            } else { # Requested to load comments, but they aren't in memcache
                     # so force a db load
                undef $info;
            }
        }

        # Load picture urls
        if ( $opts->{load_urls} && $info ) {
            my $urlmemkey = [$u->userid, "upicurl:" . $u->userid];
            my $urlinfo = LJ::MemCache::get( $urlmemkey );

            if ( defined( $urlinfo ) ) {
                my ( $pos, $nulpos );
                $pos = $nulpos = 0;
                while ( ($nulpos = index( $urlinfo, "\0", $pos )) > 0 ) {
                    my $url = substr( $urlinfo, $pos, $nulpos-$pos );
                    my $id = unpack( "N", substr( $urlinfo, $nulpos+1, 4 ) );
                    $pos = $nulpos + 5; # skip NUL + 4 bytes.
                    $info->{pic}->{$id}->{url} = $url;
                }
                $info->{_has_urls} = 1;
            } else { # Requested to load urls, but they aren't in memcache
                     # so force a db load
                undef $info;
            }
        }

        # Load picture descriptions
        if ( $opts->{load_descriptions} && $info ) {
            my $descmemkey = [$u->userid, "upicdes:" . $u->userid];
            my $descinfo = LJ::MemCache::get( $descmemkey );

            if ( defined ( $descinfo ) ) {
                my ( $pos, $nulpos );
                $pos = $nulpos = 0;
                while ( ($nulpos = index( $descinfo, "\0", $pos )) > 0 ) {
                    my $description = substr( $descinfo, $pos, $nulpos-$pos );
                    my $id = unpack( "N", substr( $descinfo, $nulpos+1, 4 ) );
                    $pos = $nulpos + 5; # skip NUL + 4 bytes.
                    $info->{pic}->{$id}->{description} = $description;
                    $info->{description}->{$id} = $description;
                }
                $info->{_has_descriptions} = 1;
            } else { # Requested to load descriptions, but they aren't in memcache
                     # so force a db load
                undef $info;
            }
        }
    }

    my %minfocom; # need this in this scope
    my %minfourl;
    my %minfodesc;
    unless ($info) {
        $info = {
            pic => {},
            kw => {}
        };
        my ($picstr, $kwstr, $predirstr, $kwmapstr);
        my $sth;
        my $dbcr = LJ::get_cluster_def_reader($u);
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        return undef unless $dbcr && $db;

        $sth = $dbcr->prepare( "SELECT picid, width, height, state, userid, comment, url, description ".
                               "FROM userpic2 WHERE userid=?" );
        $sth->execute( $u->userid );
        my @pics;
        while (my $pic = $sth->fetchrow_hashref) {
            next if $pic->{state} eq 'X'; # no expunged pics in list
            push @pics, $pic;
            $info->{pic}->{$pic->{picid}} = $pic;
            $minfocom{int($pic->{picid})} = $pic->{comment}
                if $opts->{load_comments} && $pic->{comment};
            $minfourl{int($pic->{picid})} = $pic->{url}
                if $opts->{load_urls} && $pic->{url};
            $minfodesc{int($pic->{picid})} = $pic->{description}
                if $opts->{load_descriptions} && $pic->{description};
        }


        $picstr = join('', map { pack("NCCA", $_->{picid},
                                 $_->{width}, $_->{height}, $_->{state}) } @pics);

        if ( $mapped_icons ) {
            $sth = $dbcr->prepare( "SELECT k.keyword, m.picid, m.mapid, m.redirect_mapid FROM userpicmap3 m LEFT JOIN userkeywords k ON ".
                                "( m.userid=k.userid AND m.kwid=k.kwid ) WHERE m.userid=?" );
        } else {
            $sth = $dbcr->prepare( "SELECT k.keyword, m.picid FROM userpicmap2 m, userkeywords k ".
                                "WHERE k.userid=? AND m.kwid=k.kwid AND m.userid=k.userid" );
        }
        $sth->execute($u->{'userid'});
        my %minfokw;
        my %picmap;
        my %kwmap;
        while (my ($kw, $id, $mapid, $redir) = $sth->fetchrow_array) {

            # used to be a bug that allowed these to get in.
            next if $kw =~ /[\n\r\0]/ || ( defined $kw && length($kw) == 0 );

            my $skip_kw = 0;
            if ( $mapped_icons ) {
                $picmap{$mapid} = [ int($id), int($redir) ];
                if ( $redir ) {
                    $info->{map_redir}->{$mapid} = $redir;
                } else {
                    unless ( defined $kw ) {
                        $skip_kw = 1;
                        $kw = "pic#$id";
                    }
                    $info->{kwmap}->{$kw} = $kwmap{$kw} = $mapid;
                    $info->{mapkw}->{$mapid} = $kw;
                }
            }
            next if $skip_kw;

            next unless $info->{pic}->{$id};
            $info->{kw}->{$kw} = $info->{pic}->{$id};
            $info->{mapid}->{$mapid} = $info->{pic}->{$id} if $mapped_icons && $id;
            $minfokw{$kw} = int($id);
        }
        $kwstr = join('', map { pack("Z*N", $_, $minfokw{$_}) } keys %minfokw);
        if ( $mapped_icons ) {
            $predirstr = join('', map { pack("NNN", $_, @{ $picmap{$_} } ) } keys %picmap);
            $kwmapstr = join('', map { pack("Z*N", $_, $kwmap{$_}) } keys %kwmap);
        }

        $memkey = [$u->{'userid'},"upicinf:$u->{'userid'}"];
        $minfo = [ $VERSION_PICINFO, $picstr, $kwstr, $predirstr, $kwmapstr ];
        LJ::MemCache::set($memkey, $minfo);

        if ( $opts->{load_comments} ) {
            $info->{comment} = \%minfocom;
            my $commentstr = join( '', map { pack( "Z*N", $minfocom{$_}, $_ ) } keys %minfocom );

            my $memkey = [$u->userid, "upiccom:" . $u->userid];
            LJ::MemCache::set( $memkey, $commentstr );

            $info->{_has_comments} = 1;
        }

        if ($opts->{load_urls}) {
            my $urlstr = join( '', map { pack( "Z*N", $minfourl{$_}, $_ ) } keys %minfourl );

            my $memkey = [$u->userid, "upicurl:" . $u->userid];
            LJ::MemCache::set( $memkey, $urlstr );

            $info->{_has_urls} = 1;
        }

        if ($opts->{load_descriptions}) {
            $info->{description} = \%minfodesc;
            my $descstring = join( '', map { pack( "Z*N", $minfodesc{$_}, $_ ) } keys %minfodesc );

            my $memkey = [$u->userid, "upicdes:" . $u->userid];
            LJ::MemCache::set( $memkey, $descstring );

            $info->{_has_descriptions} = 1;
        }
    }

    $LJ::CACHE_USERPIC_INFO{$u->userid} = $info;
    return $info;
}

=head3 C<< $u->get_userpic_kw_map >>

Gets a mapping from userpic ids to keywords for this User.

=cut
sub get_userpic_kw_map {
    my ( $u ) = @_;

    return $u->{picid_kw_map} if $u->{picid_kw_map};  # cache

    my $picinfo = $u->get_userpic_info( { load_comments => 0 } );
    my $keywords = {};
    foreach my $keyword ( keys %{$picinfo->{kw}} ) {
        my $picid = $picinfo->{kw}->{$keyword}->{picid};
        $keywords->{$picid} = [] unless $keywords->{$picid};
        push @{$keywords->{$picid}}, $keyword if ( $keyword && $picid && $keyword !~ m/^pic\#(\d+)$/ );
    }

    return $u->{picid_kw_map} = $keywords;
}

=head3 C<< $u->mogfs_userpic_key( $pic ) >>

Make a mogilefs key for the given pic for the user.

Arguments:

=over 4

=item pic

Either the userpic hash or the picid of the userpic.

=back

=cut
sub mogfs_userpic_key {
    my $self = shift or return undef;
    my $pic = shift or croak "missing required arg: userpic";

    my $picid = ref $pic ? $pic->{picid} : $pic+0;
    return "up:" . $self->userid . ":$picid";
}

=head3 C<< $u->resolve_mapid_redirects( $mapid, %opts ) >>

Resolve any mapid redirect, guarding against any redirect loops.

Returns: new map id, or 0 if the mapping cannot be resolved.

Arguments:

=over 4

=item mapid

=back

Additional options:

=over 4

=item redir_callback

Called if the mapping is redirected to another mapping with the following arguments

( $u, $old_mapid, $new_mapid )

=back

=cut
sub resolve_mapid_redirects {
    my ( $u, $mapid, %opts ) = @_;

    my $info = LJ::isu( $u ) ? $u->get_userpic_info : undef;
    return 0 unless $info;

    my %seen = ( $mapid => 1 );
    my $orig_id = $mapid;

    while ( $info->{map_redir}->{ $mapid } ) {
        $orig_id = $mapid;
        $mapid = $info->{map_redir}->{ $mapid };

        # To implement lazy updating or the like
        $opts{redir_callback}->($u, $orig_id, $mapid) if $opts{redir_callback};

        # This should never happen, but am checking it here mainly in case
        # never *does* happen, so we don't hang the web process with an endless loop.
        if ( $seen{$mapid}++ ) {
            warn("userpicmap3 redirectloop for " . $u->id . " on mapid " . $mapid);
            return 0;
        }
    }

    return $mapid;
}

=head3 C<< $u->userpic >>

Returns LJ::Userpic for default userpic, if it exists.

=cut
sub userpic {
    my $u = shift;
    return undef unless $u->{defaultpicid};
    return LJ::Userpic->new($u, $u->{defaultpicid});
}

=head3 C<< $u->userpic_have_mapid >>

Returns true if the userpicmap keyword mappings have a mapid column ( dversion 9 or higher )

=cut
# FIXME: This probably should be userpics_use_mapid
sub userpic_have_mapid {
    return $_[0]->dversion >= 9;
}

=head3 C<< $u->userpic_quota >>

Returns the number of userpics the user can upload (base account type cap + bonus slots purchased)

=cut
sub userpic_quota {
    my $u = shift or return undef;
    my $ct = $u->get_cap( 'userpics' );
    $ct += $u->prop('bonus_icons') // 0
        if $u->is_paid; # paid accounts get bonus icons
    return min( $ct, $LJ::USERPIC_MAXIMUM );
}

# Intentionally no POD here.
# This is an internal helper method
# takes a $kwid and $picid ( either can be undef )
# and creates a mapid row for it
sub _create_mapid {
    my ( $u, $kwid, $picid ) = @_;
    return 0 unless $u->userpic_have_mapid;

    my $mapid = LJ::alloc_user_counter($u,'Y');
    $u->do( "INSERT INTO userpicmap3 (userid, mapid, kwid, picid) VALUES (?,?,?,?)", undef, $u->id, $mapid, $kwid, $picid);
    return 0 if $u->err;

    LJ::Userpic->delete_cache($u);
    $u->clear_userpic_kw_map;

    return $mapid;
}

########################################################################
###  99. Miscellaneous Legacy Items

# return true if we know user is a minor (< 18)
sub is_minor {
    my $self = shift;
    my $age = $self->best_guess_age;
    return 0 unless $age;
    return 1 if ($age < 18);
    return 0;
}


########################################################################
###  99B. Deprecated (FIXME: we shouldn't need these)


# THIS IS DEPRECATED DO NOT USE
sub email {
    my ($u, $remote) = @_;
    return $u->emails_visible($remote);
}


# FIXME: Needs updating for WTF
sub opt_showmutualfriends {
    my $u = shift;
    return $u->raw_prop('opt_showmutualfriends') ? 1 : 0;
}

# FIXME: Needs updating for WTF
# only certain journaltypes can show mutual friends
sub show_mutualfriends {
    my $u = shift;

    return 0 unless $u->is_individual;
    return $u->opt_showmutualfriends ? 1 : 0;
}




########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

use Carp;

########################################################################
### Please keep these categorized and alphabetized for ease of use.
### If you need a new category, add it at the end.
### Categories kinda fuzzy, but better than nothing. Weird numbers are
### to match the sections above -- please check up there if adding.
###
### Categories:
###  3. Working with All Types of Accounts
###  4. Login, Session, and Rename Functions
###  5. Database and Memcache Functions
###  6. What the App Shows to Users
###  9. Logging and Recording Actions
###  15. Email-Related Functions
###  16. Entry-Related Functions
###  19. OpenID and Identity Functions
###  23. Relationship Functions
###  24. Styles and S2-Related Functions

########################################################################
###  2. Working with All Types of Accounts

=head2 Working with All Types of Accounts (LJ)
=cut

# <LJFUNC>
# name: LJ::canonical_username
# des: normalizes username.
# info:
# args: user
# returns: the canonical username given, or blank if the username is not well-formed
# </LJFUNC>
sub canonical_username
{
    my $input = lc( $_[0] );
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
    $url = "http://$url" unless $url =~ m!^http://!;
    $url .= "/" unless $url =~ m!/$!;

    # get from memcache
    {
        # overload the uidof memcache key to accept both display name and name
        my $uid = LJ::MemCache::get( "uidof:$url" );
        my $u = $uid ? LJ::memcache_get_u( [ $uid, "userid:$uid" ] ) : undef;
        return _set_u_req_cache( $u ) if $u;
    }

    my $dbh = LJ::get_db_writer();
    my $uid = $dbh->selectrow_array("SELECT userid FROM identitymap WHERE idtype=? AND identity=?",
                                    undef, 'O', $url);

    my $u = $uid ? LJ::load_userid($uid) : undef;

    # set user in memcache
    if ( $u ) {
        # memcache URL-to-userid for identity users
        LJ::MemCache::set( "uidof:$url", $uid, 1800 );
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
sub load_userids
{
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
sub want_user
{
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
sub want_userid
{
    my $uuserid = shift;
    return ($uuserid->{userid} + 0) if ref $uuserid;
    return ($uuserid + 0);
}


########################################################################
###  3. Login, Session, and Rename Functions

=head2 Login, Session, and Rename Functions (LJ)
=cut

sub get_active_journal
{
    return $LJ::ACTIVE_JOURNAL;
}

# <LJFUNC>
# name: LJ::get_authas_user
# des: Given a username, will return a user object if remote is an admin for the
#      username.  Otherwise returns undef.
# returns: user object if authenticated, otherwise undef.
# args: user
# des-opts: Username of user to attempt to auth as.
# </LJFUNC>
sub get_authas_user {
    my $user = $_[0];
    return undef unless $user;

    # get a remote
    my $remote = LJ::get_remote();
    return undef unless $remote;

    # remote is already what they want?
    return $remote if $remote->user eq $user;

    # load user and authenticate
    my $u = LJ::load_user($user);
    return undef unless $u;
    return undef unless $u->{clusterid};

    # does $remote have admin access to $u?
    return undef unless $remote->can_manage( $u );

    # passed all checks, return $u
    return $u;
}

# returns either $remote or the authenticated user that $remote is working with
sub get_effective_remote {
    my $authas_arg = shift || "authas";

    return undef unless LJ::is_web_context();

    my $remote = LJ::get_remote();
    return undef unless $remote;

    my $authas = $BMLCodeBlock::GET{authas} || $BMLCodeBlock::POST{authas} || $remote->user;
    return $remote if $authas eq $remote->user;

    return LJ::get_authas_user($authas);
}


# <LJFUNC>
# name: LJ::get_remote
# des: authenticates the user at the remote end based on their cookies
#      and returns a hashref representing them.
# args: opts?
# des-opts: 'criterr': scalar ref to set critical error flag.  if set, caller
#           should stop processing whatever it's doing and complain
#           about an invalid login with a link to the logout page.
#           'ignore_ip': ignore IP address of remote for IP-bound sessions
# returns: hashref containing 'user' and 'userid' if valid user, else
#          undef.
# </LJFUNC>
sub get_remote
{
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    return $LJ::CACHE_REMOTE if $LJ::CACHED_REMOTE && ! $opts->{'ignore_ip'};

    my $no_remote = sub {
        LJ::User->set_remote(undef);
        return undef;
    };

    # can't have a remote user outside of web context
    my $r = eval { BML::get_request(); };
    return $no_remote->() unless $r;

    my $criterr = $opts->{criterr} || do { my $d; \$d; };
    $$criterr = 0;

    $LJ::CACHE_REMOTE_BOUNCE_URL = "";

    # set this flag if any of their ljsession cookies contained the ".FS"
    # opt to use the fast server.  if we later find they're not logged
    # in and set it, or set it with a free account, then we give them
    # the invalid cookies error.
    my $tried_fast = 0;
    my $sessobj = LJ::Session->session_from_cookies(tried_fast   => \$tried_fast,
                                                    redirect_ref => \$LJ::CACHE_REMOTE_BOUNCE_URL,
                                                    ignore_ip    => $opts->{ignore_ip},
                                                    );

    my $u = $sessobj ? $sessobj->owner : undef;

    # inform the caller that this user is faking their fast-server cookie
    # attribute.
    if ($tried_fast && ! LJ::get_cap($u, "fastserver")) {
        $$criterr = 1;
    }

    return $no_remote->() unless $sessobj;

    # renew soon-to-expire sessions
    $sessobj->try_renew;

    # augment hash with session data;
    $u->{'_session'} = $sessobj;

    # keep track of activity for the user we just loaded from db/memcache
    # - if necessary, this code will actually run in Apache's cleanup handler
    #   so latency won't affect the user
    if ( @LJ::MEMCACHE_SERVERS && LJ::is_enabled('active_user_tracking') ) {
        push @LJ::CLEANUP_HANDLERS, sub { $u->note_activity('A') };
    }

    LJ::User->set_remote($u);
    $r->notes->{ljuser} = $u->user;
    return $u;
}


sub handle_bad_login
{
    my ($u, $ip) = @_;
    return 1 unless $u;

    $ip ||= LJ::get_remote_ip();
    return 1 unless $ip;

    # an IP address is permitted such a rate of failures
    # until it's banned for a period of time.
    my $udbh;
    if (! $u->rate_log( "failed_login", 1, { limit_by_ip => $ip } ) &&
        ($udbh = LJ::get_cluster_master($u)))
    {
        $udbh->do("REPLACE INTO loginstall (userid, ip, time) VALUES ".
                  "(?,INET_ATON(?),UNIX_TIMESTAMP())", undef, $u->userid, $ip);
    }
    return 1;
}


sub login_ip_banned
{
    my ($u, $ip) = @_;
    return 0 unless $u;

    $ip ||= LJ::get_remote_ip();
    return 0 unless $ip;

    my $udbr;
    my $rateperiod = LJ::get_cap($u, "rateperiod-failed_login");
    if ($rateperiod && ($udbr = LJ::get_cluster_reader($u))) {
        my $bantime = $udbr->selectrow_array( "SELECT time FROM loginstall WHERE ".
                                              "userid=? AND ip=INET_ATON(?)",
                                              undef, $u->userid, $ip );
        if ($bantime && $bantime > time() - $rateperiod) {
            return 1;
        }
    }
    return 0;
}


# returns URL we have to bounce the remote user to in order to
# get their domain cookie
sub remote_bounce_url {
    return $LJ::CACHE_REMOTE_BOUNCE_URL;
}


sub set_active_journal
{
    $LJ::ACTIVE_JOURNAL = shift;
}


sub set_remote {
    my $remote = shift;
    LJ::User->set_remote($remote);
    1;
}


sub unset_remote
{
    LJ::User->unset_remote;
    1;
}


########################################################################
###  5. Database and Memcache Functions

=head2 Database and Memcache Functions (LJ)
=cut

sub memcache_get_u
{
    my @keys = @_;
    my @ret;
    foreach my $ar (values %{LJ::MemCache::get_multi(@keys) || {}}) {
        my $row = LJ::MemCache::array_to_hash("user", $ar)
            or next;
        my $u = LJ::User->new_from_row($row);
        push @ret, $u;
    }
    return wantarray ? @ret : $ret[0];
}


# <LJFUNC>
# name: LJ::memcache_kill
# des: Kills a memcache entry, given a userid and type.
# args: uuserid, type
# des-uuserid: a userid or u object
# des-type: memcached key type, will be used as "$type:$userid"
# returns: results of LJ::MemCache::delete
# </LJFUNC>
sub memcache_kill {
    my ($uuid, $type) = @_;
    my $userid = LJ::want_userid($uuid);
    return undef unless $userid && $type;

    return LJ::MemCache::delete([$userid, "$type:$userid"]);
}


sub memcache_set_u
{
    my $u = shift;
    return unless $u;
    my $expire = time() + 1800;
    my $ar = LJ::MemCache::hash_to_array("user", $u);
    return unless $ar;
    LJ::MemCache::set( [$u->userid, "userid:" . $u->userid], $ar, $expire );
    LJ::MemCache::set( "uidof:" . $u->user, $u->userid );
}


# FIXME: this should go away someday... see bug 2760
sub update_user
{
    my ( $u, $ref ) = @_;
    $u = LJ::want_user( $u ) or return 0;
    my $uid = $u->id;

    my @sets;
    my @bindparams;
    my $used_raw = 0;
    while (my ($k, $v) = each %$ref) {
        if ($k eq "raw") {
            $used_raw = 1;
            push @sets, $v;
        } elsif ($k eq 'email') {
            LJ::set_email( $uid, $v );
        } elsif ($k eq 'password') {
            $u->set_password( $v );
        } else {
            push @sets, "$k=?";
            push @bindparams, $v;
        }
    }
    return 1 unless @sets;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;
    {
        local $" = ",";
        my $where = "userid=$uid";
        $dbh->do("UPDATE user SET @sets WHERE $where", undef,
                 @bindparams);
        return 0 if $dbh->err;
    }
    if (@LJ::MEMCACHE_SERVERS) {
        LJ::memcache_kill( $uid, "userid" );
    }

    if ($used_raw) {
        # for a load of userids from the master after update
        # so we pick up the values set via the 'raw' option
        LJ::DB::require_master( sub { LJ::load_userid($uid) } );
    } else {
        while ( my ($k, $v) = each %$ref ) {
            my $cache = $LJ::REQ_CACHE_USER_ID{$uid} or next;
            $cache->{$k} = $v;
        }
    }

    # log this update
    LJ::Hooks::run_hooks( "update_user", userid => $uid, fields => $ref );

    return 1;
}


# <LJFUNC>
# name: LJ::wipe_major_memcache
# des: invalidate all major memcache items associated with a given user.
# args: u
# returns: nothing
# </LJFUNC>
sub wipe_major_memcache
{
    my $u = shift;
    my $userid = LJ::want_userid($u);
    foreach my $key ("userid","bio","talk2ct","talkleftct","log2ct",
                     "log2lt","memkwid","dayct2","s1overr","s1uc","fgrp",
                     "wt_edges","wt_edges_rev","tu","upicinf","upiccom",
                     "upicurl", "upicdes", "intids", "memct", "lastcomm")
    {
        LJ::memcache_kill($userid, $key);
    }
}

# <LJFUNC>
# name: LJ::_load_user_raw
# des-db:  $dbh/$dbr
# des-key:  either "userid" or "user"  (the WHERE part)
# des-vals: value or arrayref of values for key to match on
# des-hook: optional code ref to run for each $u
# returns: last $u found
sub _load_user_raw
{
    my ($db, $key, $vals, $hook) = @_;
    $hook ||= sub {};
    $vals = [ $vals ] unless ref $vals eq "ARRAY";

    my $use_isam;
    unless ($LJ::CACHE_NO_ISAM{user} || scalar(@$vals) > 10) {
        eval { $db->do("HANDLER user OPEN"); };
        if ($@ || $db->err) {
            $LJ::CACHE_NO_ISAM{user} = 1;
        } else {
            $use_isam = 1;
        }
    }

    my $last;

    if ($use_isam) {
        $key = "PRIMARY" if $key eq "userid";
        foreach my $v (@$vals) {
            my $sth = $db->prepare("HANDLER user READ `$key` = (?) LIMIT 1");
            $sth->execute($v);
            my $row = $sth->fetchrow_hashref;
            if ($row) {
                my $u = LJ::User->new_from_row($row);
                $hook->($u);
                $last = $u;
            }
        }
        $db->do("HANDLER user close");
    } else {
        my $in = join(", ", map { $db->quote($_) } @$vals);
        my $sth = $db->prepare("SELECT * FROM user WHERE $key IN ($in)");
        $sth->execute;
        while (my $row = $sth->fetchrow_hashref) {
            my $u = LJ::User->new_from_row($row);
            $hook->($u);
            $last = $u;
        }
    }

    return $last;
}


sub _set_u_req_cache {
    my $u = shift or die "no u to set";

    # if we have an existing user singleton, upgrade it with
    # the latested data, but keep using its address
    if ( my $eu = $LJ::REQ_CACHE_USER_ID{$u->userid} ) {
        LJ::assert_is( $eu->userid, $u->userid );
        $eu->selfassert;
        $u->selfassert;

        $eu->{$_} = $u->{$_} foreach keys %$u;
        $u = $eu;
    }
    $LJ::REQ_CACHE_USER_NAME{$u->user} = $u;
    $LJ::REQ_CACHE_USER_ID{$u->userid} = $u;
    return $u;
}


########################################################################
###  6. What the App Shows to Users

=head2 What the App Shows to Users (LJ)
=cut

# <LJFUNC>
# name: LJ::get_times_multi
# des: Get the last update time and time create.
# args: opt?, uids
# des-opt: optional hashref, currently can contain 'memcache_only'
#          to only retrieve data from memcache
# des-uids: list of userids to load timeupdate and timecreate for
# returns: hashref; uid => {timeupdate => unix timeupdate, timecreate => unix timecreate}
# </LJFUNC>
sub get_times_multi {
    my ($opt, @uids) = @_;

    # allow optional opt hashref as first argument
    unless (ref $opt eq 'HASH') {
        push @uids, $opt;
        $opt = {};
    }
    return {} unless @uids;

    my @memkeys = map { [$_, "tu:$_"], [$_, "tc:$_"] } @uids;
    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    my @need  = ();
    my %times = ();
    foreach my $uid (@uids) {
        my ($tc, $tu) = ('', '');
        if ($tu = $mem->{"tu:$uid"}) {
            $times{updated}->{$uid} = unpack("N", $tu);
        }
        if ($tc = $mem->{"tc:$_"}){
            $times{created}->{$_} = $tc;
        }

        push @need => $uid
            unless $tc and $tu;
    }

    # if everything was in memcache, return now
    return \%times if $opt->{'memcache_only'} or not @need;

    # fill in holes from the database.  safe to use the reader because we
    # only do an add to memcache, whereas postevent does a set, overwriting
    # any potentially old data
    my $dbr = LJ::get_db_reader();
    my $need_bind = join(",", map { "?" } @need);

    # Fetch timeupdate and timecreate from DB.
    # Timecreate is loaded in pre-emptive goals.
    # This is tiny optimization for 'get_timecreate_multi',
    # which is called right after this method during
    # friends page generation.
    my $sth = $dbr->prepare("
        SELECT userid,
               UNIX_TIMESTAMP(timeupdate),
               UNIX_TIMESTAMP(timecreate)
        FROM   userusage
        WHERE
               userid IN ($need_bind)");
    $sth->execute(@need);
    while (my ($uid, $tu, $tc) = $sth->fetchrow_array){
        $times{updated}->{$uid} = $tu;
        $times{created}->{$uid} = $tc;

        # set memcache for this row
        LJ::MemCache::add([$uid, "tu:$uid"], pack("N", $tu), 30*60);
        # set this for future use
        LJ::MemCache::add([$uid, "tc:$uid"], $tc, 60*60*24); # as in LJ::User->timecreate
    }

    return \%times;
}


# <LJFUNC>
# name: LJ::get_timeupdate_multi
# des: Get the last time a list of users updated.
# args: opt?, uids
# des-opt: optional hashref, currently can contain 'memcache_only'
#          to only retrieve data from memcache
# des-uids: list of userids to load timeupdates for
# returns: hashref; uid => unix timeupdate
# </LJFUNC>
sub get_timeupdate_multi {
    my ($opt, @uids) = @_;

    # allow optional opt hashref as first argument
    if ( $opt && ref $opt ne 'HASH' ) {
        push @uids, $opt;
        $opt = {};
    }
    return {} unless @uids;

    my @memkeys = map { [$_, "tu:$_"] } @uids;
    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    my @need;
    my %timeupdate; # uid => timeupdate
    foreach (@uids) {
        if ($mem->{"tu:$_"}) {
            $timeupdate{$_} = unpack("N", $mem->{"tu:$_"});
        } else {
            push @need, $_;
        }
    }

    # if everything was in memcache, return now
    return \%timeupdate if $opt->{'memcache_only'} || ! @need;

    # fill in holes from the database.  safe to use the reader because we
    # only do an add to memcache, whereas postevent does a set, overwriting
    # any potentially old data
    my $dbr = LJ::get_db_reader();
    my $need_bind = join(",", map { "?" } @need);
    my $sth = $dbr->prepare("SELECT userid, UNIX_TIMESTAMP(timeupdate) " .
                            "FROM userusage WHERE userid IN ($need_bind)");
    $sth->execute(@need);
    while (my ($uid, $tu) = $sth->fetchrow_array) {
        $timeupdate{$uid} = $tu;

        # set memcache for this row
        LJ::MemCache::add([$uid, "tu:$uid"], pack("N", $tu), 30*60);
    }

    return \%timeupdate;
}


# <LJFUNC>
# name: LJ::get_timezone
# des: Gets the timezone offset for the user.
# args: u, offsetref, fakedref
# des-u: user object.
# des-offsetref: reference to scalar to hold timezone offset;
# des-fakedref: reference to scalar to hold whether this timezone was
#               faked.  0 if it is the timezone specified by the user.
# returns: nonzero if successful.
# </LJFUNC>
sub get_timezone {
    my ($u, $offsetref, $fakedref) = @_;

    # See if the user specified their timezone
    if (my $tz = $u->prop('timezone')) {
        # If the eval fails, we'll fall through to guessing instead
        my $dt = eval {
            DateTime->from_epoch(
                                 epoch => time(),
                                 time_zone => $tz,
                                 );
        };

        if ($dt) {
            $$offsetref = $dt->offset() / (60 * 60); # Convert from seconds to hours
            $$fakedref  = 0 if $fakedref;

            return 1;
        }
    }

    # Either the user hasn't set a timezone or we failed at
    # loading it.  We guess their current timezone's offset
    # by comparing the gmtime of their last post with the time
    # they specified on that post.

    # first, check request cache
    my $timezone = $u->{_timezone_guess};
    if ($timezone) {
        $$offsetref = $timezone;
        return 1;
    }

    # next, check memcache
    my $memkey = [$u->userid, 'timezone_guess:' . $u->userid];
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $u->{_timezone_guess} = $memcache_data;
        $$offsetref = $memcache_data;
        return 1;
    }

    # nothing in cache; check db
    my $dbcr = LJ::get_cluster_def_reader($u);
    return 0 unless $dbcr;

    $$fakedref = 1 if $fakedref;

    # grab the times on the last post that wasn't backdated.
    # (backdated is rlogtime == $LJ::EndOfTime)
    if (my $last_row = $dbcr->selectrow_hashref(
        qq{
            SELECT rlogtime, eventtime
            FROM log2
            WHERE journalid = ? AND rlogtime <> ?
            ORDER BY rlogtime LIMIT 1
        }, undef, $u->userid, $LJ::EndOfTime)) {
        my $logtime = $LJ::EndOfTime - $last_row->{'rlogtime'};
        my $eventtime = LJ::mysqldate_to_time($last_row->{'eventtime'}, 1);
        my $hourdiff = ($eventtime - $logtime) / 3600;

        # if they're up to a quarter hour behind, round up.
        $hourdiff = $hourdiff > 0 ? int($hourdiff + 0.25) : int($hourdiff - 0.25);

        # if the offset is more than 24h in either direction, then the last
        # entry is probably unreliable. don't use any offset at all.
        $$offsetref = (-24 < $hourdiff && $hourdiff < 24) ? $hourdiff : 0;

        # set the caches
        $u->{_timezone_guess} = $$offsetref;
        my $expire = 60*60*24; # 24 hours
        LJ::MemCache::set($memkey, $$offsetref, $expire);
    }

    return 1;
}


# <LJFUNC>
# class: component
# name: LJ::ljuser
# des: Make link to profile/journal of user.
# info: Returns the HTML for a profile/journal link pair for a given user
#       name, just like LJUSER does in BML.  This is for files like cleanhtml.pl
#       and ljpoll.pl which need this functionality too, but they aren't run as BML.
# args: user, opts?
# des-user: Username to link to, or user hashref.
# des-opts: Optional hashref to control output.  Key 'full' when true causes
#           a link to the mode=full profile.   Key 'type' when 'C' makes
#           a community link, when 'Y' makes a syndicated account link,
#           when 'I' makes an identity account link (e.g. OpenID),
#           otherwise makes a user account
#           link. If user parameter is a hashref, its 'journaltype' overrides
#           this 'type'.  Key 'del', when true, makes a tag for a deleted user.
#           If user parameter is a hashref, its 'statusvis' overrides 'del'.
#           Key 'no_follow', when true, disables traversal of renamed users.
# returns: HTML with a little head image & bold text link.
# </LJFUNC>
sub ljuser
{
    my ( $user, $opts ) = @_;

    my $andfull = $opts->{'full'} ? "?mode=full" : "";
    my $img = $opts->{'imgroot'} || $LJ::IMGPREFIX;
    my $profile_url = $opts->{'profile_url'} || '';
    my $journal_url = $opts->{'journal_url'} || '';
    my $display_class = $opts->{no_ljuser_class} ? "" : " class='ljuser'";
    my $profile;

    my $make_tag = sub {
        my ($fil, $url, $x, $y, $type) = @_;
        $y ||= $x;  # make square if only one dimension given
        my $strike = $opts->{'del'} ? ' text-decoration: line-through;' : '';

        # Backwards check, because we want it to default to on
        my $bold = (exists $opts->{'bold'} and $opts->{'bold'} == 0) ? 0 : 1;
        my $ljusername = $bold ? "<b>$user</b>" : "$user";
        my $lj_user = $opts->{no_ljuser_class} ? "" : " lj:user='$user'";

        my $alttext = $type ? "$type profile" : "profile";

        my $link_color = "";
        # Make sure it's really a color
        if ($opts->{'link_color'} && $opts->{'link_color'} =~ /^#([a-fA-F0-9]{3}|[a-fA-F0-9]{6})$/) {
            $link_color = " style='color: " . $opts->{'link_color'} . ";'";
        }

        $profile = $profile_url ne '' ? $profile_url : $profile . $andfull;
        $url = $journal_url ne '' ? $journal_url : $url;

        return "<span$lj_user style='white-space: nowrap;$strike'$display_class>" .
            "<a href='$profile'><img src='$img/$fil' alt='[$alttext] ' width='$x' height='$y'" .
            " style='vertical-align: text-bottom; border: 0; padding-right: 1px;' /></a>" .
            "<a href='$url'$link_color>$ljusername</a></span>";
    };

    my $u = isu($user) ? $user : LJ::load_user($user);

    # Traverse the renames to the final journal
    if ($u && !$opts->{'no_follow'}) {
        ( $u, $user ) = $u->get_renamed_user;
    }

    # if invalid user, link to dummy userinfo page
    unless ($u && isu($u)) {
        $user = LJ::canonical_username($user);
        $profile = "$LJ::SITEROOT/profile?user=$user";
        return $make_tag->('silk/identity/user.png', "$LJ::SITEROOT/profile?user=$user", 17);
    }

    $profile = $u->profile_url;

    my $type = $u->journaltype;
    my $type_readable = $u->journaltype_readable;

    # Mark accounts as deleted that aren't visible, memorial, locked, or read-only
    $opts->{'del'} = 1 unless $u->is_visible || $u->is_memorial || $u->is_locked || $u->is_readonly;
    $user = $u->user;

    my $url = $u->journal_base . "/";
    my $head_size = $opts->{head_size};

    if (my ($icon, $size) = LJ::Hooks::run_hook("head_icon", $u, head_size => $head_size)) {
        return $make_tag->($icon, $url, $size || 16) if $icon;
    }

    if ( $type eq 'C' ) {
        if ( $u->get_cap( 'staff_headicon' ) ) {
            return $make_tag->( "silk/${head_size}/comm_staff.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'comm_staff.png', $url, 16, '', 'site community' );
        } else {
            return $make_tag->( "silk/${head_size}/community.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'silk/identity/community.png', $url, 16, '', $type_readable );
        }
    } elsif ( $type eq 'Y' ) {
        return $make_tag->( "silk/${head_size}/feed.png", $url, $head_size, '', $type_readable ) if $head_size;
        return $make_tag->( 'silk/identity/feed.png', $url, 16, '', $type_readable );
    } elsif ( $type eq 'I' ) {
        return $u->ljuser_display($opts);
    } else {
        if ( $u->get_cap( 'staff_headicon' ) ) {
            return $make_tag->( "silk/${head_size}/user_staff.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'silk/identity/user_staff.png', $url, 17, '', 'staff' );
        }
        else {
            return $make_tag->( "silk/${head_size}/user.png", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'silk/identity/user.png', $url, 17, '', $type_readable );
        }
    }
}


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


########################################################################
###  15. Email-Related Functions

=head2 Email-Related Functions (LJ)
=cut

# <LJFUNC>
# name: LJ::check_email
# des: checks for and rejects bogus e-mail addresses.
# info: Checks that the address is of the form username@some.domain,
#        does not contain invalid characters. in the username, is a valid domain.
#       Also checks for mis-spellings of common webmail providers,
#       and web addresses instead of an e-mail address.
# args:
# returns: nothing on success, or error with error message if invalid/bogus e-mail address
# </LJFUNC>
sub check_email
{
    my ($email, $errors) = @_;

    # Trim off whitespace and force to lowercase.
    $email =~ s/^\s+//;
    $email =~ s/\s+$//;
    $email = lc $email;

    my $reject = sub {
        my $errcode = shift;
        my $errmsg = shift;
        # TODO: add $opts to end of check_email and make option
        #       to either return error codes, or let caller supply
        #       a subref to resolve error codes into native language
        #       error messages (probably via BML::ML hash, or something)
        push @$errors, $errmsg;
        return;
    };

    # Empty email addresses are not good.
    unless ($email) {
        return $reject->("empty",
                         "Your email address cannot be blank.");
    }

    # Check that the address is of the form username@some.domain.
    my ($username, $domain);
    if ($email =~ /^([^@]+)@([^@]+)/) {
        $username = $1;
        $domain = $2;
    } else {
        return $reject->("bad_form",
                         "You did not give a valid email address.  An email address looks like username\@some.domain");
    }

    # Check the username for invalid characters.
    unless ($username =~ /^[^\s\",;\(\)\[\]\{\}\<\>]+$/) {
        return $reject->("bad_username",
                         "You have invalid characters in your email address username.");
    }

    # Check the domain name.
    unless ($domain =~ /^[\w-]+(\.[\w-]+)*\.(ac|ad|ae|aero|af|ag|ai|al|am|an|ao|aq|ar|arpa|as|at|au|aw|az|ba|bb|bd|be|bf|bg|bh|bi|biz|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cd|cf|cg|ch|ci|ck|cl|cm|cn|co|com|coop|cr|cu|cv|cx|cy|cz|de|dj|dk|dm|do|dz|ec|edu|ee|eg|er|es|et|eu|fi|fj|fk|fm|fo|fr|ga|gb|gd|ge|gf|gg|gh|gi|gl|gm|gn|gov|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|info|int|io|iq|ir|is|it|je|jm|jo|jp|ke|kg|kh|ki|km|kn|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc|md|me|mg|mh|mil|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|museum|mv|mw|mx|my|mz|na|name|nc|ne|net|nf|ng|ni|nl|no|np|nr|nu|nz|om|org|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|pro|ps|pt|pw|py|qa|re|ro|rs|ru|rw|sa|sb|sc|sd|se|sg|sh|si|sj|sk|sl|sm|sn|so|sr|st|su|sv|sy|sz|tc|td|tf|tg|th|tj|tk|tl|tm|tn|to|tp|tr|tt|tv|tw|tz|ua|ug|uk|um|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za|zm|zw)$/)
    {
        return $reject->("bad_domain",
                         "Your email address domain is invalid.");
    }

    # Catch misspellings of hotmail.com
    if ($domain =~ /^(otmail|hotmial|hotmil|hotamail|hotmaul|hoatmail|hatmail|htomail)\.(cm|co|com|cmo|om)$/ or
        $domain =~ /^hotmail\.(cm|co|om|cmo)$/)
    {
        return $reject->("bad_hotmail_spelling",
                         "You gave $email as your email address.  Are you sure you didn't mean hotmail.com?");
    }

    # Catch misspellings of aol.com
    elsif ($domain =~ /^(ol|aoll)\.(cm|co|com|cmo|om)$/ or
           $domain =~ /^aol\.(cm|co|om|cmo)$/)
    {
        return $reject->("bad_aol_spelling",
                         "You gave $email as your email address.  Are you sure you didn't mean aol.com?");
    }

    # Catch web addresses (two or more w's followed by a dot)
    elsif ($username =~ /^www*\./)
    {
        return $reject->("web_address",
                         "You gave $email as your email address, but it looks more like a web address to me.");
    }
}

sub set_email {
    my ($userid, $email) = @_;

    my $dbh = LJ::get_db_writer();
    if ($LJ::DEBUG{'write_emails_to_user_table'}) {
        $dbh->do("UPDATE user SET email=? WHERE userid=?", undef,
                 $email, $userid);
    }
    $dbh->do("REPLACE INTO email (userid, email) VALUES (?, ?)",
             undef, $userid, $email);

    # update caches
    LJ::memcache_kill($userid, "userid");
    LJ::MemCache::delete([$userid, "email:$userid"]);
    my $cache = $LJ::REQ_CACHE_USER_ID{$userid} or return;
    $cache->{'_email'} = $email;
}


########################################################################
###  19. OpenID and Identity Functions

=head2 OpenID and Identity Functions (LJ)
=cut

# given a LJ userid/u, return a hashref of:
# type, extuser, extuserid
# returns undef if user isn't an externally mapped account.
sub get_extuser_map
{
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
sub get_extuser_uid
{
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


########################################################################
###  23. Relationship Functions

=head2 Relationship Functions (formerly ljrelation.pl)
=cut

# <LJFUNC>
# name: LJ::get_reluser_id
# des: for [dbtable[reluser2]], numbers 1 - 31999 are reserved for
#      livejournal stuff, whereas numbers 32000-65535 are used for local sites.
# info: If you wish to add your own hooks to this, you should define a
#       hook "get_reluser_id" in ljlib-local.pl. No reluser2 [special[reluserdefs]]
#        types can be a single character, those are reserved for
#        the [dbtable[reluser]] table, so we don't have namespace problems.
# args: type
# des-type: the name of the type you're trying to access, e.g. "hide_comm_assoc"
# returns: id of type, 0 means it's not a reluser2 type
# </LJFUNC>
sub get_reluser_id {
    my $type = shift;
    return 0 if length $type == 1; # must be more than a single character
    my $val =
        {
            'hide_comm_assoc' => 1,
        }->{$type}+0;
    return $val if $val;
    return 0 unless $type =~ /^local-/;
    return LJ::Hooks::run_hook('get_reluser_id', $type)+0;
}

# <LJFUNC>
# name: LJ::load_rel_user
# des: Load user relationship information. Loads all relationships of type 'type' in
#      which user 'userid' participates on the left side (is the source of the
#      relationship).
# args: db?, userid, type
# des-userid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_user {
    my $db = LJ::DB::isdb( $_[0] ) ? shift : undef;
    my ($userid, $type) = @_;
    return undef unless $type and $userid;
    my $u = LJ::want_user($userid);
    $userid = LJ::want_userid($userid);
    my $typeid = LJ::get_reluser_id($type)+0;
    if ($typeid) {
        # clustered reluser2 table
        $db = LJ::get_cluster_reader($u);
        return $db->selectcol_arrayref("SELECT targetid FROM reluser2 WHERE userid=? AND type=?",
                                       undef, $userid, $typeid);
    } else {
        # non-clustered reluser global table
        $db ||= LJ::get_db_reader();
        return $db->selectcol_arrayref("SELECT targetid FROM reluser WHERE userid=? AND type=?",
                                       undef, $userid, $type);
    }
}

# <LJFUNC>
# name: LJ::load_rel_user_cache
# des: Loads user relationship information of the type 'type' where user
#      'targetid' participates on the left side (is the source of the relationship)
#      trying memcache first.  The results from this sub should be
#      <strong>treated as inaccurate and out of date</strong>.
# args: userid, type
# des-userid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_user_cache {
    my ($userid, $type) = @_;
    return undef unless $type && $userid;

    my $u = LJ::want_user($userid);
    return undef unless $u;
    $userid = $u->{'userid'};

    my $key = [ $userid, "reluser:$userid:$type" ];
    my $res = LJ::MemCache::get($key);

    return $res if $res;

    $res = LJ::load_rel_user($userid, $type);

    my $exp = time() + 60*30; # 30 min
    LJ::MemCache::set($key, $res, $exp);

    return $res;
}

# <LJFUNC>
# name: LJ::load_rel_target
# des: Load user relationship information. Loads all relationships of type 'type' in
#      which user 'targetid' participates on the right side (is the target of the
#      relationship).
# args: db?, targetid, type
# des-targetid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_target {
    my $db = LJ::DB::isdb( $_[0] ) ? shift : undef;
    my ($targetid, $type) = @_;
    return undef unless $type and $targetid;
    my $u = LJ::want_user($targetid);
    $targetid = LJ::want_userid($targetid);
    my $typeid = LJ::get_reluser_id($type)+0;
    if ($typeid) {
        # clustered reluser2 table
        $db = LJ::get_cluster_reader($u);
        return $db->selectcol_arrayref("SELECT userid FROM reluser2 WHERE targetid=? AND type=?",
                                       undef, $targetid, $typeid);
    } else {
        # non-clustered reluser global table
        $db ||= LJ::get_db_reader();
        return $db->selectcol_arrayref("SELECT userid FROM reluser WHERE targetid=? AND type=?",
                                       undef, $targetid, $type);
    }
}

# <LJFUNC>
# name: LJ::load_rel_target_cache
# des: Loads user relationship information of the type 'type' where user
#      'targetid' participates on the right side (is the target of the relationship)
#      trying memcache first.  The results from this sub should be
#      <strong>treated as inaccurate and out of date</strong>.
# args: targetid, type
# des-userid: userid or a user hash to load relationship information for.
# des-type: type of the relationship
# returns: reference to an array of userids
# </LJFUNC>
sub load_rel_target_cache {
    my ($userid, $type) = @_;
    return undef unless $type && $userid;

    my $u = LJ::want_user($userid);
    return undef unless $u;
    $userid = $u->{'userid'};

    my $key = [ $userid, "reluser_rev:$userid:$type" ];
    my $res = LJ::MemCache::get($key);

    return $res if $res;

    $res = LJ::load_rel_target($userid, $type);

    my $exp = time() + 60*30; # 30 min
    LJ::MemCache::set($key, $res, $exp);

    return $res;
}

# <LJFUNC>
# name: LJ::_get_rel_memcache
# des: Helper function: returns memcached value for a given (userid, targetid, type) triple, if valid.
# args: userid, targetid, type
# des-userid: source userid, nonzero
# des-targetid: target userid, nonzero
# des-type: type (reluser) or typeid (rel2) of the relationship
# returns: undef on failure, 0 or 1 depending on edge existence
# </LJFUNC>
sub _get_rel_memcache {
    return undef unless @LJ::MEMCACHE_SERVERS;
    return undef unless LJ::is_enabled('memcache_reluser');

    my ($userid, $targetid, $type) = @_;
    return undef unless $userid && $targetid && defined $type;

    # memcache keys
    my $relkey  = [$userid,   "rel:$userid:$targetid:$type"]; # rel $uid->$targetid edge
    my $modukey = [$userid,   "relmodu:$userid:$type"      ]; # rel modtime for uid
    my $modtkey = [$targetid, "relmodt:$targetid:$type"    ]; # rel modtime for targetid

    # do a get_multi since $relkey and $modukey are both hashed on $userid
    my $memc = LJ::MemCache::get_multi($relkey, $modukey);
    return undef unless $memc && ref $memc eq 'HASH';

    # [{0|1}, modtime]
    my $rel = $memc->{$relkey->[1]};
    return undef unless $rel && ref $rel eq 'ARRAY';

    # check rel modtime for $userid
    my $relmodu = $memc->{$modukey->[1]};
    return undef if ! $relmodu || $relmodu > $rel->[1];

    # check rel modtime for $targetid
    my $relmodt = LJ::MemCache::get($modtkey);
    return undef if ! $relmodt || $relmodt > $rel->[1];

    # return memcache value if it's up-to-date
    return $rel->[0] ? 1 : 0;
}

# <LJFUNC>
# name: LJ::_set_rel_memcache
# des: Helper function: sets memcache values for a given (userid, targetid, type) triple
# args: userid, targetid, type
# des-userid: source userid, nonzero
# des-targetid: target userid, nonzero
# des-type: type (reluser) or typeid (rel2) of the relationship
# returns: 1 on success, undef on failure
# </LJFUNC>
sub _set_rel_memcache {
    return 1 unless @LJ::MEMCACHE_SERVERS;

    my ($userid, $targetid, $type, $val) = @_;
    return undef unless $userid && $targetid && defined $type;
    $val = $val ? 1 : 0;

    # memcache keys
    my $relkey  = [$userid,   "rel:$userid:$targetid:$type"]; # rel $uid->$targetid edge
    my $modukey = [$userid,   "relmodu:$userid:$type"      ]; # rel modtime for uid
    my $modtkey = [$targetid, "relmodt:$targetid:$type"    ]; # rel modtime for targetid

    my $now = time();
    my $exp = $now + 3600*6; # 6 hour
    LJ::MemCache::set($relkey, [$val, $now], $exp);
    LJ::MemCache::set($modukey, $now, $exp);
    LJ::MemCache::set($modtkey, $now, $exp);

    # Also, delete these keys, since the contents have changed.
    LJ::MemCache::delete([$userid, "reluser:$userid:$type"]);
    LJ::MemCache::delete([$targetid, "reluser_rev:$targetid:$type"]);

    return 1;
}

# <LJFUNC>
# name: LJ::check_rel
# des: Checks whether two users are in a specified relationship to each other.
# args: userid, targetid, type
# des-userid: source userid, nonzero; may also be a user hash.
# des-targetid: target userid, nonzero; may also be a user hash.
# des-type: type of the relationship
# returns: 1 if the relationship exists, 0 otherwise
# </LJFUNC>
sub check_rel {
    my ($userid, $targetid, $type) = @_;
    return undef unless $type && $userid && $targetid;

    my $u = LJ::want_user($userid);
    $userid = LJ::want_userid($userid);
    $targetid = LJ::want_userid($targetid);

    my $typeid = LJ::get_reluser_id($type)+0;
    my $eff_type = $typeid || $type;

    my $key = "$userid-$targetid-$eff_type";
    return $LJ::REQ_CACHE_REL{$key} if defined $LJ::REQ_CACHE_REL{$key};

    # did we get something from memcache?
    my $memval = LJ::_get_rel_memcache($userid, $targetid, $eff_type);
    return $memval if defined $memval;

    # are we working on reluser or reluser2?
    my ( $db, $table );
    if ($typeid) {
        # clustered reluser2 table
        $db = LJ::get_cluster_reader($u);
        $table = "reluser2";
    } else {
        # non-clustered reluser table
        $db = LJ::get_db_reader();
        $table = "reluser";
    }

    # get data from db, force result to be {0|1}
    my $dbval = $db->selectrow_array("SELECT COUNT(*) FROM $table ".
                                     "WHERE userid=? AND targetid=? AND type=? ",
                                     undef, $userid, $targetid, $eff_type)
        ? 1 : 0;

    # set in memcache
    LJ::_set_rel_memcache($userid, $targetid, $eff_type, $dbval);

    # return and set request cache
    return $LJ::REQ_CACHE_REL{$key} = $dbval;
}

# <LJFUNC>
# name: LJ::set_rel
# des: Sets relationship information for two users.
# args: dbs?, userid, targetid, type
# des-dbs: Deprecated; optional, a master/slave set of database handles.
# des-userid: source userid, or a user hash
# des-targetid: target userid, or a user hash
# des-type: type of the relationship
# returns: 1 if set succeeded, otherwise undef
# </LJFUNC>
sub set_rel {
    my ($userid, $targetid, $type) = @_;
    return undef unless $type and $userid and $targetid;

    my $u = LJ::want_user($userid);
    $userid = LJ::want_userid($userid);
    $targetid = LJ::want_userid($targetid);

    my $typeid = LJ::get_reluser_id($type)+0;
    my $eff_type = $typeid || $type;

    # working on reluser or reluser2?
    my ($db, $table);
    if ($typeid) {
        # clustered reluser2 table
        $db = LJ::get_cluster_master($u);
        $table = "reluser2";
    } else {
        # non-clustered reluser global table
        $db = LJ::get_db_writer();
        $table = "reluser";
    }
    return undef unless $db;

    # set in database
    $db->do("REPLACE INTO $table (userid, targetid, type) VALUES (?, ?, ?)",
            undef, $userid, $targetid, $eff_type);
    return undef if $db->err;

    # set in memcache
    LJ::_set_rel_memcache($userid, $targetid, $eff_type, 1);

    return 1;
}

# <LJFUNC>
# name: LJ::set_rel_multi
# des: Sets relationship edges for lists of user tuples.
# args: edges
# des-edges: array of arrayrefs of edges to set: [userid, targetid, type].
#            Where:
#            userid: source userid, or a user hash;
#            targetid: target userid, or a user hash;
#            type: type of the relationship.
# returns: 1 if all sets succeeded, otherwise undef
# </LJFUNC>
sub set_rel_multi {
    return _mod_rel_multi({ mode => 'set', edges => \@_ });
}

# <LJFUNC>
# name: LJ::clear_rel_multi
# des: Clear relationship edges for lists of user tuples.
# args: edges
# des-edges: array of arrayrefs of edges to clear: [userid, targetid, type].
#            Where:
#            userid: source userid, or a user hash;
#            targetid: target userid, or a user hash;
#            type: type of the relationship.
# returns: 1 if all clears succeeded, otherwise undef
# </LJFUNC>
sub clear_rel_multi {
    return _mod_rel_multi({ mode => 'clear', edges => \@_ });
}

# <LJFUNC>
# name: LJ::_mod_rel_multi
# des: Sets/Clears relationship edges for lists of user tuples.
# args: keys, edges
# des-keys: keys: mode  => {clear|set}.
# des-edges: edges =>  array of arrayrefs of edges to set: [userid, targetid, type]
#            Where:
#            userid: source userid, or a user hash;
#            targetid: target userid, or a user hash;
#            type: type of the relationship.
# returns: 1 if all updates succeeded, otherwise undef
# </LJFUNC>
sub _mod_rel_multi {
    my $opts = shift;
    return undef unless @{$opts->{edges}};

    my $mode = $opts->{mode} eq 'clear' ? 'clear' : 'set';
    my $memval = $mode eq 'set' ? 1 : 0;

    my @reluser  = (); # [userid, targetid, type]
    my @reluser2 = ();
    foreach my $edge (@{$opts->{edges}}) {
        my ($userid, $targetid, $type) = @$edge;
        $userid = LJ::want_userid($userid);
        $targetid = LJ::want_userid($targetid);
        next unless $type && $userid && $targetid;

        my $typeid = LJ::get_reluser_id($type)+0;
        my $eff_type = $typeid || $type;

        # working on reluser or reluser2?
        push @{$typeid ? \@reluser2 : \@reluser}, [$userid, $targetid, $eff_type];
    }

    # now group reluser2 edges by clusterid
    my %reluser2 = (); # cid => [userid, targetid, type]
    my $users = LJ::load_userids(map { $_->[0] } @reluser2);
    foreach (@reluser2) {
        my $cid = $users->{$_->[0]}->{clusterid} or next;
        push @{$reluser2{$cid}}, $_;
    }
    @reluser2 = ();

    # try to get all required cluster masters before we start doing database updates
    my %cache_dbcm = ();
    foreach my $cid (keys %reluser2) {
        next unless @{$reluser2{$cid}};

        # return undef immediately if we won't be able to do all the updates
        $cache_dbcm{$cid} = LJ::get_cluster_master($cid)
            or return undef;
    }

    # if any error occurs with a cluster, we'll skip over that cluster and continue
    # trying to process others since we've likely already done some amount of db
    # updates already, but we'll return undef to signify that everything did not
    # go smoothly
    my $ret = 1;

    # do clustered reluser2 updates
    foreach my $cid (keys %cache_dbcm) {
        # array of arrayrefs: [userid, targetid, type]
        my @edges = @{$reluser2{$cid}};

        # set in database, then in memcache.  keep the two atomic per clusterid
        my $dbcm = $cache_dbcm{$cid};

        my @vals = map { @$_ } @edges;

        if ($mode eq 'set') {
            my $bind = join(",", map { "(?,?,?)" } @edges);
            $dbcm->do("REPLACE INTO reluser2 (userid, targetid, type) VALUES $bind",
                      undef, @vals);
        }

        if ($mode eq 'clear') {
            my $where = join(" OR ", map { "(userid=? AND targetid=? AND type=?)" } @edges);
            $dbcm->do("DELETE FROM reluser2 WHERE $where", undef, @vals);
        }

        # don't update memcache if db update failed for this cluster
        if ($dbcm->err) {
            $ret = undef;
            next;
        }

        # updates to this cluster succeeded, set memcache
        LJ::_set_rel_memcache(@$_, $memval) foreach @edges;
    }

    # do global reluser updates
    if (@reluser) {

        # nothing to do after this block but return, so we can
        # immediately return undef from here if there's a problem
        my $dbh = LJ::get_db_writer()
            or return undef;

        my @vals = map { @$_ } @reluser;

        if ($mode eq 'set') {
            my $bind = join(",", map { "(?,?,?)" } @reluser);
            $dbh->do("REPLACE INTO reluser (userid, targetid, type) VALUES $bind",
                     undef, @vals);
        }

        if ($mode eq 'clear') {
            my $where = join(" OR ", map { "userid=? AND targetid=? AND type=?" } @reluser);
            $dbh->do("DELETE FROM reluser WHERE $where", undef, @vals);
        }

        # don't update memcache if db update failed for this cluster
        return undef if $dbh->err;

        # $_ = [userid, targetid, type] for each iteration
        LJ::_set_rel_memcache(@$_, $memval) foreach @reluser;
    }

    return $ret;
}


# <LJFUNC>
# name: LJ::clear_rel
# des: Deletes a relationship between two users or all relationships of a particular type
#      for one user, on either side of the relationship.
# info: One of userid,targetid -- bit not both -- may be '*'. In that case,
#       if, say, userid is '*', then all relationship edges with target equal to
#       targetid and of the specified type are deleted.
#       If both userid and targetid are numbers, just one edge is deleted.
# args: dbs?, userid, targetid, type
# des-dbs: Deprecated; optional, a master/slave set of database handles.
# des-userid: source userid, or a user hash, or '*'
# des-targetid: target userid, or a user hash, or '*'
# des-type: type of the relationship
# returns: 1 if clear succeeded, otherwise undef
# </LJFUNC>
sub clear_rel {
    my ($userid, $targetid, $type) = @_;
    return undef if $userid eq '*' and $targetid eq '*';

    my $u;
    $u = LJ::want_user($userid) unless $userid eq '*';
    $userid = LJ::want_userid($userid) unless $userid eq '*';
    $targetid = LJ::want_userid($targetid) unless $targetid eq '*';
    return undef unless $type && $userid && $targetid;

    my $typeid = LJ::get_reluser_id($type)+0;

    if ($typeid) {
        # clustered reluser2 table
        return undef unless $u->writer;

        $u->do("DELETE FROM reluser2 WHERE " . ($userid ne '*' ? "userid=$userid AND " : "") .
               ($targetid ne '*' ? "targetid=$targetid AND " : "") . "type=$typeid");

        return undef if $u->err;
    } else {
        # non-clustered global reluser table
        my $dbh = LJ::get_db_writer()
            or return undef;

        my $qtype = $dbh->quote($type);
        $dbh->do("DELETE FROM reluser WHERE " . ($userid ne '*' ? "userid=$userid AND " : "") .
                 ($targetid ne '*' ? "targetid=$targetid AND " : "") . "type=$qtype");

        return undef if $dbh->err;
    }

    # if one of userid or targetid are '*', then we need to note the modtime
    # of the reluser edge from the specified id (the one that's not '*')
    # so that subsequent gets on rel:userid:targetid:type will know to ignore
    # what they got from memcache
    my $eff_type = $typeid || $type;
    if ($userid eq '*') {
        LJ::MemCache::set([$targetid, "relmodt:$targetid:$eff_type"], time());
    } elsif ($targetid eq '*') {
        LJ::MemCache::set([$userid, "relmodu:$userid:$eff_type"], time());

    # if neither userid nor targetid are '*', then just call _set_rel_memcache
    # to update the rel:userid:targetid:type memcache key as well as the
    # userid and targetid modtime keys
    } else {
        LJ::_set_rel_memcache($userid, $targetid, $eff_type, 0);
    }

    return 1;
}

########################################################################
###  24. Styles and S2-Related Functions

=head2 Styles and S2-Related Functions (LJ)
=cut

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
sub journal_base
{
    my ($user, $vhost) = @_;

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
            return "http://$user.$LJ::DOMAIN";
        } else {
            return "http://$rule->[1]/$user";
        }
    }

    if ($vhost eq "users") {
        my $he_user = $user;
        $he_user =~ s/_/-/g;
        return "http://$he_user.$LJ::USER_DOMAIN";
    } elsif ($vhost eq "tilde") {
        return "$LJ::SITEROOT/~$user";
    } elsif ($vhost eq "community") {
        return "$LJ::SITEROOT/community/$user";
    } elsif ($vhost eq "front") {
        return $LJ::SITEROOT;
    } elsif ($vhost =~ /^other:(.+)/) {
        return "http://$1";
    } else {
        return "$LJ::SITEROOT/users/$user";
    }
}


# FIXME: Update to pull out S1 support.
# <LJFUNC>
# name: LJ::make_journal
# class:
# des:
# info:
# args: dbarg, user, view, remote, opts
# des-:
# returns:
# </LJFUNC>
sub make_journal {
    my ($user, $view, $remote, $opts) = @_;

    my $r = DW::Request->get;
    my $geta = $opts->{'getargs'};

    my $u = $opts->{'u'} || LJ::load_user($user);
    unless ($u) {
        $opts->{'baduser'} = 1;
        return "<!-- No such user -->";  # return value ignored
    }
    LJ::set_active_journal($u);

    my ($styleid);
    if ($opts->{'styleid'}) {  # s1 styleid
        confess 'S1 was removed, sorry.';
    } else {

        $view ||= "lastn";    # default view when none specified explicitly in URLs
        if ($LJ::viewinfo{$view} || $view eq "month" ||
            $view eq "entry" || $view eq "reply")  {
            $styleid = -1;    # to get past the return, then checked later for -1 and fixed, once user is loaded.
        } else {
            $opts->{'badargs'} = 1;
        }
    }
    return unless $styleid;


    $u->{'_journalbase'} = $u->journal_base( $opts->{'vhost'} );

    my $eff_view = $LJ::viewinfo{$view}->{'styleof'} || $view;

    my @needed_props = ("stylesys", "s2_style", "url", "urlname", "opt_nctalklinks",
                        "renamedto",  "opt_blockrobots", "opt_usesharedpic", "icbm",
                        "journaltitle", "journalsubtitle", "external_foaf_url",
                        "adult_content", "opt_viewjournalstyle", "opt_viewentrystyle");

    # preload props the view creation code will need later (combine two selects)
    if (ref $LJ::viewinfo{$eff_view}->{'owner_props'} eq "ARRAY") {
        push @needed_props, @{$LJ::viewinfo{$eff_view}->{'owner_props'}};
    }

    $u->preload_props(@needed_props);

    # if the remote is the user to be viewed, make sure the $remote
    # hashref has the value of $u's opt_nctalklinks (though with
    # LJ::load_user caching, this may be assigning between the same
    # underlying hashref)
    $remote->{opt_nctalklinks} = $u->{opt_nctalklinks}
        if $remote && $remote->equals( $u );

    # What style are we shooting for, based on user preferences and get arguments?
    my $stylearg = LJ::determine_viewing_style( $geta, $view, $remote );
    my $stylesys = 1;

    if ($styleid == -1) {

        my $get_styleinfo = sub {

            # forced s2 style id
            if ($geta->{'s2id'}) {

                # get the owner of the requested style
                my $style = LJ::S2::load_style( $geta->{s2id} );
                my $owner = $style && $style->{userid} ? $style->{userid} : 0;

                # remote can use s2id on this journal if:
                # owner of the style is remote or managed by remote OR
                # owner of the style has s2styles cap and remote is viewing owner's journal OR
                # all layers in this style are public (public layer or is_public)

                if ($u->id == $owner && $u->get_cap("s2styles")) {
                    $opts->{'style_u'} = LJ::load_userid($owner);
                    return (2, $geta->{'s2id'});
                }

                if ($remote && $remote->can_manage($owner)) {
                    # check is owned style still available: paid user possible became plus...
                    my $lay_id = $style->{layer}->{layout};
                    my $theme_id = $style->{layer}->{theme};
                    my %lay_info;
                    LJ::S2::load_layer_info(\%lay_info, [$style->{layer}->{layout}, $style->{layer}->{theme}]);

                    if (LJ::S2::can_use_layer($remote, $lay_info{$lay_id}->{redist_uniq})
                        and LJ::S2::can_use_layer($remote, $lay_info{$theme_id}->{redist_uniq})) {
                        $opts->{'style_u'} = LJ::load_userid($owner);
                        return (2, $geta->{'s2id'});
                    } # else this style not allowed by policy
                }

                return ( 2, $geta->{s2id} ) if LJ::S2::style_is_public( $style );
            }

            # style=mine passed in GET or userprop to use mine?
            if ( $remote && $stylearg eq 'mine' ) {
                # get remote props and decide what style remote uses
                $remote->preload_props("stylesys", "s2_style");

                # remote using s2; make sure we pass down the $remote object as the style_u to
                # indicate that they should use $remote to load the style instead of the regular $u
                if ($remote->{'stylesys'} == 2 && $remote->{'s2_style'}) {
                    $opts->{'checkremote'} = 1;
                    $opts->{'style_u'} = $remote;
                    return (2, $remote->{'s2_style'});
                }

                # return stylesys 2; will fall back on default style
                $opts->{style_u} = $remote;
                return ( 2, undef );
            }

            # resource URLs have the styleid in it
            # unless they're a special style, like sitefeeds (which have no styleid)
            # in which case, let them fall through. Something else will handle it
            if ( $view eq "res" && $opts->{'pathextra'} =~ m!^/(\d+)/! && $1 ) {
                return (2, $1);
            }

            # feed accounts have a special style
            if ( $u->is_syndicated && %$LJ::DEFAULT_FEED_STYLE ) {
                return (2, "sitefeeds");
            }

            my $forceflag = 0;
            LJ::Hooks::run_hooks("force_s1", $u, \$forceflag);

            # if none of the above match, they fall through to here
            if ( !$forceflag && $u->{'stylesys'} == 2 ) {
                return (2, $u->{'s2_style'});
            }

            # no special case, let it fall back on the default
            return ( 2, undef );
        };

        ($stylesys, $styleid) = $get_styleinfo->();
    }

    # transcode the tag filtering information into the tag getarg; this has to
    # be done above the s1shortcomings section so that we can fall through to that
    # style for lastn filtered by tags view
    if ($view eq 'lastn' && $opts->{pathextra} && $opts->{pathextra} =~ /^\/tag\/(.+)$/) {
        $opts->{getargs}->{tag} = LJ::durl($1);
        $opts->{pathextra} = undef;
    }

    # do the same for security filtering
    elsif ( ( $view eq 'lastn' || $view eq 'read' ) && $opts->{pathextra} && $opts->{pathextra} =~ /^\/security\/(.*)$/ ) {
        $opts->{getargs}->{security} = LJ::durl($1);
        $opts->{pathextra} = undef;
    }

    $r->note( journalid => $u->userid )
        if $r;

    my $notice = sub {
        my ( $msg, $status ) = @_;

        my $url = "$LJ::SITEROOT/users/$user/";
        $opts->{'status'} = $status if $status;

        my $head = $u->meta_discovery_links( feeds => 1, openid => 1, foaf => 1, remote => $remote );

        return qq{
            <html>
            <head>
            $head
            </head>
            <body>
             <h1>Notice</h1>
             <p>$msg</p>
             <p>Instead, please use <nobr><a href=\"$url\">$url</a></nobr></p>
            </body>
            </html>
        }.("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 50);
    };
    my $error = sub {
        my ( $msg, $status, $header ) = @_;
        $header ||= 'Error';
        $opts->{'status'} = $status if $status;

        return qq{
            <h1>$header</h1>
            <p>$msg</p>
        }.("<!-- xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -->\n" x 50);
    };
    if ( $LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && ! $u->is_redirect &&
        ! LJ::get_cap( $u, "userdomain" ) ) {
        return $notice->( BML::ml( 'error.vhost.nodomain', { user_domain => $LJ::USER_DOMAIN } ) );
    }
    if ($opts->{'vhost'} =~ /^other:/ && ! LJ::get_cap($u, "domainmap")) {
        return $notice->( BML::ml( 'error.vhost.noalias' ) );
    }
    if ($opts->{'vhost'} eq "customview" && ! LJ::get_cap($u, "styles")) {
        return $notice->( BML::ml( 'error.vhost.nostyle' ) );
    }
    if ($opts->{'vhost'} eq "community" && $u->journaltype !~ /[CR]/) {
        $opts->{'badargs'} = 1; # Output a generic 'bad URL' message if available
        return $notice->( BML::ml( 'error.vhost.nocomm' ) );
    }
    if ($view eq "network" && ! LJ::get_cap($u, "friendsfriendsview")) {
        my $inline;
        if ($inline .= LJ::Hooks::run_hook("cprod_inline", $u, 'FriendsFriendsInline')) {
            return $inline;
        } else {
            return BML::ml('cprod.friendsfriendsinline.text3.v1');
        }
    }

    # signal to LiveJournal.pm that we can't handle this
    # FIXME: Make this properly invoke siteviews all the time -- once all the views are ready.
    # Most of this if and tons of messy conditionals can go away once all views are done.
    if ( $stylesys == 1 || $stylearg eq 'site' || $stylearg eq 'light' ) {
        my $fallback = "bml"; # FIXME: Should be S2 once everything's done

        # if we are in this path, and they have style=mine set, it means
        # they either think they can get a S2 styled page but their account
        # type won't let them, or they really want this to fallback to bml
        if ( $remote && ( $stylearg eq 'mine' ) ) {
            $fallback = 'bml';
        }

        # If they specified ?format=light, it means they want a page easy
        # to deal with text-only or on a mobile device.  For now that means
        # render it in the lynx site scheme.
        if ( $stylearg eq 'light' ) {
            $fallback = 'bml';
            DW::SiteScheme->set_for_request( 'lynx' );
        }

        # but if the user specifies which they want, override the fallback we picked
        if ($geta->{'fallback'} && $geta->{'fallback'} =~ /^s2|bml$/) {
            $fallback = $geta->{'fallback'};
        }

        # there are no BML handlers for these views, so force s2
        # FIXME: Temporaray until talkread/talkpost/month views are converted

        if ( !( {   entry => ! LJ::BetaFeatures->user_in_beta( $remote => "s2comments" ),
        reply => ! LJ::BetaFeatures->user_in_beta( $remote => "s2comments" ),
        month => 1 }->{$view} ) ) {
            $fallback = "s2";
        }

        # fall back to legacy BML unless we're using BML-wrapped s2
        if ($fallback eq "bml") {
            ${$opts->{'handle_with_bml_ref'}} = 1;
            return;
        }

        # Render a system-owned S2 style that renders
        # this content, then passes it to get treated as BML
        $stylesys = 2;
        $styleid = "siteviews";
    }

    # now, if there's a GET argument for tags, split those out
    if (exists $opts->{getargs}->{tag}) {
        my $tagfilter = $opts->{getargs}->{tag};

        unless ( $tagfilter ) {
            $opts->{redir} = $u->journal_base . "/tag/";
            return;
        }

        # error if disabled
        return $error->( BML::ml( 'error.tag.disabled' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            unless LJ::is_enabled('tags');

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $error->( BML::ml( 'error.tag.s1' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            if $stylesys == 1 && $view ne 'data' && ! $u->is_redirect;

        # overwrite any tags that exist
        $opts->{tags} = [];
        return $error->( BML::ml( 'error.tag.invalid' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            unless LJ::Tags::is_valid_tagstring($tagfilter, $opts->{tags}, { omit_underscore_check => 1 });

        # get user's tags so we know what remote can see, and setup an inverse mapping
        # from keyword to tag
        $opts->{tagids} = [];
        my $tags = LJ::Tags::get_usertags($u, { remote => $remote });
        my %kwref = ( map { $tags->{$_}->{name} => $_ } keys %{$tags || {}} );

        foreach (@{$opts->{tags}}) {
            return $error->( BML::ml( 'error.tag.undef' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
                unless $kwref{$_};
            push @{$opts->{tagids}}, $kwref{$_};
        }

        my $tagmode = $opts->{getargs}->{mode} || '';
        $opts->{tagmode} = $tagmode eq 'and' ? 'and' : 'or';
        # also allow mode=all (equivalent to 'and')
        $opts->{tagmode} = 'and' if $tagmode eq 'all';
    }

    # validate the security filter
    if (exists $opts->{getargs}->{security}) {
        my $securityfilter = $opts->{getargs}->{security};

        my $r = DW::Request->get;
        my $security_err = sub {
            my ( $args, %opts ) = @_;

            my $status = $opts{status} || $r->NOT_FOUND;

            my @levels;
            my @groups;
            # error message is an appropriate type to show the list
            if ( $opts{show_list}
                # viewing recent entries
                && ( $view eq "lastn"
                    # or your own read page (can't see locked entries on others' read page anyway)
                    || ( $view eq "read" && $u->equals( $remote ) ) ) ) {

                my $path = $view eq "read" ? "/read/security" : "/security";
                @levels  = ( { link => LJ::create_url( "$path/public", viewing_style => 1 ),
                                name_ml => "label.security.public" } );

                if ( $u->is_comm ) {
                    push @levels, { link => LJ::create_url( "$path/access", viewing_style => 1 ),
                                    name_ml => "label.security.members" }
                                if $remote && $remote->member_of( $u );

                    push @levels, { link => LJ::create_url( "$path/private", viewing_style => 1 ),
                                    name_ml => "label.security.maintainers" }
                                if $remote && $remote->can_manage_other( $u );
                } else {
                    push @levels, { link => LJ::create_url( "$path/access", viewing_style => 1 ),
                                    name_ml => "label.security.accesslist" }
                                if $u->trusts( $remote );

                    push @levels, { link => LJ::create_url( "$path/private", viewing_style => 1 ),
                                    name_ml => "label.security.private" }
                                if $u->equals( $remote );
                }

                $args->{levels} = \@levels;

                @groups = map { { link => LJ::create_url( "$path/group:" . $_->{groupname} ), name => $_->{groupname} } } $remote->trust_groups if $u->equals( $remote );
                $args->{groups} = \@groups;
            }

            ${$opts->{handle_with_siteviews_ref}} = 1;
            my $ret = DW::Template->template_string( "journal/security.tt",
                $args,
                {
                    status => $status,
                }
            );
            $opts->{siteviews_extra_content} = $args->{sections};
            return $ret;
        };

        return $security_err->( { message => undef }, show_list => 1 )
            unless $securityfilter;

        return $security_err->( { message => "error.security.nocap2" }, status => $r->FORBIDDEN )
            unless LJ::get_cap( $remote, "security_filter" ) || LJ::get_cap( $u, "security_filter" );

        return $security_err->( { message => "error.security.disabled2" } )
            unless LJ::is_enabled( "security_filter" );

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $security_err->( { message => "error.security.s1.2" } )
            if $stylesys == 1 && $view ne 'data' && ! $u->is_redirect;

        # check the filter itself
        if ( lc( $securityfilter ) eq 'friends' ) {
            $opts->{securityfilter} = 'access';
        } elsif ($securityfilter =~ /^(?:public|access|private)$/i) {
            $opts->{securityfilter} = lc($securityfilter);

        # see if they want to filter by a custom group
        } elsif ( $securityfilter =~ /^group:(.+)$/i && $view eq 'lastn' ) {
            my $tf = $u->trust_groups( name => $1 );
            if ( $tf && ( $u->equals( $remote ) ||
                          $u->trustmask( $remote ) & ( 1 << $tf->{groupnum} ) ) ) {
                # let them filter the results page by this group
                $opts->{securityfilter} = $tf->{groupnum};
            }
        }

        return $security_err->( { message => "error.security.invalid2" }, show_list => 1 )
            unless defined $opts->{securityfilter};
    }

    unless ( $geta->{'viewall'} && $remote && $remote->has_priv( "canview", "suspended" ) ||
             $opts->{'pathextra'} =~ m!/(\d+)/stylesheet$! ) { # don't check style sheets
        return $u->display_journal_deleted( $remote, journal_opts => $opts ) if $u->is_deleted;

        if ( $u->is_suspended ) {
            my $warning = BML::ml( 'error.suspended.text', { user => $u->ljuser_display, sitename => $LJ::SITENAME } );
            return $error->( $warning, "403 Forbidden", BML::ml( 'error.suspended.name' ) );
        }

        my $entry = $opts->{ljentry};
        if ( $entry && $entry->is_suspended_for( $remote ) ) {
            my $journal_base = $u->journal_base;
            my $warning = BML::ml( 'error.suspended.entry', { aopts => "href='$journal_base/'" } );
            return $error->( $warning, "403 Forbidden", BML::ml( 'error.suspended.name' ) );
        }
    }
    return $error->( BML::ml( 'error.purged.text' ), "410 Gone", BML::ml( 'error.purged.name' ) ) if $u->is_expunged;

    my %valid_identity_views = (
        read => 1,
        res  => 1,
        icons => 1,
    );
    # FIXME: pretty this up at some point, to maybe auto-redirect to
    # the external URL or something, but let's just do this for now
    # res is a resource, such as an external stylesheet
    if ( $u->is_identity && !$valid_identity_views{$view} ) {
        my $location = $u->openid_identity;
        my $warning = BML::ml( 'error.nojournal.openid', { aopts => "href='$location'", id => $location } );
        return $error->( $warning, "404 Not here" );
    }

    $opts->{'view'} = $view;

    # what charset we put in the HTML
    $opts->{'saycharset'} ||= "utf-8";

    if ($view eq 'data') {
        return LJ::Feed::make_feed($r, $u, $remote, $opts);
    }

    if ($stylesys == 2) {
        $r->note(codepath => "s2.$view")
            if $r;

        eval { LJ::S2->can("dostuff") };  # force Class::Autouse

        my $mj;

        unless ( $opts->{'handle_with_bml_ref'} && ${$opts->{'handle_with_bml_ref'}} ) {
            $mj = LJ::S2::make_journal($u, $styleid, $view, $remote, $opts);
        }

        # intercept flag to handle_with_bml_ref and instead use siteviews
        # FIXME: Temporary, till everything is converted.
        if ( $opts->{'handle_with_bml_ref'} && ${$opts->{'handle_with_bml_ref'}} && ( $geta->{fallback} eq "s2" || {
                entry => LJ::BetaFeatures->user_in_beta( $remote => "s2comments" ),
                reply => LJ::BetaFeatures->user_in_beta( $remote => "s2comments" ),
                icons => 1, tag => 1 }->{$view} ) ) {
            $mj = LJ::S2::make_journal($u, "siteviews", $view, $remote, $opts);
        }

        return $mj;
    }

    # if we get here, then we tried to run the old S1 path, so die and hope that
    # somebody comes along to fix us :(
    confess 'Tried to run S1 journal rendering path.';
}


1;
