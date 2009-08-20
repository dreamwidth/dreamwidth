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
use lib "$LJ::HOME/cgi-bin";
use List::Util ();
use LJ::Constants;
use LJ::MemCache;
use LJ::Session;
use DW::User::Edges;
use DW::Logic::ProfilePage;

use Class::Autouse qw(
                      LJ::Subscription
                      LJ::Identity
                      LJ::Auth
                      LJ::Jabber::Presence
                      LJ::S2
                      IO::Socket::INET
                      Time::Local
                      LJ::BetaFeatures
                      LJ::S2Theme
                      );

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
###  16. Entry-Related Functions
###  17. Interest-Related Functions
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


sub can_expunge {
    my $u = shift;

    # must be already deleted
    return 0 unless $u->is_deleted;

    # and deleted 30 days ago
    my $expunge_days = LJ::conf_test($LJ::DAYS_BEFORE_EXPUNGE) || 30;
    return 0 unless $u->statusvisdate_unix < time() - 86400*$expunge_days;

    my $hook_rv = 0;
    if (LJ::are_hooks("can_expunge_user", $u)) {
        $hook_rv = LJ::run_hook("can_expunge_user", $u);
        return $hook_rv ? 1 : 0;
    }

    return 1;
}


# class method to create a new account.
sub create {
    my ($class, %opts) = @_;

    my $username = LJ::canonical_username($opts{user}) or return;

    my $cluster     = $opts{cluster} || LJ::new_account_cluster();
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

    my $u = LJ::load_userid($userid, "force");

    my $status   = $opts{status}   || ($LJ::EVERYONE_VALID ? 'A' : 'N');
    my $name     = $opts{name}     || $username;
    my $bdate    = $opts{bdate}    || "0000-00-00";
    my $email    = $opts{email}    || "";
    my $password = $opts{password} || "";

    LJ::update_user($u, { 'status' => $status, 'name' => $name, 'bdate' => $bdate,
                          'email' => $email, 'password' => $password, %LJ::USER_INIT });

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

    LJ::run_hooks("post_create", {
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

    my $remote = LJ::get_remote();
    LJ::set_rel($u, $remote, "A");  # maintainer
    LJ::set_rel($u, $remote, "M") if $opts{moderated}; # moderator if moderated
    LJ::join_community($remote, $u, 1, 1); # member

    LJ::set_comm_settings($u, $remote, { membership => $opts{membership},
                                         postlevel => $opts{postlevel} });
    return $u;
}


sub create_personal {
    my ($class, %opts) = @_;

    my $u = LJ::User->create(%opts) or return;

    $u->set_prop("init_bdate", $opts{bdate});

    # so birthday notifications get sent
    $u->set_next_birthday;

    # Set the default style
    LJ::run_hook('set_default_style', $u);

    if ( $opts{inviter} ) {
        # store inviter, if there was one
        my $inviter = LJ::load_user( $opts{inviter} );
        if ( $inviter ) {
            LJ::set_rel( $u, $inviter, 'I' );
            LJ::statushistory_add( $u, $inviter, 'create_from_invite', "Created new account." );
            LJ::Event::InvitedFriendJoins->new( $inviter, $u )->fire;
        }
    }
    # if we have initial friends for new accounts, add them.
    # TODO(mark): INITIAL_FRIENDS should be moved/renamed.
    foreach my $friend ( @LJ::INITIAL_FRIENDS ) {
        my $friendid = LJ::get_userid( $friend )
            or next;
        $u->add_edge( $friendid, watch => {} );
    }

    # apply any paid time that this account should get
    if ( $LJ::USE_ACCT_CODES && $opts{code} ) {
        my $code = $opts{code};
        my $itemidref;
        if ( DW::InviteCodes->is_promo_code( code => $code ) ) {
            LJ::statushistory_add( $u, undef, 'create_from_promo', "Created new account from promo code '$code'." );
        } elsif ( my $cart = DW::Shop::Cart->get_from_invite( $code, itemidref => \$itemidref ) ) {
            my $item = $cart->get_item( $itemidref );
            if ( $item && $item->isa( 'DW::Shop::Item::Account' ) ) {
                # first update the item's target user and the cart
                $item->t_userid( $u->id );
                $cart->save( no_memcache => 1 );

                # now add paid time to the user
                my $from_u = $item->from_userid ? LJ::load_userid( $item->from_userid ) : undef;
                if ( DW::Pay::add_paid_time( $u, $item->class, $item->months ) ) {
                    LJ::statushistory_add( $u, $from_u, 'paid_from_invite', "Created new '" . $item->class . "' account." );
                } else {
                    my $paid_error = DW::Pay::error_text() || $@ || 'unknown error';
                    LJ::statushistory_add( $u, $from_u, 'paid_from_invite', "Failed to create new '" . $item->class . "' account: $paid_error" );
                }
            }
        }
    }

    # populate some default friends groups
    # TODO(mark): this should probably be removed or refactored, especially since
    #             editfriendgroups is dying/dead
#    LJ::do_request(
#                   {
#                       'mode'           => 'editfriendgroups',
#                       'user'           => $u->user,
#                       'ver'            => $LJ::PROTOCOL_VER,
#                       'efg_set_1_name' => 'Family',
#                       'efg_set_2_name' => 'Local Friends',
#                       'efg_set_3_name' => 'Online Friends',
#                       'efg_set_4_name' => 'School',
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
    # TODO: delete from user tables
    # TODO: delete from global tables
    my $dbh = LJ::get_db_writer();

    my @tables = qw(user useridmap reluser priv_map infohistory email password);
    foreach my $table (@tables) {
        $dbh->do("DELETE FROM $table WHERE userid=?", undef, $u->id);
    }

    $dbh->do("DELETE FROM wt_edges WHERE from_userid = ? OR to_userid = ?", undef, $u->id, $u->id);
    $dbh->do("DELETE FROM reluser WHERE targetid=?", undef, $u->id);
    $dbh->do("DELETE FROM email_aliases WHERE alias=?", undef, $u->user . "\@$LJ::USER_DOMAIN");

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


sub postreg_completed {
    my $u = shift;

    return 0 unless $u->bio;
    return 0 unless $u->interest_count;
    return 1;
}


sub who_invited {
    my $u = shift;
    my $inviterid = LJ::load_rel_user($u, 'I');

    return LJ::load_userid($inviterid);
}



########################################################################
###  2. Statusvis and Account Types

sub get_previous_statusvis {
    my $u = shift;
    
    my $extra = $u->selectcol_arrayref(
        "SELECT extra FROM userlog WHERE userid=? AND action='accountstatus' ORDER BY logtime DESC",
        undef, $u->{userid});
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
    return $u->statusvis eq 'D' || $u->statusvis eq 'X' || $u->statusvis eq 'S';
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
    return $u->statusvis eq 'O';
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
    LJ::run_hooks("account_delete", $u);
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
    return LJ::update_user($u, { statusvis => $statusvis,
                                 raw => 'statusvisdate=NOW()' });
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

    LJ::run_hooks("account_cancel", $u);

    if (my $err = LJ::run_hook("cdn_purge_userpics", $u)) {
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

    my $res = $u->set_statusvis('V');
    unless ($res) {
        $$errref = "DB error while setting statusvis to 'V'" if ref $errref;
        return $res;
    }

    LJ::statushistory_add($u, $who, "unsuspend", $reason);

    return $res; # success
}


sub set_visible {
    my $u = shift;
    return $u->set_statusvis('V');
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
    return LJ::mysqldate_to_time($u->{statusvisdate});
}



########################################################################
### 3. Working with All Types of Account


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
    # Without url_message "Send Message" link should not display
    $ret{url_message} = $u->message_url unless ($u->opt_usermsg eq 'N');

    LJ::run_hook("extra_info_for_js", $u, \%ret);

    my $up = $u->userpic;

    if ($up) {
        $ret{url_userpic} = $up->url;
        $ret{userpic_w}   = $up->width;
        $ret{userpic_h}   = $up->height;
    }

    return %ret;
}


sub is_community {
    my $u = shift;
    return $u->{journaltype} eq "C";
}
*is_comm = \&is_community;


sub is_identity {
    my $u = shift;
    return $u->{journaltype} eq "I";
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
    my $u = shift;
    return $u->{journaltype} eq "P";
}
*is_personal = \&is_person;


sub is_redirect {
    my $u = shift;
    return $u->{journaltype} eq "R";
}


sub is_syndicated {
    my $u = shift;
    return $u->{journaltype} eq "Y";
}


sub journaltype {
    my $u = shift;
    return $u->{journaltype};
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
    }->{$u->{journaltype}};
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


sub preload_props {
    LJ::load_user_props( @_ );
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

    # Traverse the renames to the final journal
    if ($u) {
        while ($u->{'journaltype'} eq 'R' && $hops-- > 0) {
            my $rt = $u->prop("renamedto");
            last unless length $rt;
            $u = LJ::load_user($rt);
        }
    }

    return $u;
}


# name: LJ::User->get_timeactive
# des:  retrieve last active time for user from [dbtable[clustertrack2]] or
#       memcache
sub get_timeactive {
    my ($u) = @_;
    my $memkey = [$u->{userid}, "timeactive:$u->{userid}"];
    my $active;
    unless (defined($active = LJ::MemCache::get($memkey))) {
        # TODO: die if unable to get handle? This was left verbatim from
        # refactored code.
        my $dbcr = LJ::get_cluster_def_reader($u) or return 0;
        $active = $dbcr->selectrow_array("SELECT timeactive FROM clustertrack2 ".
                                         "WHERE userid=?", undef, $u->{userid});
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
    if ($LJ::CACHE_REMOTE && $LJ::CACHE_REMOTE->{userid} == $u->{userid}) {
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

    if ($LJ::CACHE_REMOTE && $LJ::CACHE_REMOTE->{userid} == $u->{userid}) {
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


sub make_login_session {
    my ($u, $exptype, $ipfixed) = @_;
    $exptype ||= 'short';
    return 0 unless $u;

    eval { BML::get_request()->notes->{ljuser} = $u->{user}; };

    # create session and log user in
    my $sess_opts = {
        'exptype' => $exptype,
        'ipfixed' => $ipfixed,
    };

    my $sess = LJ::Session->create($u, %$sess_opts);
    $sess->update_master_cookie;

    LJ::User->set_remote($u);

    # add a uniqmap row if we don't have one already
    my $uniq = LJ::UniqCookie->current_uniq;
    LJ::UniqCookie->save_mapping($uniq => $u);

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
    LJ::run_hooks("login_add_opts", {
        "u" => $u,
        "form" => {},
        "opts" => \@sopts
    });
    my $sopts = @sopts ? ":" . join('', map { ".$_" } @sopts) : "";
    $sess->flags($sopts);

    my $etime = $sess->expiration_time;
    LJ::run_hooks("post_login", {
        "u" => $u,
        "form" => {},
        "expiretime" => $etime,
    });

    # activity for cluster usage tracking
    LJ::mark_user_active($u, 'login');

    # activity for global account number tracking
    $u->note_activity('A');

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
    my $uid    = $u->{userid}; # yep, lazy typist w/ rsi
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


sub rate_check { LJ::rate_check( @_ ); }

sub rate_log { LJ::rate_log( @_ ); }


sub record_login {
    my ($u, $sessid) = @_;

    my $too_old = time() - 86400 * 30;
    $u->do("DELETE FROM loginlog WHERE userid=? AND logintime < ?",
           undef, $u->{userid}, $too_old);

    my $r  = DW::Request->get;
    my $ip = LJ::get_remote_ip();
    my $ua = $r->header_in('User-Agent');

    return $u->do("INSERT INTO loginlog SET userid=?, sessid=?, logintime=UNIX_TIMESTAMP(), ".
                  "ip=?, ua=?", undef, $u->{userid}, $sessid, $ip, $ua);
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
    LJ::Session->clear_master_cookie;
    LJ::User->set_remote(undef);
    delete $BML::COOKIE{'BMLschemepref'};
    eval { BML::set_scheme(undef); };
}


########################################################################
### 5. Database and Memcache Functions


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


sub cache {
    my ($u, $key) = @_;
    my $val = $u->selectrow_array("SELECT value FROM userblobcache WHERE userid=? AND bckey=?",
                                  undef, $u->{userid}, $key);
    return undef unless defined $val;
    if (my $thaw = eval { Storable::thaw($val); }) {
        return $thaw;
    }
    return $val;
}


# front-end to LJ::cmd_buffer_add, which has terrible interface
#   cmd: scalar
#   args: hashref
sub cmd_buffer_add {
    my ($u, $cmd, $args) = @_;
    $args ||= {};
    return LJ::cmd_buffer_add($u->{clusterid}, $u->{userid}, $cmd, $args);
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

    my $uid = $u->{userid}+0
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
    return $LJ::CACHE_CLUSTER_IS_INNO{$u->{clusterid}}
    if defined $LJ::CACHE_CLUSTER_IS_INNO{$u->{clusterid}};

    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u)
        or croak $u->nodb_err;
    my (undef, $ctable) = $dbcm->selectrow_array("SHOW CREATE TABLE log2");
    die "Failed to auto-discover database type for cluster \#$u->{clusterid}: [$ctable]"
        unless $ctable =~ /^CREATE TABLE/;

    my $is_inno = ($ctable =~ /=InnoDB/i ? 1 : 0);
    return $LJ::CACHE_CLUSTER_IS_INNO{$u->{clusterid}} = $is_inno;
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

    my $memkey = [$u->{'userid'}, "log2lt:$u->{'userid'}"];
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
    return LJ::MemCache::get( [$_[0]->{userid}, "$_[1]:$_[0]->{userid}"] );
}


# sets a predictably named item. usage:
#   $u->memc_set( key => 'value', [ $timeout ] );
sub memc_set {
    return LJ::MemCache::set( [$_[0]->{userid}, "$_[1]:$_[0]->{userid}"], $_[2], $_[3] || 1800 );
}


# deletes a predictably named item. usage:
#   $u->memc_delete( key );
sub memc_delete {
    return LJ::MemCache::delete( [$_[0]->{userid}, "$_[1]:$_[0]->{userid}"] );
}


sub mysql_insertid {
    my $u = shift;
    if ($u->isa("LJ::User")) {
        return $u->{_mysql_insertid};
    } elsif (LJ::isdb($u)) {
        my $db = $u;
        return $db->{'mysql_insertid'};
    } else {
        die "Unknown object '$u' being passed to LJ::User::mysql_insertid.";
    }
}


sub nodb_err {
    my $u = shift;
    return "Database handle unavailable (user: " . $u->user . "; cluster: " . $u->clusterid . ")";
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
    LJ::assert_is($u->{userid}, $u->{_orig_userid})
        if $u->{_orig_userid};
    LJ::assert_is($u->{user}, $u->{_orig_user})
        if $u->{_orig_user};
    return 1;
}


sub set_cache {
    my ($u, $key, $value, $expr) = @_;
    my $now = time();
    $expr ||= $now + 86400;
    $expr += $now if $expr < 315532800;  # relative to absolute time
    $value = Storable::nfreeze($value) if ref $value;
    $u->do("REPLACE INTO userblobcache (userid, bckey, value, timeexpire) VALUES (?,?,?,?)",
           undef, $u->{userid}, $key, $value, $expr);
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
# is elsewhere (talklib.pl), but this $dbh->do wrapper is provided
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

    my $memkey = [$u->{'userid'}, "talk2:$u->{'userid'}:$nodetype:$nodeid"];
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
    LJ::MemCache::delete([$u->{userid}, "uprop:$u->{userid}:$prop->{id}"]);
    delete $u->{$name};
    return 1;
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

    return 1 if LJ::check_priv($u, "supporthelp");
    return 1 if LJ::check_priv($u, "supportviewscreened");
    return 1 if LJ::check_priv($u, "siteadmin");

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


sub tosagree_set
{
    my ($u, $err) = @_;
    return undef unless $u;

    unless (-f "$LJ::HOME/htdocs/inc/legal-tos") {
        $$err = "TOS include file could not be found";
        return undef;
    }

    my $rev;
    open (TOS, "$LJ::HOME/htdocs/inc/legal-tos");
    while ((!$rev) && (my $line = <TOS>)) {
        my $rcstag = "Revision";
        if ($line =~ /\$$rcstag:\s*(\S+)\s*\$/) {
            $rev = $1;
        }
    }
    close TOS;

    # if the required version of the tos is not available, error!
    my $rev_req = $LJ::REQUIRED_TOS{rev};
    if ($rev_req > 0 && $rev ne $rev_req) {
        $$err = "Required Terms of Service revision is $rev_req, but system version is $rev.";
        return undef;
    }

    my $newval = join(', ', time(), $rev);
    my $rv = $u->set_prop("legal_tosagree", $newval);

    # set in $u object for callers later
    $u->{legal_tosagree} = $newval if $rv;

    return $rv;
}


sub tosagree_verify {
    my $u = shift;
    return 1 unless $LJ::TOS_CHECK;

    my $rev_req = $LJ::REQUIRED_TOS{rev};
    return 1 unless $rev_req > 0;

    my $rev_cur = (split(/\s*,\s*/, $u->prop("legal_tosagree")))[1];
    return $rev_cur eq $rev_req;
}


########################################################################
### 7. Userprops, Caps, and Displaying Content to Others


sub add_to_class {
    my ($u, $class) = @_;
    my $bit = LJ::class_bit($class);
    die "unknown class '$class'" unless defined $bit;

    # call add_to_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs the new we say we'll be adding
    if (LJ::are_hooks('add_to_class')) {
        LJ::run_hooks('add_to_class', $u, $class);
    }

    return LJ::modify_caps($u, [$bit], []);
}


sub caps {
    my $u = shift;
    return $u->{caps};
}


sub can_be_text_messaged_by {
    my ($u, $sender) = @_;

    return 0 unless $u->get_cap("textmessaging");

    my $security = LJ::TextMessage->tm_security($u);

    return 0 if $security eq "none";
    return 1 if $security eq "all";

    if ($sender) {
        return 1 if $security eq "reg";
        return 1 if $security eq "friends" && $u->trusts( $sender );
    }

    return 0;
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


sub can_use_google_analytics {
    return $_[0]->get_cap( 'google_analytics' ) ? 1 : 0;
}

# Check if the user can use *any* page statistic module for their own journal.
sub can_use_page_statistics {
    return $_[0]->can_use_google_analytics;
}

sub clear_prop {
    my ($u, $prop) = @_;
    $u->set_prop($prop, undef);
    return 1;
}


sub control_strip_display {
    my $u = shift;

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'control_strip_display' );
    return 0 if $prop_val eq 'none';
    return $prop_val if $prop_val =~ /^\d+$/;

    # otherwise, return the default: all options checked
    my $ret;
    my @pageoptions = LJ::run_hook( 'page_control_strip_options' );
    for ( my $i = 0; $i < scalar @pageoptions; $i++ ) {
        $ret |= 1 << $i;
    }

    return $ret ? $ret : 0;
}


# returns the country specified by the user
sub country {
    return $_[0]->prop( 'country' );
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
    return 1 if $LJ::T_HAS_ALL_CAPS;
    return LJ::get_cap( $u, $cname );
}


# get/set the gizmo account of a user
sub gizmo_account {
    my $u = shift;

    # parse out their account information
    my $acct = $u->prop( 'gizmo' );
    my ($validated, $gizmo);
    if ($acct && $acct =~ /^([01]);(.+)$/) {
        ($validated, $gizmo) = ($1, $2);
    }

    # setting the account
    # all account sets are initially unvalidated
    if (@_) {
        my $newgizmo = shift;
        $u->set_prop( 'gizmo' => "0;$newgizmo" );

        # purge old memcache keys
        LJ::MemCache::delete( "gizmo-ljmap:$gizmo" );
    }

    # return the information (either account + validation or just account)
    return wantarray ? ($gizmo, $validated) : $gizmo unless @_;
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


# tests to see if a user is in a specific named class. class
# names are site-specific.
sub in_class {
    my ($u, $class) = @_;
    return LJ::caps_in_group($u->{caps}, $class);
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
        return "<img src='$LJ::IMGPREFIX/silk/24x24/$_[0]' border='0' height='24' " .
            "width='24' style='padding: 0px 2px 0px 0px' />";
    };

    # hook will return image to use if it cares about
    # the $u it's been passed
    my $hook_img = LJ::run_hook("large_journal_icon", $u);
    return $wrap_img->($hook_img) if $hook_img;

    if ($u->is_comm) {
        return $wrap_img->("community.png");
    }

    if ($u->is_syndicated) {
        return $wrap_img->("feed.png");
    }

    if ($u->is_identity) {
        return $wrap_img->("openid.png");
    }

    # personal or unknown fallthrough
    return $wrap_img->("user.png");
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
    my $u = shift;

    my $user_email = $LJ::USER_EMAIL && $u->get_cap( 'useremail' ) ? 1 : 0;

    # return prop value if it exists and is valid
    my $prop_val = $u->prop( 'opt_whatemailshow' );
    if ( $user_email ) {
        return $prop_val if $prop_val =~ /^[ALBNDV]$/;
    } else {
        return $prop_val if $prop_val =~ /^[AND]$/;
    }

    # otherwise, return the default: no email shown
    return 'N';
}


sub profile_url {
    my ($u, %opts) = @_;

    my $url;
    if ($u->{journaltype} eq "I") {
        $url = "$LJ::SITEROOT/userinfo?userid=$u->{'userid'}&t=I";
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


sub raw_prop {
    my ($u, $prop) = @_;
    $u->preload_props($prop) unless exists $u->{$_};
    return $u->{$prop};
}


sub remove_from_class {
    my ($u, $class) = @_;
    my $bit = LJ::class_bit($class);
    die "unknown class '$class'" unless defined $bit;

    # call remove_from_class hook before we modify the
    # current $u, so it can make inferences from the
    # old $u caps vs what we'll be removing
    if (LJ::are_hooks('remove_from_class')) {
        LJ::run_hooks('remove_from_class', $u, $class);
    }

    return LJ::modify_caps($u, [], [$bit]);
}


# sets prop, and also updates $u's cached version
sub set_prop {
    my ($u, $prop, $value) = @_;
    return 0 unless LJ::set_userprop($u, $prop, $value);  # FIXME: use exceptions
    $u->{$prop} = $value;
}


sub share_contactinfo {
    my ($u, $remote) = @_;

    return 0 if $u->{journaltype} eq "Y";
    return 0 if $u->opt_showcontact eq 'N';
    return 0 if $u->opt_showcontact eq 'R' && !$remote;
    return 0 if $u->opt_showcontact eq 'F' && !$u->trusts( $remote );
    return 1;
}


sub should_block_robots {
    my $u = shift;

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


sub should_show_schools_to {
    my ($u, $targetu) = @_;

    return 0 unless LJ::is_enabled("schools");
    return 1 if $u->{'opt_showschools'} eq '' || $u->{'opt_showschools'} eq 'Y';
    return 1 if $u->{'opt_showschools'} eq 'F' && $u->trusts( $targetu );

    return 0;
}

# should show the thread expander for this user/journal
sub show_thread_expander {
    my ( $u, $remote ) = @_;

    return 1 if $remote && $remote->get_cap( 'thread_expander' )
        || $u->get_cap( 'thread_expander' );

    return 0;
}

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
    LJ::update_user($u, { allow_infoshow => ' ' })
        or die "unable to update user after infoshow migration";
    $u->{allow_infoshow} = ' ';

    return 1;
}


########################################################################
### 8. Formatting Content Shown to Users

sub ajax_auth_token {
    my $u = shift;
    return LJ::Auth->ajax_auth_token($u, @_);
}


sub bio {
    my $u = shift;
    return LJ::get_bio($u);
}


sub check_ajax_auth_token {
    my $u = shift;
    return LJ::Auth->check_ajax_auth_token($u, @_);
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
        require Net::OpenID::Consumer;
        $url = $id->value;
        $name = Net::OpenID::VerifiedIdentity::DisplayOfURL($url, $LJ::IS_DEV_SERVER);
        $name = LJ::run_hook("identity_display_name", $name) || $name;

        ## Unescape %xx sequences
        $name =~ s/%([\dA-Fa-f]{2})/chr(hex($1))/ge;
    }
    return $name;
}


sub equals {
    return LJ::u_equals( @_ );
}


# userid
*userid = \&id;
sub id {
    return $_[0]->{userid};
}


sub ljuser_display {
    my $u = shift;
    my $opts = shift;

    return LJ::ljuser($u, $opts) unless $u->{'journaltype'} eq "I";

    my $id = $u->identity;
    return "<b>????</b>" unless $id;

    my $andfull = $opts->{'full'} ? "&amp;mode=full" : "";
    my $img = $opts->{'imgroot'} || $LJ::IMGPREFIX;
    my $strike = $opts->{'del'} ? ' text-decoration: line-through;' : '';
    my $profile_url = $opts->{'profile_url'} || '';
    my $journal_url = $opts->{'journal_url'} || '';
    my $display_class = $opts->{no_ljuser_class} ? "" : "class='ljuser'";
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
            $imgurl = "$img/openid_${head_size}.gif";
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

        my $profile = $profile_url ne '' ? $profile_url : "$LJ::SITEROOT/userinfo?userid=$u->{userid}&amp;t=I$andfull";

        return "<span $display_class lj:user='$name' style='white-space: nowrap;$strike'><a href='$profile'><img src='$imgurl' alt='[info - $type] ' width='$width' height='$height' style='vertical-align: bottom; border: 0; padding-right: 1px;' /></a><a href='$url' rel='nofollow'><b>$name</b></a></span>";

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
    $u->{_orig_userid} = $u->{userid};
    $u->{_orig_user}   = $u->{user};

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


sub url {
    my $u = shift;

    my $url;

    if ( $u->{journaltype} eq 'I' && ! $u->prop( 'url' ) ) {
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
    my $u = shift;
    return $u->{user};
}


# if bio_absent is set to "yes", bio won't be updated
sub set_bio {
    my ($u, $text, $bio_absent) = @_;
    $bio_absent = "" unless $bio_absent;

    my $oldbio = $u->bio;
    my $newbio = $bio_absent eq "yes" ? $oldbio : $text;
    my $has_bio = ($newbio =~ /\S/) ? "Y" : "N";

    my %update = (
        'has_bio' => $has_bio,
    );
    LJ::update_user($u, \%update);

    # update their bio text
    if (($oldbio ne $text) && $bio_absent ne "yes") {
        if ($has_bio eq "N") {
            $u->do("DELETE FROM userbio WHERE userid=?", undef, $u->id);
            $u->dudata_set('B', 0, 0);
        } else {
            $u->do("REPLACE INTO userbio (userid, bio) VALUES (?, ?)",
                   undef, $u->id, $text);
            $u->dudata_set('B', 0, length($text));
        }
        LJ::MemCache::set([$u->id, "bio:" . $u->id], $text);
    }
}


########################################################################
### 9. Logging and Recording Actions


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
               $u->{userid}, $area);
    } else {
        $u->do("DELETE FROM dudata WHERE userid=? AND ".
               "area=? AND areaid=$areaid", undef,
               $u->{userid}, $area);
    }
    return 1;
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
           "VALUES (?, UNIX_TIMESTAMP(), ?, ?, ?, ?, ?, ?)", undef, $u->{userid}, $type,
           $targetid, $remote ? $remote->{userid} : undef, $ip, $uniq, $extra);
    return undef if $u->err;
    return 1;
}


########################################################################
### 10. Banning-Related Functions


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
        LJ::run_hooks('ban_set', $u, $us->{$banuid}) if $us->{$banuid};
    }

    return 1;
}


# return if $target is banned from $u's journal
*has_banned = \&is_banned;
sub is_banned {
    my ($u, $target) = @_;
    return LJ::is_banned($target->userid, $u->userid);
}


sub unban_user_multi {
    my ($u, @unbanlist) = @_;

    LJ::clear_rel_multi(map { [$u->id, $_, 'B'] } @unbanlist);

    my $us = LJ::load_userids(@unbanlist);
    foreach my $banuid (@unbanlist) {
        $u->log_event('ban_unset', { actiontarget => $banuid, remote => LJ::get_remote() });
        LJ::run_hooks('ban_unset', $u, $us->{$banuid}) if $us->{$banuid};
    }

    return 1;
}


########################################################################
### 11. Birthdays and Age-Related Functions
###   FIXME: Some of these may be outdated when we remove under-13 accounts.



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
# D - Only Show Month/Day
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
        $sth->execute($u->{'userid'});
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


sub can_manage {
    return LJ::can_manage( @_ );
}


# can $u post to $targetu?
sub can_post_to {
    my ($u, $targetu) = @_;

    return LJ::can_use_journal($u->id, $targetu->user);
}


sub is_closed_membership {
    my $u = shift;

    return $u->membership_level eq 'closed' ? 1 : 0;
}


sub is_moderated_membership {
    my $u = shift;

    return $u->membership_level eq 'moderated' ? 1 : 0;
}


sub is_open_membership {
    my $u = shift;

    return $u->membership_level eq 'open' ? 1 : 0;
}


# returns an array of maintainer userids
sub maintainer_userids {
    my $u = shift;

    return () unless $u->is_community;
    return @{LJ::load_rel_user_cache( $u->id, 'A' )};
}


# returns the membership level of a community
sub membership_level {
    my $u = shift;

    return undef unless $u->is_community;

    my ( $membership_level, $post_level ) = LJ::get_comm_settings( $u );
    return $membership_level || undef;
}


# returns an array of moderator userids
sub moderator_userids {
    my $u = shift;

    return () unless $u->is_community && $u->prop( 'moderated' );
    return @{LJ::load_rel_user_cache( $u->id, 'M' )};
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
    foreach my $membershipid ( keys %$memberships ) {
        my $membershipu = $memberships->{$membershipid};

        next unless $membershipu->is_community;
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
    my $u = shift;
    my %opts = @_;

    return 1 unless LJ::is_enabled( 'adult_content' ) && LJ::is_enabled( 'safe_search' );

    my $adult_content = $u->adult_content_calculated;

    my $for_u = $opts{for};
    unless (LJ::isu($for_u)) {
        return $adult_content eq "none" ? 1 : 0;
    }

    my $safe_search = $for_u->safe_search;
    return 1 if $safe_search == 0;

    my $adult_content_flag_level = $LJ::CONTENT_FLAGS{$adult_content} ? $LJ::CONTENT_FLAGS{$adult_content}->{safe_search_level} : 0;

    return 0 if $adult_content_flag_level && ($safe_search >= $adult_content_flag_level);
    return 1;
}


########################################################################
###  15. Email-Related Functions


sub delete_email_alias {
    my $u = shift;

    return if exists $LJ::FIXED_ALIAS{$u->{user}};

    my $dbh = LJ::get_db_writer();
    $dbh->do( "DELETE FROM email_aliases WHERE alias=?",
              undef, "$u->{user}\@$LJ::USER_DOMAIN" );

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
    $u->{_email} ||= LJ::MemCache::get_or_set([$u->{userid}, "email:$u->{userid}"], sub {
        my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
        return $dbh->selectrow_array("SELECT email FROM email WHERE userid=?",
                                     undef, $u->id);
    });
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

    return () if $u->{journaltype} =~ /[YI]/;

    # security controls
    return () unless $u->share_contactinfo($remote);

    my $whatemail = $u->opt_whatemailshow;
    my $useremail_cap = LJ::get_cap($u, 'useremail');

    # some classes of users we want to have their contact info hidden
    # after so much time of activity, to prevent people from bugging
    # them for their account or trying to brute force it.
    my $hide_contactinfo = sub {
        my $hide_after = LJ::get_cap($u, "hide_email_after");
        return 0 unless $hide_after;
        my $active = $u->get_timeactive;
        return $active && (time() - $active) > $hide_after * 86400;
    };

    return () if $whatemail eq "N" ||
        $whatemail eq "L" && ($u->prop("no_mail_alias") || ! $useremail_cap || ! $LJ::USER_EMAIL) ||
        $hide_contactinfo->();

    my @emails = ();

    if ( $u->prop( 'opt_whatemailshow' ) eq "A" || $u->prop( 'opt_whatemailshow' ) eq "B" ) {
        push @emails, $u->email_raw;
    } elsif ( $u->prop( 'opt_whatemailshow' ) eq "D" || $u->prop( 'opt_whatemailshow' ) eq "V" ) {
        push @emails, $u->prop( 'opt_profileemail' );
    } 

    if ($LJ::USER_EMAIL && $useremail_cap) {
        if ($whatemail eq "B" || $whatemail eq "V" || $whatemail eq "L") {
            push @emails, "$u->{'user'}\@$LJ::USER_DOMAIN" unless $u->prop('no_mail_alias');
        }
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


sub set_email {
    my ($u, $email) = @_;
    return LJ::set_email($u->id, $email);
}


sub update_email_alias {
    my $u = shift;

    return unless $u && $u->get_cap("useremail");
    return if exists $LJ::FIXED_ALIAS{$u->{'user'}};
    return if $u->prop("no_mail_alias");
    return unless $u->is_validated;

    my $dbh = LJ::get_db_writer();
    $dbh->do("REPLACE INTO email_aliases (alias, rcpt) VALUES (?,?)",
             undef, "$u->{'user'}\@$LJ::USER_DOMAIN", $u->email_raw);

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
#           TODO: Add caching?
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
    push(@vals, $u->{userid});

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


sub newpost_minsecurity {
    my $u = shift;

    return $u->prop('newpost_minsecurity') || 'public';
}


*get_post_count = \&number_of_posts;
sub number_of_posts {
    my ($u, %opts) = @_;

    # to count only a subset of all posts
    if (%opts) {
        $opts{return} = 'count';
        return $u->get_post_ids(%opts);
    }

    my $memkey = [$u->{userid}, "log2ct:$u->{userid}"];
    my $expire = time() + 3600*24*2; # 2 days
    return LJ::MemCache::get_or_set($memkey, sub {
        return $u->selectrow_array("SELECT COUNT(*) FROM log2 WHERE journalid=?",
                                   undef, $u->{userid});
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
        clusterid => $u->{clusterid},
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
                            undef, $new, $u->{userid}, $prop->{id}, length $old);
            return 0 unless $rv > 0;
            $u->uncache_prop("entry_draft");
            return 1;
        };
        push @methods, [ "append", $appending, 40 + length $new ];
    }

    # TODO: prepending/middle insertion (the former being just the latter), as well
    # appending, wihch we could then get rid of

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
###  17. Interest-Related Functions

sub interest_count {
    my $u = shift;

    # FIXME: fall back to SELECT COUNT(*) if not cached already?
    return scalar @{LJ::get_interests($u, { justids => 1 })};
}


sub interest_list {
    my $u = shift;

    return map { $_->[1] } @{ LJ::get_interests($u) };
}


# return hashref with intname => intid
sub interests {
    my $u = shift;
    my $uints = LJ::get_interests($u);
    my %interests;

    foreach my $int (@$uints) {
        $interests{$int->[1]} = $int->[0];  # $interests{name} = intid
    }

    return \%interests;
}


sub lazy_interests_cleanup {
    my $u = shift;

    my $dbh = LJ::get_db_writer();

    if ($u->is_community) {
        $dbh->do("INSERT IGNORE INTO comminterests SELECT * FROM userinterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM userinterests WHERE userid=?", undef, $u->id);
    } else {
        $dbh->do("INSERT IGNORE INTO userinterests SELECT * FROM comminterests WHERE userid=?", undef, $u->id);
        $dbh->do("DELETE FROM comminterests WHERE userid=?", undef, $u->id);
    }

    LJ::memcache_kill($u, "intids");
    return 1;
}


sub set_interests {
    LJ::set_interests( @_ );
}


########################################################################
###  18. Jabber-Related Functions


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

    return $u->{'user'}.'@'.$LJ::USER_DOMAIN;
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

# returns a true value if user has a reserved 'ext' name.
sub external {
    my $u = shift;
    return $u->{user} =~ /^ext_/;
}


# returns LJ::Identity object
sub identity {
    my $u = shift;
    return $u->{_identity} if $u->{_identity};
    return undef unless $u->{'journaltype'} eq "I";

    my $memkey = [$u->{userid}, "ident:$u->{userid}"];
    my $ident = LJ::MemCache::get($memkey);
    if ($ident) {
        my $i = LJ::Identity->new(
                                  typeid => $ident->[0],
                                  value  => $ident->[1],
                                  );

        return $u->{_identity} = $i;
    }

    my $dbh = LJ::get_db_writer();
    $ident = $dbh->selectrow_arrayref("SELECT idtype, identity FROM identitymap ".
                                      "WHERE userid=? LIMIT 1", undef, $u->{userid});
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
    my $dbh = LJ::get_db_writer();
    my $uid;

    for (1..10) {
        my $extuser = 'ext_' . LJ::alloc_global_counter('E');

        my $name = $extuser;
        if ($type eq "O" && ref $vident) {
            $name = $vident->display;
        }

        $uid = LJ::create_account({
            caps => undef,
            user => $extuser,
            name => $ident,
            journaltype => 'I',
        });
        last if $uid;
        select undef, undef, undef, .10;  # lets not thrash over this
    }
    return undef unless $uid &&
        $dbh->do("INSERT INTO identitymap (idtype, identity, userid) VALUES (?,?,?)",
                 undef, $type, $ident, $uid);

    $u = LJ::load_userid($uid);

    # record create information
    my $remote = LJ::get_remote();
    $u->log_event('account_create', { remote => $remote });

    return $u;
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

    LJ::infohistory_add($u, 'identity', $from);

    return 1;
}


########################################################################
###  20. Page Notices Functions

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
    $u->{_password} ||= LJ::MemCache::get_or_set([$u->{userid}, "pw:$u->{userid}"], sub {
        my $dbh = LJ::get_db_writer() or die "Couldn't get db master";
        return $dbh->selectrow_array("SELECT password FROM password WHERE userid=?",
                                     undef, $u->id);
    });
    return $u->{_password};
}


sub set_password {
    my ($u, $password) = @_;
    return LJ::set_password($u->id, $password);
}


########################################################################
###  22. Priv-Related Functions


sub has_priv {
    my ( $u, $priv, $arg ) = @_;

    # FIXME: migrate check_priv here and have users call this instead
    return LJ::check_priv( $u, $priv, $arg );
}

sub grant_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||= "";
    my $dbh = LJ::get_db_writer();

    return 1 if LJ::check_priv($u, $priv, $arg);

    my $privid = $dbh->selectrow_array("SELECT prlid FROM priv_list".
                                       " WHERE privcode = ?", undef, $priv);
    return 0 unless $privid;

    $dbh->do("INSERT INTO priv_map (userid, prlid, arg) VALUES (?, ?, ?)",
             undef, $u->id, $privid, $arg);
    return 0 if $dbh->err;

    undef $u->{'_privloaded'}; # to force reloading of privs later
    return 1;
}

sub revoke_priv {
    my ($u, $priv, $arg) = @_;
    $arg ||="";
    my $dbh = LJ::get_db_writer();

    return 1 unless LJ::check_priv($u, $priv, $arg);

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


sub journal_base {
    my $u = shift;
    return LJ::journal_base($u);
}


sub opt_ctxpopup {
    my $u = shift;

    # if unset, default to on
    my $prop = $u->raw_prop('opt_ctxpopup') || 'Y';

    return $prop eq 'Y';
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


sub show_control_strip {
    my $u = shift;

    LJ::run_hook('control_strip_propcheck', $u, 'show_control_strip') if LJ::is_enabled('control_strip_propcheck');

    my $prop = $u->raw_prop('show_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}


sub view_control_strip {
    my $u = shift;

    LJ::run_hook('control_strip_propcheck', $u, 'view_control_strip') if LJ::is_enabled('control_strip_propcheck');

    my $prop = $u->raw_prop('view_control_strip');
    return 0 if $prop =~ /^off/;

    return 'dark' if $prop eq 'forced';

    return $prop;
}


########################################################################
###  25. Subscription, Notifiction, and Messaging Functions


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
    return "$LJ::SITEROOT/inbox/compose?user=$u->{'user'}";
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

# retrieve hash of basic syndicated info
sub get_syndicated {
    my $u = shift;

    return unless $u->is_syndicated;
    my $memkey = [$u->{'userid'}, "synd:$u->{'userid'}"];

    my $synd = {};
    $synd = LJ::MemCache::get($memkey);
    unless ($synd) {
        my $dbr = LJ::get_db_reader();
        return unless $dbr;
        $synd = $dbr->selectrow_hashref("SELECT * FROM syndicated WHERE userid=$u->{'userid'}");
        LJ::MemCache::set($memkey, $synd, 60 * 30) if $synd;
    }

    return $synd;
}


########################################################################
###  27. Tag-Related Functions

# can $u add existing tags to $targetu's entries?
sub can_add_tags_to {
    my ($u, $targetu) = @_;

    return LJ::Tags::can_add_tags($targetu, $u);
}


sub tags {
    my $u = shift;

    return LJ::Tags::get_usertags($u);
}


########################################################################
###  28. Userpic-Related Functions

# <LJFUNC>
# name: LJ::User::activate_userpics
# des: Sets/unsets userpics as inactive based on account caps.
# returns: nothing
# </LJFUNC>
sub activate_userpics {
    my $u = shift;

    # this behavior is optional, but enabled by default
    return 1 if $LJ::ALLOW_PICS_OVER_QUOTA;

    return undef unless LJ::isu($u);

    # can't get a cluster read for expunged users since they are clusterid 0,
    # so just return 1 to the caller from here and act like everything went fine
    return 1 if $u->is_expunged;

    my $userid = $u->{'userid'};

    # active / inactive lists
    my @active = ();
    my @inactive = ();
    my $allow = LJ::get_cap($u, "userpics");

    # get a database handle for reading/writing
    my $dbh = LJ::get_db_writer();
    my $dbcr = LJ::get_cluster_def_reader($u);

    # select all userpics and build active / inactive lists
    my $sth;
    if ($u->{'dversion'} > 6) {
        return undef unless $dbcr;
        $sth = $dbcr->prepare("SELECT picid, state FROM userpic2 WHERE userid=?");
    } else {
        return undef unless $dbh;
        $sth = $dbh->prepare("SELECT picid, state FROM userpic WHERE userid=?");
    }
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
    if (@active > $allow) {
        my $to_ban = @active - $allow;

        # find first jitemid greater than time 2 months ago using rlogtime index
        # ($LJ::EndOfTime - UnixTime)
        my $jitemid = $dbcr->selectrow_array("SELECT jitemid FROM log2 USE INDEX (rlogtime) " .
                                             "WHERE journalid=? AND rlogtime > ? LIMIT 1",
                                             undef, $userid, $LJ::EndOfTime - time() + 86400*60);

        # query all pickws in logprop2 with jitemid > that value
        my %count_kw = ();
        my $propid = LJ::get_prop("log", "picture_keyword")->{'id'};
        my $sth = $dbcr->prepare("SELECT value, COUNT(*) FROM logprop2 " .
                                 "WHERE journalid=? AND jitemid > ? AND propid=?" .
                                 "GROUP BY value");
        $sth->execute($userid, $jitemid, $propid);
        while (my ($value, $ct) = $sth->fetchrow_array) {
            # keyword => count
            $count_kw{$value} = $ct;
        }

        my $keywords_in = join(",", map { $dbh->quote($_) } keys %count_kw);

        # map pickws to picids for freq hash below
        my %count_picid = ();
        if ($keywords_in) {
            my $sth;
            if ($u->{'dversion'} > 6) {
                $sth = $dbcr->prepare("SELECT k.keyword, m.picid FROM userkeywords k, userpicmap2 m ".
                                      "WHERE k.keyword IN ($keywords_in) AND k.kwid=m.kwid AND k.userid=m.userid " .
                                      "AND k.userid=?");
            } else {
                $sth = $dbh->prepare("SELECT k.keyword, m.picid FROM keywords k, userpicmap m " .
                                     "WHERE k.keyword IN ($keywords_in) AND k.kwid=m.kwid " .
                                     "AND m.userid=?");
            }
            $sth->execute($userid);
            while (my ($keyword, $picid) = $sth->fetchrow_array) {
                # keyword => picid
                $count_picid{$picid} += $count_kw{$keyword};
            }
        }

        # we're only going to ban the least used, excluding the user's default
        my @ban = (grep { $_ != $u->{'defaultpicid'} }
                   sort { $count_picid{$a} <=> $count_picid{$b} } @active);

        @ban = splice(@ban, 0, $to_ban) if @ban > $to_ban;
        my $ban_in = join(",", map { $dbh->quote($_) } @ban);
        if ($u->{'dversion'} > 6) {
            $u->do("UPDATE userpic2 SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                   undef, $userid) if $ban_in;
        } else {
            $dbh->do("UPDATE userpic SET state='I' WHERE userid=? AND picid IN ($ban_in)",
                     undef, $userid) if $ban_in;
        }
    }

    # activate previously inactivated userpics
    if (@inactive && @active < $allow) {
        my $to_activate = $allow - @active;
        $to_activate = @inactive if $to_activate > @inactive;

        # take the $to_activate newest (highest numbered) pictures
        # to reactivated
        @inactive = sort @inactive;
        my @activate_picids = splice(@inactive, -$to_activate);

        my $activate_in = join(",", map { $dbh->quote($_) } @activate_picids);
        if ($activate_in) {
            if ($u->{'dversion'} > 6) {
                $u->do("UPDATE userpic2 SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                       undef, $userid);
            } else {
                $dbh->do("UPDATE userpic SET state='N' WHERE userid=? AND picid IN ($activate_in)",
                         undef, $userid);
            }
        }
    }

    # delete userpic info object from memcache
    LJ::Userpic->delete_cache($u);

    return 1;
}


sub allpics_base {
    my $u = shift;
    return $u->journal_base . "/icons";;
}


sub get_userpic_count {
    my $u = shift or return undef;
    my $count = scalar LJ::Userpic->load_user_userpics($u);

    return $count;
}


# <LJFUNC>
# name: LJ::User::mogfs_userpic_key
# class: mogilefs
# des: Make a mogilefs key for the given pic for the user.
# args: pic
# des-pic: Either the userpic hash or the picid of the userpic.
# returns: 1.
# </LJFUNC>
sub mogfs_userpic_key {
    my $self = shift or return undef;
    my $pic = shift or croak "missing required arg: userpic";

    my $picid = ref $pic ? $pic->{picid} : $pic+0;
    return "up:$self->{userid}:$picid";
}


sub userpic {
    my $u = shift;
    return undef unless $u->{defaultpicid};
    return LJ::Userpic->new($u, $u->{defaultpicid});
}


sub userpic_quota {
    my $u = shift or return undef;
    my $quota = $u->get_cap('userpics');

    return $quota;
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


*has_friend = \&is_friend;
sub is_friend {
    confess 'LJ::User->is_friend is deprecated';
}


sub add_friend {
    confess 'LJ::User->add_friend deprecated.';
}


sub remove_friend {
    confess 'LJ::User->remove_friend has been deprecated.';
}


# take a user on dversion 7 and upgrade them to dversion 8 (clustered polls)
# DW doesn't support anything earlier than dversion 8, so this can
# probably go away at some point.

# returns if this user's polls are clustered
# DW doesn't support anything earlier than dversion 8, so this can
# probably go away at some point.
sub polls_clustered {
    my $u = shift;
    return $u->dversion >= 8;
}


sub upgrade_to_dversion_8 {
    my ( $u, $dbh, $dbhslo, $dbcm ) = @_;

    # If user has been purged, go ahead and update version
    # Otherwise move their polls
    my $ok = $u->is_expunged ? 1 : LJ::Poll->make_polls_clustered($u, $dbh, $dbhslo, $dbcm);

    LJ::update_user($u, { 'dversion' => 8 }) if $ok;

    return $ok;
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

    return 0 unless $u->journaltype =~ /[PSI]/;
    return $u->opt_showmutualfriends ? 1 : 0;
}


# FIXME: Needs updating for our gift shop
# after that, it goes in section 7
# returns the gift shop URL to buy a gift for that user
sub gift_url {
    return "$LJ::SITEROOT/shop/account?for=gift";
}



########################################################################
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

use Carp;

########################################################################
### Please keep these categorized and alphabetized for ease of use. 
### If you need a new category, add it at the end, BEFORE category 99.
### Categories kinda fuzzy, but better than nothing. Weird numbers are
### to match the sections above -- please check up there if adding.
###
### Categories:
###  1. Creating and Deleting Accounts
###  3. Working with All Types of Accounts
###  4. Login, Session, and Rename Functions
###  5. Database and Memcache Functions
###  6. What the App Shows to Users
###  7. Userprops, Caps, and Displaying Content to Others
###  8. Formatting Content Shown to Users
###  9. Logging and Recording Actions
###  12. Comment-Related Functions
###  13. Community-Related Functions and Authas
###  15. Email-Related Functions
###  16. Entry-Related Functions
###  17. Interest-Related Functions
###  19. OpenID and Identity Functions
###  21. Password Functions
###  22. Priv-Related Functions
###  24. Styles and S2-Related Functions
###  28. Userpic-Related Functions
###  99. Miscellaneous Legacy Items

########################################################################
###  1. Creating and Deleting Accounts


# <LJFUNC>
# name: LJ::create_account
# des: Creates a new basic account.  <strong>Note:</strong> This function is
#      not really too useful but should be extended to be useful so
#      htdocs/create.bml can use it, rather than doing the work itself.
# returns: integer of userid created, or 0 on failure.
# args: dbarg?, opts
# des-opts: hashref containing keys 'user', 'name', 'password', 'email', 'caps', 'journaltype'.
# </LJFUNC>
sub create_account {
    &nodb;
    my $opts = shift;
    my $u = LJ::User->create(%$opts)
        or return 0;

    return $u->id;
}


# <LJFUNC>
# name: LJ::new_account_cluster
# des: Which cluster to put a new account on.  $DEFAULT_CLUSTER if it's
#      a scalar, random element from [ljconfig[default_cluster]] if it's arrayref.
#      also verifies that the database seems to be available.
# returns: clusterid where the new account should be created; 0 on error
#          (such as no clusters available).
# </LJFUNC>
sub new_account_cluster
{
    # if it's not an arrayref, put it in an array ref so we can use it below
    my $clusters = ref $LJ::DEFAULT_CLUSTER ? $LJ::DEFAULT_CLUSTER : [ $LJ::DEFAULT_CLUSTER+0 ];

    # select a random cluster from the set we've chosen in $LJ::DEFAULT_CLUSTER
    return LJ::random_cluster(@$clusters);
}


# returns the clusterid of a random cluster which is up
# -- accepts @clusters as an arg to enforce a subset, otherwise
#    uses @LJ::CLUSTERS
sub random_cluster {
    my @clusters = @_ ? @_ : @LJ::CLUSTERS;

    # iterate through the new clusters from a random point
    my $size = @clusters;
    my $start = int(rand() * $size);
    foreach (1..$size) {
        my $cid = $clusters[$start++ % $size];

        # verify that this cluster is in @LJ::CLUSTERS
        my @check = grep { $_ == $cid } @LJ::CLUSTERS;
        next unless scalar(@check) >= 1 && $check[0] == $cid;

        # try this cluster to see if we can use it, return if so
        my $dbcm = LJ::get_cluster_master($cid);
        return $cid if $dbcm;
    }

    # if we get here, we found no clusters that were up...
    return 0;
}


########################################################################
###  2. Working with All Types of Accounts


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
sub get_userid
{
    &nodb;
    my $user = LJ::canonical_username( $_[0] );

    if ($LJ::CACHE_USERID{$user}) { return $LJ::CACHE_USERID{$user}; }

    my $userid = LJ::MemCache::get("uidof:$user");
    return $LJ::CACHE_USERID{$user} = $userid if $userid;

    my $dbr = LJ::get_db_reader();
    $userid = $dbr->selectrow_array("SELECT userid FROM useridmap WHERE user=?", undef, $user);

    # implicitly create an account if we're using an external
    # auth mechanism
    if (! $userid && ref $LJ::AUTH_EXISTS eq "CODE")
    {
        $userid = LJ::create_account({ 'user' => $user,
                                       'name' => $user,
                                       'password' => '', });
    }

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
sub get_username
{
    &nodb;
    my $userid = $_[0] + 0;

    # Checked the cache first.
    if ($LJ::CACHE_USERNAME{$userid}) { return $LJ::CACHE_USERNAME{$userid}; }

    # if we're using memcache, it's faster to just query memcache for
    # an entire $u object and just return the username.  otherwise, we'll
    # go ahead and query useridmap
    if (@LJ::MEMCACHE_SERVERS) {
        my $u = LJ::load_userid($userid);
        return undef unless $u;

        $LJ::CACHE_USERNAME{$userid} = $u->{'user'};
        return $u->{'user'};
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
sub load_user
{
    &nodb;
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

    # setup LDAP handler if this is the first time
    if ($LJ::LDAP_HOST && ! $LJ::AUTH_EXISTS) {
        require LJ::LDAP;
        $LJ::AUTH_EXISTS = sub {
            my $user = shift;
            my $rec = LJ::LDAP::load_ldap_user($user);
            return $rec ? $rec : undef;
        };
    }

    # if user doesn't exist in the LJ database, it's possible we're using
    # an external authentication source and we should create the account
    # implicitly.
    my $lu;
    if (ref $LJ::AUTH_EXISTS eq "CODE" && ($lu = $LJ::AUTH_EXISTS->($user)))
    {
        my $name = ref $lu eq "HASH" ? ($lu->{'nick'} || $lu->{name} || $user) : $user;
        if (LJ::create_account({
            'user' => $user,
            'name' => $name,
            'email' => ref $lu eq "HASH" ? $lu->email_raw : "",
            'password' => "",
        }))
        {
            # this should pull from the master, since it was _just_ created
            return $get_user->("master");
        }
    }

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
        my $u = LJ::memcache_get_u( [ $uid, "userid:$uid" ] ) if $uid;
        return _set_u_req_cache( $u ) if $u;
    }

    my $dbh = LJ::get_db_writer();
    my $uid = $dbh->selectrow_array("SELECT userid FROM identitymap WHERE idtype=? AND identity=?",
                                    undef, 'O', $url);

    my $u = LJ::load_userid($uid) if $uid;

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
# returns: Hashref with keys being columns of [dbtable[user]] table.
# </LJFUNC>
sub load_userid
{
    &nodb;
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
sub load_userids_multiple
{
    &nodb;
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

        foreach (@{$need{$u->{'userid'}}}) {
            # check if existing target is defined and not what we already have.
            if (my $eu = $$_) {
                LJ::assert_is($u->{userid}, $eu->{userid});
            }
            $$_ = $u;
        }

        delete $need{$u->{'userid'}};
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
    my $uid = $u->{userid};
    return 0 unless $uid && $u->{clusterid};

    # Update the clustertrack2 table, but not if we've done it for this
    # user in the last hour.  if no memcache servers are configured
    # we don't do the optimization and just always log the activity info
    if (@LJ::MEMCACHE_SERVERS == 0 ||
        LJ::MemCache::add("rate:tracked:$uid", 1, 3600)) {

        return 0 unless $u->writer;
        my $active = time();
        $u->do("REPLACE INTO clustertrack2 SET ".
               "userid=?, timeactive=?, clusterid=?", undef,
               $uid, $active, $u->{clusterid}) or return 0;
        my $memkey = [$u->{userid}, "timeactive:$u->{userid}"];
        LJ::MemCache::set($memkey, $active, 86400);
    }
    return 1;
}


# <LJFUNC>
# name: LJ::u_equals
# des: Compares two user objects to see if they are the same user.
# args: userobj1, userobj2
# des-userobj1: First user to compare.
# des-userobj2: Second user to compare.
# returns: Boolean, true if userobj1 and userobj2 are defined and have equal userids.
# </LJFUNC>
sub u_equals {
    my ($u1, $u2) = @_;
    return $u1 && $u2 && $u1->{'userid'} == $u2->{'userid'};
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
    return ($uuserid->{'userid'} + 0) if ref $uuserid;
    return ($uuserid + 0);
}


########################################################################
###  3. Login, Session, and Rename Functions


# returns the country that the remote IP address comes from
# undef is returned if the country cannot be determined from the IP
sub country_of_remote_ip {
    if (eval "use IP::Country::Fast; 1;") {
        my $ip = LJ::get_remote_ip();
        return undef unless $ip;

        my $reg = IP::Country::Fast->new();
        my $country = $reg->inet_atocc($ip);

        # "**" is returned if the IP is private
        return undef if $country eq "**";
        return $country;
    }

    return undef;
}

1;


sub get_active_journal
{
    return $LJ::ACTIVE_JOURNAL;
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
    $r->notes->{ljuser} = $u->{user};
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
    if (! LJ::rate_log($u, "failed_login", 1, { 'limit_by_ip' => $ip }) &&
        ($udbh = LJ::get_cluster_master($u)))
    {
        $udbh->do("REPLACE INTO loginstall (userid, ip, time) VALUES ".
                  "(?,INET_ATON(?),UNIX_TIMESTAMP())", undef, $u->{'userid'}, $ip);
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
        my $bantime = $udbr->selectrow_array("SELECT time FROM loginstall WHERE ".
                                             "userid=$u->{'userid'} AND ip=INET_ATON(?)",
                                             undef, $ip);
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


# $dom: 'L' == log, 'T' == talk, 'M' == modlog, 'S' == session,
#       'R' == memory (remembrance), 'K' == keyword id,
#       'P' == phone post, 'C' == pending comment
#       'V' == 'vgift', 'E' == ESN subscription id
#       'Q' == Notification Inbox, 
#       'D' == 'moDule embed contents', 'I' == Import data block
#       'Z' == import status item, 'X' == eXternal account
#
# FIXME: both phonepost and vgift are ljcom.  need hooks. but then also
#        need a separate namespace.  perhaps a separate function/table?
sub alloc_user_counter
{
    my ($u, $dom, $opts) = @_;
    $opts ||= {};

    ##################################################################
    # IF YOU UPDATE THIS MAKE SURE YOU ADD INITIALIZATION CODE BELOW #
    return undef unless $dom =~ /^[LTMPSRKCOVEQGDIZX]$/;             #
    ##################################################################

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $newmax;
    my $uid = $u->{'userid'}+0;
    return undef unless $uid;
    my $memkey = [$uid, "auc:$uid:$dom"];

    # in a master-master DB cluster we need to be careful that in
    # an automatic failover case where one cluster is slightly behind
    # that the same counter ID isn't handed out twice.  use memcache
    # as a sanity check to record/check latest number handed out.
    my $memmax = int(LJ::MemCache::get($memkey) || 0);

    my $rs = $dbh->do("UPDATE usercounter SET max=LAST_INSERT_ID(GREATEST(max,$memmax)+1) ".
                      "WHERE journalid=? AND area=?", undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");

        # if we've got a supplied callback, lets check the counter
        # number for consistency.  If it fails our test, wipe
        # the counter row and start over, initializing a new one.
        # callbacks should return true to signal 'all is well.'
        if ($opts->{callback} && ref $opts->{callback} eq 'CODE') {
            my $rv = 0;
            eval { $rv = $opts->{callback}->($u, $newmax) };
            if ($@ or ! $rv) {
                $dbh->do("DELETE FROM usercounter WHERE " .
                         "journalid=? AND area=?", undef, $uid, $dom);
                return LJ::alloc_user_counter($u, $dom);
            }
        }

        LJ::MemCache::set($memkey, $newmax);
        return $newmax;
    }

    if ($opts->{recurse}) {
        # We shouldn't ever get here if all is right with the world.
        return undef;
    }

    my $qry_map = {
        # for entries:
        'log'         => "SELECT MAX(jitemid) FROM log2     WHERE journalid=?",
        'logtext'     => "SELECT MAX(jitemid) FROM logtext2 WHERE journalid=?",
        'talk_nodeid' => "SELECT MAX(nodeid)  FROM talk2    WHERE nodetype='L' AND journalid=?",
        # for comments:
        'talk'     => "SELECT MAX(jtalkid) FROM talk2     WHERE journalid=?",
        'talktext' => "SELECT MAX(jtalkid) FROM talktext2 WHERE journalid=?",
    };

    my $consider = sub {
        my @tables = @_;
        foreach my $t (@tables) {
            my $res = $u->selectrow_array($qry_map->{$t}, undef, $uid);
            $newmax = $res if $res > $newmax;
        }
    };

    # Make sure the counter table is populated for this uid/dom.
    if ($dom eq "L") {
        # back in the ol' days IDs were reused (because of MyISAM)
        # so now we're extra careful not to reuse a number that has
        # foreign junk "attached".  turns out people like to delete
        # each entry by hand, but we do lazy deletes that are often
        # too lazy and a user can see old stuff come back alive
        $consider->("log", "logtext", "talk_nodeid");
    } elsif ($dom eq "T") {
        # just paranoia, not as bad as above.  don't think we've ever
        # run into cases of talktext without a talk, but who knows.
        # can't hurt.
        $consider->("talk", "talktext");
    } elsif ($dom eq "M") {
        $newmax = $u->selectrow_array("SELECT MAX(modid) FROM modlog WHERE journalid=?",
                                      undef, $uid);
    } elsif ($dom eq "S") {
        $newmax = $u->selectrow_array("SELECT MAX(sessid) FROM sessions WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "R") {
        $newmax = $u->selectrow_array("SELECT MAX(memid) FROM memorable2 WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "K") {
        $newmax = $u->selectrow_array("SELECT MAX(kwid) FROM userkeywords WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "P") {
        my $userblobmax = $u->selectrow_array("SELECT MAX(blobid) FROM userblob WHERE journalid=? AND domain=?",
                                              undef, $uid, LJ::get_blob_domainid("phonepost"));
        my $ppemax = $u->selectrow_array("SELECT MAX(blobid) FROM phonepostentry WHERE userid=?",
                                         undef, $uid);
        $newmax = ($ppemax > $userblobmax) ? $ppemax : $userblobmax;
    } elsif ($dom eq "C") {
        $newmax = $u->selectrow_array("SELECT MAX(pendid) FROM pendcomments WHERE jid=?",
                                      undef, $uid);
    } elsif ($dom eq "V") {
        $newmax = $u->selectrow_array("SELECT MAX(giftid) FROM vgifts WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "E") {
        $newmax = $u->selectrow_array("SELECT MAX(subid) FROM subs WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "Q") {
        $newmax = $u->selectrow_array("SELECT MAX(qid) FROM notifyqueue WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "D") {
        $newmax = $u->selectrow_array("SELECT MAX(moduleid) FROM embedcontent WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "I") {
        $newmax = $dbh->selectrow_array("SELECT MAX(import_data_id) FROM import_data WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "Z") {
        $newmax = $dbh->selectrow_array("SELECT MAX(import_status_id) FROM import_status WHERE userid=?",
                                      undef, $uid);
    } elsif ($dom eq "X") {
        $newmax = $u->selectrow_array("SELECT MAX(acctid) FROM externalaccount WHERE userid=?",
                                      undef, $uid);
    } else {
        die "No user counter initializer defined for area '$dom'.\n";
    }
    $newmax += 0;
    $dbh->do("INSERT IGNORE INTO usercounter (journalid, area, max) VALUES (?,?,?)",
             undef, $uid, $dom, $newmax) or return undef;

    # The 2nd invocation of the alloc_user_counter sub should do the
    # intended incrementing.
    return LJ::alloc_user_counter($u, $dom, { recurse => 1 });
}


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
    LJ::MemCache::set([$u->{'userid'}, "userid:$u->{'userid'}"], $ar, $expire);
    LJ::MemCache::set("uidof:$u->{user}", $u->{userid});
}


sub update_user
{
    my ($arg, $ref) = @_;
    my @uid;

    if (ref $arg eq "ARRAY") {
        @uid = @$arg;
    } else {
        @uid = want_userid($arg);
    }
    @uid = grep { $_ } map { $_ + 0 } @uid;
    return 0 unless @uid;

    my @sets;
    my @bindparams;
    my $used_raw = 0;
    while (my ($k, $v) = each %$ref) {
        if ($k eq "raw") {
            $used_raw = 1;
            push @sets, $v;
        } elsif ($k eq 'email') {
            set_email($_, $v) foreach @uid;
        } elsif ($k eq 'password') {
            set_password($_, $v) foreach @uid;
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
        my $where = @uid == 1 ? "userid=$uid[0]" : "userid IN (@uid)";
        $dbh->do("UPDATE user SET @sets WHERE $where", undef,
                 @bindparams);
        return 0 if $dbh->err;
    }
    if (@LJ::MEMCACHE_SERVERS) {
        LJ::memcache_kill($_, "userid") foreach @uid;
    }

    if ($used_raw) {
        # for a load of userids from the master after update
        # so we pick up the values set via the 'raw' option
        require_master(sub { LJ::load_userids(@uid) });
    } else {
        foreach my $uid (@uid) {
            while (my ($k, $v) = each %$ref) {
                my $cache = $LJ::REQ_CACHE_USER_ID{$uid} or next;
                $cache->{$k} = $v;
            }
        }
    }

    # log this updates
    LJ::run_hooks("update_user", userid => $_, fields => $ref)
        for @uid;

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
    # FIXME: this function is unused as of Aug 2009 - kareila
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
    if (my $eu = $LJ::REQ_CACHE_USER_ID{$u->{'userid'}}) {
        LJ::assert_is($eu->{userid}, $u->{userid});
        $eu->selfassert;
        $u->selfassert;

        $eu->{$_} = $u->{$_} foreach keys %$u;
        $u = $eu;
    }
    $LJ::REQ_CACHE_USER_NAME{$u->{'user'}} = $u;
    $LJ::REQ_CACHE_USER_ID{$u->{'userid'}} = $u;
    return $u;
}


########################################################################
###  6. What the App Shows to Users

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
        }, undef, $u->{userid}, $LJ::EndOfTime)) {
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
# des: Make link to userinfo/journal of user.
# info: Returns the HTML for a userinfo/journal link pair for a given user
#       name, just like LJUSER does in BML.  This is for files like cleanhtml.pl
#       and ljpoll.pl which need this functionality too, but they aren't run as BML.
# args: user, opts?
# des-user: Username to link to, or user hashref.
# des-opts: Optional hashref to control output.  Key 'full' when true causes
#           a link to the mode=full userinfo.   Key 'type' when 'C' makes
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
    my $display_class = $opts->{no_ljuser_class} ? "" : "class='ljuser'";
    my $profile;

    my $make_tag = sub {
        my ($fil, $url, $x, $y, $type) = @_;
        $y ||= $x;  # make square if only one dimension given
        my $strike = $opts->{'del'} ? ' text-decoration: line-through;' : '';

        # Backwards check, because we want it to default to on
        my $bold = (exists $opts->{'bold'} and $opts->{'bold'} == 0) ? 0 : 1;
        my $ljusername = $bold ? "<b>$user</b>" : "$user";

        my $alttext = $type ? " - $type" : "";

        my $link_color = "";
        # Make sure it's really a color
        if ($opts->{'link_color'} && $opts->{'link_color'} =~ /^#([a-fA-F0-9]{3}|[a-fA-F0-9]{6})$/) {
            $link_color = " style='color: " . $opts->{'link_color'} . ";'";
        }

        $profile = $profile_url ne '' ? $profile_url : $profile . $andfull;
        $url = $journal_url ne '' ? $journal_url : $url;

        return "<span $display_class lj:user='$user' style='white-space: nowrap;$strike'>" .
            "<a href='$profile'><img src='$img/$fil' alt='[info$alttext] ' width='$x' height='$y'" .
            " style='vertical-align: bottom; border: 0; padding-right: 1px;' /></a>" .
            "<a href='$url'$link_color>$ljusername</a></span>";
    };

    my $u = isu($user) ? $user : LJ::load_user($user);

    # Traverse the renames to the final journal
    if ($u && !$opts->{'no_follow'}) {
        $u = $u->get_renamed_user;
    }

    # if invalid user, link to dummy userinfo page
    unless ($u && isu($u)) {
        $user = LJ::canonical_username($user);
        $profile = "$LJ::SITEROOT/userinfo?user=$user";
        return $make_tag->('silk/identity/user.png', "$LJ::SITEROOT/userinfo?user=$user", 17);
    }

    $profile = $u->profile_url;

    my $type = $u->{'journaltype'};
    my $type_readable = $u->journaltype_readable;

    # Mark accounts as deleted that aren't visible, memorial, locked, or read-only
    $opts->{'del'} = 1 unless $u->is_visible || $u->is_memorial || $u->is_locked || $u->is_readonly;
    $user = $u->{'user'};

    my $url = $u->journal_base . "/";
    my $head_size = $opts->{head_size};

    if (my ($icon, $size) = LJ::run_hook("head_icon", $u, head_size => $head_size)) {
        return $make_tag->($icon, $url, $size || 16) if $icon;
    }

    if ( $type eq 'C' ) {
        return $make_tag->( "comm_${head_size}.gif", $url, $head_size, '', $type_readable ) if $head_size;
        return $make_tag->( 'silk/identity/community.png', $url, 16, '', $type_readable );
    } elsif ( $type eq 'Y' ) {
        return $make_tag->( "syn_${head_size}.gif", $url, $head_size, '', $type_readable ) if $head_size;
        return $make_tag->( 'silk/identity/feed.png', $url, 16, '', $type_readable );
    } elsif ( $type eq 'I' ) {
        return $u->ljuser_display($opts);
    } else {
        if ( $u->get_cap( 'staff_headicon' ) == 1 ) {
            return $make_tag->( "staff_${head_size}.gif", $url, $head_size, '', 'staff' ) if $head_size;
            return $make_tag->( 'silk/identity/user_staff.png', $url, 17, '', 'staff' );
        }
        else {
            return $make_tag->( "user_${head_size}.gif", $url, $head_size, '', $type_readable ) if $head_size;
            return $make_tag->( 'silk/identity/user.png', $url, 17, '', $type_readable );
        }
    }
}


########################################################################
###  7. Userprops, Caps, and Displaying Content to Others

# <LJFUNC>
# name: LJ::get_bio
# des: gets a user bio, from DB or memcache.
# args: u, force
# des-force: true to get data from cluster master.
# returns: string
# </LJFUNC>
sub get_bio {
    my ($u, $force) = @_;
    return unless $u && $u->{'has_bio'} eq "Y";

    my $bio;

    my $memkey = [$u->{'userid'}, "bio:$u->{'userid'}"];
    unless ($force) {
        my $bio = LJ::MemCache::get($memkey);
        return $bio if defined $bio;
    }

    # not in memcache, fall back to disk
    my $db = @LJ::MEMCACHE_SERVERS || $force ?
      LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
    $bio = $db->selectrow_array("SELECT bio FROM userbio WHERE userid=?",
                                undef, $u->{'userid'});

    # set in memcache
    LJ::MemCache::add($memkey, $bio);

    return $bio;
}


# <LJFUNC>
# name: LJ::load_user_props
# des: Given a user hashref, loads the values of the given named properties
#      into that user hashref.
# args: dbarg?, u, opts?, propname*
# des-opts: hashref of opts.  set key 'cache' to use memcache.
# des-propname: the name of a property from the [dbtable[userproplist]] table.
# </LJFUNC>
sub load_user_props
{
    &nodb;

    my $u = shift;
    return unless isu($u);
    return if $u->is_expunged;

    my $opts = ref $_[0] ? shift : {};
    my (@props) = @_;

    my ($sql, $sth);
    LJ::load_props("user");

    ## user reference
    my $uid = $u->{'userid'}+0;
    $uid = LJ::get_userid($u->{'user'}) unless $uid;

    my $mem = {};
    my $use_master = 0;
    my $used_slave = 0;  # set later if we ended up using a slave

    if (@LJ::MEMCACHE_SERVERS) {
        my @keys;
        foreach (@props) {
            next if exists $u->{$_};
            my $p = LJ::get_prop("user", $_);
            die "Invalid userprop $_ passed to LJ::load_user_props." unless $p;
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
            die "Invalid userprop $_ passed to LJ::load_user_props." unless $p;
            if (defined $mem->{"uprop:$uid:$p->{'id'}"}) {
                $u->{$_} = $mem->{"uprop:$uid:$p->{'id'}"};
                next;
            }
            push @needwrite, [ $p->{'id'}, $_ ];
            my $source = $p->{'indexed'} ? "userprop" : "userproplite";
            if ($p->{datatype} eq 'blobchar') {
                $source = "userpropblob"; # clustered blob
            }
            elsif ($p->{'cldversion'} && $u->{'dversion'} >= $p->{'cldversion'}) {
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


# <LJFUNC>
# name: LJ::modify_caps
# des: Given a list of caps to add and caps to remove, updates a user's caps.
# args: uuid, cap_add, cap_del, res
# des-cap_add: arrayref of bit numbers to turn on
# des-cap_del: arrayref of bit numbers to turn off
# des-res: hashref returned from 'modify_caps' hook
# returns: updated u object, retrieved from $dbh, then 'caps' key modified
#          otherwise, returns 0 unless all hooks run properly.
# </LJFUNC>
sub modify_caps {
    my ($argu, $cap_add, $cap_del, $res) = @_;
    my $userid = LJ::want_userid($argu);
    return undef unless $userid;

    $cap_add ||= [];
    $cap_del ||= [];
    my %cap_add_mod = ();
    my %cap_del_mod = ();

    # convert capnames to bit numbers
    if (LJ::are_hooks("get_cap_bit")) {
        foreach my $bit (@$cap_add, @$cap_del) {
            next if $bit =~ /^\d+$/;

            # bit is a magical reference into the array
            $bit = LJ::run_hook("get_cap_bit", $bit);
        }
    }

    # get a u object directly from the db
    my $u = LJ::load_userid($userid, "force");

    # add new caps
    my $newcaps = int($u->{'caps'});
    foreach (@$cap_add) {
        my $cap = 1 << $_;

        # about to turn bit on, is currently off?
        $cap_add_mod{$_} = 1 unless $newcaps & $cap;
        $newcaps |= $cap;
    }

    # remove deleted caps
    foreach (@$cap_del) {
        my $cap = 1 << $_;

        # about to turn bit off, is it currently on?
        $cap_del_mod{$_} = 1 if $newcaps & $cap;
        $newcaps &= ~$cap;
    }

    # run hooks for modified bits
    if (LJ::are_hooks("modify_caps")) {
        $res = LJ::run_hook("modify_caps",
                            { 'u' => $u,
                              'newcaps' => $newcaps,
                              'oldcaps' => $u->{'caps'},
                              'cap_on_req'  => { map { $_ => 1 } @$cap_add },
                              'cap_off_req' => { map { $_ => 1 } @$cap_del },
                              'cap_on_mod'  => \%cap_add_mod,
                              'cap_off_mod' => \%cap_del_mod,
                          });

        # hook should return a status code
        return undef unless defined $res;
    }

    # update user row
    return 0 unless LJ::update_user($u, { 'caps' => $newcaps });

    $u->{caps} = $newcaps;
    $argu->{caps} = $newcaps if ref $argu; # FIXME: temp hack
    return $u;
}


# <LJFUNC>
# name: LJ::set_userprop
# des: Sets/deletes a userprop by name for a user.
# info: This adds or deletes from the
#       [dbtable[userprop]]/[dbtable[userproplite]] tables.  One
#       crappy thing about this interface is that it doesn't allow
#       a batch of userprops to be updated at once, which is the
#       common thing to do.
# args: dbarg?, uuserid, propname, value, memonly?
# des-uuserid: The userid of the user or a user hashref.
# des-propname: The name of the property.  Or a hashref of propname keys and corresponding values.
# des-value: The value to set to the property.  If undefined or the
#            empty string, then property is deleted.
# des-memonly: if true, only writes to memcache, and not to database.
# </LJFUNC>
sub set_userprop
{
    &nodb;
    my ($u, $propname, $value, $memonly) = @_;
    $u = ref $u ? $u : LJ::load_userid($u);
    my $userid = $u->{'userid'}+0;

    my $hash = ref $propname eq "HASH" ? $propname : { $propname => $value };

    my %action;  # $table -> {"replace"|"delete"} -> [ "($userid, $propid, $qvalue)" | propid ]
    my %multihomed;  # { $propid => $value }

    foreach $propname (keys %$hash) {
        LJ::run_hook("setprop", prop => $propname,
                     u => $u, value => $value);

        my $p = LJ::get_prop("user", $propname) or
            die "Invalid userprop $propname passed to LJ::set_userprop.";
        if ($p->{multihomed}) {
            # collect into array for later handling
            $multihomed{$p->{id}} = $hash->{$propname};
            next;
        }
        my $table = $p->{'indexed'} ? "userprop" : "userproplite";
        if ($p->{datatype} eq 'blobchar') {
            $table = 'userpropblob';
        }
        elsif ($p->{'cldversion'} && $u->{'dversion'} >= $p->{'cldversion'}) {
            $table = "userproplite2";
        }
        unless ($memonly) {
            my $db = $action{$table}->{'db'} ||= (
                $table !~ m{userprop(lite2|blob)}
                    ? LJ::get_db_writer()
                    : $u->writer );
            return 0 unless $db;
        }
        $value = $hash->{$propname};
        if (defined $value && $value) {
            push @{$action{$table}->{"replace"}}, [ $p->{'id'}, $value ];
        } else {
            push @{$action{$table}->{"delete"}}, $p->{'id'};
        }
    }

    my $expire = time() + 3600*24;
    foreach my $table (keys %action) {
        my $db = $action{$table}->{'db'};
        if (my $list = $action{$table}->{"replace"}) {
            if ($db) {
                my $vals = join(',', map { "($userid,$_->[0]," . $db->quote($_->[1]) . ")" } @$list);
                $db->do("REPLACE INTO $table (userid, upropid, value) VALUES $vals");
            }
            LJ::MemCache::set([$userid,"uprop:$userid:$_->[0]"], $_->[1], $expire) foreach (@$list);
        }
        if (my $list = $action{$table}->{"delete"}) {
            if ($db) {
                my $in = join(',', @$list);
                $db->do("DELETE FROM $table WHERE userid=$userid AND upropid IN ($in)");
            }
            LJ::MemCache::set([$userid,"uprop:$userid:$_"], "", $expire) foreach (@$list);
        }
    }

    # if we had any multihomed props, set them here
    if (%multihomed) {
        my $dbh = LJ::get_db_writer();
        return 0 unless $dbh && $u->writer;
        while (my ($propid, $pvalue) = each %multihomed) {
            if (defined $pvalue && $pvalue) {
                # replace data into master
                $dbh->do("REPLACE INTO userprop VALUES (?, ?, ?)",
                         undef, $userid, $propid, $pvalue);
            } else {
                # delete data from master, but keep in cluster
                $dbh->do("DELETE FROM userprop WHERE userid = ? AND upropid = ?",
                         undef, $userid, $propid);
            }

            # fail out?
            return 0 if $dbh->err;

            # put data in cluster
            $pvalue ||= '';
            $u->do("REPLACE INTO userproplite2 VALUES (?, ?, ?)",
                   undef, $userid, $propid, $pvalue);
            return 0 if $u->err;

            # set memcache
            LJ::MemCache::set([$userid,"uprop:$userid:$propid"], $pvalue, $expire);
        }
    }

    return 1;
}


########################################################################
###  8. Formatting Content Shown to Users


# Returns HTML to display user search results
# Args: %args
# des-args:
#           users    => hash ref of userid => u object like LJ::load userids
#                       returns or array ref of user objects
#           userids  => array ref of userids to include in results, ignored
#                       if users is defined
#           timesort => set to 1 to sort by last updated instead
#                       of username
#           perpage  => Enable pagination and how many users to display on
#                       each page
#           curpage  => What page of results to display
#           navbar   => Scalar reference for paging bar
#           pickwd   => userpic keyword to display instead of default if it
#                       exists for the user
#           self_link => Sub ref to generate link to use for pagination
sub user_search_display {
    my %args = @_;

    my $loaded_users;
    unless (defined $args{users}) {
        $loaded_users = LJ::load_userids(@{$args{userids}});
    } else {
        if (ref $args{users} eq 'HASH') { # Assume this is direct from LJ::load_userids
            $loaded_users = $args{users};
        } elsif (ref $args{users} eq 'ARRAY') { # They did a grep on it or something
            foreach (@{$args{users}}) {
                $loaded_users->{$_->{userid}} = $_;
            }
        } else {
            return undef;
        }
    }

    # If we're sorting by last updated, we need to load that
    # info for all users before the sort.  If sorting by
    # username we can load it for a subset of users later,
    # if paginating.
    my $updated;
    my @display;

    if ($args{timesort}) {
        $updated = LJ::get_timeupdate_multi(keys %$loaded_users);
        @display = sort { $updated->{$b->{userid}} <=> $updated->{$a->{userid}} } values %$loaded_users;
    } else {
        @display = sort { $a->{user} cmp $b->{user} } values %$loaded_users;
    }

    if (defined $args{perpage}) {
        my %items = BML::paging(\@display, $args{curpage}, $args{perpage});

        # Fancy paging bar
        my $opts;
        $opts->{self_link} = $args{self_link} if $args{self_link};
        ${$args{navbar}} = LJ::paging_bar($items{'page'}, $items{'pages'}, $opts);

        # Now pull out the set of users to display
        @display = @{$items{'items'}};
    }

    # If we aren't sorting by time updated, load last updated time for the
    # set of users we are displaying.
    $updated = LJ::get_timeupdate_multi(map { $_->{userid} } @display)
        unless $args{timesort};

    # Allow caller to specify a custom userpic to use instead
    # of the user's default all userpics
    my $get_picid = sub {
        my $u = shift;
        return $u->{'defaultpicid'} unless $args{'pickwd'};
        return LJ::get_picid_from_keyword($u, $args{'pickwd'});
    };

    my $ret;
    foreach my $u (@display) {
        # We should always have loaded user objects, but it seems
        # when the site is overloaded we don't always load the users
        # we request.
        next unless LJ::isu($u);

        $ret .= "<div class='user-search-display'>";
        $ret .= "<table style='height: 105px'><tr>";

        $ret .= "<td style='width: 100px; text-align: center;'>";
        $ret .= "<a href='" . $u->allpics_base . "'>";
        if (my $picid = $get_picid->($u)) {
            $ret .= "<img src='$LJ::USERPIC_ROOT/$picid/$u->{userid}' alt='$u->{user} userpic' style='border: 1px solid #000;' />";
        } else {
            $ret .= "<img src='$LJ::IMGPREFIX/nouserpic.png' alt='" . BML::ml( 'search.user.nopic' );
            $ret .= "' style='border: 1px solid #000;' width='100' height='100' />";
        }
        $ret .= "</a>";

        $ret .= "</td><td style='padding-left: 5px;' valign='top'><table>";

        $ret .= "<tr><td class='searchusername' colspan='2' style='text-align: left;'>";
        $ret .= $u->ljuser_display({ head_size => $args{head_size} });
        $ret .= "</td></tr><tr>";

        if ($u->{name}) {
            $ret .= "<td width='1%' style='font-size: smaller' valign='top'>" . BML::ml( 'search.user.name' );
            $ret .= "</td><td style='font-size: smaller'><a href='" . $u->profile_url . "'>";
            $ret .= LJ::ehtml($u->{name});
            $ret .= "</a>";
            $ret .= "</td></tr><tr>";
        }

        if (my $jtitle = $u->prop('journaltitle')) {
            $ret .= "<td width='1%' style='font-size: smaller' valign='top'>" . BML::ml( 'search.user.journal' );
            $ret .= "</td><td style='font-size: smaller'><a href='" . $u->journal_base . "'>";
            $ret .= LJ::ehtml($jtitle) . "</a>";
            $ret .= "</td></tr>";
        }

        $ret .= "<tr><td colspan='2' style='text-align: left; font-size: smaller' class='lastupdated'>";

        if ( $updated->{$u->userid} > 0 ) {
            $ret .= BML::ml( 'search.user.update.last', { time => LJ::ago_text( time() - $updated->{$u->userid} ) } );
        } else {
            $ret .= BML::ml( 'search.user.update.never' );
        }

        $ret .= "</td></tr>";

        $ret .= "</table>";
        $ret .= "</td></tr>";
        $ret .= "</table></div>";
    }

    return $ret;
}


########################################################################
###  9. Logging and Recording Actions

# <LJFUNC>
# name: LJ::infohistory_add
# des: Add a line of text to the [[dbtable[infohistory]] table for an account.
# args: uuid, what, value, other?
# des-uuid: User id or user object to insert infohistory for.
# des-what: What type of history is being inserted (15 chars max).
# des-value: Value for the item (255 chars max).
# des-other: Optional. Extra information / notes (30 chars max).
# returns: 1 on success, 0 on error.
# </LJFUNC>
sub infohistory_add {
    my ($uuid, $what, $value, $other) = @_;
    $uuid = LJ::want_userid($uuid);
    return unless $uuid && $what && $value;

    # get writer and insert
    my $dbh = LJ::get_db_writer();
    my $gmt_now = LJ::mysql_time(time(), 1);
    $dbh->do("INSERT INTO infohistory (userid, what, timechange, oldvalue, other) VALUES (?, ?, ?, ?, ?)",
             undef, $uuid, $what, $gmt_now, $value, $other);
    return $dbh->err ? 0 : 1;
}


# returns 1 if action is permitted.  0 if above rate or fail.
sub rate_check {
    my ($u, $ratename, $count, $opts) = @_;

    my $rateperiod = LJ::get_cap($u, "rateperiod-$ratename");
    return 1 unless $rateperiod;

    my $rp = defined $opts->{'rp'} ? $opts->{'rp'}
             : LJ::get_prop("rate", $ratename);
    return 0 unless $rp;

    my $now = defined $opts->{'now'} ? $opts->{'now'} : time();
    my $beforeperiod = $now - $rateperiod;

    # check rate.  (okay per period)
    my $opp = LJ::get_cap($u, "rateallowed-$ratename");
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
    $u->do("DELETE FROM ratelog WHERE userid=$u->{'userid'} AND rlid=$rp->{'id'} ".
           "AND evttime < $beforeperiod LIMIT 1000");

    my $udbr = LJ::get_cluster_reader($u);
    my $ip = defined $opts->{'ip'}
             ? $opts->{'ip'}
             : $udbr->quote($opts->{'limit_by_ip'} || "0.0.0.0");
    my $sth = $udbr->prepare("SELECT evttime, quantity FROM ratelog WHERE ".
                             "userid=$u->{'userid'} AND rlid=$rp->{'id'} ".
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
        # TODO: optionally log to rateabuse, unless caller is doing it themselves
        # somehow, like with the "loginstall" table.
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
sub rate_log
{
    my ($u, $ratename, $count, $opts) = @_;
    my $rateperiod = LJ::get_cap($u, "rateperiod-$ratename");
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
    return 0 unless LJ::rate_check($u, $ratename, $count, $opts);

    # log current
    $count = $count + 0;
    $u->do("INSERT INTO ratelog (userid, rlid, evttime, ip, quantity) VALUES ".
           "($u->{'userid'}, $rp->{'id'}, $now, INET_ATON($ip), $count)");

    # delete memcache, except in the case of rate limiting by ip
    unless ($opts->{limit_by_ip}) {
        LJ::MemCache::delete($u->rate_memkey($rp));
    }

    return 1;
}


########################################################################
###  12. Comment-Related Functions

# <LJFUNC>
# name: LJ::delete_all_comments
# des: deletes all comments from a post, permanently, for when a post is deleted
# info: The tables [dbtable[talk2]], [dbtable[talkprop2]], [dbtable[talktext2]],
#       are deleted from, immediately.
# args: u, nodetype, nodeid
# des-nodetype: The thread nodetype (probably 'L' for log items).
# des-nodeid: The thread nodeid for the given nodetype (probably the jitemid
#             from the [dbtable[log2]] row).
# returns: boolean; success value
# </LJFUNC>
sub delete_all_comments {
    my ($u, $nodetype, $nodeid) = @_;

    my $dbcm = LJ::get_cluster_master($u);
    return 0 unless $dbcm && $u->writer;

    # delete comments
    my ($t, $loop) = (undef, 1);
    my $chunk_size = 200;
    while ($loop &&
           ($t = $dbcm->selectcol_arrayref("SELECT jtalkid FROM talk2 WHERE ".
                                           "nodetype=? AND journalid=? ".
                                           "AND nodeid=? LIMIT $chunk_size", undef,
                                           $nodetype, $u->{'userid'}, $nodeid))
           && $t && @$t)
    {
        my $in = join(',', map { $_+0 } @$t);
        return 1 unless $in;
        foreach my $table (qw(talkprop2 talktext2 talk2)) {
            $u->do("DELETE FROM $table WHERE journalid=? AND jtalkid IN ($in)",
                   undef, $u->{'userid'});
        }
        # decrement memcache
        LJ::MemCache::decr([$u->{'userid'}, "talk2ct:$u->{'userid'}"], scalar(@$t));
        $loop = 0 unless @$t == $chunk_size;
    }
    return 1;

}


########################################################################
###  13. Community-Related Functions and Authas


sub can_delete_journal_item {
    return LJ::can_manage(@_);
}


# <LJFUNC>
# name: LJ::can_manage
# des: Given a user and a target user, will determine if the first user is an
#      admin for the target user.
# returns: bool: true if authorized, otherwise fail
# args: remote, u
# des-remote: user object or userid of user to try and authenticate
# des-u: user object or userid of target user
# </LJFUNC>
sub can_manage {
    my $remote = LJ::want_user(shift);
    my $u = LJ::want_user(shift);
    return undef unless $remote && $u;

    # is same user?
    return 1 if LJ::u_equals($u, $remote);

    # people/syn/rename accounts can only be managed by the one account
    return undef if $u->{journaltype} =~ /^[PYR]$/;

    # check for admin access
    return undef unless LJ::check_rel($u, $remote, 'A');

    # passed checks, return true
    return 1;
}


# <LJFUNC>
# name: LJ::can_manage_other
# des: Given a user and a target user, will determine if the first user is an
#      admin for the target user, but not if the two are the same.
# args: remote, u
# des-remote: user object or userid of user to try and authenticate
# des-u: user object or userid of target user
# returns: bool: true if authorized, otherwise fail
# </LJFUNC>
sub can_manage_other {
    my ($remote, $u) = @_;
    return 0 if LJ::want_userid($remote) == LJ::want_userid($u);
    return LJ::can_manage($remote, $u);
}


# <LJFUNC>
# name: LJ::get_authas_list
# des: Get a list of usernames a given user can authenticate as.
# returns: an array of usernames.
# args: u, opts?
# des-opts: Optional hashref.  keys are:
#           - type: 'P' to only return users of journaltype 'P'.
#           - cap:  cap to filter users on.
# </LJFUNC>
sub get_authas_list {
    my ($u, $opts) = @_;

    # used to accept a user type, now accept an opts hash
    $opts = { 'type' => $opts } unless ref $opts;

    # Two valid types, Personal or Community
    $opts->{'type'} = undef unless $opts->{'type'} =~ m/^(P|C)$/;

    my $ids = LJ::load_rel_target($u, 'A');
    return undef unless $ids;

    # load_userids_multiple
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);

    return map { $_->{'user'} }
               grep { ! $opts->{'cap'} || LJ::get_cap($_, $opts->{'cap'}) }
               grep { ! $opts->{'type'} || $opts->{'type'} eq $_->{'journaltype'} }

               # unless overridden, hide non-visible/non-read-only journals. always display the user's acct
               grep { $opts->{'showall'} || $_->is_visible || $_->is_readonly || LJ::u_equals($_, $u) }

               # can't work as an expunged account
               grep { !$_->is_expunged && $_->{clusterid} > 0 }
               $u,  sort { $a->{'user'} cmp $b->{'user'} } values %users;
}


# <LJFUNC>
# name: LJ::get_postto_list
# des: Get the list of usernames a given user can post to.
# returns: an array of usernames
# args: u, opts?
# des-opts: Optional hashref.  keys are:
#           - type: 'P' to only return users of journaltype 'P'.
#           - cap:  cap to filter users on.
# </LJFUNC>
sub get_postto_list {
    my ($u, $opts) = @_;

    # used to accept a user type, now accept an opts hash
    $opts = { 'type' => $opts } unless ref $opts;

    # only one valid type right now
    $opts->{'type'} = 'P' if $opts->{'type'};

    my $ids = LJ::load_rel_target($u, 'P');
    return undef unless $ids;

    # load_userids_multiple
    my %users;
    LJ::load_userids_multiple([ map { $_, \$users{$_} } @$ids ], [$u]);

    return $u->{'user'}, sort map { $_->{'user'} }
                         grep { ! $opts->{'cap'} || LJ::get_cap($_, $opts->{'cap'}) }
                         grep { ! $opts->{'type'} || $opts->{'type'} eq $_->{'journaltype'} }
                         grep { $_->clusterid > 0 }
                         grep { $_->is_visible }
                         values %users;
}


########################################################################
###  15. Email-Related Functions

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
###  16. Entry-Related Functions

# <LJFUNC>
# name: LJ::can_view
# des: Checks to see if the remote user can view a given journal entry.
#      <b>Note:</b> This is meant for use on single entries at a time,
#      not for calling many times on every entry in a journal.
# returns: boolean; 1 if remote user can see item
# args: remote, item
# des-item: Hashref from the 'log' table.
# </LJFUNC>
sub can_view
{

# TODO: fold this into LJ::Entry->visible_to :(

    &nodb;
    my ( $remote, $item ) = @_;

    # public is okay
    return 1 if $item->{'security'} eq "public";

    # must be logged in otherwise
    return 0 unless $remote;

    my $userid = int($item->{'ownerid'} || $item->{'journalid'});
    my $remoteid = int($remote->{'userid'});

    # owners can always see their own.
    return 1 if $userid == $remoteid;

    # other people can't read private
    return 0 if $item->{'security'} eq "private";

    # should be 'usemask' security from here out, otherwise
    # assume it's something new and return 0
    return 0 unless $item->{'security'} eq "usemask";

    # if it's usemask, we have to refuse non-personal journals,
    # so we have to load the user
    return 0 unless $remote->{'journaltype'} eq 'P' || $remote->{'journaltype'} eq 'I';

    # this far down we have to load the user
    my $u = LJ::want_user( $userid ) or return 0;

    # check if it's a community and they're a member
    return 1 if $u->is_community &&
                $remote->member_of( $u );

    # now load allowmask
    my $allowed = ( $u->trustmask( $remoteid ) & int($item->{'allowmask'}) );
    return $allowed ? 1 : 0;  # no need to return matching mask
}


########################################################################
###  17. Interest-Related Functions

# $opts is optional, with keys:
#    forceids => 1   : don't use memcache for loading the intids
#    forceints => 1   : don't use memcache for loading the interest rows
#    justids => 1 : return arrayref of intids only, not names/counts
# returns otherwise an arrayref of interest rows, sorted by interest name
sub get_interests
{
    my ($u, $opts) = @_;
    $opts ||= {};
    return undef unless $u;

    # first check request cache inside $u
    if (my $ints = $u->{_cache_interests}) {
        if ($opts->{justids}) {
            return [ map { $_->[0] } @$ints ];
        }
        return $ints;
    }

    my $uid = $u->{userid};
    my $uitable = $u->{'journaltype'} eq 'C' ? 'comminterests' : 'userinterests';

    # load the ids
    my $ids;
    my $mk_ids = [$uid, "intids:$uid"];
    $ids = LJ::MemCache::get($mk_ids) unless $opts->{'forceids'};
    unless ($ids && ref $ids eq "ARRAY") {
        $ids = [];
        my $dbh = LJ::get_db_writer();
        my $sth = $dbh->prepare("SELECT intid FROM $uitable WHERE userid=?");
        $sth->execute($uid);
        push @$ids, $_ while ($_) = $sth->fetchrow_array;
        LJ::MemCache::add($mk_ids, $ids, 3600*12);
    }

    # FIXME: set a 'justids' $u cache key in this case, then only return that
    #        later if 'justids' is requested?  probably not worth it.
    return $ids if $opts->{'justids'};

    # load interest rows
    my %need;
    $need{$_} = 1 foreach @$ids;
    my @ret;

    unless ($opts->{'forceints'}) {
        if (my $mc = LJ::MemCache::get_multi(map { [$_, "introw:$_"] } @$ids)) {
            while (my ($k, $v) = each %$mc) {
                next unless $k =~ /^introw:(\d+)/;
                delete $need{$1};
                push @ret, $v;
            }
        }
    }

    if (%need) {
        my $ids = join(",", map { $_+0 } keys %need);
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT intid, interest, intcount FROM interests ".
                                "WHERE intid IN ($ids)");
        $sth->execute;
        my $memc_store = 0;
        while (my ($intid, $int, $count) = $sth->fetchrow_array) {
            # minimize latency... only store 25 into memcache at a time
            # (too bad we don't have set_multi.... hmmmm)
            my $aref = [$intid, $int, $count];
            if ($memc_store++ < 25) {
                # if the count is fairly high, keep item in memcache longer,
                # since count's not so important.
                my $expire = $count < 10 ? 3600*12 : 3600*48;
                LJ::MemCache::add([$intid, "introw:$intid"], $aref, $expire);
            }
            push @ret, $aref;
        }
    }

    @ret = sort { $a->[1] cmp $b->[1] } @ret;
    return $u->{_cache_interests} = \@ret;
}


sub interest_string_to_list {
    my $intstr = shift;

    $intstr =~ s/^\s+//;  # strip leading space
    $intstr =~ s/\s+$//;  # strip trailing space
    $intstr =~ s/\n/,/g;  # newlines become commas
    $intstr =~ s/\s+/ /g; # strip duplicate spaces from the interest

    # final list is ,-sep
    return grep { length } split (/\s*,\s*/, $intstr);
}


# <LJFUNC>
# name: LJ::set_interests
# des: Change a user's interests.
# args: dbarg?, u, old, new
# des-old: hashref of old interests (hashing being interest => intid)
# des-new: listref of new interests
# returns: 1 on success, undef on failure
# </LJFUNC>
sub set_interests
{
    my ($u, $old, $new) = @_;

    $u = LJ::want_user($u);
    my $userid = $u->{'userid'};
    return undef unless $userid;

    return undef unless ref $old eq 'HASH';
    return undef unless ref $new eq 'ARRAY';

    my $dbh = LJ::get_db_writer();
    my %int_new = ();
    my %int_del = %$old;  # assume deleting everything, unless in @$new

    # user interests go in a different table than user interests,
    # though the schemas are the same so we can run the same queries on them
    my $uitable = $u->{'journaltype'} eq 'C' ? 'comminterests' : 'userinterests';

    # track if we made changes to refresh memcache later.
    my $did_mod = 0;

    my @valid_ints = LJ::validate_interest_list(@$new);
    foreach my $int (@valid_ints)
    {
        $int_new{$int} = 1 unless $old->{$int};
        delete $int_del{$int};
    }

    ### were interests removed?
    if (%int_del)
    {
        ## easy, we know their IDs, so delete them en masse
        my $intid_in = join(", ", values %int_del);
        $dbh->do("DELETE FROM $uitable WHERE userid=$userid AND intid IN ($intid_in)");
        $dbh->do("UPDATE interests SET intcount=intcount-1 WHERE intid IN ($intid_in)");
        $did_mod = 1;
    }

    ### do we have new interests to add?
    my @new_intids = ();  ## existing IDs we'll add for this user
    if (%int_new)
    {
        $did_mod = 1;

        ## difficult, have to find intids of interests, and create new ints for interests
        ## that nobody has ever entered before
        my $int_in = join(", ", map { $dbh->quote($_); } keys %int_new);
        my %int_exist;

        ## find existing IDs
        my $sth = $dbh->prepare("SELECT interest, intid FROM interests WHERE interest IN ($int_in)");
        $sth->execute;
        while (my ($intr, $intid) = $sth->fetchrow_array) {
            push @new_intids, $intid;       # - we'll add this later.
            delete $int_new{$intr};         # - so we don't have to make a new intid for
                                            #   this next pass.
        }

        if (@new_intids) {
            my $sql = "";
            foreach my $newid (@new_intids) {
                if ($sql) { $sql .= ", "; }
                else { $sql = "REPLACE INTO $uitable (userid, intid) VALUES "; }
                $sql .= "($userid, $newid)";
            }
            $dbh->do($sql);

            my $intid_in = join(", ", @new_intids);
            $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid IN ($intid_in)");
        }
    }

    ### do we STILL have interests to add?  (must make new intids)
    if (%int_new)
    {
        foreach my $int (keys %int_new)
        {
            my $intid;
            my $qint = $dbh->quote($int);

            $dbh->do("INSERT INTO interests (intid, intcount, interest) ".
                     "VALUES (NULL, 1, $qint)");
            if ($dbh->err) {
                # somebody beat us to creating it.  find its id.
                $intid = $dbh->selectrow_array("SELECT intid FROM interests WHERE interest=$qint");
                $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid=$intid");
            } else {
                # newly created
                $intid = $dbh->{'mysql_insertid'};
            }
            if ($intid) {
                ## now we can actually insert it into the userinterests table:
                $dbh->do("INSERT INTO $uitable (userid, intid) ".
                         "VALUES ($userid, $intid)");
                push @new_intids, $intid;
            }
        }
    }
    LJ::run_hooks("set_interests", $u, \%int_del, \@new_intids); # interest => intid

    # do migrations to clean up userinterests vs comminterests conflicts
    $u->lazy_interests_cleanup;

    LJ::memcache_kill($u, "intids") if $did_mod;
    $u->{_cache_interests} = undef if $did_mod;

    return 1;
}


sub validate_interest_list {
    my $interrors = ref $_[0] eq "ARRAY" ? shift : [];
    my @ints = @_;

    my @valid_ints = ();
    foreach my $int (@ints) {
        $int = lc($int);       # FIXME: use utf8?
        $int =~ s/^i like //;  # *sigh*
        next unless $int;

        # Specific interest failures
        my ($bytes,$chars) = LJ::text_length($int);

        my $error_string = '';
        if ($int =~ /[\<\>]/) {
            $int = LJ::ehtml($int);
            $error_string .= '.invalid';
        } else {
            $error_string .= '.bytes' if $bytes > LJ::BMAX_INTEREST;
            $error_string .= '.chars' if $chars > LJ::CMAX_INTEREST;
        }

        if ($error_string) {
            $error_string = "error.interest$error_string";
            push @$interrors, [ $error_string,
                                { int => $int,
                                  bytes => $bytes,
                                  bytes_max => LJ::BMAX_INTEREST,
                                  chars => $chars,
                                  chars_max => LJ::CMAX_INTEREST
                                }
                              ];
            next;
        }
        push @valid_ints, $int;
    }
    return @valid_ints;
}


########################################################################
###  19. OpenID and Identity Functions

# create externally mapped user.
# return uid of LJ user on success, undef on error.
# opts = {
#     extuser or extuserid (or both, but one is required.),
#     caps
# }
# opts also can contain any additional options that create_account takes. (caps?)
sub create_extuser
{
    my ($type, $opts) = @_;
    return undef unless $type && $LJ::EXTERNAL_NAMESPACE{$type}->{id};
    return undef unless ref $opts &&
        ($opts->{extuser} || defined $opts->{extuserid});

    my $uid;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # make sure a mapping for this user doesn't already exist.
    $uid = LJ::get_extuser_uid( $type, $opts, 'force' );
    return $uid if $uid;

    # increment ext_ counter until we successfully create an LJ account.
    # hard cap it at 10 tries. (arbitrary, but we really shouldn't have *any*
    # failures here, let alone 10 in a row.)
    for (1..10) {
        my $extuser = 'ext_' . LJ::alloc_global_counter( 'E' );
        $uid =
          LJ::create_account(
            { caps => $opts->{caps}, user => $extuser, name => $extuser } );
        last if $uid;
        select undef, undef, undef, .10;  # lets not thrash over this.
    }
    return undef unless $uid;

    # add extuser mapping.
    my $sql = "INSERT INTO extuser SET userid=?, siteid=?";
    my @bind = ($uid, $LJ::EXTERNAL_NAMESPACE{$type}->{id});

    if ($opts->{extuser}) {
        $sql .= ", extuser=?";
        push @bind, $opts->{extuser};
    }

    if ($opts->{extuserid}) {
        $sql .= ", extuserid=? ";
        push @bind, $opts->{extuserid}+0;
    }

    $dbh->do($sql, undef, @bind) or return undef;
    return $uid;
}


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
###  21. Password Functions

# Checks if they are flagged as having a bad password and redirects
# to changepassword.bml.  If returl is on it returns the URL to
# redirect to vs doing the redirect itself.  Useful in non-BML context
# and for QuickReply links
sub bad_password_redirect {
    my $opts = shift;

    my $remote = LJ::get_remote();
    return undef unless $remote;

    return undef unless LJ::is_enabled('force_pass_change');

    return undef unless $remote->prop('badpassword');

    my $redir = "$LJ::SITEROOT/changepassword";
    unless (defined $opts->{'returl'}) {
        return BML::redirect($redir);
    } else {
        return $redir;
    }
}


sub set_password {
    my ($userid, $password) = @_;

    my $dbh = LJ::get_db_writer();
    if ($LJ::DEBUG{'write_passwords_to_user_table'}) {
        $dbh->do("UPDATE user SET password=? WHERE userid=?", undef,
                 $password, $userid);
    }
    $dbh->do("REPLACE INTO password (userid, password) VALUES (?, ?)",
             undef, $userid, $password);

    # update caches
    LJ::memcache_kill($userid, "userid");
    LJ::MemCache::delete([$userid, "pw:$userid"]);
    my $cache = $LJ::REQ_CACHE_USER_ID{$userid} or return;
    $cache->{'_password'} = $password;
}


########################################################################
###  22. Priv-Related Functions

# <LJFUNC>
# name: LJ::check_priv
# des: Check to see if a user has a certain privilege.
# info: Usually this is used to check the privs of a $remote user.
#       See [func[LJ::get_remote]].  As such, a $u argument of undef
#       is okay to pass: 0 will be returned, as an unknown user can't
#       have any rights.
# args: dbarg?, u, priv, arg?
# des-priv: Priv name to check for (see [dbtable[priv_list]])
# des-arg: Optional argument.  If defined, function only returns true
#          when $remote has a priv of type $priv also with arg $arg, not
#          just any priv of type $priv, which is the behavior without
#          an $arg. Arg can be "*", for all args.
# returns: boolean; true if user has privilege
# </LJFUNC>
sub check_priv
{
    &nodb;
    my ($u, $priv, $arg) = @_;
    return 0 unless $u;

    LJ::load_user_privs($u, $priv)
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


# <LJFUNC>
# name: LJ::load_user_privs
# class:
# des: loads all of the given privs for a given user into a hashref, inside
#      the user record.  See also [func[LJ::check_priv]].
# args: u, priv, arg?
# des-priv: Priv names to load (see [dbtable[priv_list]]).
# des-arg: Optional argument.  See also [func[LJ::check_priv]].
# returns: boolean
# </LJFUNC>
sub load_user_privs
{
    &nodb;
    my ( $remote, @privs ) = @_;
    return unless $remote and @privs;

    # return if we've already loaded these privs for this user.
    @privs = grep { ! $remote->{'_privloaded'}->{$_} } @privs;
    return unless @privs;

    my $dbr = LJ::get_db_reader();
    return unless $dbr;
    foreach (@privs) { $remote->{'_privloaded'}->{$_}++; }
    @privs = map { $dbr->quote($_) } @privs;
    my $sth = $dbr->prepare("SELECT pl.privcode, pm.arg ".
                            "FROM priv_map pm, priv_list pl ".
                            "WHERE pm.prlid=pl.prlid AND ".
                            "pl.privcode IN (" . join(',',@privs) . ") ".
                            "AND pm.userid=$remote->{'userid'}");
    $sth->execute;
    while (my ($priv, $arg) = $sth->fetchrow_array) {
        unless (defined $arg) { $arg = ""; }  # NULL -> ""
        $remote->{'_priv'}->{$priv}->{$arg} = 1;
    }
}


########################################################################
###  24. Styles and S2-Related Functions


# returns undef on error, or otherwise arrayref of arrayrefs,
# each of format [ year, month, day, count ] for all days with
# non-zero count.  examples:
#  [ [ 2003, 6, 5, 3 ], [ 2003, 6, 8, 4 ], ... ]
#
sub get_daycounts
{
    my ($u, $remote, $not_memcache) = @_;
    # NOTE: $remote not yet used.  one of the oldest LJ shortcomings is that
    # it's public how many entries users have per-day, even if the entries
    # are protected.  we'll be fixing that with a new table, but first
    # we're moving everything to this API.

    $u = LJ::want_user( $u ) or return undef;
    my $uid = $u->id;

    my $memkind = 'p'; # public only, changed below
    my $secwhere = "AND security='public'";
    my $viewall = 0;
    if ($remote) {
        # do they have the viewall priv?
        my $r = eval { Apache->request; }; # web context
        my %getargs = $r->args if $r;
        if (defined $getargs{'viewall'} and $getargs{'viewall'} eq '1' and LJ::check_priv($remote, 'canview', '*')) {
            $viewall = 1;
            LJ::statushistory_add($u->{'userid'}, $remote->{'userid'},
                "viewall", "calendar");
        }

        if ($remote->{'userid'} == $uid || $viewall) {
            $secwhere = "";   # see everything
            $memkind = 'a'; # all
        } elsif ( $remote->is_individual ) {

            # if we're viewing a community, we intuit the security mask from the membership
            my $gmask = 0;
            if ( $u->is_community ) {
                $gmask = 1
                    if $remote->member_of( $u );

            } else {
                $gmask = $u->trustmask( $remote );
            }

            if ( $gmask ) {
                $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))";
                $memkind = 'g' . $gmask; # friends case: allowmask == gmask == 1
            }
        }
    }

    ##
    ## the first element of array, that is stored in memcache,
    ## is the time of the creation of the list. The memcache is
    ## invalid if there are new entries in journal since that time.
    ##
    my $memkey = [$uid, "dayct2:$uid:$memkind"];
    unless ($not_memcache) {
        my $list = LJ::MemCache::get($memkey);
        if ($list) {
            my $list_create_time = shift @$list;
            return $list if $list_create_time >= $u->timeupdate;
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
    LJ::MemCache::add($memkey, [time, @days]);
    return \@days;
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
sub journal_base
{
    my ($user, $vhost) = @_;

    if (! isu($user) && LJ::are_hooks("journal_base")) {
        my $u = LJ::load_user($user);
        $user = $u if $u;
    }

    if (isu($user)) {
        my $u = $user;

        my $hookurl = LJ::run_hook("journal_base", $u, $vhost);
        return $hookurl if $hookurl;

        $user = $u->{'user'};
        unless (defined $vhost) {
            if ($LJ::FRONTPAGE_JOURNAL eq $user) {
                $vhost = "front";
            } elsif ($u->{'journaltype'} eq "P") {
                $vhost = "";
            } elsif ($u->{'journaltype'} eq "C") {
                $vhost = "community";
            }

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
sub make_journal
{
    &nodb;
    my ($user, $view, $remote, $opts) = @_;

    my $r = DW::Request->get;
    my $geta = $opts->{'getargs'};

    if ($LJ::SERVER_DOWN) {
        if ($opts->{'vhost'} eq "customview") {
            return "<!-- LJ down for maintenance -->";
        }
        return LJ::server_down_html();
    }

    my $u = $opts->{'u'} || LJ::load_user($user);
    unless ($u) {
        $opts->{'baduser'} = 1;
        return "<!-- No such user -->";  # return value ignored
    }
    LJ::set_active_journal($u);

    # S1 style hashref.  won't be loaded now necessarily,
    # only if via customview.
    my $style;

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


    $u->{'_journalbase'} = LJ::journal_base($u->{'user'}, $opts->{'vhost'});

    my $eff_view = $LJ::viewinfo{$view}->{'styleof'} || $view;

    my @needed_props = ("stylesys", "s2_style", "url", "urlname", "opt_nctalklinks",
                        "renamedto",  "opt_blockrobots", "opt_usesharedpic", "icbm",
                        "journaltitle", "journalsubtitle", "external_foaf_url",
                        "adult_content");

    # preload props the view creation code will need later (combine two selects)
    if (ref $LJ::viewinfo{$eff_view}->{'owner_props'} eq "ARRAY") {
        push @needed_props, @{$LJ::viewinfo{$eff_view}->{'owner_props'}};
    }

    $u->preload_props(@needed_props);

    # if the remote is the user to be viewed, make sure the $remote
    # hashref has the value of $u's opt_nctalklinks (though with
    # LJ::load_user caching, this may be assigning between the same
    # underlying hashref)
    $remote->{'opt_nctalklinks'} = $u->{'opt_nctalklinks'} if
        ($remote && $remote->{'userid'} == $u->{'userid'});

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
                # owner of the style has s2styles cap and remote is viewing owner's journal

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
            }

            # style=mine passed in GET?
            if ( $remote && ( lc( $geta->{'style'} ) eq 'mine' ) ) {

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
                return ( 2, undef );
            }

            # resource URLs have the styleid in it
            if ($view eq "res" && $opts->{'pathextra'} =~ m!^/(\d+)/!) {
                return (2, $1);
            }

            my $forceflag = 0;
            LJ::run_hooks("force_s1", $u, \$forceflag);

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
    elsif ($view eq 'lastn' && $opts->{pathextra} && $opts->{pathextra} =~ /^\/security\/(.+)$/) {
        $opts->{getargs}->{security} = LJ::durl($1);
        $opts->{pathextra} = undef;
    }

    $r->note(journalid => $u->{'userid'})
        if $r;

    my $notice = sub {
        my $msg = shift;
        my $status = shift;

        my $url = "$LJ::SITEROOT/users/$user/";
        $opts->{'status'} = $status if $status;

        my $head;
        my $journalbase = LJ::journal_base($user);

        # Automatic Discovery of RSS/Atom
        $head .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$journalbase/data/rss" />\n};
        $head .= qq{<link rel="alternate" type="application/atom+xml" title="Atom" href="$journalbase/data/atom" />\n};
        $head .= qq{<link rel="service.feed" type="application/atom+xml" title="AtomAPI-enabled feed" href="$LJ::SITEROOT/interface/atom/feed" />\n};
        $head .= qq{<link rel="service.post" type="application/atom+xml" title="Create a new post" href="$LJ::SITEROOT/interface/atom/post" />\n};

        # OpenID Server and Yadis
        $head .= $u->openid_tags;

        # FOAF autodiscovery
        my $foafurl = $u->{external_foaf_url} ? LJ::eurl($u->{external_foaf_url}) : "$journalbase/data/foaf";
        $head .= qq{<link rel="meta" type="application/rdf+xml" title="FOAF" href="$foafurl" />\n};

        if ($u->email_visible($remote)) {
            my $digest = Digest::SHA1::sha1_hex('mailto:' . $u->email_raw);
            $head .= qq{<meta name="foaf:maker" content="foaf:mbox_sha1sum '$digest'" />\n};
        }

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
    if ($LJ::USER_VHOSTS && $opts->{'vhost'} eq "users" && $u->{'journaltype'} ne 'R' &&
        ! LJ::get_cap($u, "userdomain")) {
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
        if ($inline .= LJ::run_hook("cprod_inline", $u, 'FriendsFriendsInline')) {
            return $inline;
        } else {
            return BML::ml('cprod.friendsfriendsinline.text3.v1');
        }
    }

    # signal to LiveJournal.pm that we can't handle this
    if (($stylesys == 1 || $geta->{'format'} eq 'light' || $geta->{'style'} eq 'light') &&
        ({ entry=>1, reply=>1, month=>1, tag=>1 }->{$view} || ($view eq 'lastn' && ($geta->{tag} || $geta->{security})))) {

        # pick which fallback method (s2 or bml) we'll use by default, as configured with
        # $S1_SHORTCOMINGS
        my $fallback = $LJ::S1_SHORTCOMINGS ? "s2" : "bml";

        # but if the user specifies which they want, override the fallback we picked
        if ($geta->{'fallback'} && $geta->{'fallback'} =~ /^s2|bml$/) {
            $fallback = $geta->{'fallback'};
        }

        # if we are in this path, and they have style=mine set, it means
        # they either think they can get a S2 styled page but their account
        # type won't let them, or they really want this to fallback to bml
        if ( $remote && ( $geta->{'style'} eq 'mine' ) ) {
            $fallback = 'bml';
        }

        # If they specified ?format=light, it means they want a page easy
        # to deal with text-only or on a mobile device.  For now that means
        # render it in the lynx site scheme.
        if ( $geta->{'format'} eq 'light' || $geta->{'style'} eq 'light' ) {
            $fallback = 'bml';
            $r->note(bml_use_scheme => 'lynx');
        }

        # there are no BML handlers for these views, so force s2
        if ($view eq 'tag' || $view eq 'lastn') {
            $fallback = "s2";
        }

        # fall back to BML unless we're using S2
        # fallback (the "s1shortcomings/layout")
        if ($fallback eq "bml") {
            ${$opts->{'handle_with_bml_ref'}} = 1;
            return;
        }

        # S1 can't handle these views, so we fall back to a
        # system-owned S2 style (magic value "s1short") that renders
        # this content
        $stylesys = 2;
        $styleid = "s1short";
    }

    # now, if there's a GET argument for tags, split those out
    if (exists $opts->{getargs}->{tag}) {
        my $tagfilter = $opts->{getargs}->{tag};
        return $error->( BML::ml( 'error.tag.noarg' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            unless $tagfilter;

        # error if disabled
        return $error->( BML::ml( 'error.tag.disabled' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            unless LJ::is_enabled('tags');

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $error->( BML::ml( 'error.tag.s1' ), "404 Not Found", BML::ml( 'error.tag.name' ) )
            if $stylesys == 1 && $view ne 'data' && $u->{journaltype} ne 'R';

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
    }

    # validate the security filter
    if (exists $opts->{getargs}->{security}) {
        my $securityfilter = $opts->{getargs}->{security};
        return $error->( BML::ml( 'error.security.noarg' ), "404 Not Found", BML::ml( 'error.security.name' ) )
            unless $securityfilter;

        return $error->( BML::ml( 'error.security.nocap' ), "403 Forbidden", BML::ml( 'error.security.name' ) )
            unless LJ::get_cap($remote, "security_filter") || LJ::get_cap($u, "security_filter");

        # error if disabled
        return $error->( BML::ml( 'error.security.disabled' ), "404 Not Found", BML::ml( 'error.security.name' ) )
            unless LJ::is_enabled("security_filter");

        # throw an error if we're rendering in S1, but not for renamed accounts
        return $error->( BML::ml( 'error.security.s1' ), "404 Not Found", BML::ml( 'error.security.name' ) )
            if $stylesys == 1 && $view ne 'data' && $u->journaltype ne 'R';

        # check the filter itself
        if ($securityfilter =~ /^(?:public|friends|private)$/i) {
            $opts->{'securityfilter'} = lc($securityfilter);

        # see if they want to filter by a custom group
        } elsif ($securityfilter =~ /^group:(.+)$/i) {
            my $tf = $u->trust_groups( name => $1 );
            if ( $tf && ( $u->equals( $remote ) ||
                          $u->trustmask( $remote ) & ( 1 << $tf->{groupnum} ) ) ) {
                # let them filter the results page by this group
                $opts->{securityfilter} = $tf->{groupnum};
            }
        }

        return $error->( BML::ml( 'error.security.invalid' ), "404 Not Found", BML::ml( 'error.security.name' ) )
            unless defined $opts->{securityfilter};

    }

    unless ($geta->{'viewall'} && LJ::check_priv($remote, "canview", "suspended") ||
            $opts->{'pathextra'} =~ m!/(\d+)/stylesheet$!) { # don't check style sheets
        if ( $u->is_deleted ) {
            my $warning;

            if ( $u->prop( 'delete_reason' ) ) {
                $warning = BML::ml( 'error.deleted.text.withreason', { user => $u->display_name, reason => $u->prop( 'delete_reason' ) } );
            } else {
                $warning = BML::ml( 'error.deleted.text', { user => $u->display_name } );
            }

            return $error->( $warning, "404 Not Found", BML::ml( 'error.deleted.name' ) );
        }
        if ( $u->is_suspended ) {
            my $warning = BML::ml( 'error.suspended.text', { user => $u->ljuser_display, sitename => $LJ::SITENAME } );
            return $error->( $warning, "403 Forbidden", BML::ml( 'error.suspended.name' ) );
        }

        my $entry = $opts->{ljentry};
        if ( $entry && $entry->is_suspended_for( $remote ) ) {
            my $warning = BML::ml( 'error.suspended.entry', { aopts => "href='$u->journal_base/'" } );
            return $error->( $warning, "403 Forbidden", BML::ml( 'error.suspended.name' ) );
        }
    }
    return $error->( BML::ml( 'error.purged.text' ), "410 Gone", BML::ml( 'error.purged.name' ) ) if $u->is_expunged;

    # FIXME: pretty this up at some point, to maybe auto-redirect to 
    # the external URL or something, but let's just do this for now
    if ( $u->is_identity && $view ne "read" ) {
        my $warning = BML::ml( 'error.nojournal.openid', { aopts => "href='$u->openid_identity'", id => $u->openid_identity } );
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
        my $mj = LJ::S2::make_journal($u, $styleid, $view, $remote, $opts);

        # intercept flag to handle_with_bml_ref and instead use S1 shortcomings
        # if BML is disabled
        if ($opts->{'handle_with_bml_ref'} && ${$opts->{'handle_with_bml_ref'}} &&
            ($LJ::S1_SHORTCOMINGS || $geta->{fallback} eq "s2"))
        {
            # kill the flag
            ${$opts->{'handle_with_bml_ref'}} = 0;

            # and proceed with s1shortcomings (which looks like BML) instead of BML
            $mj = LJ::S2::make_journal($u, "s1short", $view, $remote, $opts);
        }

        return $mj;
    }

    # if we get here, then we tried to run the old S1 path, so die and hope that
    # somebody comes along to fix us :(
    confess 'Tried to run S1 journal rendering path.';
}


########################################################################
###  28. Userpic-Related Functions

# <LJFUNC>
# name: LJ::userpic_count
# des: Gets a count of userpics for a given user.
# args: dbarg?, upics, idlist
# des-upics: hashref to load pictures into, keys being the picids
# des-idlist: [$u, $picid] or [[$u, $picid], [$u, $picid], +] objects
#             also supports deprecated old method, of an array ref of picids.
# </LJFUNC>
sub userpic_count {
    my $u = shift or return undef;

    if ($u->{'dversion'} > 6) {
        my $dbcr = LJ::get_cluster_def_reader($u) or return undef;
        return $dbcr->selectrow_array("SELECT COUNT(*) FROM userpic2 " .
                                      "WHERE userid=? AND state <> 'X'", undef, $u->{'userid'});
    }

    my $dbh = LJ::get_db_writer() or return undef;
    return $dbh->selectrow_array("SELECT COUNT(*) FROM userpic " .
                                 "WHERE userid=? AND state <> 'X'", undef, $u->{'userid'});
}


########################################################################
###  99. Miscellaneous Legacy Items

# FIXME: these are deprecated and no longer used; check what calls them and kill it.
sub add_friend    { confess 'LJ::add_friend has been deprecated.';    }
sub remove_friend { confess 'LJ::remove_friend has been deprecated.'; }


# <LJFUNC>
# name: LJ::remote_has_priv
# class:
# des: Check to see if the given remote user has a certain privilege.
# info: <strong>Deprecated</strong>.  You should
#       use [func[LJ::load_user_privs]] + [func[LJ::check_priv]], instead.
# FIXME: Check what calls this and kill it.
# args:
# des-:
# returns:
# </LJFUNC>
sub remote_has_priv
{
    &nodb;
    my $remote = shift;
    my $privcode = shift;     # required.  priv code to check for.
    my $ref = shift;  # optional, arrayref or hashref to populate
    return 0 unless ($remote);

    ### authentication done.  time to authorize...

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT pm.arg FROM priv_map pm, priv_list pl WHERE pm.prlid=pl.prlid AND pl.privcode=? AND pm.userid=?");
    $sth->execute($privcode, $remote->{'userid'});

    my $match = 0;
    if (ref $ref eq "ARRAY") { @$ref = (); }
    if (ref $ref eq "HASH") { %$ref = (); }
    while (my ($arg) = $sth->fetchrow_array) {
        $match++;
        if (ref $ref eq "ARRAY") { push @$ref, $arg; }
        if (ref $ref eq "HASH") { $ref->{$arg} = 1; }
    }
    return $match;
}
