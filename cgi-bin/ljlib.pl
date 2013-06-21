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

package LJ;

use strict;
no warnings 'uninitialized';

BEGIN {
    # ugly hack to shutup dependent libraries which sometimes want to bring in
    # ljlib.pl (via require, ick!).  so this lets them know if it's recursive.
    # we REALLY need to move the rest of this crap to .pm files.


    # ensure we have $LJ::HOME, or complain very vigorously
    $LJ::HOME ||= $ENV{LJHOME};
    die "No \$LJ::HOME set, or not a directory!\n"
        unless $LJ::HOME && -d $LJ::HOME;

    # Please do not change this to "LJ::Directories"
    require $LJ::HOME . "/cgi-bin/LJ/Directories.pm";
}

# now that the library is setup, we can start pulling things in.  start with
# the configuration library we need.
use lib "$LJ::HOME/cgi-bin";
use lib "$LJ::HOME/extlib/lib/perl5";
use LJ::Config;

BEGIN {
    # mod_perl does this early too, make sure we do as well
    LJ::Config->load;

    # arch support has to be done pretty early
    if ( $LJ::ARCH32 ) {
        $LJ::ARCH = 32;
        $LJ::LOGMEMCFMT = 'NNNLN';
        $LJ::PUBLICBIT = 2 ** 31;
    } else {
        $LJ::ARCH32 = 0;
        $LJ::ARCH = 64;
        $LJ::LOGMEMCFMT = 'NNNQN';
        $LJ::PUBLICBIT = 2 ** 63;
    }
}

use Apache2::Connection ();
use Carp;
use DBI;
use DBI::Role;
use Digest::MD5 ();
use Digest::SHA1 ();
use HTTP::Date ();
use LJ::Hooks;
use LJ::MemCache;
use LJ::Error;
use LJ::User;      # has a bunch of pkg LJ, non-OO methods at bottom
use LJ::Entry;     # has a bunch of pkg LJ, non-OO methods at bottom
use LJ::Global::Constants;  # formerly LJ::Constants
use Time::Local ();
use Storable ();
use Compress::Zlib ();
use DW::Request;
use TheSchwartz;
use TheSchwartz::Job;
use LJ::Comment;
use LJ::ExternalSite;
use LJ::Message;
use LJ::ConvUTF8;
use LJ::Userpic;
use LJ::ModuleCheck;
use IO::Socket::INET;
use LJ::UniqCookie;
use LJ::WorkerResultStorage;
use LJ::EventLogRecord;
use LJ::EventLogRecord::DeleteComment;
use DW::External::Account;
use DW::External::User;
use DW::Logic::LogItems;
use LJ::CleanHTML;
use DW::LatestFeed;
use LJ::Keywords;
use LJ::Procnotify;
use LJ::DB;
use LJ::Tags;
use LJ::TextUtil;
use LJ::Time;
use LJ::Capabilities;
use DW::Mood;
use LJ::Global::Img;  # defines LJ::Img
use DW::Media;

# make Unicode::MapUTF8 autoload:
sub Unicode::MapUTF8::AUTOLOAD {
    die "Unknown subroutine $Unicode::MapUTF8::AUTOLOAD"
        unless $Unicode::MapUTF8::AUTOLOAD =~ /::(utf8_supported_charset|to_utf8|from_utf8)$/;
    LJ::ConvUTF8->load;
    no strict 'refs';
    goto *{$Unicode::MapUTF8::AUTOLOAD}{CODE};
}

sub END { LJ::end_request(); }

use LJ::DB;
use LJ::Tags;
use LJ::TextUtil;
use LJ::Time;
use LJ::Capabilities;
use DW::Mood;
use LJ::Global::Img;  # defines LJ::Img
use LJ::Global::Secrets;  # defines LJ::Secrets

require "$LJ::HOME/cgi-bin/ljlib-local.pl"
    if -e "$LJ::HOME/cgi-bin/ljlib-local.pl";

# if this is a dev server, alias LJ::D to Data::Dumper::Dumper
if ($LJ::IS_DEV_SERVER) {
    eval "use Data::Dumper ();";
    *LJ::D = \&Data::Dumper::Dumper;
}

LJ::MemCache::init();

# $LJ::PROTOCOL_VER is the version of the client-server protocol
# used uniformly by server code which uses the protocol.
$LJ::PROTOCOL_VER = ($LJ::UNICODE ? "1" : "0");

# declare views for user journals
%LJ::viewinfo = (
                 "lastn" => {
                     "des" => "Most Recent Events",
                 },
                 "archive" => {
                     "des" => "Archive",
                 },
                 "day" => {
                     "des" => "Day View",
                 },
                 "read" => {
                     "des" => "Reading Page",
                     "owner_props" => ["opt_usesharedpic", "friendspagetitle", "friendspagesubtitle"],
                 },
                 "network" => {
                     "des" => "Network View",
                     "styleof" => "read",
                 },
                 "data" => {
                     "des" => "Data View (RSS, etc.)",
                     "owner_props" => ["opt_whatemailshow", "no_mail_alias"],
                 },
                 "rss" => {  # this is now provided by the "data" view.
                     "des" => "RSS View (XML)",
                 },
                 "res" => {
                     "des" => "S2-specific resources (stylesheet)",
                 },
                 "info" => {
                     # just a redirect to profile.bml for now.
                     # in S2, will be a real view.
                     "des" => "Profile Page",
                 },
                 "profile" => {
                     # just a redirect to profile.bml for now.
                     # in S2, will be a real view.
                     "des" => "Profile Page",
                 },
                 "tag" => {
                     "des" => "Filtered Recent Entries View",
                 },
                 "security" => {
                     "des" => "Filtered Recent Entries View",
                 },
                 "update" => {
                     # just a redirect to update.bml for now.
                     # real solution is some sort of better nav
                     # within journal styles.
                     "des" => "Update Journal",
                 },
                 "icons" => {
                    "des" => "Icons",
                 },
                 );

## we want to set this right away, so when we get a HUP signal later
## and our signal handler sets it to true, perl doesn't need to malloc,
## since malloc may not be thread-safe and we could core dump.
## see LJ::clear_caches and LJ::handle_caches
$LJ::CLEAR_CACHES = 0;

# DB Reporting UDP socket object
$LJ::ReportSock = undef;

# DB Reporting handle collection. ( host => $dbh )
%LJ::DB_REPORT_HANDLES = ();

my $GTop;     # GTop object (created if $LJ::LOG_GTOP is true)
my %SecretCache;

