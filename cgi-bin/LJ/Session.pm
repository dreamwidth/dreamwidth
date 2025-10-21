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

package LJ::Session;
use strict;
use Carp qw(croak);
use Digest::HMAC_SHA1 qw(hmac_sha1 hmac_sha1_hex);

use constant VERSION => 1;

# NOTES
#
# * fields in this object:
#     userid, sessid, exptype, auth, timecreate, timeexpire, ipfixed
#
# * do not store any references in the LJ::Session instances because of serialization
#   and storage in memcache
#
# * a user makes a session(s).  cookies aren't sessions.  cookies are handles into
#   sessions, and there can be lots of cookies to get the same session.
#
# * this file is a mix of instance, class, and util functions/methods
#
# * the 'auth' field of the session object is the prized possession which
#   we might hide from XSS attackers.  they can steal domain cookies but
#   they're not good very long and can't do much.  it's the ljmastersession
#   containing the auth that we care about.
#

############################################################################
#  CREATE/LOAD SESSIONS OBJECTS
############################################################################

sub instance {
    my ( $class, $u, $sessid ) = @_;

    return undef unless $u && !$u->is_expunged;

    # try memory
    my $memkey = _memkey( $u, $sessid );
    my $sess   = LJ::MemCache::get($memkey);
    return $sess if $sess;

    # try master
    $sess = $u->selectrow_hashref(
        "SELECT userid, sessid, exptype, auth, timecreate, timeexpire, ipfixed "
            . "FROM sessions WHERE userid=? AND sessid=?",
        undef, $u->{'userid'}, $sessid
    ) or return undef;

    bless $sess;
    LJ::MemCache::set( $memkey, $sess );
    return $sess;
}

sub active_sessions {
    my ( $class, $u ) = @_;
    return unless $u && !$u->is_expunged;

    my $sth = $u->prepare( "SELECT userid, sessid, exptype, auth, timecreate, timeexpire, ipfixed "
            . "FROM sessions WHERE userid=? AND timeexpire > UNIX_TIMESTAMP()" );
    $sth->execute( $u->{userid} );
    my @ret;
    while ( my $rec = $sth->fetchrow_hashref ) {
        bless $rec;
        push @ret, $rec;
    }
    return @ret;
}

sub create {
    my ( $class, $u, %opts ) = @_;

    # validate options
    my $exptype = delete $opts{'exptype'} || "short";
    my $ipfixed = delete $opts{'ipfixed'};              # undef or scalar ipaddress  FIXME: validate
    my $nolog   = delete $opts{'nolog'} || 0;           # 1 to not log to loginlogs
    croak("Invalid exptype") unless $exptype =~ /^short|long|once$/;

    croak( "Invalid options: " . join( ", ", keys %opts ) ) if %opts;

    my $udbh = LJ::get_cluster_master($u);
    return undef unless $udbh;

    # clean up any old, expired sessions they might have (lazy clean)
    $u->do( "DELETE FROM sessions WHERE userid=? AND timeexpire < UNIX_TIMESTAMP()",
        undef, $u->{userid} );

    # FIXME: but this doesn't remove their memcached keys

    my $expsec     = LJ::Session->session_length($exptype);
    my $timeexpire = time() + $expsec;

    my $sess = {
        auth       => LJ::rand_chars(10),
        exptype    => $exptype,
        ipfixed    => $ipfixed,
        timeexpire => $timeexpire,
    };

    my $id = LJ::alloc_user_counter( $u, 'S' );
    return undef unless $id;

    $u->record_login($id)
        unless $nolog;

    $u->do(
        "REPLACE INTO sessions (userid, sessid, auth, exptype, "
            . "timecreate, timeexpire, ipfixed) VALUES (?,?,?,?,UNIX_TIMESTAMP()," . "?,?)",
        undef, $u->{'userid'}, $id, $sess->{'auth'}, $exptype, $timeexpire, $ipfixed
    );

    return undef if $u->err;
    $sess->{'sessid'} = $id;
    $sess->{'userid'} = $u->{'userid'};

    # clean up old sessions
    my $old =
        $udbh->selectcol_arrayref( "SELECT sessid FROM sessions WHERE "
            . "userid=$u->{'userid'} AND "
            . "timeexpire < UNIX_TIMESTAMP()" );
    $u->kill_sessions(@$old) if $old;

    # mark account as being used
    LJ::mark_user_active( $u, 'login' );

    bless $sess;
    return $u->{'_session'} = $sess;
}

