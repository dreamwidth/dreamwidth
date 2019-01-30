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

    use lib ( $LJ::HOME || $ENV{LJHOME} ) . "/extlib/lib/perl5";

    # Please do not change this to "LJ::Directories"
    require $LJ::HOME . "/cgi-bin/LJ/Directories.pm";
}

# now that the library is setup, we can start pulling things in.  start with
# the configuration library we need.
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

# Now set up logging support for everybody else to access; this is done
# very early. We may be called by a test though, which will set the flag,
# and in that case we disable all the logging.
use Log::Log4perl;
BEGIN {
    if ( $LJ::_T_CONFIG ) {
        # Tests, don't log
        my $conf = q{
log4perl.rootLogger=FATAL, DevNull

log4perl.appender.DevNull=Log::Log4perl::Appender::File
log4perl.appender.DevNull.filename=/dev/null
log4perl.appender.DevNull.layout=Log::Log4perl::Layout::SimpleLayout
        };
        Log::Log4perl::init( \$conf );
    } else {
        Log::Log4perl::init_and_watch( LJ::resolve_file( 'etc/log4perl.conf' ), 10 );
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
use LJ::Auth;      # has a bunch of pkg LJ functions at bottom
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
use LJ::Message;
use LJ::ConvUTF8;
use LJ::Userpic;
use LJ::ModuleCheck;
use IO::Socket::INET;
use IO::Socket::SSL;
use Mozilla::CA;

use LJ::UniqCookie;
use LJ::WorkerResultStorage;
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
use LJ::Global::Secrets;  # defines LJ::Secrets
use DW::Media;
use DW::Stats;
use DW::Proxy;

$Net::HTTPS::SSL_SOCKET_CLASS = "IO::Socket::SSL";

# make Unicode::MapUTF8 autoload:
sub Unicode::MapUTF8::AUTOLOAD {
    die "Unknown subroutine $Unicode::MapUTF8::AUTOLOAD"
        unless $Unicode::MapUTF8::AUTOLOAD =~ /::(utf8_supported_charset|to_utf8|from_utf8)$/;
    LJ::ConvUTF8->load;
    no strict 'refs';
    goto *{$Unicode::MapUTF8::AUTOLOAD}{CODE};
}

sub END { LJ::end_request(); }

require "$LJ::HOME/cgi-bin/ljlib-local.pl"
    if -e "$LJ::HOME/cgi-bin/ljlib-local.pl";

# if this is a dev server, alias LJ::D to Data::Dumper::Dumper
if ($LJ::IS_DEV_SERVER) {
    eval "use Data::Dumper ();";
    *LJ::D = \&Data::Dumper::Dumper;
}

LJ::MemCache::init();

# $LJ::PROTOCOL_VER is the version of the client-server protocol
# used uniformly by server code which uses the protocol.  We used
# to set this to "0" if $LJ::UNICODE was false, but now we assume
# we always want to use Unicode.
$LJ::PROTOCOL_VER = "1";

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

# Initialize our statistics reporting library if needed
if ( $LJ::STATS{host} && $LJ::STATS{port} ) {
    DW::Stats::setup( $LJ::STATS{host}, $LJ::STATS{port} );
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

    return $LJ::LOCKER_OBJ;
}

sub gearman_client {
    my $purpose = shift;

    return undef unless @LJ::GEARMAN_SERVERS;
    eval "use Gearman::Client; 1;" or die "No Gearman::Client available: $@";

    my $client = Gearman::Client->new;
    $client->job_servers(@LJ::GEARMAN_SERVERS);

    return $client;
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
#      state codes, color name/value mappings, etc.
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
    $LJ::ACTIVE_RES_GROUP = undef;    # use whatever is current site default

    %LJ::PAID_STATUS = ();            # per-request paid status

    %LJ::REQUEST_CACHE = ();          # request cached items ( longterm goal, store everything in here )

    $LJ::CACHE_REMOTE_BOUNCE_URL = undef;
    LJ::Userpic->reset_singletons;
    LJ::Comment->reset_singletons;
    LJ::Entry->reset_singletons;
    LJ::Message->reset_singletons;

    LJ::UniqCookie->clear_request_cache;

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
        LJ::need_res( { group => 'foundation', priority => $LJ::LIB_RES_PRIORITY },
            'js/jquery/jquery-1.8.3.js',
            'js/foundation/vendor/custom.modernizr.js',
            'js/foundation/foundation/foundation.js',
            'js/foundation/foundation/foundation.topbar.js',
            'js/dw/dw-core.js'
        );

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
                        ));

        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY, group => "default" }, qw (
                        stc/lj_base.css
                        ));
        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY, group => "jquery" }, qw (
                        stc/lj_base.css
                        ));

        # esn ajax
        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY }, qw(
                        js/esn.js
                        stc/esn.css
                        ))
            if LJ::is_enabled('esn_ajax');

        # contextual popup JS
        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY, group => "default" }, qw(
                        js/6alib/ippu.js
                        js/lj_ippu.js
                        js/6alib/hourglass.js
                        js/contextualhover.js
                        stc/contextualhover.css
                        ));

        my @ctx_popup_libraries = qw(
                js/jquery/jquery.ui.core.js
                js/jquery/jquery.ui.widget.js

                js/jquery/jquery.ui.tooltip.js
                js/jquery.ajaxtip.js
                js/jquery/jquery.ui.position.js
                stc/jquery/jquery.ui.core.css
                stc/jquery/jquery.ui.tooltip.css


                js/jquery.hoverIntent.js
                js/jquery.contextualhover.js
                stc/jquery.contextualhover.css
            );

        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY, group=> 'jquery' }, @ctx_popup_libraries );
        LJ::need_res( { priority => $LJ::LIB_RES_PRIORITY, group=> 'foundation' }, @ctx_popup_libraries );

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