## if this library is used in a BML page, we don't want to destroy BML's
## HUP signal handler.
if ($SIG{'HUP'}) {
    my $oldsig = $SIG{'HUP'};
    $SIG{'HUP'} = sub {
        &{$oldsig} if ref $oldsig eq "CODE";
        LJ::clear_caches();
    };
} else {
    $SIG{'HUP'} = \&LJ::clear_caches;
}


sub get_blob_domainid
{
    my $name = shift;
    my $id = {
        "userpic" => 1,
    }->{$name};
    # FIXME: add hook support, so sites can't define their own
    # general code gets priority on numbers, say, 1-200, so verify
    # hook returns a number 201-255
    return $id if $id;
    die "Unknown blob domain: $name";
}

sub _using_blockwatch {
    unless ( LJ::is_enabled('blockwatch') ) {
        # Config override to disable blockwatch.
        return 0;
    }

    unless (LJ::ModuleCheck->have('LJ::Blockwatch')) {
        # If we don't have or are unable to load LJ::Blockwatch, then give up too
        return 0;
    }
    return 1;
}

sub locker {
    return $LJ::LOCKER_OBJ if $LJ::LOCKER_OBJ;
    eval "use DDLockClient ();";
    die "Couldn't load locker client: $@" if $@;

    $LJ::LOCKER_OBJ =
        new DDLockClient (
                          servers => [ @LJ::LOCK_SERVERS ],
                          lockdir => $LJ::LOCKDIR || "$LJ::HOME/locks",
                          );

    if (_using_blockwatch()) {
        eval { LJ::Blockwatch->setup_ddlock_hooks($LJ::LOCKER_OBJ) };

        warn "Unable to add Blockwatch hooks to DDLock client object: $@"
            if $@;
    }

    return $LJ::LOCKER_OBJ;
}

sub gearman_client {
    my $purpose = shift;

    return undef unless @LJ::GEARMAN_SERVERS;
    eval "use Gearman::Client; 1;" or die "No Gearman::Client available: $@";

    my $client = Gearman::Client->new;
    $client->job_servers(@LJ::GEARMAN_SERVERS);

    if (_using_blockwatch()) {
        eval { LJ::Blockwatch->setup_gearman_hooks($client) };

        warn "Unable to add Blockwatch hooks to Gearman client object: $@"
            if $@;
    }

    return $client;
}

sub mogclient {
    return $LJ::MogileFS if $LJ::MogileFS;

    if (%LJ::MOGILEFS_CONFIG && $LJ::MOGILEFS_CONFIG{hosts}) {
        eval "use MogileFS::Client;";
        die "Couldn't load MogileFS: $@" if $@;

        $LJ::MogileFS = MogileFS::Client->new(
                                      domain => $LJ::MOGILEFS_CONFIG{domain},
                                      root   => $LJ::MOGILEFS_CONFIG{root},
                                      hosts  => $LJ::MOGILEFS_CONFIG{hosts},
                                      readonly => $LJ::DISABLE_MEDIA_UPLOADS,
                                      timeout => $LJ::MOGILEFS_CONFIG{timeout},
                                      )
            or die "Could not initialize MogileFS";

        # set preferred ip list if we have one
        $LJ::MogileFS->set_pref_ip(\%LJ::MOGILEFS_PREF_IP)
            if %LJ::MOGILEFS_PREF_IP;

        if (_using_blockwatch()) {
            eval { LJ::Blockwatch->setup_mogilefs_hooks($LJ::MogileFS) };

            warn "Unable to add Blockwatch hooks to MogileFS client object: $@"
                if $@;
        }
    }

    return $LJ::MogileFS;
}

sub theschwartz {
    return LJ::Test->theschwartz(@_) if $LJ::_T_FAKESCHWARTZ;

    my $opts = shift;

    my $role = $opts->{role} || "default";

    return $LJ::SchwartzClient{$role} if $LJ::SchwartzClient{$role};

    unless (scalar grep { defined $_->{role} } @LJ::THESCHWARTZ_DBS) { # old config
        $LJ::SchwartzClient{$role} = TheSchwartz->new(databases => \@LJ::THESCHWARTZ_DBS);
        return $LJ::SchwartzClient{$role};
    }

    my @dbs = grep { $_->{role}->{$role} } @LJ::THESCHWARTZ_DBS;
    die "Unknown role in LJ::theschwartz: '$role'" unless @dbs;

    $LJ::SchwartzClient{$role} = TheSchwartz->new(databases => \@dbs);

    return $LJ::SchwartzClient{$role};
}

sub gtop {
    return unless $LJ::LOG_GTOP && LJ::ModuleCheck->have("GTop");
    return $GTop ||= GTop->new;
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

    my $userid = shift;  $userid += 0;
    my $action = $dbh->quote(shift);
    my $arg1 = $dbh->quote(shift);

    # make the authcode
    my $authcode = LJ::make_auth_code(15);
    my $qauthcode = $dbh->quote($authcode);

    $dbh->do("INSERT INTO authactions (aaid, userid, datecreate, authcode, action, arg1) ".
             "VALUES (NULL, $userid, NOW(), $qauthcode, $action, $arg1)");

    return 0 if $dbh->err;
    return { 'aaid' => $dbh->{'mysql_insertid'},
             'authcode' => $authcode,
         };
}

sub get_authaction {
    my ($id, $action, $arg1, $opts) = @_;

    my $dbh = $opts->{force} ? LJ::get_db_writer() : LJ::get_db_reader();
    return $dbh->selectrow_hashref("SELECT aaid, authcode, datecreate FROM authactions " .
                                   "WHERE userid=? AND arg1=? AND action=? AND used='N' LIMIT 1",
                                   undef, $id, $arg1, $action);
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
    my ($aaid, $auth) = @_;
    return $dbh->selectrow_hashref("SELECT * FROM authactions WHERE aaid=? AND authcode=?",
                                   undef, $aaid, $auth);
}

# <LJFUNC>
# name: LJ::mark_authaction_used
# des: Marks an authaction as being used.
# args: aaid
# des-aaid: Either an authaction hashref or the id of the authaction to mark used.
# returns: 1 on success, undef on error.
# </LJFUNC>
sub mark_authaction_used
{
    my $aaid = ref $_[0] ? $_[0]->{aaid}+0 : $_[0]+0
        or return undef;
    my $dbh = LJ::get_db_writer()
        or return undef;
    $dbh->do("UPDATE authactions SET used='Y' WHERE aaid = ?", undef, $aaid);
    return undef if $dbh->err;
    return 1;
}

# <LJFUNC>
# name: LJ::make_auth_code
# des: Makes a random string of characters of a given length.
# returns: string of random characters, from an alphabet of 30
#          letters & numbers which aren't easily confused.
# args: length
# des-length: length of auth code to return
# </LJFUNC>
sub make_auth_code
{
    my $length = shift;
    my $digits = "abcdefghjkmnpqrstvwxyz23456789";
    my $auth;
    for (1..$length) { $auth .= substr($digits, int(rand(30)), 1); }
    return $auth;
}