############################################################################
#  INSTANCE METHODS
############################################################################

# not stored in database, call this before calling to update cookie strings
sub set_flags {
    my ( $sess, $flags ) = @_;
    $sess->{flags} = $flags;
    return;
}

sub flags {
    my $sess = shift;
    return $sess->{flags};
}

sub set_ipfixed {
    my ( $sess, $ip ) = @_;
    return $sess->_dbupdate( ipfixed => $ip );
}

sub set_exptype {
    my ( $sess, $exptype ) = @_;
    croak("Invalid exptype") unless $exptype =~ /^short|long|once$/;
    return $sess->_dbupdate(
        exptype    => $exptype,
        timeexpire => time() + LJ::Session->session_length($exptype)
    );
}

sub _dbupdate {
    my ( $sess, %changes ) = @_;
    my $u = $sess->owner;

    my $n_userid = $sess->{userid} + 0;
    my $n_sessid = $sess->{sessid} + 0;

    my @sets;
    my @values;
    foreach my $k ( keys %changes ) {
        push @sets,   "$k=?";
        push @values, $changes{$k};
    }

    my $rv = $u->do(
        "UPDATE sessions SET "
            . join( ", ", @sets )
            . " WHERE userid=$n_userid AND sessid=$n_sessid",
        undef, @values
    );
    if ( !$rv ) {

        # FIXME: eventually use Error::Strict here on return
        return 0;
    }

    # update ourself, once db update succeeded
    foreach my $k ( keys %changes ) {
        $sess->{$k} = $changes{$k};
    }

    LJ::MemCache::delete( $sess->_memkey );
    return 1;

}

# returns unix timestamp of expiration
sub expiration_time {
    my $sess = shift;

    # expiration time if we have it,
    return $sess->{timeexpire} if $sess->{timeexpire};

    $sess->{timeexpire} = time() + LJ::Session->session_length( $sess->{exptype} );
    return $sess->{timeexpire};
}

# return format of the "ljloggedin" cookie.
sub loggedin_cookie_string {
    my ($sess) = @_;
    return "u$sess->{userid}:s$sess->{sessid}";
}

sub master_cookie_string {
    my $sess = shift;

    my $ver    = VERSION;
    my $cookie = "v$ver:" . "u$sess->{userid}:" . "s$sess->{sessid}:" . "a$sess->{auth}";

    if ( $sess->{flags} ) {
        $cookie .= ":f$sess->{flags}";
    }

    $cookie .= "//" . LJ::eurl( $LJ::COOKIE_GEN || "" );
    return $cookie;
}

sub domsess_cookie_string {
    my ( $sess, $domcook ) = @_;
    croak("No domain cookie provided") unless $domcook;

    # compute a signed domain key
    my ( $time, $key ) = LJ::get_secret();
    my $sig = domsess_signature( $time, $sess, $domcook );

    # the cookie
    my $ver = VERSION;
    my $value =
          "v$ver:"
        . "u$sess->{userid}:"
        . "s$sess->{sessid}:"
        . "t$time:"
        . "g$sig//"
        . LJ::eurl( $LJ::COOKIE_GEN || "" );

    return $value;
}

# sets new ljmastersession cookie given the session object
sub update_master_cookie {
    my ($sess) = @_;

    my @expires;
    if ( $sess->{exptype} eq 'long' ) {
        push @expires, expires => $sess->expiration_time;
    }

    my $domain = $LJ::ONLY_USER_VHOSTS ? ( $LJ::DOMAIN_WEB || $LJ::DOMAIN ) : $LJ::DOMAIN;

    set_cookie(
        ljmastersession => $sess->master_cookie_string,
        domain          => $domain,
        path            => '/',
        http_only       => 1,
        @expires,
    );

    set_cookie(
        ljloggedin => $sess->loggedin_cookie_string,
        domain     => $LJ::DOMAIN,
        path       => '/',
        http_only  => 1,
        @expires,
    );

    $sess->owner->preload_props('schemepref');

    if ( my $scheme = $sess->owner->prop('schemepref') ) {
        set_cookie(
            BMLschemepref => $scheme,
            domain        => $LJ::DOMAIN,
            path          => '/',
            http_only     => 1,
            @expires,
        );
    }
    else {
        set_cookie(
            BMLschemepref => "",
            domain        => $LJ::DOMAIN,
            path          => '/',
            delete        => 1
        );
    }

    return;
}

