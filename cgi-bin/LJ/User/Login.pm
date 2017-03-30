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

use LJ::Session;

########################################################################
### 4. Login, Session, and Rename Functions

=head2 Login, Session, and Rename Functions
=cut

# returns a new LJ::Session object, or undef on failure
sub create_session {
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
    $sessid = defined $sessid ? $sessid + 0 : 0;
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
### End LJ::User functions

########################################################################
### Begin LJ functions

package LJ;

########################################################################
###  4. Login, Session, and Rename Functions

=head2 Login, Session, and Rename Functions (LJ)
=cut

sub get_active_journal {
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

    my $authas = $BMLCodeBlock::GET{authas} || $BMLCodeBlock::POST{authas};

    unless ( $authas ) {
        my $r = DW::Request->get;
        $authas = $r->get_args->{authas} || $r->post_args->{authas};
    }

    $authas ||= $remote->user;
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
sub get_remote {
    my $opts = ref $_[0] eq "HASH" ? shift : {};
    return $LJ::CACHE_REMOTE if $LJ::CACHED_REMOTE && ! $opts->{'ignore_ip'};

    my $no_remote = sub {
        LJ::User->set_remote(undef);
        return undef;
    };

    # can't have a remote user outside of web context
    my $apache_r = eval { BML::get_request(); };
    return $no_remote->() unless $apache_r;

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
    $apache_r->notes->{ljuser} = $u->user;
    return $u;
}


sub handle_bad_login {
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


sub login_ip_banned {
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


sub set_active_journal {
    $LJ::ACTIVE_JOURNAL = shift;
}


sub set_remote {
    my $remote = shift;
    LJ::User->set_remote($remote);
    1;
}


sub unset_remote {
    LJ::User->unset_remote;
    1;
}


1;
