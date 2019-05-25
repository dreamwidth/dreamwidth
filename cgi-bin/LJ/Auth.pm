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

# This is the LiveJournal Authentication module.
# It contains useful authentication methods.

package LJ::Auth;
use strict;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);
use Digest::SHA1 qw(sha1_hex);
use Carp qw (croak);

# Generate an auth token for AJAX requests to use.
# Arguments: ($remote, $action, %postvars)
#   $remote: remote user object
#   $uri: what uri this is for
#   %postvars: the expected post variables
# Returns: Auth token good for the current hour
sub ajax_auth_token {
    my ( $class, $remote, $uri, %postvars ) = @_;

    $remote = LJ::want_user($remote) || LJ::get_remote();

    croak "No URI specified" unless $uri;

    my ( $stime, $secret ) = LJ::get_secret();
    my $postvars = join( '&', map { $postvars{$_} } sort keys %postvars );
    my $remote_session_id =
        $remote && $remote->session ? $remote->session->id : LJ::UniqCookie->current_uniq;
    my $remote_userid = $remote ? $remote->id : 0;

    my $chalbare = qq {ajax:$stime:$remote_userid:$remote_session_id:$uri:$postvars};
    my $chalsig  = sha1_hex( $chalbare, $secret );
    return qq{$chalbare:$chalsig};
}

# Checks an auth token sent by an ajax request
# Arguments: $remote, $uri, %POST variables
# Returns: bool whether or not key is good
sub check_ajax_auth_token {
    my ( $class, $remote, $uri, %postvars ) = @_;

    $remote = LJ::want_user($remote) || LJ::get_remote();

    # get auth token out of post vars
    my $auth_token = delete $postvars{auth_token} or return 0;

    # recompute post vars
    my $postvars = join( '&', map { $postvars{$_} } sort keys %postvars );

    # get vars out of token string
    my ( $c_ver, $stime, $remoteid, $sessid, $chal_uri, $chal_postvars, $chalsig ) =
        split( ':', $auth_token );

    # get secret based on $stime
    my $secret = LJ::get_secret($stime);

    # no time?
    return 0 unless $stime && $secret;

    # right version?
    return 0 unless $c_ver eq 'ajax';

    # in logged-out case $remoteid is 0 and $sessid is uniq_cookie
    my $req_remoteid = $remoteid > 0 ? $remote->id          : 0;
    my $req_sessid   = $remoteid > 0 ? $remote->session->id : LJ::UniqCookie->current_uniq;

    # do signitures match?
    my $chalbare = qq {$c_ver:$stime:$remoteid:$sessid:$chal_uri:$chal_postvars};
    my $realsig  = sha1_hex( $chalbare, $secret );
    return 0 unless $realsig eq $chalsig;

    return 0
        unless $remoteid == $req_remoteid &&    # remote id matches or logged-out 0=0
        $sessid == $req_sessid            &&    # remote sessid or logged-out uniq cookie match
        $uri eq $chal_uri                 &&    # uri matches
        $postvars eq $chal_postvars;            # post vars to uri

    return 1;
}

# this is similar to the above methods but doesn't require a session or remote
sub sessionless_auth_token {
    my ( $class, $uri, %reqvars ) = @_;

    croak "No URI specified" unless $uri;

    my ( $stime, $secret ) = LJ::get_secret();
    my $reqvars = join( '&', map { $reqvars{$_} } sort keys %reqvars );

    my $chalbare = qq {sessionless:$stime:$uri:$reqvars};
    my $chalsig  = sha1_hex( $chalbare, $secret );
    return qq{$chalbare:$chalsig};
}