# Loads and caches one or more of the various *proplist (and ratelist)
# tables, which describe the various meta-data that can be stored on log
# (journal) items, comments, users, media, etc.
#
# Please use LJ::get_prop to actually retrieve properties. You probably
# don't want to call this function directly.
sub load_props {
    my %keyname = (
        log   => [ 'propid',  'logproplist'     ],
        media => [ 'propid',  'media_prop_list' ],
        rate  => [ 'rlid',    'ratelist'        ],
        talk  => [ 'tpropid', 'talkproplist'    ],
        user  => [ 'upropid', 'userproplist'    ],
    );

    my $dbr = LJ::get_db_reader()
        or croak 'Failed to get database reader handle';

    foreach my $t ( @_ ) {
        confess 'Attempted to load invalid property list'
            unless exists $keyname{$t};
        next if defined $LJ::CACHE_PROP{$t};

        my ( $key, $table ) = @{$keyname{$t}};
        my $res = $dbr->selectall_hashref( "SELECT * FROM $table", $key );
        croak $dbr->errstr if $dbr->err;
        croak 'Failed to load properties from list'
            unless $res && ref $res eq 'HASH';

        foreach my $id ( keys %$res ) {
            my $p = $res->{$id};

            $p->{id} = $id;
            $LJ::CACHE_PROP{$t}->{$p->{name}} = $p;
            $LJ::CACHE_PROPID{$t}->{$p->{id}} = $p;
        }
    }
}

# <LJFUNC>
# name: LJ::get_prop
# des: This is used to retrieve
#      a hashref of a row from the given tablename's proplist table.
#      One difference from getting it straight from the database is
#      that the 'id' key is always present, as a copy of the real
#      proplist unique id for that table.
# args: table, name
# returns: hashref of proplist row from db
# des-table: the tables to get a proplist hashref from.  Can be one of
#            "log", "talk", or "user".
# des-name: the name of the prop to get the hashref of.
# </LJFUNC>
sub get_prop
{
    my $table = shift;
    my $name = shift;
    unless (defined $LJ::CACHE_PROP{$table} && $LJ::CACHE_PROP{$table}->{$name}) {
        $LJ::CACHE_PROP{$table} = undef;
        LJ::load_props($table);
    }

    unless ($LJ::CACHE_PROP{$table}) {
        warn "Prop table has no data: $table" if $LJ::IS_DEV_SERVER;
        return undef;
    }

    unless ($LJ::CACHE_PROP{$table}->{$name}) {
        warn "Prop does not exist: $table - $name" if $LJ::IS_DEV_SERVER;
        return undef;
    }

    return $LJ::CACHE_PROP{$table}->{$name};
}

