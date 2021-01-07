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
use Math::Random::Secure qw(irand);

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
# des: Validates a user's password. This is the preferred
#      way to validate a password (as opposed to doing it by hand).
# returns: boolean; 1 if authentication succeeded, 0 on failure
# args: u, password, opts
# des-clear: Clear text password the client is sending.
# des-ip_banned: Optional scalar ref which this function will set to true
#                if IP address of remote user is banned.
# des-opts: Hash of options, including 'is_ip_banned'
# </LJFUNC>
sub auth_okay {
    my ( $u, $password, %opts ) = @_;
    return 0 unless LJ::isu($u);

    # set the IP banned flag, if it was provided.
    my $ref = delete $opts{is_ip_banned};
    if ( LJ::login_ip_banned($u) ) {
        $$ref = 1 if ref $ref;
        return 0;
    }
    else {
        $$ref = 0 if ref $ref;
    }

    my $bad_login = sub {
        LJ::handle_bad_login($u);
        return 0;
    };

    ## LJ default authorization:
    return 1 if $u->check_password( $password, %opts );
    return $bad_login->();
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
    for ( 1 .. $length ) { $auth .= substr( $digits, irand(30), 1 ); }
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