sub check_sessionless_auth_token {
    my ( $class, $uri, %reqvars ) = @_;

    # get auth token out of post vars
    my $auth_token = delete $reqvars{auth_token} or return 0;

    # recompute post vars
    my $reqvars = join( '&', map { $reqvars{$_} // '' } qw(journalid moduleid preview) );

    # get vars out of token string
    my ( $c_ver, $stime, $chal_uri, $chal_reqvars, $chalsig ) = split( ':', $auth_token );

    # get secret based on $stime
    my $secret = LJ::get_secret($stime);

    # no time?
    return 0 unless $stime && $secret;

    # right version?
    return 0 unless $c_ver eq 'sessionless';

    # do signitures match?
    my $chalbare = qq {$c_ver:$stime:$chal_uri:$chal_reqvars};
    my $realsig  = sha1_hex( $chalbare, $secret );
    return 0 unless $realsig eq $chalsig;

    # do other vars match?
    return 0 unless $uri eq $chal_uri && $reqvars eq $chal_reqvars;

    return 1;
}

# move over auth-related functions from ljlib.pl

package LJ;

use Digest::MD5 ();

# <LJFUNC>
# name: LJ::auth_okay
# des: Validates a user's password.  The "clear" or "md5" argument
#      must be present, and either the "actual" argument (the correct
#      password) must be set, or the first argument must be a user
#      object ($u) with the 'password' key set.  This is the preferred
#      way to validate a password (as opposed to doing it by hand).
# returns: boolean; 1 if authentication succeeded, 0 on failure
# args: u, clear, md5, actual?, ip_banned?
# des-clear: Clear text password the client is sending. (need this or md5)
# des-md5: MD5 of the password the client is sending. (need this or clear).
#          If this value instead of clear, clear can be anything, as md5
#          validation will take precedence.
# des-actual: The actual password for the user.  Ignored if a pluggable
#             authenticator is being used.  Required unless the first
#             argument is a user object instead of a username scalar.
# des-ip_banned: Optional scalar ref which this function will set to true
#                if IP address of remote user is banned.
# </LJFUNC>
sub auth_okay {
    my ( $u, $clear, $md5, $actual, $ip_banned ) = @_;
    return 0 unless LJ::isu($u);

    $actual ||= $u->password;

    my $user = $u->{'user'};

    # set the IP banned flag, if it was provided.
    my $fake_scalar;
    my $ref = ref $ip_banned ? $ip_banned : \$fake_scalar;
    if ( LJ::login_ip_banned($u) ) {
        $$ref = 1;
        return 0;
    }
    else {
        $$ref = 0;
    }

    my $bad_login = sub {
        LJ::handle_bad_login($u);
        return 0;
    };

    ## LJ default authorization:
    return 0 unless $actual;
    return 1 if $md5 && lc($md5) eq Digest::MD5::md5_hex($actual);
    return 1 if $clear eq $actual;
    return $bad_login->();
}

# Validate a challenge string previously supplied by challenge_generate
# return 1 "good" 0 "bad", plus sets keys in $opts:
# 'valid'=1/0 whether the string itself was valid
# 'expired'=1/0 whether the challenge expired, provided it's valid
# 'count'=N number of times we've seen this challenge, including this one,
#           provided it's valid and not expired
# $opts also supports in parameters:
#   'dont_check_count' => if true, won't return a count field
# the return value is 1 if 'valid' and not 'expired' and 'count'==1
sub challenge_check {
    my ( $chal, $opts ) = @_;
    my ( $valid, $expired, $count ) = ( 1, 0, 0 );

    my ( $c_ver, $stime, $s_age, $goodfor, $rand, $chalsig ) = split /:/, $chal;
    my $secret   = LJ::get_secret($stime);
    my $chalbare = "$c_ver:$stime:$s_age:$goodfor:$rand";

    # Validate token
    $valid = 0
        unless $secret && $c_ver eq 'c0';    # wrong version
    $valid = 0
        unless Digest::MD5::md5_hex( $chalbare . $secret ) eq $chalsig;

    $expired = 1
        unless ( not $valid )
        or time() - ( $stime + $s_age ) < $goodfor;

    # Check for token dups
    if ( $valid && !$expired && !$opts->{dont_check_count} ) {
        if (@LJ::MEMCACHE_SERVERS) {
            $count = LJ::MemCache::incr( "chaltoken:$chal", 1 );
            unless ($count) {
                LJ::MemCache::add( "chaltoken:$chal", 1, $goodfor );
                $count = 1;
            }
        }
        else {
            my $dbh = LJ::get_db_writer();
            my $rv  = $dbh->do( "SELECT GET_LOCK(?,5)", undef, $chal );
            if ($rv) {
                $count = $dbh->selectrow_array( "SELECT count FROM challenges WHERE challenge=?",
                    undef, $chal );
                if ($count) {
                    $dbh->do( "UPDATE challenges SET count=count+1 WHERE challenge=?",
                        undef, $chal );
                    $count++;
                }
                else {
                    $dbh->do( "INSERT INTO challenges SET ctime=?, challenge=?, count=1",
                        undef, $stime + $s_age, $chal );
                    $count = 1;
                }
            }
            $dbh->do( "SELECT RELEASE_LOCK(?)", undef, $chal );
        }

        # if we couldn't get the count (means we couldn't store either)
        # , consider it invalid
        $valid = 0 unless $count;
    }

    if ($opts) {
        $opts->{'expired'} = $expired;
        $opts->{'valid'}   = $valid;
        $opts->{'count'}   = $count;
    }

    return ( $valid && !$expired && ( $count == 1 || $opts->{dont_check_count} ) );
}

# Validate login/talk md5 responses.
# Return 1 on valid, 0 on invalid.
sub challenge_check_login {
    my ( $u, $chal, $res, $banned, $opts ) = @_;
    return 0 unless $u;
    my $pass = $u->password;
    return 0 if $pass eq "";

    # set the IP banned flag, if it was provided.
    my $fake_scalar;
    my $ref = ref $banned ? $banned : \$fake_scalar;
    if ( LJ::login_ip_banned($u) ) {
        $$ref = 1;
        return 0;
    }
    else {
        $$ref = 0;
    }

    # check the challenge string validity
    return 0 unless LJ::challenge_check( $chal, $opts );

    # Validate password
    my $hashed = Digest::MD5::md5_hex( $chal . Digest::MD5::md5_hex($pass) );
    if ( $hashed eq $res ) {
        return 1;
    }
    else {
        LJ::handle_bad_login($u);
        return 0;
    }
}

# Create a challenge token for secure logins
sub challenge_generate {
    my ( $goodfor, $attr ) = @_;

    $goodfor ||= 60;
    $attr    ||= LJ::rand_chars(20);

    my ( $stime, $secret ) = LJ::get_secret();

    # challenge version, secret time, secret age, time in secs token is good for, random chars.
    my $s_age    = time() - $stime;
    my $chalbare = "c0:$stime:$s_age:$goodfor:$attr";
    my $chalsig  = Digest::MD5::md5_hex( $chalbare . $secret );
    my $chal     = "$chalbare:$chalsig";

    return $chal;
}

sub get_authaction {
    my ( $id, $action, $arg1, $opts ) = @_;

    my $dbh = $opts->{force} ? LJ::get_db_writer() : LJ::get_db_reader();
    return $dbh->selectrow_hashref(
        "SELECT aaid, authcode, datecreate FROM authactions "
            . "WHERE userid=? AND arg1=? AND action=? AND used='N' LIMIT 1",
        undef, $id, $arg1, $action
    );
}

# Return challenge info.
# This could grow later - for now just return the rand chars used.
sub get_challenge_attributes {
    return ( split /:/, shift )[4];
}

# <LJFUNC>
# name: LJ::is_valid_authaction
# des: Validates a shared secret (authid/authcode pair)
# info: See [func[LJ::register_authaction]].
# returns: Hashref of authaction row from database.
# args: dbarg?, aaid, auth
# des-aaid: Integer; the authaction ID.
# des-auth: String; the auth string. (random chars the client already got)
# </LJFUNC>
sub is_valid_authaction {

    # we use the master db to avoid races where authactions could be
    # used multiple times
    my $dbh = LJ::get_db_writer();
    my ( $aaid, $auth ) = @_;
    return $dbh->selectrow_hashref( "SELECT * FROM authactions WHERE aaid=? AND authcode=?",
        undef, $aaid, $auth );
}

# <LJFUNC>
# name: LJ::make_auth_code
# des: Makes a random string of characters of a given length.
# returns: string of random characters, from an alphabet of 30
#          letters & numbers which aren't easily confused.
# args: length
# des-length: length of auth code to return
# </LJFUNC>
sub make_auth_code {
    my $length = shift;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    my $auth;
    for ( 1 .. $length ) { $auth .= substr( $digits, int( rand(30) ), 1 ); }
    return $auth;
}

# <LJFUNC>
# name: LJ::mark_authaction_used
# des: Marks an authaction as being used.
# args: aaid
# des-aaid: Either an authaction hashref or the id of the authaction to mark used.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub mark_authaction_used {
    my $aaid = ref $_[0] ? $_[0]->{aaid} + 0 : $_[0] + 0
        or return undef;
    my $dbh = LJ::get_db_writer()
        or return undef;
    $dbh->do( "UPDATE authactions SET used='Y' WHERE aaid = ?", undef, $aaid );
    return undef if $dbh->err;
    return 1;
}

# <LJFUNC>
# name: LJ::register_authaction
# des: Registers a secret to have the user validate.
# info: Some things, like requiring a user to validate their e-mail address, require
#       making up a secret, mailing it to the user, then requiring them to give it
#       back (usually in a URL you make for them) to prove they got it.  This
#       function creates a secret, attaching what it's for and an optional argument.
#       Background maintenance jobs keep track of cleaning up old unvalidated secrets.
# args: dbarg?, userid, action, arg?
# des-userid: Userid of user to register authaction for.
# des-action: Action type to register.   Max chars: 50.
# des-arg: Optional argument to attach to the action.  Max chars: 255.
# returns: 0 if there was an error.  Otherwise, a hashref
#          containing keys 'aaid' (the authaction ID) and the 'authcode',
#          a 15 character string of random characters from
#          [func[LJ::make_auth_code]].
# </LJFUNC>
sub register_authaction {
    my $dbh = LJ::get_db_writer();

    my $userid = shift;
    $userid += 0;
    my $action = $dbh->quote(shift);
    my $arg1   = $dbh->quote(shift);

    # make the authcode
    my $authcode  = LJ::make_auth_code(15);
    my $qauthcode = $dbh->quote($authcode);

    $dbh->do( "INSERT INTO authactions (aaid, userid, datecreate, authcode, action, arg1) "
            . "VALUES (NULL, $userid, NOW(), $qauthcode, $action, $arg1)" );

    return 0 if $dbh->err;
    return {
        'aaid'     => $dbh->{'mysql_insertid'},
        'authcode' => $authcode,
    };
}

1;