# <LJFUNC>
# name: LJ::load_codes
# des: Populates hashrefs with lookup data from the database or from memory,
#      if already loaded in the past.  Examples of such lookup data include
#      state codes, country codes, color name/value mappings, etc.
# args: dbarg?, whatwhere
# des-whatwhere: a hashref with keys being the code types you want to load
#                and their associated values being hashrefs to where you
#                want that data to be populated.
# </LJFUNC>
sub load_codes {
    my $req = shift;

    my $dbr = LJ::get_db_reader()
        or die "Unable to get database handle";

    foreach my $type (keys %{$req})
    {
        my $memkey = "load_codes:$type";
        unless ($LJ::CACHE_CODES{$type} ||= LJ::MemCache::get($memkey))
        {
            $LJ::CACHE_CODES{$type} = [];
            my $sth = $dbr->prepare("SELECT code, item, sortorder FROM codes WHERE type=?");
            $sth->execute($type);
            while (my ($code, $item, $sortorder) = $sth->fetchrow_array)
            {
                push @{$LJ::CACHE_CODES{$type}}, [ $code, $item, $sortorder ];
            }
            @{$LJ::CACHE_CODES{$type}} =
                sort { $a->[2] <=> $b->[2] } @{$LJ::CACHE_CODES{$type}};
            LJ::MemCache::set($memkey, $LJ::CACHE_CODES{$type}, 60*15);
        }

        foreach my $it (@{$LJ::CACHE_CODES{$type}})
        {
            if (ref $req->{$type} eq "HASH") {
                $req->{$type}->{$it->[0]} = $it->[1];
            } elsif (ref $req->{$type} eq "ARRAY") {
                push @{$req->{$type}}, { 'code' => $it->[0], 'item' => $it->[1] };
            }
        }
    }
}

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
sub auth_okay
{
    my $u = shift;
    my $clear = shift;
    my $md5 = shift;
    my $actual = shift;
    my $ip_banned = shift;
    return 0 unless isu($u);

    $actual ||= $u->password;

    my $user = $u->{'user'};

    # set the IP banned flag, if it was provided.
    my $fake_scalar;
    my $ref = ref $ip_banned ? $ip_banned : \$fake_scalar;
    if (LJ::login_ip_banned($u)) {
        $$ref = 1;
        return 0;
    } else {
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

# Create a challenge token for secure logins
sub challenge_generate
{
    my ($goodfor, $attr) = @_;

    $goodfor ||= 60;
    $attr ||= LJ::rand_chars(20);

    my ($stime, $secret) = LJ::get_secret();

    # challenge version, secret time, secret age, time in secs token is good for, random chars.
    my $s_age = time() - $stime;
    my $chalbare = "c0:$stime:$s_age:$goodfor:$attr";
    my $chalsig = Digest::MD5::md5_hex($chalbare . $secret);
    my $chal = "$chalbare:$chalsig";

    return $chal;
}

# Return challenge info.
# This could grow later - for now just return the rand chars used.
sub get_challenge_attributes
{
    return (split /:/, shift)[4];
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
    my ($chal, $opts) = @_;
    my ($valid, $expired, $count) = (1, 0, 0);

    my ($c_ver, $stime, $s_age, $goodfor, $rand, $chalsig) = split /:/, $chal;
    my $secret = LJ::get_secret($stime);
    my $chalbare = "$c_ver:$stime:$s_age:$goodfor:$rand";

    # Validate token
    $valid = 0
        unless $secret && $c_ver eq 'c0'; # wrong version
    $valid = 0
        unless Digest::MD5::md5_hex($chalbare . $secret) eq $chalsig;

    $expired = 1
        unless (not $valid) or time() - ($stime + $s_age) < $goodfor;

    # Check for token dups
    if ($valid && !$expired && !$opts->{dont_check_count}) {
        if (@LJ::MEMCACHE_SERVERS) {
            $count = LJ::MemCache::incr("chaltoken:$chal", 1);
            unless ($count) {
                LJ::MemCache::add("chaltoken:$chal", 1, $goodfor);
                $count = 1;
            }
        } else {
            my $dbh = LJ::get_db_writer();
            my $rv = $dbh->do("SELECT GET_LOCK(?,5)", undef, $chal);
            if ($rv) {
                $count = $dbh->selectrow_array("SELECT count FROM challenges WHERE challenge=?",
                                               undef, $chal);
                if ($count) {
                    $dbh->do("UPDATE challenges SET count=count+1 WHERE challenge=?",
                             undef, $chal);
                    $count++;
                } else {
                    $dbh->do("INSERT INTO challenges SET ctime=?, challenge=?, count=1",
                         undef, $stime + $s_age, $chal);
                    $count = 1;
                }
            }
            $dbh->do("SELECT RELEASE_LOCK(?)", undef, $chal);
        }
        # if we couldn't get the count (means we couldn't store either)
        # , consider it invalid
        $valid = 0 unless $count;
    }

    if ($opts) {
        $opts->{'expired'} = $expired;
        $opts->{'valid'} = $valid;
        $opts->{'count'} = $count;
    }

    return ($valid && !$expired && ($count==1 || $opts->{dont_check_count}));
}


# Validate login/talk md5 responses.
# Return 1 on valid, 0 on invalid.
sub challenge_check_login
{
    my ($u, $chal, $res, $banned, $opts) = @_;
    return 0 unless $u;
    my $pass = $u->password;
    return 0 if $pass eq "";

    # set the IP banned flag, if it was provided.
    my $fake_scalar;
    my $ref = ref $banned ? $banned : \$fake_scalar;
    if (LJ::login_ip_banned($u)) {
        $$ref = 1;
        return 0;
    } else {
        $$ref = 0;
    }

    # check the challenge string validity
    return 0 unless LJ::challenge_check($chal, $opts);

    # Validate password
    my $hashed = Digest::MD5::md5_hex($chal . Digest::MD5::md5_hex($pass));
    if ($hashed eq $res) {
        return 1;
    } else {
        LJ::handle_bad_login($u);
        return 0;
    }
}


# <LJFUNC>
# name: LJ::get_talktext2
# des: Retrieves comment text. Tries slave servers first, then master.
# info: Efficiently retrieves batches of comment text. Will try alternate
#       servers first. See also [func[LJ::get_logtext2]].
# returns: Hashref with the talkids as keys, values being [ $subject, $event ].
# args: u, opts?, jtalkids
# des-opts: A hashref of options. 'onlysubjects' will only retrieve subjects.
# des-jtalkids: A list of talkids to get text for.
# </LJFUNC>
sub get_talktext2
{
    my $u = shift;
    my $clusterid = $u->{'clusterid'};
    my $journalid = $u->{'userid'}+0;

    my $opts = ref $_[0] ? shift : {};

    # return structure.
    my $lt = {};
    return $lt unless $clusterid;

    # keep track of itemids we still need to load.
    my %need;
    my @mem_keys;
    foreach (@_) {
        my $id = $_+0;
        $need{$id} = 1;
        push @mem_keys, [$journalid,"talksubject:$clusterid:$journalid:$id"];
        unless ($opts->{'onlysubjects'}) {
            push @mem_keys, [$journalid,"talkbody:$clusterid:$journalid:$id"];
        }
    }

    # try the memory cache
    my $mem = LJ::MemCache::get_multi(@mem_keys) || {};

    if ($LJ::_T_GET_TALK_TEXT2_MEMCACHE) {
        $LJ::_T_GET_TALK_TEXT2_MEMCACHE->();
    }

    while (my ($k, $v) = each %$mem) {
        $k =~ /^talk(.*):(\d+):(\d+):(\d+)/;
        if ($opts->{'onlysubjects'} && $1 eq "subject") {
            delete $need{$4};
            $lt->{$4} = [ $v ];
        }
        if (! $opts->{'onlysubjects'} && $1 eq "body" &&
            exists $mem->{"talksubject:$2:$3:$4"}) {
            delete $need{$4};
            $lt->{$4} = [ $mem->{"talksubject:$2:$3:$4"}, $v ];
        }
    }
    return $lt unless %need;

    my $bodycol = $opts->{'onlysubjects'} ? "" : ", body";

    # pass 1 (slave) and pass 2 (master)
    foreach my $pass (1, 2) {
        next unless %need;
        my $db = $pass == 1 ? LJ::get_cluster_reader($clusterid) :
            LJ::get_cluster_def_reader($clusterid);

        unless ($db) {
            next if $pass == 1;
            die "Could not get db handle";
        }

        my $in = join(",", keys %need);
        my $sth = $db->prepare("SELECT jtalkid, subject $bodycol FROM talktext2 ".
                               "WHERE journalid=$journalid AND jtalkid IN ($in)");
        $sth->execute;
        while (my ($id, $subject, $body) = $sth->fetchrow_array) {
            $subject = "" unless defined $subject;
            $body = "" unless defined $body;
            LJ::text_uncompress(\$body);
            $lt->{$id} = [ $subject, $body ];
            LJ::MemCache::add([$journalid,"talkbody:$clusterid:$journalid:$id"], $body)
                unless $opts->{'onlysubjects'};
            LJ::MemCache::add([$journalid,"talksubject:$clusterid:$journalid:$id"], $subject);
            delete $need{$id};
        }
    }
    return $lt;
}

# <LJFUNC>
# name: LJ::clear_caches
# des: This function is called from a HUP signal handler and is intentionally
#      very very simple (1 line) so we don't core dump on a system without
#      reentrant libraries.  It just sets a flag to clear the caches at the
#      beginning of the next request (see [func[LJ::handle_caches]]).
#      There should be no need to ever call this function directly.
# </LJFUNC>
sub clear_caches
{
    $LJ::CLEAR_CACHES = 1;
}

# <LJFUNC>
# name: LJ::handle_caches
# des: clears caches if the CLEAR_CACHES flag is set from an earlier
#      HUP signal that called [func[LJ::clear_caches]], otherwise
#      does nothing.
# returns: true (always) so you can use it in a conjunction of
#          statements in a while loop around the application like:
#          while (LJ::handle_caches() && FCGI::accept())
# </LJFUNC>
sub handle_caches
{
    return 1 unless $LJ::CLEAR_CACHES;
    $LJ::CLEAR_CACHES = 0;

    LJ::Config->load;

    $LJ::DBIRole->flush_cache();

    %LJ::CACHE_PROP = ();
    %LJ::CACHE_STYLE = ();
    $LJ::CACHED_MOODS = 0;
    $LJ::CACHED_MOOD_MAX = 0;
    %LJ::CACHE_MOODS = ();
    %LJ::CACHE_MOOD_THEME = ();
    %LJ::CACHE_USERID = ();
    %LJ::CACHE_USERNAME = ();
    %LJ::CACHE_CODES = ();
    %LJ::CACHE_USERPROP = ();  # {$prop}->{ 'upropid' => ... , 'indexed' => 0|1 };
    %LJ::CACHE_ENCODINGS = ();

    return 1;
}

# <LJFUNC>
# name: LJ::start_request
# des: Before a new web request is obtained, this should be called to
#      determine if process should die or keep working, clean caches,
#      reload config files, etc.
# returns: 1 if a new request is to be processed, 0 if process should die.
# </LJFUNC>
sub start_request
{
    handle_caches();
    # TODO: check process growth size

    # clear per-request caches
    LJ::unset_remote();               # clear cached remote
    $LJ::ACTIVE_JOURNAL = undef;      # for LJ::{get,set}_active_journal
    $LJ::ACTIVE_CRUMB = '';           # clear active crumb
    %LJ::CACHE_USERPIC = ();          # picid -> hashref
    %LJ::CACHE_USERPIC_INFO = ();     # uid -> { ... }
    %LJ::CACHE_S2THEME = ();
    %LJ::REQ_CACHE_USER_NAME = ();    # users by name
    %LJ::REQ_CACHE_USER_ID = ();      # users by id
    %LJ::REQ_CACHE_REL = ();          # relations from LJ::check_rel()
    %LJ::REQ_LANGDATFILE = ();        # caches language files
    %LJ::S2::REQ_CACHE_STYLE_ID = (); # styleid -> hashref of s2 layers for style
    %LJ::S2::REQ_CACHE_LAYER_ID = (); # layerid -> hashref of s2 layer info (from LJ::S2::load_layer)
    %LJ::S2::REQ_CACHE_LAYER_INFO = (); # layerid -> hashref of s2 layer info (from LJ::S2::load_layer_info)
    %LJ::REQ_HEAD_HAS = ();           # avoid code duplication for js
    %LJ::NEEDED_RES = ();             # needed resources (css/js/etc):
    @LJ::NEEDED_RES = ();             # needed resources, in order requested (implicit dependencies)
                                      #  keys are relative from htdocs, values 1 or 2 (1=external, 2=inline)

    %LJ::REQ_GLOBAL = ();             # per-request globals
    %LJ::_ML_USED_STRINGS = ();       # strings looked up in this web request
    %LJ::REQ_CACHE_USERTAGS = ();     # uid -> { ... }; populated by get_usertags, so we don't load it twice
    $LJ::ADV_PER_PAGE = 0;            # Counts ads displayed on a page
    $LJ::ACTIVE_RES_GROUP = undef;    # use whatever is current site default


    %LJ::PAID_STATUS = ();            # per-request paid status

    $LJ::CACHE_REMOTE_BOUNCE_URL = undef;
    LJ::Userpic->reset_singletons;
    LJ::Comment->reset_singletons;
    LJ::Entry->reset_singletons;
    LJ::Message->reset_singletons;

    LJ::UniqCookie->clear_request_cache;

    # we use this to fake out get_remote's perception of what
    # the client's remote IP is, when we transfer cookies between
    # authentication domains.  see the FotoBilder interface.
    $LJ::_XFER_REMOTE_IP = undef;

    # clear the handle request cache (like normal cache, but verified already for
    # this request to be ->ping'able).
    $LJ::DBIRole->clear_req_cache();

    # need to suck db weights down on every request (we check
    # the serial number of last db weight change on every request
    # to validate master db connection, instead of selecting
    # the connection ID... just as fast, but with a point!)
    $LJ::DBIRole->trigger_weight_reload();

    # reset BML's cookies
    eval { BML::reset_cookies() };

    # reload config if necessary
    LJ::Config->start_request_reload;

    # reset the request abstraction layer
    DW::Request->reset;

    # include standard files if this is web-context
    if ( DW::Request->get ) {

        # note that we're calling need_res and advising that these items
        # are the new style global items

        LJ::need_res( { group => 'jquery', priority => $LJ::LIB_RES_PRIORITY },
            # jquery library is the big one, load first
            'js/jquery/jquery-1.8.3.js',

            # the rest of the libraries
            qw(
                js/dw/dw-core.js
            ),
        );

        # old/standard libraries are below here.

        # standard site-wide JS and CSS
        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY }, qw(
                        js/6alib/core.js
                        js/6alib/dom.js
                        js/6alib/httpreq.js
                        js/livejournal.js
                        stc/lj_base.css
                        ));

        # esn ajax
        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY }, qw(
                        js/esn.js
                        stc/esn.css
                        ))
            if LJ::is_enabled('esn_ajax');

        # contextual popup JS
        if ( $LJ::CTX_POPUP ) {
            LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY, group => "default" }, qw(
                            js/6alib/ippu.js
                            js/lj_ippu.js
                            js/6alib/hourglass.js
                            js/contextualhover.js
                            stc/contextualhover.css
                            ));

            LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY, group=> 'jquery' },
                qw(
                    js/jquery/jquery.ui.core.js
                    js/jquery/jquery.ui.widget.js

                    js/jquery/jquery.ui.tooltip.js
                    js/jquery.ajaxtip.js
                    js/jquery/jquery.ui.position.js
                    stc/jquery/jquery.ui.core.css
                    stc/jquery/jquery.ui.tooltip.css
                    stc/jquery/jquery.ui.theme.smoothness.css

                    js/jquery.hoverIntent.js
                    js/jquery.contextualhover.js
                    stc/jquery.contextualhover.css
                ));
        }

        # development JS
        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY }, qw(
                        js/6alib/devel.js
                        js/livejournal-devel.js
                        ))
            if $LJ::IS_DEV_SERVER;
    }

    LJ::Hooks::run_hooks("start_request");

    return 1;
}