sub site_variables_list {
    return qw(IMGPREFIX JSPREFIX STATPREFIX WSTATPREFIX USERPIC_ROOT SITEROOT);
}

sub use_ssl_site_variables {
    # save a backup of the original config value
    unless ( %LJ::_ORIG_CONFIG ) {
        %LJ::_ORIG_CONFIG = ();
        $LJ::_ORIG_CONFIG{$_} = ${$LJ::{$_}}
            foreach LJ::site_variables_list();
    }

    $LJ::SITEROOT = $LJ::SSLROOT;
    $LJ::IMGPREFIX = $LJ::SSLIMGPREFIX;
    $LJ::STATPREFIX = $LJ::SSLSTATPREFIX;
    $LJ::JSPREFIX = $LJ::SSLJSPREFIX;
    $LJ::WSTATPREFIX = $LJ::SSLWSTATPREFIX;
    $LJ::USERPIC_ROOT = $LJ::SSLICONPREFIX;
}

sub use_config_site_variables {
    # restore original siteroot, etc
    ${$LJ::{$_}} = $LJ::_ORIG_CONFIG{$_}
        foreach qw(IMGPREFIX JSPREFIX STATPREFIX WSTATPREFIX USERPIC_ROOT SITEROOT);
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

my %RAND_CHARSETS = (
    default => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    urlsafe_b64 => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_",
);

sub rand_chars {
    my ( $length, $charset ) = @_;
    my $chal = "";
    my $digits = $RAND_CHARSETS{ $charset || 'default' };
    my $digit_len = length( $digits );
    die "Invalid charset $charset" unless $digits && ( $digit_len > 0 );

    for (1..$length) {
        $chal .= substr($digits, int(rand($digit_len)), 1);
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
    my $filename = "$LJ::HTDOCS/inc/$file";
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

# Returns a LWP::UserAgent or LWP::UserAgent::Paranoid agent depending on role
# passed in by the caller.
# Des-%opts:
#           role     => what is this UA being used for? (required)
#           timeout  => seconds before request will timeout, defaults to 10
#           max_size => maximum size of returned document, defaults to no limit
sub get_useragent {
    my %opts = @_;

    my $timeout  = $opts{'timeout'}  || 10;
    my $max_size = $opts{'max_size'} || undef;
    my $agent    = $opts{'agent'};
    my $role     = $opts{'role'};
    return unless $role;

    my $lib = 'LWP::UserAgent::Paranoid';
    $lib = $LJ::USERAGENT_LIB{$role} if defined $LJ::USERAGENT_LIB{$role};

    eval "require $lib";
    my $ua = $lib->new(
        request_timeout  => $timeout,
        max_size => $max_size,
        ssl_opts => {
            # FIXME: we still need verify_hostname off. Investigate.
            verify_hostname => 0,
            # also needed for LWP::Protocol::https < 6.06
            SSL_verify_mode => 0,
            #ca_file => Mozilla::CA::SSL_ca_file()
        });
    #$ua->agent($agent) if $agent;
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
# but that stopped working in Perl 5.10.
sub no_utf8_flag {
    # tell Perl to ignore the SvUTF8 flag in this scope.
    use bytes;
    # make a copy of the input string that doesn't have the flag at all.
    return substr($_[0], 0);
}

# return 1 if root caller is a test, else 0
sub in_test {
    return $LJ::_T_CONFIG == 1 ? 1 : 0;
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