sub auth {
    my $sess = shift;
    return $sess->{auth};
}

# NOTE: do not store any references in the LJ::Session instances because of serialization
# and storage in memcache
sub owner {
    my $sess = shift;
    return LJ::load_userid( $sess->{userid} );
}

# instance method:  has this session expired, or is it IP bound and
# bound to the wrong IP?
sub valid {
    my $sess = shift;
    my $now  = time();
    my $err  = sub { 0; };

    return $err->("Invalid auth") if $sess->{'timeexpire'} < $now;

    if ( $sess->{'ipfixed'} && !$LJ::Session::OPT_IGNORE_IP ) {
        my $remote_ip = LJ::get_remote_ip();
        return $err->("Session wrong IP ($remote_ip != $sess->{ipfixed})")
            if $sess->{'ipfixed'} ne $remote_ip;
    }

    return 1;
}

sub id {
    my $sess = shift;
    return $sess->{sessid};
}

sub ipfixed {
    my $sess = shift;
    return $sess->{ipfixed};
}

sub exptype {
    my $sess = shift;
    return $sess->{exptype};
}

# end a session
sub destroy {
    my $sess = shift;
    my $id   = $sess->id;
    my $u    = $sess->owner;

    return LJ::Session->destroy_sessions( $u, $id );
}

# based on our type and current expiration length, update this cookie if we need to
sub try_renew {
    my ( $sess, $cookies ) = @_;

    # only renew long type cookies
    return if $sess->{exptype} ne 'long';

    # how long to live for
    my $u           = $sess->owner;
    my $sess_length = LJ::Session->session_length( $sess->{exptype} );
    my $now         = time();
    my $new_expire  = $now + $sess_length;

    # if there is a new session length to be set and the user's db writer is available,
    # go ahead and set the new session expiration in the database. then only update the
    # cookies if the database operation is successful
    if (   $sess_length
        && $sess->{'timeexpire'} - $now < $sess_length / 2
        && $u->writer
        && $sess->_dbupdate( timeexpire => $new_expire ) )
    {
        $sess->update_master_cookie;
    }
}

############################################################################
#  CLASS METHODS
############################################################################