# <LJFUNC>
# name: LJ::end_request
# des: Clears cached DB handles (if [ljconfig[disconnect_dbs]] is
#      true), and disconnects memcached handles (if [ljconfig[disconnect_memcache]] is
#      true).
# </LJFUNC>
sub end_request
{
    LJ::work_report_end();
    LJ::flush_cleanup_handlers();
    LJ::DB::disconnect_dbs() if $LJ::DISCONNECT_DBS;
    LJ::MemCache::disconnect_all() if $LJ::DISCONNECT_MEMCACHE;
    return 1;
}

# <LJFUNC>
# name: LJ::flush_cleanup_handlers
# des: Runs all cleanup handlers registered in @LJ::CLEANUP_HANDLERS
# </LJFUNC>
sub flush_cleanup_handlers {
    while (my $ref = shift @LJ::CLEANUP_HANDLERS) {
        next unless ref $ref eq 'CODE';
        $ref->();
    }
}

# <LJFUNC>
# name: LJ::cmd_buffer_add
# des: Schedules some command to be run sometime in the future which would
#      be too slow to do synchronously with the web request.  An example
#      is deleting a journal entry, which requires recursing through a lot
#      of tables and deleting all the appropriate stuff.
# args: db, journalid, cmd, hargs
# des-db: Global db handle to run command on, or user clusterid if cluster
# des-journalid: Journal id command affects.  This is indexed in the
#                [dbtable[cmdbuffer]] table, so that all of a user's queued
#                actions can be run before that user is potentially moved
#                between clusters.
# des-cmd: Text of the command name.  30 chars max.
# des-hargs: Hashref of command arguments.
# </LJFUNC>
sub cmd_buffer_add
{
    my ($db, $journalid, $cmd, $args) = @_;

    return 0 unless $cmd;

    my $cid = ref $db ? 0 : $db+0;
    $db = $cid ? LJ::get_cluster_master($cid) : $db;
    my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$cid};

    return 0 unless $db;

    my $arg_str;
    if (ref $args eq 'HASH') {
        foreach (sort keys %$args) {
            $arg_str .= LJ::eurl($_) . "=" . LJ::eurl($args->{$_}) . "&";
        }
        chop $arg_str;
    } else {
        $arg_str = $args || "";
    }

    my $rv;
    if ($ab eq 'a' || $ab eq 'b') {
        # get a lock
        my $locked = $db->selectrow_array("SELECT GET_LOCK('cmd-buffer-$cid',10)");
        return 0 unless $locked; # 10 second timeout elapsed

        # a or b -- a goes odd, b goes even!
        my $max = $db->selectrow_array('SELECT MAX(cbid) FROM cmdbuffer');
        $max += $ab eq 'a' ? ($max & 1 ? 2 : 1) : ($max & 1 ? 1 : 2);

        # insert command
        $db->do('INSERT INTO cmdbuffer (cbid, journalid, instime, cmd, args) ' .
                'VALUES (?, ?, NOW(), ?, ?)', undef,
                $max, $journalid, $cmd, $arg_str);
        $rv = $db->err ? 0 : 1;

        # release lock
        $db->selectrow_array("SELECT RELEASE_LOCK('cmd-buffer-$cid')");
    } else {
        # old method
        $db->do("INSERT INTO cmdbuffer (journalid, cmd, instime, args) ".
                "VALUES (?, ?, NOW(), ?)", undef,
                $journalid, $cmd, $arg_str);
        $rv = $db->err ? 0 : 1;
    }

    return $rv;
}


# <LJFUNC>
# name: LJ::load_talk_props2
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub load_talk_props2
{
    my $db = LJ::DB::isdb( $_[0] ) ? shift @_ : undef;
    my ($uuserid, $listref, $hashref) = @_;

    my $userid = want_userid($uuserid);
    my $u = ref $uuserid ? $uuserid : undef;

    $hashref = {} unless ref $hashref eq "HASH";

    my %need;
    my @memkeys;
    foreach (@$listref) {
        my $id = $_+0;
        $need{$id} = 1;
        push @memkeys, [$userid,"talkprop:$userid:$id"];
    }
    return $hashref unless %need;

    my $mem = LJ::MemCache::get_multi(@memkeys) || {};

    # allow hooks to count memcaches in this function for testing
    if ($LJ::_T_GET_TALK_PROPS2_MEMCACHE) {
        $LJ::_T_GET_TALK_PROPS2_MEMCACHE->();
    }

    while (my ($k, $v) = each %$mem) {
        next unless $k =~ /(\d+):(\d+)/ && ref $v eq "HASH";
        delete $need{$2};
        $hashref->{$2}->{$_[0]} = $_[1] while @_ = each %$v;
    }
    return $hashref unless %need;

    if (!$db || @LJ::MEMCACHE_SERVERS) {
        $u ||= LJ::load_userid($userid);
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) :  LJ::get_cluster_reader($u);
        return $hashref unless $db;
    }

    LJ::load_props("talk");
    my $in = join(',', keys %need);
    my $sth = $db->prepare("SELECT jtalkid, tpropid, value FROM talkprop2 ".
                           "WHERE journalid=? AND jtalkid IN ($in)");
    $sth->execute($userid);
    while (my ($jtalkid, $propid, $value) = $sth->fetchrow_array) {
        my $p = $LJ::CACHE_PROPID{'talk'}->{$propid};
        next unless $p;
        $hashref->{$jtalkid}->{$p->{'name'}} = $value;
    }
    foreach my $id (keys %need) {
        LJ::MemCache::set([$userid,"talkprop:$userid:$id"], $hashref->{$id} || {});
    }
    return $hashref;
}

my $work_open = 0;
sub work_report_start { $work_open = 1; work_report("start"); }
sub work_report_end   { return unless $work_open; work_report("end"); $work_open = 0;   }

# report before/after a request, so a supervisor process can watch for
# hangs/spins
my $udp_sock;
sub work_report {
    my $what = shift;
    my $dest = $LJ::WORK_REPORT_HOST;
    return unless $dest;

    my $r = DW::Request->get;
    return unless $r;
    return if $r->method eq "OPTIONS";

    $dest = $dest->() if ref $dest eq "CODE";
    return unless $dest;

    $udp_sock ||= IO::Socket::INET->new(Proto => "udp");
    return unless $udp_sock;

    my ($host, $port) = split(/:/, $dest);
    return unless $host && $port;

    my @fields = ($$, $what);
    if ($what eq "start") {
        my $host = $r->host;
        my $uri = $r->uri;
        my $args = $r->query_string;
        $args = substr($args, 0, 100) if length $args > 100;
        push @fields, $host, $uri, $args;

        my $remote = LJ::User->remote;
        push @fields, $remote->{user} if $remote;
    }

    my $msg = join(",", @fields);

    my $dst = Socket::sockaddr_in($port, Socket::inet_aton($host));
    my $rv = $udp_sock->send($msg, 0, $dst);
}