# NOTE: internal function REQUIRES trusted input
sub helper_url {
    my ( $class, $dest ) = @_;

    return unless $dest;

    my $u = LJ::get_remote();
    unless ($u) {
        LJ::Session->clear_master_cookie;
        return $dest;
    }

    my $domcook = LJ::Session->domain_cookie($dest)
        or return;

    if ( $dest =~ m!^(https?://)([^/]*?)\.\Q$LJ::USER_DOMAIN\E/?([^/]*)! ) {
        my $url = "$1$2.$LJ::USER_DOMAIN/";
        if ( is_journal_subdomain($2) ) {
            $url .= "$3/"
                if $3 && ( $3 ne '/' );    # 'http://community.livejournal.com/name/__setdomsess'
        }

        my $sess   = $u->session;
        my $cookie = $sess->domsess_cookie_string($domcook);
        return
              $url
            . "__setdomsess?dest="
            . LJ::eurl($dest) . "&k="
            . LJ::eurl($domcook) . "&v="
            . LJ::eurl($cookie);
    }

    return;
}

# given a URL (or none, for current url), what domain cookie represents this URL?
# return undef if not URL for a domain cookie, which means either bogus URL
# or the master cookies should be tried.
sub domain_cookie {
    my ( $class,     $url )  = @_;
    my ( $subdomain, $user ) = LJ::Session->domain_journal($url);

    # undef:  not on a user-subdomain
    return undef unless $subdomain;

    # on a user subdomain, or shared subdomain
    if ( $user ne "" ) {
        $user =~ s/-/_/g;    # URLs may be - or _, convert to _ which is what usernames contain
        return "ljdomsess.$subdomain.$user";
    }
    else {
        return "ljdomsess.$subdomain";
    }
}

# given an optional URL (by default, the current URL), what is the username
# of that URL?.  undef if no user.  in list context returns the ($subdomain, $user)
# where $user can be "" if $subdomain isn't, say, "community" or "users".
# in scalar context, userame is always the canonical username (no hypens/capitals)
sub domain_journal {
    my ( $class, $url ) = @_;

    $url ||= LJ::create_url( undef, keep_args => 1 );
    return undef
        unless $url =~ m!^https?://(.+?)(/.*)$!;

    my ( $host, $path ) = ( $1, $2 );
    $host = lc($host);

    # don't return a domain cookie for the master domain
    return undef if $host eq lc($LJ::DOMAIN_WEB) || $host eq lc($LJ::DOMAIN);

    return undef
        unless $host =~ m!^([-\w\.]{1,50})\.\Q$LJ::USER_DOMAIN\E$!;

    my $subdomain = lc($1);
    if ( is_journal_subdomain($subdomain) ) {
        my $user = get_path_user($path);
        return undef unless $user;
        return wantarray ? ( $subdomain, $user ) : $user;
    }

    # where $subdomain is actually a username:
    return wantarray ? ( $subdomain, "" ) : LJ::canonical_username($subdomain);
}

sub url_owner {
    my ( $class, $url ) = @_;
    $url ||= LJ::create_url( undef, keep_args => 1 );
    my ( $subdomain, $user ) = LJ::Session->domain_journal($url);
    $user = $subdomain if $user eq "";
    return LJ::canonical_username($user);
}

# CLASS METHOD
#  -- frontend to session_from_domain_cookie and session_from_master_cookie below
sub session_from_cookies {
    my $class   = shift;
    my %getopts = @_;

    my $r = DW::Request->get;
    return undef unless $r;

    my $sessobj;

    my $domain_cookie = LJ::Session->domain_cookie;
    if ($domain_cookie) {

        # journal domain
        $sessobj =
            LJ::Session->session_from_domain_cookie( \%getopts, $r->cookie_multi($domain_cookie) );
    }
    else {
        # this is the master cookie at "www.livejournal.com" or "livejournal.com";
        my @cookies = $r->cookie_multi('ljmastersession');

        # but support old clients who are just sending an "ljsession" cookie which they got
        # from LJ::Protocol's "generatesession" mode.
        unless (@cookies) {
            @cookies = $r->cookie_multi('ljsession');
            $getopts{old_cookie} = 1;
        }
        $sessobj = LJ::Session->session_from_master_cookie( \%getopts, @cookies );
    }

    return $sessobj;
}

# CLASS METHOD
#   -- but not called directly.  usually called by LJ::Session->session_from_cookies above
sub session_from_domain_cookie {
    my $class = shift;
    my $opts  = ref $_[0] ? shift() : {};

    my $r = DW::Request->get;

    # the logged-in cookie
    my $li_cook = $r->cookie('ljloggedin');
    return undef unless $li_cook;

    my $no_session = sub {
        my $reason = shift;
        warn "No session found for domain cookie: $reason\n" if $LJ::IS_DEV_SERVER;

        my $rr = $opts->{redirect_ref};
        $$rr =
            "$LJ::SITEROOT/misc/get_domain_session?return="
            . LJ::eurl( LJ::create_url( undef, keep_args => 1 ) )
            if $rr;

        return undef;
    };

    my @cookies = grep { $_ } @_;
    return $no_session->("no cookies") unless @cookies;

    my $domcook = LJ::Session->domain_cookie;

    foreach my $cookie (@cookies) {
        my $sess = valid_domain_cookie( $domcook, $cookie->[0], $li_cook );
        return $sess if $sess;
    }

    return $no_session->("no valid cookie");
}

# CLASS METHOD
#   -- but not called directly.  usually called by LJ::Session->session_from_cookies above
# call: ( $opts?, @ljmastersession_cookie(s) )
# return value is LJ::Session object if we found one; else undef
# FIXME: document ops
sub session_from_master_cookie {
    my $class   = shift;
    my $opts    = ref $_[0] ? shift() : {};
    my @cookies = grep { $_ } @_;
    return undef unless @cookies;

    my $r = DW::Request->get;

    my $errs       = delete $opts->{errlist}    || [];
    my $tried_fast = delete $opts->{tried_fast} || do { my $foo; \$foo; };
    my $ignore_ip  = delete $opts->{ignore_ip}  ? 1 : 0;
    my $old_cookie = delete $opts->{old_cookie} ? 1 : 0;

    delete $opts->{redirect_ref};    # we don't use this
    croak("Unknown options") if %$opts;

    my $now = time();

    # our return value
    my $sess;

    my $li_cook = $r->cookie('ljloggedin');

COOKIE:
    foreach my $sessdata (@cookies) {
        my ( $cookie, $gen ) = split( m!//!, $sessdata->[0] );

        my ( $version, $userid, $sessid, $auth, $flags );

        my $dest = {
            v => \$version,
            u => \$userid,
            s => \$sessid,
            a => \$auth,
            f => \$flags,
        };

        my $bogus = 0;
        foreach my $var ( split /:/, $cookie ) {
            if ( $var =~ /^(\w)(.+)$/ && $dest->{$1} ) {
                ${ $dest->{$1} } = $2;
            }
            else {
                $bogus = 1;
            }
        }

        # must do this first so they can't trick us
        $$tried_fast = 1 if $flags && $flags =~ /\.FS\b/;

        next COOKIE if $bogus;

        next COOKIE unless valid_cookie_generation($gen);

        my $err = sub {
            $sess = undef;
            push @$errs, "$sessdata: $_[0]";
        };

        # fail unless version matches current
        unless ( $version == VERSION ) {
            $err->("no ws auth");
            next COOKIE;
        }

        my $u = LJ::load_userid($userid);
        unless ($u) {
            $err->("user doesn't exist");
            next COOKIE;
        }

        # locked accounts can't be logged in
        if ( $u->is_locked ) {
            $err->("User account is locked.");
            next COOKIE;
        }

        $sess = LJ::Session->instance( $u, $sessid );

        unless ($sess) {
            $err->("Couldn't find session");
            next COOKIE;
        }

        unless ( $sess->{auth} eq $auth ) {
            $err->("Invald auth");
            next COOKIE;
        }

        unless ( $sess->valid ) {
            $err->("expired or IP bound problems");
            next COOKIE;
        }

        # make sure their ljloggedin cookie
        unless ( $old_cookie || $sess->loggedin_cookie_string eq $li_cook ) {
            $err->("loggedin cookie bogus");
            next COOKIE;
        }

        last COOKIE;
    }

    return $sess;
}

# class method
sub destroy_all_sessions {
    my ( $class, $u ) = @_;
    return 0 unless $u;

    my $udbh = LJ::get_cluster_master($u)
        or return 0;

    my $sessions = $udbh->selectcol_arrayref( "SELECT sessid FROM sessions WHERE " . "userid=?",
        undef, $u->{'userid'} );

    return LJ::Session->destroy_sessions( $u, @$sessions ) if @$sessions;
    return 1;
}

# class method
sub destroy_sessions {
    my ( $class, $u, @sessids ) = @_;

    my $in = join( ',', map { $_ + 0 } @sessids );
    return 1 unless $in;
    my $userid = $u->{'userid'};
    foreach (qw(sessions sessions_data)) {
        $u->do( "DELETE FROM $_ WHERE userid=? AND " . "sessid IN ($in)", undef, $userid )
            or return 0;    # FIXME: use Error::Strict
    }
    foreach my $id (@sessids) {
        $id += 0;
        LJ::MemCache::delete( _memkey( $u, $id ) );
    }
    return 1;

}

sub clear_master_cookie {
    my ($class) = @_;

    my $domain = $LJ::ONLY_USER_VHOSTS ? ( $LJ::DOMAIN_WEB || $LJ::DOMAIN ) : $LJ::DOMAIN;

    set_cookie(
        ljmastersession => "",
        domain          => $domain,
        path            => '/',
        delete          => 1
    );

    set_cookie(
        ljloggedin => "",
        domain     => $LJ::DOMAIN,
        path       => '/',
        delete     => 1
    );
}

# CLASS method for getting the length of a given session type in seconds
sub session_length {
    my ( $class, $exptype ) = @_;
    croak("Invalid exptype") unless $exptype =~ /^short|long|once$/;

    return {
        short => 60 * 60 * 24 * 1.5,    # 1.5 days
        long  => 60 * 60 * 24 * 60,     # 60 days
        once  => 60 * 60 * 2,           # 2 hours
    }->{$exptype};
}

# returns the URL to go to after setting the domain cookie
sub setdomsess_handler {
    my ($class) = @_;

    my $r = DW::Request->get;

    my $get = $r->get_args;

    my $dest    = $get->{'dest'};
    my $domcook = $get->{'k'};
    my $cookie  = $get->{'v'};

    return "$LJ::SITEROOT" unless valid_destination($dest);
    return $dest unless valid_domain_cookie( $domcook, $cookie, $r->cookie('ljloggedin') );

    my $path = get_cookie_path($dest);

    my $expires = $LJ::DOMSESS_EXPIRATION || 0;    # session-cookie only
    set_cookie(
        $domcook  => $cookie,
        path      => $path,
        http_only => 1,
        expires   => $expires
    );

    # add in a trailing slash, if URL doesn't have at least two slashes.
    # otherwise the path on the cookie above (which is like /community/)
    # won't be caught when we bounce them to /community.
    unless ( $dest =~ m!^https?://.+?/.+?/! || $path eq "/" ) {

        # add a slash unless we can slip one in before the query parameters
        $dest .= "/" unless $dest =~ s!\?!/?!;
    }

    return $dest;
}

############################################################################
#  UTIL FUNCTIONS
############################################################################

sub domsess_signature {
    my ( $time, $sess, $domcook ) = @_;

    my $u      = $sess->owner;
    my $secret = LJ::get_secret($time);

    my $data = join( "-", $sess->{auth}, $domcook, $u->{userid}, $sess->{sessid}, $time );
    my $sig  = hmac_sha1_hex( $data, $secret );
    return $sig;
}

# function or instance method.
# FIXME: update the documentation for memkeys
sub _memkey {
    if ( @_ == 2 ) {
        my ( $u, $sessid ) = @_;
        $sessid += 0;
        return [ $u->{'userid'}, "ljms:$u->{'userid'}:$sessid" ];
    }
    else {
        my $sess = shift;
        return [ $sess->{'userid'}, "ljms:$sess->{'userid'}:$sess->{sessid}" ];
    }
}

# FIXME: move this somewhere better
sub set_cookie {
    my ( $key, $value, %opts ) = @_;

    my $r = DW::Request->get;
    return unless $r;

    my $http_only = delete $opts{http_only};
    my $domain    = delete $opts{domain};
    my $path      = delete $opts{path};
    my $expires   = delete $opts{expires};
    my $delete    = delete $opts{delete};
    croak( "Invalid cookie options: " . join( ", ", keys %opts ) ) if %opts;

    # Mac IE 5 can't handle HttpOnly, so filter it out
    if ( $http_only && !$LJ::DEBUG{no_mac_ie_httponly} ) {
        my $ua = $r->header_in('User-Agent');
        $http_only = 0 if $ua =~ /MSIE.+Mac_/;
    }

    # expires can be absolute or relative.  this is gross or clever, your pick.
    $expires += time() if $expires && $expires <= 1135217120;

    if ($delete) {

        # set expires to 5 seconds after 1970.  definitely in the past.
        # so cookie will be deleted.
        $expires = 5 if $delete;
    }

    $r->add_cookie(
        name     => $key,
        value    => $value,
        expires  => $expires ? LJ::time_to_cookie($expires) : undef,
        domain   => $domain || undef,
        path     => $path || undef,
        httponly => $http_only ? 1 : 0,
    );

    # Backwards compatability for older browsers
    return unless defined $domain;
    my @labels = split( /\./, $domain );
    if ( scalar @labels == 2 && !$LJ::DEBUG{no_extra_dot_cookie} ) {
        $r->add_cookie(
            name     => $key,
            value    => $value,
            expires  => $expires ? LJ::time_to_cookie($expires) : undef,
            domain   => $domain,
            path     => $path || undef,
            httponly => $http_only ? 1 : 0,
        );
    }
}

# returns undef or a session, given a $domcook and its $val, as well
# as the current logged-in cookie $li_cook which says the master
# session's uid/sessid
sub valid_domain_cookie {
    my ( $domcook, $val, $li_cook, $opts ) = @_;
    $opts ||= {};

    my ( $cookie, $gen ) = split m!//!, $val;

    my ( $version, $uid, $sessid, $time, $sig, $flags );
    my $dest = {
        v => \$version,
        u => \$uid,
        s => \$sessid,
        t => \$time,
        g => \$sig,
        f => \$flags,
    };

    my $bogus = 0;
    foreach my $var ( split /:/, $cookie ) {
        if ( $var =~ /^(\w)(.+)$/ && $dest->{$1} ) {
            ${ $dest->{$1} } = $2;
        }
        else {
            $bogus = 1;
        }
    }

    my $not_valid = sub {
        my $reason = shift;
        warn "Invalid domain cookie: $reason\n" if $LJ::IS_DEV_SERVER;

        return undef;
    };

    return $not_valid->("bogus params") if $bogus;
    return $not_valid->("wrong gen") unless valid_cookie_generation($gen);
    return $not_valid->("wrong ver") if $version != VERSION;

    # have to be relatively new.  these shouldn't last longer than a day
    # or so anyway.
    unless ( $opts->{ignore_age} ) {
        my $now = time();
        return $not_valid->("old cookie") unless $time > $now - 86400 * 7;
    }

    my $u = LJ::load_userid($uid)
        or return $not_valid->("no user $uid");

    my $sess = $u->session($sessid)
        or return $not_valid->("no session $sessid");

    # the master session can't be expired or ip-bound to wrong IP
    return $not_valid->("not valid") unless $sess->valid;

    # the per-domain cookie has to match the session of the master cookie
    unless ( $opts->{ignore_li_cook} ) {
        my $sess_licook = $sess->loggedin_cookie_string;
        return $not_valid->("li_cook mismatch.  session=$sess_licook, user=$li_cook")
            unless $sess_licook eq $li_cook;
    }

    my $correct_sig = domsess_signature( $time, $sess, $domcook );
    return $not_valid->("signature wrong") unless $correct_sig eq $sig;

    return $sess;
}

sub valid_destination {
    my $dest = shift;
    return $dest =~ qr!^https?://[-\w\.]+\.\Q$LJ::USER_DOMAIN\E/!;
}

sub valid_cookie_generation {
    my $gen  = shift || '';
    my $dgen = LJ::durl($gen);
    foreach my $okay ( $LJ::COOKIE_GEN, @LJ::COOKIE_GEN_OKAY ) {
        $okay = '' unless defined $okay;
        return 1 if $gen eq $okay;
        return 1 if $dgen eq $okay;
    }
    return 0;
}

sub is_journal_subdomain {
    my ($subdomain) = @_;
    return 0 unless defined $subdomain;
    $subdomain = lc $subdomain;

    my $func = $LJ::SUBDOMAIN_FUNCTION{$subdomain};
    return $func && $func eq "journal" ? 1 : 0;
}

sub get_cookie_path {
    my ($dest) = @_;
    my $path = '/';    # By default cookie path is root

    # If it is not the master domain, include the username

    if ( $dest && $dest =~ m!^https?://(.+?)(/.*)$! ) {
        my ( $host, $url_path ) = ( lc($1), $2 );
        my $path_user = get_path_user($url_path);

        if (
            $host =~ m!^([-\w\.]{1,50})\.\Q$LJ::USER_DOMAIN\E$!
            && is_journal_subdomain($1)    # undef: not on a user-subdomain
            && $path_user
            )
        {

            $path = '/' . $path_user . '/';
        }
    }

    return $path;
}

sub get_path_user {
    my ($path) = @_;
    return unless $path =~ m!^/(\w{1,$LJ::USERNAME_MAXLENGTH})\b!;
    return lc $1;
}

1;