# <LJFUNC>
# name: LJ::blocking_report
# des: Log a report on the total amount of time used in a slow operation to a
#      remote host via UDP.
# args: host, type, time, notes
# des-host: The DB host the operation used.
# des-type: The type of service the operation was talking to (e.g., 'database',
#           'memcache', etc.)
# des-time: The amount of time (in floating-point seconds) the operation took.
# des-notes: A short description of the operation.
# </LJFUNC>
sub blocking_report {
    my ( $host, $type, $time, $notes ) = @_;

    if ( $LJ::DB_LOG_HOST ) {
        unless ( $LJ::ReportSock ) {
            my ( $host, $port ) = split /:/, $LJ::DB_LOG_HOST, 2;
            return unless $host && $port;

            $LJ::ReportSock = new IO::Socket::INET (
                PeerPort => $port,
                Proto    => 'udp',
                PeerAddr => $host
               ) or return;
        }

        my $msg = join( "\x3", $host, $type, $time, $notes );
        $LJ::ReportSock->send( $msg );
    }
}


# <LJFUNC>
# name: LJ::color_fromdb
# des: Takes a value of unknown type from the DB and returns an #rrggbb string.
# args: color
# des-color: either a 24-bit decimal number, or an #rrggbb string.
# returns: scalar; #rrggbb string, or undef if unknown input format
# </LJFUNC>
sub color_fromdb
{
    my $c = shift;
    return $c if $c =~ /^\#[0-9a-f]{6,6}$/i;
    return sprintf("\#%06x", $c) if $c =~ /^\d+$/;
    return undef;
}

# <LJFUNC>
# name: LJ::color_todb
# des: Takes an #rrggbb value and returns a 24-bit decimal number.
# args: color
# des-color: scalar; an #rrggbb string.
# returns: undef if bogus color, else scalar; 24-bit decimal number, can be up to 8 chars wide as a string.
# </LJFUNC>
sub color_todb
{
    my $c = shift;
    return undef unless $c =~ /^\#[0-9a-f]{6,6}$/i;
    return hex(substr($c, 1, 6));
}

# We're not always running under mod_perl... sometimes scripts (syndication sucker)
# call paths which end up thinking they need the remote IP, but don't.
sub get_remote_ip
{
    return $LJ::_T_FAKE_IP if $LJ::IS_DEV_SERVER && $LJ::_T_FAKE_IP;

    my $r = DW::Request->get;
    return ( $r ? $r->get_remote_ip : undef ) || $ENV{'FAKE_IP'};
}

sub md5_struct
{
    my ($st, $md5) = @_;
    $md5 ||= Digest::MD5->new;
    unless (ref $st) {
        # later Digest::MD5s die while trying to
        # get at the bytes of an invalid utf-8 string.
        # this really shouldn't come up, but when it
        # does, we clear the utf8 flag on the string and retry.
        # see http://zilla.livejournal.org/show_bug.cgi?id=851
        eval { $md5->add($st); };
        if ($@) {
            $st = LJ::no_utf8_flag ( $st );
            $md5->add($st);
        }
        return $md5;
    }
    if (ref $st eq "HASH") {
        foreach (sort keys %$st) {
            md5_struct($_, $md5);
            md5_struct($st->{$_}, $md5);
        }
        return $md5;
    }
    if (ref $st eq "ARRAY") {
        foreach (@$st) {
            md5_struct($_, $md5);
        }
        return $md5;
    }
}

sub urandom {
    my %args = @_;
    my $length = $args{size} or die 'Must Specify size';

    my $result;
    open my $fh, '<', '/dev/urandom' or die "Cannot open random: $!";
    while ($length) {
        my $chars;
        $fh->read($chars, $length) or die "Cannot read /dev/urandom: $!";
        $length -= length($chars);
        $result .= $chars;
    }
    $fh->close;

    return $result;
}

sub urandom_int {
    my %args = @_;

    return unpack('N', LJ::urandom( size => 4 ));
}

sub rand_chars
{
    my $length = shift;
    my $chal = "";
    my $digits = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    for (1..$length) {
        $chal .= substr($digits, int(rand(62)), 1);
    }
    return $chal;
}

# ($time, $secret) = LJ::get_secret();       # will generate
# $secret          = LJ::get_secret($time);  # won't generate
# ($time, $secret) = LJ::get_secret($time);  # will generate (in wantarray)
sub get_secret
{
    my $time = int($_[0]);
    return undef if $_[0] && ! $time;
    my $want_new = ! $time || wantarray;

    if (! $time) {
        $time = time();
        $time -= $time % 3600;  # one hour granularity
    }

    my $memkey = "secret:$time";
    my $secret = ($SecretCache{$memkey} ||= LJ::MemCache::get($memkey));
    return $want_new ? ($time, $secret) : $secret if $secret;

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;
    $secret = $dbh->selectrow_array("SELECT secret FROM secrets ".
                                    "WHERE stime=?", undef, $time);
    if ($secret) {
        $SecretCache{$memkey} = $secret;
        LJ::MemCache::set($memkey, $secret);
        return $want_new ? ($time, $secret) : $secret;
    }

    # return if they specified an explicit time they wanted.
    # (calling with no args means generate a new one if secret
    # doesn't exist)
    return undef unless $want_new;

    # don't generate new times that don't fall in our granularity
    return undef if $time % 3600;

    $secret = LJ::rand_chars(32);
    $dbh->do("INSERT IGNORE INTO secrets SET stime=?, secret=?",
             undef, $time, $secret);
    # check for races:
    $secret = get_secret($time);
    return ($time, $secret);
}


sub is_web_context {
    return $ENV{MOD_PERL} ? 1 : 0;
}

sub is_open_proxy
{
    my $ip = $_[0] || DW::Request->get;
    return 0 unless $ip;

    if ( ref $ip ) {
        $ip = $ip->get_remote_ip;
    }

    my $dbr = LJ::get_db_reader();
    my $stat = $dbr->selectrow_hashref("SELECT status, asof FROM openproxy WHERE addr=?",
                                       undef, $ip);

    # only cache 'clear' hosts for a day; 'proxy' for two days
    $stat = undef if $stat && $stat->{'status'} eq "clear" && $stat->{'asof'} > 0 && $stat->{'asof'} < time()-86400;
    $stat = undef if $stat && $stat->{'status'} eq "proxy" && $stat->{'asof'} < time()-2*86400;

    # open proxies are considered open forever, unless cleaned by another site-local mechanism
    return 1 if $stat && $stat->{'status'} eq "proxy";

    # allow things to be cached clear for a day before re-checking
    return 0 if $stat && $stat->{'status'} eq "clear";

    # no RBL defined?
    return 0 unless @LJ::RBL_LIST;

    my $src = undef;
    my $rev = join('.', reverse split(/\./, $ip));
    foreach my $rbl (@LJ::RBL_LIST) {
        my @res = gethostbyname("$rev.$rbl");
        if ($res[4]) {
            $src = $rbl;
            last;
        }
    }

    my $dbh = LJ::get_db_writer();
    if ($src) {
        $dbh->do("REPLACE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
                 $ip, "proxy", time(), $src);
        return 1;
    } else {
        $dbh->do("INSERT IGNORE INTO openproxy (addr, status, asof, src) VALUES (?,?,?,?)", undef,
                 $ip, "clear", time(), $src);
        return 0;
    }
}

# loads an include file, given the bare name of the file.
#   ($filename)
# returns the text of the file.  if the file is specified in %LJ::FILEEDIT_VIA_DB
# then it is loaded from memcache/DB, else it falls back to disk.
sub load_include {
    my $file = shift;
    return unless $file && $file =~ /^[a-zA-Z0-9-_\.]{1,255}$/;

    # okay, edit from where?
    if ($LJ::FILEEDIT_VIA_DB || $LJ::FILEEDIT_VIA_DB{$file}) {
        # we handle, so first if memcache...
        my $val = LJ::MemCache::get("includefile:$file");
        return $val if $val;

        # straight database hit
        my $dbh = LJ::get_db_writer();
        $val = $dbh->selectrow_array("SELECT inctext FROM includetext ".
                                     "WHERE incname=?", undef, $file);
        LJ::MemCache::set("includefile:$file", $val, time() + 3600);
        return $val if $val;
    }

    # hit it up from the file, if it exists
    my $filename = "$LJ::HOME/htdocs/inc/$file";
    return unless -e $filename;

    # get it and return it
    my $val;
    open (INCFILE, $filename)
        or return "Could not open include file: $file.";
    { local $/ = undef; $val = <INCFILE>; }
    close INCFILE;
    return $val;
}

# <LJFUNC>
# name: LJ::bit_breakdown
# des: Breaks down a bitmask into an array of bits enabled.
# args: mask
# des-mask: The number to break down.
# returns: A list of bits enabled.  E.g., 3 returns (0, 2) indicating that bits 0 and 2 (numbering
#          from the right) are currently on.
# </LJFUNC>
sub bit_breakdown {
    my $mask = shift()+0;

    # check each bit 0..63 and return only ones that are defined
    return grep { defined }
           map { $mask & (1<<$_) ? $_ : undef } 0..63;
}

sub last_error_code
{
    return $LJ::last_error;
}

sub last_error
{
    my $err = {
        'utf8' => "Encoding isn't valid UTF-8",
        'db' => "Database error",
        'comm_not_found' => "Community not found",
        'comm_not_comm' => "Account not a community",
        'comm_not_member' => "User not a member of community",
        'comm_invite_limit' => "Outstanding invitation limit reached",
        'comm_user_has_banned' => "Unable to invite; user has banned community",
    };
    my $des = $err->{$LJ::last_error};
    if ($LJ::last_error eq "db" && $LJ::db_error) {
        $des .= ": $LJ::db_error";
    }
    return $des || $LJ::last_error;
}

sub error
{
    my $err = shift;
    if ( LJ::DB::isdb( $err ) ) {
        $LJ::db_error = $err->errstr;
        $err = "db";
    } elsif ($err eq "db") {
        $LJ::db_error = "";
    }
    $LJ::last_error = $err;
    return undef;
}

*errobj = \&LJ::Error::errobj;
*throw = \&LJ::Error::throw;

# Returns a LWP::UserAgent or LWPx::Paranoid agent depending on role
# passed in by the caller.
# Des-%opts:
#           role     => what is this UA being used for? (required)
#           timeout  => seconds before request will timeout, defaults to 10
#           max_size => maximum size of returned document, defaults to no limit
sub get_useragent {
    my %opts = @_;

    my $timeout  = $opts{'timeout'}  || 10;
    my $max_size = $opts{'max_size'} || undef;
    my $role     = $opts{'role'};
    return unless $role;

    my $lib = 'LWPx::ParanoidAgent';
    $lib = $LJ::USERAGENT_LIB{$role} if defined $LJ::USERAGENT_LIB{$role};

    eval "require $lib";
    my $ua = $lib->new(
                       timeout  => $timeout,
                       max_size => $max_size,
                       );

    return $ua;
}

sub assert_is {
    my ($va, $ve) = @_;
    return 1 if $va eq $ve;
    LJ::errobj("AssertIs",
               expected => $ve,
               actual => $va,
               caller => [caller()])->throw;
}

# no_utf8_flag previously used pack('C*',unpack('C*', $_[0]))
# but that stopped working in Perl 5.10; see
# http://bugs.dwscoalition.org/show_bug.cgi?id=640
sub no_utf8_flag {
    # tell Perl to ignore the SvUTF8 flag in this scope.
    use bytes;
    # make a copy of the input string that doesn't have the flag at all.
    return substr($_[0], 0);
}

# return true if root caller is a test file
sub is_from_test {
    return $0 && $0 =~ m!(^|/)t/!;
}

our $AUTOLOAD;
sub AUTOLOAD {
    if ($AUTOLOAD eq "LJ::send_mail") {
        eval "use LJ::Sendmail;";
        goto &$AUTOLOAD;
    }
    Carp::croak("Undefined subroutine: $AUTOLOAD");
}


sub conf_test {
    my ($conf, @args) = @_;
    return 0 unless $conf;
    return $conf->(@args) if ref $conf eq "CODE";
    return $conf;
}

sub is_enabled {
    my $conf = shift;
    if ( $conf eq 'payments' ) {
        my $remote = LJ::get_remote();
        return 1 if $remote && $remote->can_beta_payments;
    }
    return ! LJ::conf_test( $LJ::DISABLED{$conf}, @_ );
}

# document valid arguments for certain privs (using hooks)
# argument: name of priv
# returns: hashref of argname/argdesc, or just list of argnames if wantarray
sub list_valid_args {
    my ( $priv ) = @_;
    my $hr = {};

    foreach ( LJ::Hooks::run_hooks( "privlist-add", $priv ) ) {
        my $ret = $_->[0];
        next unless $ret;
        # merge all results
        @{ $hr }{ keys %$ret } = values %$ret;
    }

    # optionally allow someone to remove a listing that was provided elsewhere
    foreach ( LJ::Hooks::run_hooks( "privlist-remove", $priv ) ) {
        my @del = @$_;
        # remove any keys listed by the hook
        delete $hr->{$_} foreach @del;
    }

    return wantarray ? keys %$hr : $hr;
}

# END package LJ;


package LJ::Error::InvalidParameters;
sub opt_fields { qw(params) }
sub user_caused { 0 }

package LJ::Error::AssertIs;
sub fields { qw(expected actual caller) }
sub user_caused { 0 }

sub as_string {
    my $self = shift;
    my $caller = $self->field('caller');
    my $ve = $self->field('expected');
    my $va = $self->field('actual');
    return "Assertion failure at " . join(', ', (@$caller)[0..2]) . ": expected=$ve, actual=$va";
}

1;
