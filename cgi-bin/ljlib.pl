package LJ;

use strict;
no warnings 'uninitialized';

BEGIN {
    # ugly hack to shutup dependent libraries which sometimes want to bring in
    # ljlib.pl (via require, ick!).  so this lets them know if it's recursive.
    # we REALLY need to move the rest of this crap to .pm files.
    $LJ::_LJLIB_INIT = 1;

    # ensure we have $LJ::HOME, or complain very vigorously
    $LJ::HOME ||= $ENV{LJHOME};
    die "No \$LJ::HOME set, or not a directory!\n"
        unless $LJ::HOME && -d $LJ::HOME;
}

use lib "$LJ::HOME/cgi-bin";

use Apache2::Connection ();
use Carp;
use DBI;
use DBI::Role;
use Digest::MD5 ();
use Digest::SHA1 ();
use HTTP::Date ();
use LJ::MemCache;
use LJ::Error;
use LJ::User;      # has a bunch of pkg LJ, non-OO methods at bottom
use LJ::Entry;     # has a bunch of pkg LJ, non-OO methods at bottom
use LJ::Constants;
use Time::Local ();
use Storable ();
use Compress::Zlib ();
use Class::Autouse qw(
                      DW::Request
                      TheSchwartz
                      TheSchwartz::Job
                      LJ::AdTargetedInterests
                      LJ::Comment
                      LJ::Config
                      LJ::Knob
                      LJ::ExternalSite
                      LJ::ExternalSite::Vox
                      LJ::Message
                      LJ::EventLogSink
                      LJ::PageStats
                      LJ::AccessLogSink
                      LJ::ConvUTF8
                      LJ::Userpic
                      LJ::ModuleCheck
                      IO::Socket::INET
                      LJ::UniqCookie
                      LJ::WorkerResultStorage
                      LJ::EventLogRecord
                      LJ::EventLogRecord::DeleteComment
                      LJ::Vertical
                      );

# make Unicode::MapUTF8 autoload:
sub Unicode::MapUTF8::AUTOLOAD {
    die "Unknown subroutine $Unicode::MapUTF8::AUTOLOAD"
        unless $Unicode::MapUTF8::AUTOLOAD =~ /::(utf8_supported_charset|to_utf8|from_utf8)$/;
    LJ::ConvUTF8->load;
    no strict 'refs';
    goto *{$Unicode::MapUTF8::AUTOLOAD}{CODE};
}

LJ::Config->load;

sub END { LJ::end_request(); }

# tables on user databases (ljlib-local should define @LJ::USER_TABLES_LOCAL)
# this is here and no longer in bin/upgrading/update-db-{general|local}.pl
# so other tools (in particular, the inter-cluster user mover) can verify
# that it knows how to move all types of data before it will proceed.
@LJ::USER_TABLES = ("userbio", "birthdays", "cmdbuffer", "dudata",
                    "log2", "logtext2", "logprop2", "logsec2",
                    "talk2", "talkprop2", "talktext2", "talkleft",
                    "userpicblob2", "subs", "subsprop", "has_subs",
                    "ratelog", "loginstall", "sessions", "sessions_data",
                    "s1usercache", "modlog", "modblob",
                    "userproplite2", "links", "s1overrides", "s1style",
                    "s1stylecache", "userblob", "userpropblob",
                    "clustertrack2", "captcha_session", "reluser2",
                    "tempanonips", "inviterecv", "invitesent",
                    "memorable2", "memkeyword2", "userkeywords",
                    "friendgroup2", "userpicmap2", "userpic2",
                    "s2stylelayers2", "s2compiled2", "userlog",
                    "logtags", "logtagsrecent", "logkwsum",
                    "recentactions", "usertags", "pendcomments",
                    "user_schools", "portal_config", "portal_box_prop",
                    "loginlog", "active_user", "userblobcache",
                    "notifyqueue", "cprod", "urimap",
                    "sms_msg", "sms_msgprop", "sms_msgack",
                    "sms_msgtext", "sms_msgerror",
                    "jabroster", "jablastseen", "random_user_set",
                    "poll2", "pollquestion2", "pollitem2",
                    "pollresult2", "pollsubmission2",
                    "embedcontent", "usermsg", "usermsgtext", "usermsgprop",
                    "notifyarchive", "notifybookmarks",
                    );

# keep track of what db locks we have out
%LJ::LOCK_OUT = (); # {global|user} => caller_with_lock

require "ljdb.pl";
require "taglib.pl";
require "ljtextutil.pl";
require "ljtimeutil.pl";
require "ljcapabilities.pl";
require "ljmood.pl";
require "ljhooks.pl";
require "ljrelation.pl";
require "ljuserpics.pl";

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

# declare views (calls into ljviews.pl)
@LJ::views = qw(lastn friends calendar day);
%LJ::viewinfo = (
                 "lastn" => {
                     "creator" => \&LJ::S1::create_view_lastn,
                     "des" => "Most Recent Events",
                 },
                 "calendar" => {
                     "creator" => \&LJ::S1::create_view_calendar,
                     "des" => "Calendar",
                 },
                 "day" => {
                     "creator" => \&LJ::S1::create_view_day,
                     "des" => "Day View",
                 },
                 "friends" => {
                     "creator" => \&LJ::S1::create_view_friends,
                     "des" => "Friends View",
                     "owner_props" => ["opt_usesharedpic", "friendspagetitle"],
                 },
                 "friendsfriends" => {
                     "creator" => \&LJ::S1::create_view_friends,
                     "des" => "Friends of Friends View",
                     "styleof" => "friends",
                 },
                 "data" => {
                     "creator" => \&LJ::Feed::create_view,
                     "des" => "Data View (RSS, etc.)",
                     "owner_props" => ["opt_whatemailshow", "no_mail_alias"],
                 },
                 "rss" => {  # this is now provided by the "data" view.
                     "des" => "RSS View (XML)",
                 },
                 "res" => {
                     "des" => "S2-specific resources (stylesheet)",
                 },
                 "pics" => {
                     "des" => "FotoBilder pics (root gallery)",
                 },
                 "info" => {
                     # just a redirect to userinfo.bml for now.
                     # in S2, will be a real view.
                     "des" => "Profile Page",
                 },
                 "profile" => {
                     # just a redirect to userinfo.bml for now.
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

## if this library is used in a BML page, we don't want to destroy BML's
## HUP signal handler.
if ($SIG{'HUP'}) {
    my $oldsig = $SIG{'HUP'};
    $SIG{'HUP'} = sub {
        &{$oldsig};
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
        "phonepost" => 2,
        "captcha_audio" => 3,
        "captcha_image" => 4,
        "fotobilder" => 5,
    }->{$name};
    # FIXME: add hook support, so sites can't define their own
    # general code gets priority on numbers, say, 1-200, so verify
    # hook returns a number 201-255
    return $id if $id;
    die "Unknown blob domain: $name";
}

sub _using_blockwatch {
    if (LJ::conf_test($LJ::DISABLED{blockwatch})) {
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
                                      timeout => $LJ::MOGILEFS_CONFIG{timeout} || 3,
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
    return LJ::Test->theschwartz() if $LJ::_T_FAKESCHWARTZ;
    return $LJ::SchwartzClient     if $LJ::SchwartzClient;

    my $opts = shift;

    my $mode = $opts->{mode} || "";
    my @dbs = @LJ::THESCHWARTZ_DBS;
    push @dbs, @LJ::THESCHWARTZ_DBS_NOINJECT if $mode eq "drain";

    if (@dbs) {
        # FIXME: use LJ's DBI::Role system for this.
        $LJ::SchwartzClient = TheSchwartz->new(databases => \@dbs);
    }

    return $LJ::SchwartzClient;
}

sub sms_gateway {
    my $conf_key = shift;

    # effective config key is 'default' if one wasn't specified or nonexistent
    # config was specified, meaning fall back to default
    unless ($conf_key && $LJ::SMS_GATEWAY_CONFIG{$conf_key}) {
        $conf_key = 'default';
    }

    return $LJ::SMS_GATEWAY{$conf_key} ||= do {
        my $class = "DSMS::Gateway" .
            ($LJ::SMS_GATEWAY_TYPE ? "::$LJ::SMS_GATEWAY_TYPE" : "");

        eval "use $class";
        die "unable to use $class: $@" if $@;

        $class->new(config => $LJ::SMS_GATEWAY_CONFIG{$conf_key});
    };
}

sub gtop {
    return unless $LJ::LOG_GTOP && LJ::ModuleCheck->have("GTop");
    return $GTop ||= GTop->new;
}

# <LJFUNC>
# name: LJ::get_newids
# des: Lookup an old global ID and see what journal it belongs to and its new ID.
# info: Interface to [dbtable[oldids]] table (URL compatability)
# returns: Undef if non-existent or unconverted, or arrayref of [$userid, $newid].
# args: area, oldid
# des-area: The "area" of the id.  Legal values are "L" (log), to lookup an old itemid,
#           or "T" (talk) to lookup an old talkid.
# des-oldid: The old globally-unique id of the item.
# </LJFUNC>
sub get_newids
{
    my $sth;
    my $db = LJ::get_dbh("oldids") || LJ::get_db_reader();
    return $db->selectrow_arrayref("SELECT userid, newid FROM oldids ".
                                   "WHERE area=? AND oldid=?", undef,
                                   $_[0], $_[1]);
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
    unless (ref $opt eq 'HASH') {
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
# name: LJ::get_friend_items
# des: Return friend items for a given user, filter, and period.
# args: dbarg?, opts
# des-opts: Hashref of options:
#           - userid
#           - remoteid
#           - itemshow
#           - skip
#           - filter  (opt) defaults to all
#           - friends (opt) friends rows loaded via [func[LJ::get_friends]]
#           - friends_u (opt) u objects of all friends loaded
#           - idsbycluster (opt) hashref to set clusterid key to [ [ journalid, itemid ]+ ]
#           - dateformat:  either "S2" for S2 code, or anything else for S1
#           - common_filter:  set true if this is the default view
#           - friendsoffriends: load friends of friends, not just friends
#           - u: hashref of journal loading friends of
#           - showtypes: /[PICNY]/
# returns: Array of item hashrefs containing the same elements
# </LJFUNC>
sub get_friend_items
{
    &nodb;
    my $opts = shift;

    my $dbr = LJ::get_db_reader();
    my $sth;

    my $userid = $opts->{'userid'}+0;
    return () if $LJ::FORCE_EMPTY_FRIENDS{$userid};

    # 'remote' opt takes precendence, then 'remoteid'
    my $remote = $opts->{'remote'};
    my $remoteid = $remote ? $remote->{'userid'} : 0;
    if ($remoteid == 0 && $opts->{'remoteid'}) {
        $remoteid = $opts->{'remoteid'} + 0;
        $remote = LJ::load_userid($remoteid);
    }

    # if ONLY_USER_VHOSTS is on (where each user gets his/her own domain),
    # then assume we're also using domain-session cookies, and assume
    # domain session cookies should be as most useless as possible,
    # so don't let friends pages on other domains have protected content
    # because really, nobody reads other people's friends pages anyway
    if ($LJ::ONLY_USER_VHOSTS && $remote && $remoteid != $userid) {
        $remote = undef;
        $remoteid = 0;
    }

    my @items = ();
    my $itemshow = $opts->{'itemshow'}+0;
    my $skip = $opts->{'skip'}+0;
    my $getitems = $itemshow + $skip;

    my $filter = $opts->{'filter'}+0;

    my $max_age = $LJ::MAX_FRIENDS_VIEW_AGE || 3600*24*14;  # 2 week default.
    my $lastmax = $LJ::EndOfTime - time() + $max_age;
    my $lastmax_cutoff = 0; # if nonzero, never search for entries with rlogtime higher than this (set when cache in use)

    # sanity check:
    $skip = 0 if $skip < 0;

    # given a hash of friends rows, strip out rows with invalid journaltype
    my $filter_journaltypes = sub {
        my ($friends, $friends_u, $memcache_only, $valid_types) = @_;
        return unless $friends && $friends_u;
        $valid_types ||= uc($opts->{'showtypes'});

        # load u objects for all the given
        LJ::load_userids_multiple([ map { $_, \$friends_u->{$_} } keys %$friends ], [$remote],
                                  $memcache_only);

        # delete u objects based on 'showtypes'
        foreach my $fid (keys %$friends_u) {
            my $fu = $friends_u->{$fid};
            if ($fu->{'statusvis'} ne "V" ||
                $valid_types && index(uc($valid_types), $fu->{journaltype}) == -1)
            {
                delete $friends_u->{$fid};
                delete $friends->{$fid};
            }
        }

        # all args passed by reference
        return;
    };

    my @friends_buffer = ();
    my $fr_loaded = 0;  # flag:  have we loaded friends?

    # normal friends mode
    my $get_next_friend = sub
    {
        # return one if we already have some loaded.
        return $friends_buffer[0] if @friends_buffer;
        return undef if $fr_loaded;

        # get all friends for this user and groupmask
        my $friends = LJ::get_friends($userid, $filter) || {};
        my %friends_u;

        # strip out rows with invalid journal types
        $filter_journaltypes->($friends, \%friends_u);

        # get update times for all the friendids
        my $tu_opts = {};
        my $fcount = scalar keys %$friends;
        if ($LJ::SLOPPY_FRIENDS_THRESHOLD && $fcount > $LJ::SLOPPY_FRIENDS_THRESHOLD) {
            $tu_opts->{memcache_only} = 1;
        }
        my $timeupdate = LJ::get_timeupdate_multi($tu_opts, keys %$friends);

        # now push a properly formatted @friends_buffer row
        foreach my $fid (keys %$timeupdate) {
            my $fu = $friends_u{$fid};
            my $rupdate = $LJ::EndOfTime - $timeupdate->{$fid};
            my $clusterid = $fu->{'clusterid'};
            push @friends_buffer, [ $fid, $rupdate, $clusterid, $friends->{$fid}, $fu ];
        }

        @friends_buffer = sort { $a->[1] <=> $b->[1] } @friends_buffer;

        # note that we've already loaded the friends
        $fr_loaded = 1;

        # return one if we just found some, else we're all
        # out and there's nobody else to load.
        return @friends_buffer ? $friends_buffer[0] : undef;
    };

    # memcached friends of friends mode
    $get_next_friend = sub
    {
        # return one if we already have some loaded.
        return $friends_buffer[0] if @friends_buffer;
        return undef if $fr_loaded;

        # get journal's friends
        my $friends = LJ::get_friends($userid) || {};
        return undef unless %$friends;

        my %friends_u;

        # fill %allfriends with all friendids and cut $friends
        # down to only include those that match $filter
        my %allfriends = ();
        foreach my $fid (keys %$friends) {
            $allfriends{$fid}++;

            # delete from friends if it doesn't match the filter
            next unless $filter && ! ($friends->{$fid}->{'groupmask'}+0 & $filter+0);
            delete $friends->{$fid};
        }

        # strip out invalid friend journaltypes
        $filter_journaltypes->($friends, \%friends_u, "memcache_only", "P");

        # get update times for all the friendids
        my $f_tu = LJ::get_timeupdate_multi({'memcache_only' => 1}, keys %$friends);

        # get friends of friends
        my $ffct = 0;
        my %ffriends = ();
        foreach my $fid (sort { $f_tu->{$b} <=> $f_tu->{$a} } keys %$friends) {
            last if $ffct > 50;
            my $ff = LJ::get_friends($fid, undef, "memcache_only") || {};
            my $ct = 0;
            while (my $ffid = each %$ff) {
                last if $ct > 100;
                next if $allfriends{$ffid} || $ffid == $userid;
                $ffriends{$ffid} = $ff->{$ffid};
                $ct++;
            }
            $ffct++;
        }

        # strip out invalid friendsfriends journaltypes
        my %ffriends_u;
        $filter_journaltypes->(\%ffriends, \%ffriends_u, "memcache_only");

        # get update times for all the friendids
        my $ff_tu = LJ::get_timeupdate_multi({'memcache_only' => 1}, keys %ffriends);

        # build friends buffer
        foreach my $ffid (sort { $ff_tu->{$b} <=> $ff_tu->{$a} } keys %$ff_tu) {
            my $rupdate = $LJ::EndOfTime - $ff_tu->{$ffid};
            my $clusterid = $ffriends_u{$ffid}->{'clusterid'};

            # since this is ff mode, we'll force colors to ffffff on 000000
            $ffriends{$ffid}->{'fgcolor'} = "#000000";
            $ffriends{$ffid}->{'bgcolor'} = "#ffffff";

            push @friends_buffer, [ $ffid, $rupdate, $clusterid, $ffriends{$ffid}, $ffriends_u{$ffid} ];
        }

        @friends_buffer = sort { $a->[1] <=> $b->[1] } @friends_buffer;

        # note that we've already loaded the friends
        $fr_loaded = 1;

        # return one if we just found some fine, else we're all
        # out and there's nobody else to load.
        return @friends_buffer ? $friends_buffer[0] : undef;

    } if $opts->{'friendsoffriends'} && @LJ::MEMCACHE_SERVERS;

    # old friends of friends mode
    # - use this when there are no memcache servers
    $get_next_friend = sub
    {
        # return one if we already have some loaded.
        return $friends_buffer[0] if @friends_buffer;
        return undef if $fr_loaded;

        # load all user's friends
        # TAG:FR:ljlib:old_friendsfriends_getitems
        my %f;
        my $sth = $dbr->prepare(qq{
            SELECT f.friendid, f.groupmask, $LJ::EndOfTime-UNIX_TIMESTAMP(uu.timeupdate),
            u.journaltype FROM friends f, userusage uu, user u
            WHERE f.userid=? AND f.friendid=uu.userid AND u.userid=f.friendid AND u.journaltype='P'
        });
        $sth->execute($userid);
        while (my ($id, $mask, $time, $jt) = $sth->fetchrow_array) {
            next if $id == $userid; # don't follow user's own friends
            $f{$id} = { 'userid' => $id, 'timeupdate' => $time, 'jt' => $jt,
                        'relevant' => ($filter && !($mask & $filter)) ? 0 : 1 , };
        }

        # load some friends of friends (most 20 queries)
        my %ff;
        my $fct = 0;
        foreach my $fid (sort { $f{$a}->{'timeupdate'} <=> $f{$b}->{'timeupdate'} } keys %f)
        {
            next unless $f{$fid}->{'jt'} eq "P" && $f{$fid}->{'relevant'};
            last if ++$fct > 20;
            my $extra;
            if ($opts->{'showtypes'}) {
                my @in;
                if ($opts->{'showtypes'} =~ /P/) { push @in, "'P'"; }
                if ($opts->{'showtypes'} =~ /Y/) { push @in, "'Y'"; }
                if ($opts->{'showtypes'} =~ /C/) { push @in, "'C','S','N'"; }
                $extra = "AND u.journaltype IN (".join (',', @in).")" if @in;
            }

            # TAG:FR:ljlib:old_friendsfriends_getitems2
            my $sth = $dbr->prepare(qq{
                SELECT u.*, UNIX_TIMESTAMP(uu.timeupdate) AS timeupdate
                FROM friends f, userusage uu, user u WHERE f.userid=? AND
                    f.friendid=uu.userid AND f.friendid=u.userid AND u.statusvis='V' $extra
                    AND uu.timeupdate > DATE_SUB(NOW(), INTERVAL 14 DAY) LIMIT 100
            });
            $sth->execute($fid);
            while (my $u = $sth->fetchrow_hashref) {
                my $uid = $u->{'userid'};
                next if $f{$uid} || $uid == $userid;  # we don't wanna see our friends

                # timeupdate
                my $time = $LJ::EndOfTime-$u->{'timeupdate'};
                delete $u->{'timeupdate'}; # not a proper $u column

                $ff{$uid} = [ $uid, $time, $u->{'clusterid'}, {}, $u ];
            }
        }

        @friends_buffer = sort { $a->[1] <=> $b->[1] } values %ff;
        $fr_loaded = 1;

        return @friends_buffer ? $friends_buffer[0] : undef;

    } if $opts->{'friendsoffriends'} && ! @LJ::MEMCACHE_SERVERS;

    my $loop = 1;
    my $itemsleft = $getitems;  # even though we got a bunch, potentially, they could be old
    my $fr;

    while ($loop && ($fr = $get_next_friend->()))
    {
        shift @friends_buffer;

        # load the next recent updating friend's recent items
        my $friendid = $fr->[0];

        $opts->{'friends'}->{$friendid} = $fr->[3];  # friends row
        $opts->{'friends_u'}->{$friendid} = $fr->[4]; # friend u object

        my @newitems = LJ::get_log2_recent_user({
            'clusterid' => $fr->[2],
            'userid' => $friendid,
            'remote' => $remote,
            'itemshow' => $itemsleft,
            'notafter' => $lastmax,
            'dateformat' => $opts->{'dateformat'},
            'update' => $LJ::EndOfTime - $fr->[1], # reverse back to normal
        });

        # stamp each with clusterid if from cluster, so ljviews and other
        # callers will know which items are old (no/0 clusterid) and which
        # are new
        if ($fr->[2]) {
            foreach (@newitems) { $_->{'clusterid'} = $fr->[2]; }
        }

        if (@newitems)
        {
            push @items, @newitems;

            $itemsleft--; # we'll need at least one less for the next friend

            # sort all the total items by rlogtime (recent at beginning).
            # if there's an in-second tie, the "newer" post is determined by
            # the higher jitemid, which means nothing if the posts aren't in the same
            # journal, but means everything if they are (which happens almost never
            # for a human, but all the time for RSS feeds, once we remove the
            # synsucker's 1-second delay between postevents)
            @items = sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} ||
                            $b->{'jitemid'}  <=> $a->{'jitemid'}     } @items;

            # cut the list down to what we need.
            @items = splice(@items, 0, $getitems) if (@items > $getitems);
        }

        if (@items == $getitems)
        {
            $lastmax = $items[-1]->{'rlogtime'};
            $lastmax = $lastmax_cutoff if $lastmax_cutoff && $lastmax > $lastmax_cutoff;

            # stop looping if we know the next friend's newest entry
            # is greater (older) than the oldest one we've already
            # loaded.
            my $nextfr = $get_next_friend->();
            $loop = 0 if ($nextfr && $nextfr->[1] > $lastmax);
        }
    }

    # remove skipped ones
    splice(@items, 0, $skip) if $skip;

    # get items
    foreach (@items) {
        $opts->{'owners'}->{$_->{'ownerid'}} = 1;
    }

    # return the itemids grouped by clusters, if callers wants it.
    if (ref $opts->{'idsbycluster'} eq "HASH") {
        foreach (@items) {
            push @{$opts->{'idsbycluster'}->{$_->{'clusterid'}}},
            [ $_->{'ownerid'}, $_->{'itemid'} ];
        }
    }

    return @items;
}

# <LJFUNC>
# name: LJ::get_recent_items
# class:
# des: Returns journal entries for a given account.
# info:
# args: dbarg, opts
# des-opts: Hashref of options with keys:
#           -- err: scalar ref to return error code/msg in
#           -- userid
#           -- remote: remote user's $u
#           -- remoteid: id of remote user
#           -- clusterid: clusterid of userid
#           -- tagids: arrayref of tagids to return entries with
#           -- security: (public|friends|private) or a group number
#           -- clustersource: if value 'slave', uses replicated databases
#           -- order: if 'logtime', sorts by logtime, not eventtime
#           -- friendsview: if true, sorts by logtime, not eventtime
#           -- notafter: upper bound inclusive for rlogtime/revttime (depending on sort mode),
#           defaults to no limit
#           -- skip: items to skip
#           -- itemshow: items to show
#           -- viewall: if set, no security is used.
#           -- dateformat: if "S2", uses S2's 'alldatepart' format.
#           -- itemids: optional arrayref onto which itemids should be pushed
# returns: array of hashrefs containing keys:
#          -- itemid (the jitemid)
#          -- posterid
#          -- security
#          -- alldatepart (in S1 or S2 fmt, depending on 'dateformat' req key)
#          -- system_alldatepart (same as above, but for the system time)
#          -- ownerid (if in 'friendsview' mode)
#          -- rlogtime (if in 'friendsview' mode)
# </LJFUNC>
sub get_recent_items
{
    &nodb;
    my $opts = shift;

    my $sth;

    my @items = ();             # what we'll return
    my $err = $opts->{'err'};

    my $userid = $opts->{'userid'}+0;

    # 'remote' opt takes precendence, then 'remoteid'
    my $remote = $opts->{'remote'};
    my $remoteid = $remote ? $remote->{'userid'} : 0;
    if ($remoteid == 0 && $opts->{'remoteid'}) {
        $remoteid = $opts->{'remoteid'} + 0;
        $remote = LJ::load_userid($remoteid);
    }

    my $max_hints = $LJ::MAX_SCROLLBACK_LASTN;  # temporary
    my $sort_key = "revttime";

    my $clusterid = $opts->{'clusterid'}+0;
    my @sources = ("cluster$clusterid");
    if (my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$clusterid}) {
        @sources = ("cluster${clusterid}${ab}");
    }
    unshift @sources, ("cluster${clusterid}lite", "cluster${clusterid}slave")
        if $opts->{'clustersource'} eq "slave";
    my $logdb = LJ::get_dbh(@sources);

    # community/friend views need to post by log time, not event time
    $sort_key = "rlogtime" if ($opts->{'order'} eq "logtime" ||
                               $opts->{'friendsview'});

    # 'notafter':
    #   the friends view doesn't want to load things that it knows it
    #   won't be able to use.  if this argument is zero or undefined,
    #   then we'll load everything less than or equal to 1 second from
    #   the end of time.  we don't include the last end of time second
    #   because that's what backdated entries are set to.  (so for one
    #   second at the end of time we'll have a flashback of all those
    #   backdated entries... but then the world explodes and everybody
    #   with 32 bit time_t structs dies)
    my $notafter = $opts->{'notafter'} + 0 || $LJ::EndOfTime - 1;

    my $skip = $opts->{'skip'}+0;
    my $itemshow = $opts->{'itemshow'}+0;
    if ($itemshow > $max_hints) { $itemshow = $max_hints; }
    my $maxskip = $max_hints - $itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }
    my $itemload = $itemshow + $skip;

    my $mask = 0;
    if ($remote && ($remote->{'journaltype'} eq "P" || $remote->{'journaltype'} eq "I") && $remoteid != $userid) {
        $mask = LJ::get_groupmask($userid, $remoteid);
    }

    # decide what level of security the remote user can see
    my $secwhere = "";
    if ($userid == $remoteid || $opts->{'viewall'}) {
        # no extra where restrictions... user can see all their own stuff
        # alternatively, if 'viewall' opt flag is set, security is off.
    } elsif ($mask) {
        # can see public or things with them in the mask
        $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $mask != 0))";
    } else {
        # not a friend?  only see public.
        $secwhere = "AND security='public' ";
    }

    # because LJ::get_friend_items needs rlogtime for sorting.
    my $extra_sql;
    if ($opts->{'friendsview'}) {
        $extra_sql .= "journalid AS 'ownerid', rlogtime, ";
    }

    # if we need to get by tag, get an itemid list now
    my $jitemidwhere;
    if (ref $opts->{tagids} eq 'ARRAY' && @{$opts->{tagids}}) {
        # select jitemids uniquely
        my $in = join(',', map { $_+0 } @{$opts->{tagids}});
        my $jitemids = $logdb->selectcol_arrayref(qq{
                SELECT DISTINCT jitemid FROM logtagsrecent WHERE journalid = ? AND kwid IN ($in)
            }, undef, $userid);
        die $logdb->errstr if $logdb->err;

        # set $jitemidwhere iff we have jitemids
        if (@$jitemids) {
            $jitemidwhere = " AND jitemid IN (" .
                            join(',', map { $_+0 } @$jitemids) .
                            ")";
        } else {
            # no items, so show no entries
            return ();
        }
    }

    # if we need to filter by security, build up the where clause for that too
    my $securitywhere;
    if ($opts->{'security'}) {
        my $security = $opts->{'security'};
        if (($security eq "public") || ($security eq "private")) {
            $securitywhere = " AND security = \"$security\"";
        }
        elsif ($security eq "friends") {
            $securitywhere = " AND security = \"usemask\" AND allowmask = 1";
        }
        elsif ($security=~/^\d+$/) {
            $securitywhere = " AND security = \"usemask\" AND (allowmask & " . (1 << $security) . ")";
        }
    }

    my $sql;

    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    if ($opts->{'dateformat'} eq "S2") {
        $dateformat = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    }

    $sql = qq{
        SELECT jitemid AS 'itemid', posterid, security, $extra_sql
               DATE_FORMAT(eventtime, "$dateformat") AS 'alldatepart', anum,
               DATE_FORMAT(logtime, "$dateformat") AS 'system_alldatepart',
               allowmask, eventtime, logtime
        FROM log2 USE INDEX ($sort_key)
        WHERE journalid=$userid AND $sort_key <= $notafter $secwhere $jitemidwhere $securitywhere
        ORDER BY journalid, $sort_key
        LIMIT $skip,$itemshow
    };

    unless ($logdb) {
        $$err = "nodb" if ref $err eq "SCALAR";
        return ();
    }

    $sth = $logdb->prepare($sql);
    $sth->execute;
    if ($logdb->err) { die $logdb->errstr; }

    # keep track of the last alldatepart, and a per-minute buffer
    my $last_time;
    my @buf;
    my $flush = sub {
        return unless @buf;
        push @items, sort { $b->{itemid} <=> $a->{itemid} } @buf;
        @buf = ();
    };

    while (my $li = $sth->fetchrow_hashref) {
        push @{$opts->{'itemids'}}, $li->{'itemid'};

        $flush->() if $li->{alldatepart} ne $last_time;
        push @buf, $li;
        $last_time = $li->{alldatepart};

        # construct an LJ::Entry singleton
        my $entry = LJ::Entry->new($userid, jitemid => $li->{itemid});
        $entry->absorb_row(%$li);
    }
    $flush->();

    return @items;
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
sub register_authaction
{
    &nodb;
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
# class: logging
# name: LJ::statushistory_add
# des: Adds a row to a user's statushistory
# info: See the [dbtable[statushistory]] table.
# returns: boolean; 1 on success, 0 on failure
# args: dbarg?, userid, adminid, shtype, notes?
# des-userid: The user being acted on.
# des-adminid: The site admin doing the action.
# des-shtype: The status history type code.
# des-notes: Optional notes associated with this action.
# </LJFUNC>
sub statushistory_add
{
    &nodb;
    my $dbh = LJ::get_db_writer();

    my $userid = shift;
    $userid = LJ::want_userid($userid) + 0;

    my $actid  = shift;
    $actid = LJ::want_userid($actid) + 0;

    my $qshtype = $dbh->quote(shift);
    my $qnotes  = $dbh->quote(shift);

    $dbh->do("INSERT INTO statushistory (userid, adminid, shtype, notes) ".
             "VALUES ($userid, $actid, $qshtype, $qnotes)");
    return $dbh->err ? 0 : 1;
}

# <LJFUNC>
# name: LJ::make_link
# des: Takes a group of key=value pairs to append to a URL.
# returns: The finished URL.
# args: url, vars
# des-url: A string with the URL to append to.  The URL
#          should not have a question mark in it.
# des-vars: A hashref of the key=value pairs to append with.
# </LJFUNC>
sub make_link
{
    my $url = shift;
    my $vars = shift;
    my $append = "?";
    foreach (keys %$vars) {
        next if ($vars->{$_} eq "");
        $url .= "${append}${_}=$vars->{$_}";
        $append = "&";
    }
    return $url;
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
    my $user = shift;
    return undef unless $user;

    # get a remote
    my $remote = LJ::get_remote();
    return undef unless $remote;

    # remote is already what they want?
    return $remote if $remote->{'user'} eq $user;

    # load user and authenticate
    my $u = LJ::load_user($user);
    return undef unless $u;
    return undef unless $u->{clusterid};

    # does $u have admin access?
    return undef unless LJ::can_manage($remote, $u);

    # passed all checks, return $u
    return $u;
}


# <LJFUNC>
# name: LJ::shared_member_request
# des: Registers an authaction to add a user to a
#      shared journal and sends an approval e-mail.
# returns: Hashref; output of LJ::register_authaction()
#          includes datecreate of old row if no new row was created.
# args: ju, u, attr?
# des-ju: Shared journal user object
# des-u: User object to add to shared journal
# </LJFUNC>
sub shared_member_request {
    my ($ju, $u) = @_;
    return undef unless ref $ju && ref $u;

    my $dbh = LJ::get_db_writer();

    # check for duplicates
    my $oldaa = $dbh->selectrow_hashref("SELECT aaid, authcode, datecreate FROM authactions " .
                                        "WHERE userid=? AND action='shared_invite' AND used='N' " .
                                        "AND NOW() < datecreate + INTERVAL 1 HOUR " .
                                        "ORDER BY 1 DESC LIMIT 1",
                                        undef, $ju->{'userid'});
    return $oldaa if $oldaa;

    # insert authactions row
    my $aa = LJ::register_authaction($ju->{'userid'}, 'shared_invite', "targetid=$u->{'userid'}");
    return undef unless $aa;

    # if there are older duplicates, invalidate any existing unused authactions of this type
    $dbh->do("UPDATE authactions SET used='Y' WHERE userid=? AND aaid<>? " .
             "AND action='shared_invite' AND used='N'",
             undef, $ju->{'userid'}, $aa->{'aaid'});

    my $body = "The maintainer of the $ju->{'user'} shared journal has requested that " .
        "you be given posting access.\n\n" .
        "If you do not wish to be added to this journal, just ignore this email.  " .
        "However, if you would like to accept posting rights to $ju->{'user'}, click " .
        "the link below to authorize this action.\n\n" .
        "     $LJ::SITEROOT/approve/$aa->{'aaid'}.$aa->{'authcode'}\n\n" .
        "Regards\n$LJ::SITENAME Team\n";

    LJ::send_mail({
        'to' => $u->email_raw,
        'from' => $LJ::ADMIN_EMAIL,
        'fromname' => $LJ::SITENAME,
        'charset' => 'utf-8',
        'subject' => "Community Membership: $ju->{'name'}",
        'body' => $body
        });

    return $aa;
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
sub is_valid_authaction
{
    &nodb;

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
# name: LJ::get_urls
# des: Returns a list of all referenced URLs from a string.
# args: text
# des-text: Text from which to return extra URLs.
# returns: list of URLs
# </LJFUNC>
sub get_urls
{
    return ($_[0] =~ m!https?://[^\s\"\'\<\>]+!g);
}

# <LJFUNC>
# name: LJ::record_meme
# des: Records a URL reference from a journal entry to the [dbtable[meme]] table.
# args: dbarg?, url, posterid, itemid, journalid?
# des-url: URL to log
# des-posterid: Userid of person posting
# des-itemid: Itemid URL appears in.  This is the display itemid,
#             which is the jitemid*256+anum from the [dbtable[log2]] table.
# des-journalid: Optional, journal id of item, if item is clustered.  Otherwise
#                this should be zero or undef.
# </LJFUNC>
sub record_meme
{
    my ($url, $posterid, $itemid, $jid) = @_;
    return if $LJ::DISABLED{'meme'};

    $url =~ s!/$!!;  # strip / at end
    LJ::run_hooks("canonicalize_url", \$url);

    # canonicalize_url hook might just erase it, so
    # we don't want to record it.
    return unless $url;

    my $dbh = LJ::get_db_writer();
    $dbh->do("REPLACE DELAYED INTO meme (url, posterid, journalid, itemid) " .
             "VALUES (?, ?, ?, ?)", undef, $url, $posterid, $jid, $itemid);
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

# <LJFUNC>
# name: LJ::load_props
# des: Loads and caches one or more of the various *proplist tables:
#      [dbtable[logproplist]], [dbtable[talkproplist]], and [dbtable[userproplist]], which describe
#      the various meta-data that can be stored on log (journal) items,
#      comments, and users, respectively.
# args: dbarg?, table*
# des-table: a list of tables' proplists to load. Can be one of
#            "log", "talk", "user", or "rate".
# </LJFUNC>
sub load_props
{
    my $dbarg = ref $_[0] ? shift : undef;
    my @tables = @_;
    my $dbr;
    my %keyname = qw(log  propid
                     talk tpropid
                     user upropid
                     rate rlid
                     );

    foreach my $t (@tables) {
        next unless defined $keyname{$t};
        next if defined $LJ::CACHE_PROP{$t};
        my $tablename = $t eq "rate" ? "ratelist" : "${t}proplist";
        $dbr ||= LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT * FROM $tablename");
        $sth->execute;
        while (my $p = $sth->fetchrow_hashref) {
            $p->{'id'} = $p->{$keyname{$t}};
            $LJ::CACHE_PROP{$t}->{$p->{'name'}} = $p;
            $LJ::CACHE_PROPID{$t}->{$p->{'id'}} = $p;
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
        warn "Prop table does not exist: $table" if $LJ::IS_DEV_SERVER;
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
sub load_codes
{
    &nodb;
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
# name: LJ::load_state_city_for_zip
# des: Fetches state and city for the given zip-code value
# args: dbarg?, zip
# des-zip: zip code
# </LJFUNC>
sub load_state_city_for_zip
{
    &nodb;

    my $zip = shift;
    my ($zipcity, $zipstate);

    if ($zip =~ /^\d{5}$/) {
        my $dbr = LJ::get_db_reader()
            or die "Unable to get database handle";
    
        my $sth = $dbr->prepare("SELECT city, state FROM zip WHERE zip=?");
        $sth->execute($zip) or die "Failed to fetch state and city for zip: $DBI::errstr";
        ($zipcity, $zipstate) = $sth->fetchrow_array;
    }
    
    return ($zipcity, $zipstate);
}

# <LJFUNC>
# name: LJ::auth_okay
# des: Validates a user's password.  The "clear" or "md5" argument
#      must be present, and either the "actual" argument (the correct
#      password) must be set, or the first argument must be a user
#      object ($u) with the 'password' key set.  This is the preferred
#      way to validate a password (as opposed to doing it by hand),
#      since <strong>this</strong> function will use a pluggable
#      authenticator, if one is defined, so LiveJournal installations
#       can be based off an LDAP server, for example.
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

    # setup this auth checker for LDAP
    if ($LJ::LDAP_HOST && ! $LJ::AUTH_CHECK) {
        require LJ::LDAP;
        $LJ::AUTH_CHECK = sub {
            my ($user, $try, $type) = @_;
            die unless $type eq "clear";
            return LJ::LDAP::is_good_ldap($user, $try);
        };
    }

    ## custom authorization:
    if (ref $LJ::AUTH_CHECK eq "CODE") {
        my $type = $md5 ? "md5" : "clear";
        my $try = $md5 || $clear;
        my $good = $LJ::AUTH_CHECK->($user, $try, $type);
        return $good || $bad_login->();
    }

    ## LJ default authorization:
    return 0 unless $actual;
    return 1 if $md5 && lc($md5) eq Digest::MD5::md5_hex($actual);
    return 1 if $clear eq $actual;
    return $bad_login->();
}

# Implement Digest authentication per RFC2617
# called with Apache's request oject
# modifies outgoing header fields appropriately and returns
# 1/0 according to whether auth succeeded. If succeeded, also
# calls LJ::set_remote() to set up internal LJ auth.
# this routine should be called whenever it's clear the client
# wants/the server demands digest auth, and if it returns 1,
# things proceed as usual; if it returns 0, the caller should
# $r->send_http_header(), output an auth error message in HTTP
# data and return to apache.
# Note: Authentication-Info: not sent (optional and nobody supports
# it anyway). Instead, server nonces are reused within their timeout
# limits and nonce counts are used to prevent replay attacks.

sub auth_digest {
    my ($r) = @_;

    my $decline = sub {
        my $stale = shift;

        my $nonce = LJ::challenge_generate(180); # 3 mins timeout
        my $authline = "Digest realm=\"lj\", nonce=\"$nonce\", algorithm=MD5, qop=\"auth\"";
        $authline .= ", stale=\"true\"" if $stale;
        $r->header_out("WWW-Authenticate", $authline);
        $r->status_line("401 Authentication required");
        return 0;
    };

    unless ($r->header_in("Authorization")) {
        return $decline->(0);
    }

    my $header = $r->header_in("Authorization");

    # parse it
    # TODO: could there be "," or " " inside attribute values, requiring
    # trickier parsing?

    my @vals = split(/[, \s]/, $header);
    my $authname = shift @vals;
    my %attrs;
    foreach (@vals) {
        if (/^(\S*?)=(\S*)$/) {
            my ($attr, $value) = ($1,$2);
            if ($value =~ m/^\"([^\"]*)\"$/) {
                $value = $1;
            }
            $attrs{$attr} = $value;
        }
    }

    # sanity checks
    unless ($authname eq 'Digest' && $attrs{'qop'} eq 'auth' &&
            $attrs{'realm'} eq 'lj' && (!defined $attrs{'algorithm'} || $attrs{'algorithm'} eq 'MD5')) {
        return $decline->(0);
    }

    my %opts;
    LJ::challenge_check($attrs{'nonce'}, \%opts);

    return $decline->(0) unless $opts{'valid'};

    # if the nonce expired, force a new one
    return $decline->(1) if $opts{'expired'};

    # check the nonce count
    # be lenient, allowing for error of magnitude 1 (Mozilla has a bug,
    # it repeats nc=00000001 twice...)
    # in case the count is off, force a new nonce; if a client's
    # nonce count implementation is broken and it doesn't send nc= or
    # always sends 1, this'll at least work due to leniency above

    my $ncount = hex($attrs{'nc'});

    unless (abs($opts{'count'} - $ncount) <= 1) {
        return $decline->(1);
    }

    # the username
    my $user = LJ::canonical_username($attrs{'username'});
    my $u = LJ::load_user($user);

    return $decline->(0) unless $u;

    # don't allow empty passwords

    return $decline->(0) unless $u->password;

    # recalculate the hash and compare to response

    my $a1src = $u->user . ':lj:' . $u->password;
    my $a1 = Digest::MD5::md5_hex($a1src);
    my $a2src = $r->method . ":$attrs{'uri'}";
    my $a2 = Digest::MD5::md5_hex($a2src);
    my $hashsrc = "$a1:$attrs{'nonce'}:$attrs{'nc'}:$attrs{'cnonce'}:$attrs{'qop'}:$a2";
    my $hash = Digest::MD5::md5_hex($hashsrc);

    return $decline->(0)
        unless $hash eq $attrs{'response'};

    # set the remote
    LJ::set_remote($u);

    return $u;
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
    %LJ::REQ_CACHE_USER_NAME = ();    # users by name
    %LJ::REQ_CACHE_USER_ID = ();      # users by id
    %LJ::REQ_CACHE_REL = ();          # relations from LJ::check_rel()
    %LJ::REQ_CACHE_DIRTY = ();        # caches calls to LJ::mark_dirty()
    %LJ::REQ_LANGDATFILE = ();        # caches language files
    %LJ::SMS::REQ_CACHE_MAP_UID = (); # cached calls to LJ::SMS::num_to_uid()
    %LJ::SMS::REQ_CACHE_MAP_NUM = (); # cached calls to LJ::SMS::uid_to_num()
    %LJ::S1::REQ_CACHE_STYLEMAP = (); # styleid -> uid mappings
    %LJ::S2::REQ_CACHE_STYLE_ID = (); # styleid -> hashref of s2 layers for style
    %LJ::S2::REQ_CACHE_LAYER_ID = (); # layerid -> hashref of s2 layer info (from LJ::S2::load_layer)
    %LJ::S2::REQ_CACHE_LAYER_INFO = (); # layerid -> hashref of s2 layer info (from LJ::S2::load_layer_info)
    %LJ::QotD::REQ_CACHE_QOTD = ();   # type ('current' or 'old') -> Question of the Day hashrefs
    $LJ::SiteMessages::REQ_CACHE_MESSAGES = undef; # arrayref of cached site message hashrefs
    %LJ::REQ_HEAD_HAS = ();           # avoid code duplication for js
    %LJ::NEEDED_RES = ();             # needed resources (css/js/etc):
    @LJ::NEEDED_RES = ();             # needed resources, in order requested (implicit dependencies)
                                      #  keys are relative from htdocs, values 1 or 2 (1=external, 2=inline)

    %LJ::REQ_GLOBAL = ();             # per-request globals
    %LJ::_ML_USED_STRINGS = ();       # strings looked up in this web request
    %LJ::REQ_CACHE_USERTAGS = ();     # uid -> { ... }; populated by get_usertags, so we don't load it twice
    $LJ::ADV_PER_PAGE = 0;            # Counts ads displayed on a page

    $LJ::CACHE_REMOTE_BOUNCE_URL = undef;
    LJ::Userpic->reset_singletons;
    LJ::Comment->reset_singletons;
    LJ::Entry->reset_singletons;
    LJ::Message->reset_singletons;
    LJ::Vertical->reset_singletons;

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
    unless ($LJ::DISABLED{sitewide_includes}) {
        if ( DW::Request->get ) {
            # standard site-wide JS and CSS
            LJ::need_res(qw(
                            js/core.js
                            js/dom.js
                            js/httpreq.js
                            js/livejournal.js
                            js/common/AdEngine.js
                            stc/lj_base.css
                            ));

            # esn ajax
            LJ::need_res(qw(
                            js/esn.js
                            stc/esn.css
                            ))
                unless LJ::conf_test($LJ::DISABLED{esn_ajax});

            # contextual popup JS
            LJ::need_res(qw(
                            js/ippu.js
                            js/lj_ippu.js
                            js/hourglass.js
                            js/contextualhover.js
                            stc/contextualhover.css
                            ))
                if $LJ::CTX_POPUP;

            # development JS
            LJ::need_res(qw(
                            js/devel.js
                            js/livejournal-devel.js
                            ))
                if $LJ::IS_DEV_SERVER;
        }
    }

    LJ::run_hooks("start_request");

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
    LJ::disconnect_dbs() if $LJ::DISCONNECT_DBS;
    LJ::MemCache::disconnect_all() if $LJ::DISCONNECT_MEMCACHE;
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
# name: LJ::server_down_html
# des: Returns an HTML server down message.
# returns: A string with a server down message in HTML.
# </LJFUNC>
sub server_down_html
{
    return "<b>$LJ::SERVER_DOWN_SUBJECT</b><br />$LJ::SERVER_DOWN_MESSAGE";
}

# <LJFUNC>
# name: LJ::get_cluster_description
# des: Get descriptive text for a cluster id.
# args: clusterid
# des-clusterid: id of cluster to get description of.
# returns: string representing the cluster description
# </LJFUNC>
sub get_cluster_description {
    my ($cid) = shift;
    $cid += 0;
    my $text = LJ::run_hook('cluster_description', $cid);
    return $text if $text;

    # default behavior just returns clusterid
    return $cid;
}

# <LJFUNC>
# name: LJ::do_to_cluster
# des: Given a subref, this function will pick a random cluster and run the subref,
#      passing it the cluster id.  If the subref returns a 1, this function will exit
#      with a 1.  Else, the function will call the subref again, with the next cluster.
# args: subref
# des-subref: Reference to a sub to call; @_ = (clusterid)
# returns: 1 if the subref returned a 1 at some point, undef if it didn't ever return
#          success and we tried every cluster.
# </LJFUNC>
sub do_to_cluster {
    my $subref = shift;

    # start at some random point and iterate through the clusters one by one until
    # $subref returns a true value
    my $size = @LJ::CLUSTERS;
    my $start = int(rand() * $size);
    my $rval = undef;
    my $tries = $size > 15 ? 15 : $size;
    foreach (1..$tries) {
        # select at random
        my $idx = $start++ % $size;

        # get subref value
        $rval = $subref->($LJ::CLUSTERS[$idx]);
        last if $rval;
    }

    # return last rval
    return $rval;
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
# name: LJ::get_keyword_id
# class:
# des: Get the id for a keyword.
# args: uuid?, keyword, autovivify?
# des-uuid: User object or userid to use.  Pass this <strong>only</strong> if
#           you want to use the [dbtable[userkeywords]] clustered table!  If you
#           do not pass user information, the [dbtable[keywords]] table
#           on the global will be used.
# des-keyword: A string keyword to get the id of.
# returns: Returns a kwid into [dbtable[keywords]] or
#          [dbtable[userkeywords]], depending on if you passed a user or not.
#          If the keyword doesn't exist, it is automatically created for you.
# des-autovivify: If present and 1, automatically create keyword.
#                 If present and 0, do not automatically create the keyword.
#                 If not present, default behavior is the old
#                 style -- yes, do automatically create the keyword.
# </LJFUNC>
sub get_keyword_id
{
    &nodb;

    # see if we got a user? if so we use userkeywords on a cluster
    my $u;
    if (@_ >= 2) {
        $u = LJ::want_user(shift);
        return undef unless $u;
    }

    my ($kw, $autovivify) = @_;
    $autovivify = 1 unless defined $autovivify;

    # setup the keyword for use
    unless ($kw =~ /\S/) { return 0; }
    $kw = LJ::text_trim($kw, LJ::BMAX_KEYWORD, LJ::CMAX_KEYWORD);

    # get the keyword and insert it if necessary
    my $kwid;
    if ($u && $u->{dversion} > 5) {
        # new style userkeywords -- but only if the user has the right dversion
        $kwid = $u->selectrow_array('SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                    undef, $u->{userid}, $kw) + 0;
        if ($autovivify && ! $kwid) {
            # create a new keyword
            $kwid = LJ::alloc_user_counter($u, 'K');
            return undef unless $kwid;

            # attempt to insert the keyword
            my $rv = $u->do("INSERT IGNORE INTO userkeywords (userid, kwid, keyword) VALUES (?, ?, ?)",
                            undef, $u->{userid}, $kwid, $kw) + 0;
            return undef if $u->err;

            # at this point, if $rv is 0, the keyword is already there so try again
            unless ($rv) {
                $kwid = $u->selectrow_array('SELECT kwid FROM userkeywords WHERE userid = ? AND keyword = ?',
                                            undef, $u->{userid}, $kw) + 0;
            }

            # nuke cache
            LJ::MemCache::delete([ $u->{userid}, "kws:$u->{userid}" ]);
        }
    } else {
        # old style global
        my $dbh = LJ::get_db_writer();
        my $qkw = $dbh->quote($kw);

        # Making this a $dbr could cause problems due to the insertion of
        # data based on the results of this query. Leave as a $dbh.
        $kwid = $dbh->selectrow_array("SELECT kwid FROM keywords WHERE keyword=$qkw");
        if ($autovivify && ! $kwid) {
            $dbh->do("INSERT INTO keywords (kwid, keyword) VALUES (NULL, $qkw)");
            $kwid = $dbh->{'mysql_insertid'};
        }
    }
    return $kwid;
}

sub get_interest {
    my $intid = shift
        or return undef;

    # FIXME: caching!

    my $dbr = LJ::get_db_reader();
    my ($int, $intcount) = $dbr->selectrow_array
        ("SELECT interest, intcount FROM interests WHERE intid=?",
         undef, $intid);

    return wantarray() ? ($int, $intcount) : $int;
}

sub get_interest_id {
    my $int = shift
        or return undef;

    # FIXME: caching!

    my $dbr = LJ::get_db_reader();
    my ($intid, $intcount) = $dbr->selectrow_array
        ("SELECT intid, intcount FROM interests WHERE interest=?",
         undef, $int);

    return wantarray() ? ($intid, $intcount) : $intid;
}

# <LJFUNC>
# name: LJ::can_use_journal
# class:
# des:
# info:
# args:
# des-:
# returns:
# </LJFUNC>
sub can_use_journal
{
    &nodb;
    my ($posterid, $reqownername, $res) = @_;

    ## find the journal owner's info
    my $uowner = LJ::load_user($reqownername);
    unless ($uowner) {
        $res->{'errmsg'} = "Journal \"$reqownername\" does not exist.";
        return 0;
    }
    my $ownerid = $uowner->{'userid'};

    # the 'ownerid' necessity came first, way back when.  but then
    # with clusters, everything needed to know more, like the
    # journal's dversion and clusterid, so now it also returns the
    # user row.
    $res->{'ownerid'} = $ownerid;
    $res->{'u_owner'} = $uowner;

    ## check if user has access
    return 1 if LJ::check_rel($ownerid, $posterid, 'P');

    # let's check if this community is allowing post access to non-members
    LJ::load_user_props($uowner, "nonmember_posting");
    if ($uowner->{'nonmember_posting'}) {
        my $dbr = LJ::get_db_reader() or die "nodb";
        my $postlevel = $dbr->selectrow_array("SELECT postlevel FROM ".
                                              "community WHERE userid=$ownerid");
        return 1 if $postlevel eq 'members';
    }

    # is the poster an admin for this community?
    return 1 if LJ::can_manage($posterid, $uowner);

    $res->{'errmsg'} = "You do not have access to post to this journal.";
    return 0;
}


# <LJFUNC>
# name: LJ::get_recommended_communities
# class:
# des: Get communities associated with a user.
# info:
# args: user, types
# des-types: The default value for type is 'normal', which indicates a community
#           is visible and has not been closed. A value of 'new' means the community has
#           been created in the last 10 days. Last, a value of 'mm' indicates the user
#           passed in is a maintainer or moderator of the community.
# returns: array of communities
# </LJFUNC>
sub get_recommended_communities {
    my $u = shift;
    # Indicates relationship to user, or activity of community
    my $type = shift() || {};
    my %comms;

    # Load their friendofs to determine community membership
    my @ids = LJ::get_friendofs($u);
    my %fro = %{ LJ::load_userids(@ids) || {} };

    foreach my $ulocal (values %fro) {
        next unless $ulocal->{'statusvis'} eq 'V';
        next unless $ulocal->is_community;

        # TODO: This is bad if they belong to a lot of communities,
        # is a db query to global each call
        my $ci = LJ::get_community_row($ulocal);
        next if $ci->{'membership'} eq 'closed';

        # Add to %comms
        $type->{$ulocal->{userid}} = 'normal';
        $comms{$ulocal->{userid}} = $ulocal;
    }

    # Contains timeupdate and timecreate in an array ref
    my %times;
    # Get usage information about comms
    if (%comms) {
        my $ids = join(',', keys %comms);

        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT UNIX_TIMESTAMP(timeupdate), UNIX_TIMESTAMP(timecreate), userid ".
                                 "FROM userusage WHERE userid IN ($ids)");
        $sth->execute;

        while (my @row = $sth->fetchrow_array) {
            @{$times{$row[2]}} = @row[0,1];
        }
    }

    # Prune the list by time last updated and make sure to
    # display comms created in the past 10 days or where
    # the inviter is a maint or mod
    my $over30 = 0;
    my $now = time();
    foreach my $commid (sort {$times{$b}->[0] <=> $times{$a}->[0]} keys %comms) {
        my $comm = $comms{$commid};
        if ($now - $times{$commid}->[1] <= 86400*10) {
            $type->{$commid} = 'new';
            next;
        }

        my $maintainers = LJ::load_rel_user_cache($commid, 'A') || [];
        my $moderators  = LJ::load_rel_user_cache($commid, 'M') || [];
        foreach (@$maintainers, @$moderators) {
            if ($_ == $u->{userid}) {
                $type->{$commid} = 'mm';
                next;
            }
        }

        # Once a community over 30 days old is reached
        # all subsequent communities will be older and can be deleted
        if ($over30) {
            delete $comms{$commid};
            next;
        } else {
            if ($now - $times{$commid}->[0] > 86400*30) {
                delete $comms{$commid};
                $over30 = 1;
            }
        }
    }

    # If we still have more than 20 comms, delete any with less than
    # five members
    if (%comms > 20) {
        foreach my $comm (values %comms) {
            next unless $type->{$comm->{userid}} eq 'normal';

            my $ids = LJ::get_friends($comm);
            if (%$ids < 5) {
                delete $comms{$comm->{userid}};
            }
        }
    }

    return values %comms;
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
    my $db = isdb($_[0]) ? shift @_ : undef;
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
        my $host = $r->header_in("Host");
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
# name: LJ::delete_comments
# des: deletes comments, but not the relational information, so threading doesn't break
# info: The tables [dbtable[talkprop2]] and [dbtable[talktext2]] are deleted from.  [dbtable[talk2]]
#       just has its state column modified, to 'D'.
# args: u, nodetype, nodeid, talkids+
# des-nodetype: The thread nodetype (probably 'L' for log items)
# des-nodeid: The thread nodeid for the given nodetype (probably the jitemid
#              from the [dbtable[log2]] row).
# des-talkids: List of talkids to delete.
# returns: scalar integer; number of items deleted.
# </LJFUNC>
sub delete_comments {
    my ($u, $nodetype, $nodeid, @talkids) = @_;

    return 0 unless $u->writer;

    my $jid = $u->{'userid'}+0;
    my $in = join(',', map { $_+0 } @talkids);

    # invalidate talk2row memcache
    LJ::Talk::invalidate_talk2row_memcache($u->id, @talkids);

    return 1 unless $in;
    my $where = "WHERE journalid=$jid AND jtalkid IN ($in)";

    my $num = $u->talk2_do($nodetype, $nodeid, undef,
                           "UPDATE talk2 SET state='D' $where");
    return 0 unless $num;
    $num = 0 if $num == -1;

    if ($num > 0) {
        $u->do("UPDATE talktext2 SET subject=NULL, body=NULL $where");
        $u->do("DELETE FROM talkprop2 WHERE $where");
    }

    my @jobs;
    foreach my $talkid (@talkids) {
        my $cmt = LJ::Comment->new($u, jtalkid => $talkid);
        push @jobs, LJ::EventLogRecord::DeleteComment->new($cmt)->fire_job;
    }

    my $sclient = LJ::theschwartz();
    $sclient->insert_jobs(@jobs) if @jobs;

    return $num;
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


# <LJFUNC>
# name: LJ::event_register
# des: Logs a subscribable event, if anybody is subscribed to it.
# args: dbarg?, dbc, etype, ejid, eiarg, duserid, diarg
# des-dbc: Cluster master of event
# des-etype: One character event type.
# des-ejid: Journalid event occurred in.
# des-eiarg: 4 byte numeric argument
# des-duserid: Event doer's userid
# des-diarg: Event's 4 byte numeric argument
# returns: boolean; 1 on success; 0 on fail.
# </LJFUNC>
sub event_register
{
    &nodb;
    my ($dbc, $etype, $ejid, $eiarg, $duserid, $diarg) = @_;
    my $dbr = LJ::get_db_reader();

    # see if any subscribers first of all (reads cheap; writes slow)
    return 0 unless $dbr;
    my $qetype = $dbr->quote($etype);
    my $qejid = $ejid+0;
    my $qeiarg = $eiarg+0;
    my $qduserid = $duserid+0;
    my $qdiarg = $diarg+0;

    my $has_sub = $dbr->selectrow_array("SELECT userid FROM subs WHERE etype=$qetype AND ".
                                        "ejournalid=$qejid AND eiarg=$qeiarg LIMIT 1");
    return 1 unless $has_sub;

    # so we're going to need to log this event
    return 0 unless $dbc;
    $dbc->do("INSERT INTO events (evtime, etype, ejournalid, eiarg, duserid, diarg) ".
             "VALUES (NOW(), $qetype, $qejid, $qeiarg, $qduserid, $qdiarg)");
    return $dbc->err ? 0 : 1;
}

# <LJFUNC>
# name: LJ::procnotify_add
# des: Sends a message to all other processes on all clusters.
# info: You'll probably never use this yourself.
# args: cmd, args?
# des-cmd: Command name.  Currently recognized: "DBI::Role::reload" and "rename_user"
# des-args: Hashref with key/value arguments for the given command.
#           See relevant parts of [func[LJ::procnotify_callback]], for
#           required args for different commands.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub procnotify_add
{
    &nodb;
    my ($cmd, $argref) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    my $args = join('&', map { LJ::eurl($_) . "=" . LJ::eurl($argref->{$_}) }
                    sort keys %$argref);
    $dbh->do("INSERT INTO procnotify (cmd, args) VALUES (?,?)",
             undef, $cmd, $args);

    return 0 if $dbh->err;
    return $dbh->{'mysql_insertid'};
}

# <LJFUNC>
# name: LJ::procnotify_callback
# des: Call back function process notifications.
# info: You'll probably never use this yourself.
# args: cmd, argstring
# des-cmd: Command name.
# des-argstring: String of arguments.
# returns: new serial number on success; 0 on fail.
# </LJFUNC>
sub procnotify_callback
{
    my ($cmd, $argstring) = @_;
    my $arg = {};
    LJ::decode_url_string($argstring, $arg);

    if ($cmd eq "rename_user") {
        # this looks backwards, but the cache hash names are just odd:
        delete $LJ::CACHE_USERNAME{$arg->{'userid'}};
        delete $LJ::CACHE_USERID{$arg->{'user'}};
        return;
    }

    # ip bans
    if ($cmd eq "ban_ip") {
        $LJ::IP_BANNED{$arg->{'ip'}} = $arg->{'exptime'};
        return;
    }

    if ($cmd eq "unban_ip") {
        delete $LJ::IP_BANNED{$arg->{'ip'}};
        return;
    }

    # uniq key bans
    if ($cmd eq "ban_uniq") {
        $LJ::UNIQ_BANNED{$arg->{'uniq'}} = $arg->{'exptime'};
        return;
    }

    if ($cmd eq "unban_uniq") {
        delete $LJ::UNIQ_BANNED{$arg->{'uniq'}};
        return;
    }

    # contentflag key bans
    if ($cmd eq "ban_contentflag") {
        $LJ::CONTENTFLAG_BANNED{$arg->{'username'}} = $arg->{'exptime'};
        return;
    }

    if ($cmd eq "unban_contentflag") {
        delete $LJ::CONTENTFLAG_BANNED{$arg->{'username'}};
        return;
    }

    # cluster switchovers
    if ($cmd eq 'cluster_switch') {
        $LJ::CLUSTER_PAIR_ACTIVE{ $arg->{'cluster'} } = $arg->{ 'role' };
        return;
    }

    if ($cmd eq LJ::AdTargetedInterests->procnotify_key) {
        LJ::AdTargetedInterests->reload;
        return;
    }
}

sub procnotify_check
{
    my $now = time;
    return if $LJ::CACHE_PROCNOTIFY_CHECK + 30 > $now;
    $LJ::CACHE_PROCNOTIFY_CHECK = $now;

    my $dbr = LJ::get_db_reader();
    my $max = $dbr->selectrow_array("SELECT MAX(nid) FROM procnotify");
    return unless defined $max;
    my $old = $LJ::CACHE_PROCNOTIFY_MAX;
    if (defined $old && $max > $old) {
        my $sth = $dbr->prepare("SELECT cmd, args FROM procnotify ".
                                "WHERE nid > ? AND nid <= $max ORDER BY nid");
        $sth->execute($old);
        while (my ($cmd, $args) = $sth->fetchrow_array) {
            LJ::procnotify_callback($cmd, $args);
        }
    }
    $LJ::CACHE_PROCNOTIFY_MAX = $max;
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
            $st = pack('C*', unpack('C*', $st));
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
    my $secret = LJ::MemCache::get($memkey);
    return $want_new ? ($time, $secret) : $secret if $secret;

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;
    $secret = $dbh->selectrow_array("SELECT secret FROM secrets ".
                                    "WHERE stime=?", undef, $time);
    if ($secret) {
        LJ::MemCache::set($memkey, $secret) if $secret;
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


# Single-letter domain values are for livejournal-generic code.
#  - 0-9 are reserved for site-local hooks and are mapped from a long
#    (> 1 char) string passed as the $dom to a single digit by the
#    'map_global_counter_domain' hook.
#
# LJ-generic domains:
#  $dom: 'S' == style, 'P' == userpic, 'A' == stock support answer
#        'C' == captcha, 'E' == external user, 'O' == school
#        'L' == poLL,  'M' == Messaging
#
sub alloc_global_counter
{
    my ($dom, $recurse) = @_;
    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    # $dom can come as a direct argument or as a string to be mapped via hook
    my $dom_unmod = $dom;
    # Yes, that's a duplicate L in the regex for xtra LOLS
    unless ($dom =~ /^[MLOLSPACE]$/) {
        $dom = LJ::run_hook('map_global_counter_domain', $dom);
    }
    return LJ::errobj("InvalidParameters", params => { dom => $dom_unmod })->cond_throw
        unless defined $dom;

    my $newmax;
    my $uid = 0; # userid is not needed, we just use '0'

    my $rs = $dbh->do("UPDATE counter SET max=LAST_INSERT_ID(max+1) WHERE journalid=? AND area=?",
                      undef, $uid, $dom);
    if ($rs > 0) {
        $newmax = $dbh->selectrow_array("SELECT LAST_INSERT_ID()");
        return $newmax;
    }

    return undef if $recurse;

    # no prior counter rows - initialize one.
    if ($dom eq "S") {
        $newmax = $dbh->selectrow_array("SELECT MAX(styleid) FROM s1stylemap");
    } elsif ($dom eq "P") {
        $newmax = $dbh->selectrow_array("SELECT MAX(picid) FROM userpic");
    } elsif ($dom eq "C") {
        $newmax = $dbh->selectrow_array("SELECT MAX(capid) FROM captchas");
    } elsif ($dom eq "E" || $dom eq "M") {
        # if there is no extuser or message counter row
        # start at 'ext_1'  - ( the 0 here is incremented after the recurse )
        $newmax = 0;
    } elsif ($dom eq "A") {
        $newmax = $dbh->selectrow_array("SELECT MAX(ansid) FROM support_answers");
    } elsif ($dom eq "O") {
        $newmax = $dbh->selectrow_array("SELECT MAX(schoolid) FROM schools");
    } elsif ($dom eq "L") {
        # pick maximum id from poll and pollowner
        my $max_poll      = $dbh->selectrow_array("SELECT MAX(pollid) FROM poll");
        my $max_pollowner = $dbh->selectrow_array("SELECT MAX(pollid) FROM pollowner");
        $newmax = $max_poll > $max_pollowner ? $max_poll : $max_pollowner;
    } else {
        $newmax = LJ::run_hook('global_counter_init_value', $dom);
        die "No alloc_global_counter initalizer for domain '$dom'"
            unless defined $newmax;
    }
    $newmax += 0;
    $dbh->do("INSERT IGNORE INTO counter (journalid, area, max) VALUES (?,?,?)",
             undef, $uid, $dom, $newmax) or return LJ::errobj($dbh)->cond_throw;
    return LJ::alloc_global_counter($dom, 1);
}

sub system_userid {
    return $LJ::CACHE_SYSTEM_ID if $LJ::CACHE_SYSTEM_ID;
    my $u = LJ::load_user("system")
        or die "No 'system' user available for LJ::system_userid()";
    return $LJ::CACHE_SYSTEM_ID = $u->{userid};
}

sub blobcache_replace {
    my ($key, $value) = @_;

    die "invalid key: $key" unless length $key;

    my $dbh = LJ::get_db_writer()
        or die "Unable to contact global master";

    return $dbh->do("REPLACE INTO blobcache SET bckey=?, dateupdate=NOW(), value=?",
                    undef, $key, $value);
}

sub blobcache_get {
    my $key = shift;

    die "invalid key: $key" unless length $key;

    my $dbr = LJ::get_db_reader()
        or die "Unable to contact global reader";
    
    my ($value, $timeupdate) = 
        $dbr->selectrow_array("SELECT value, UNIX_TIMESTAMP(dateupdate) FROM blobcache WHERE bckey=?",
                              undef, $key);

    return wantarray() ? ($value, $timeupdate) : $value;
}

sub note_recent_action {
    my ($cid, $action) = @_;

    # fall back to selecting a random cluster
    $cid = LJ::random_cluster() unless defined $cid;

    # accept a user object
    $cid = ref $cid ? $cid->{clusterid}+0 : $cid+0;

    return undef unless $cid;

    # make sure they gave us an action
    return undef if !$action || length($action) > 20;;

    my $dbcm = LJ::get_cluster_master($cid)
        or return undef;

    # append to recentactions table
    $dbcm->do("INSERT DELAYED INTO recentactions VALUES (?)", undef, $action);
    return undef if $dbcm->err;

    return 1;
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
    if (isdb($err)) {
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

sub no_utf8_flag {
    return pack('C*', unpack('C*', $_[0]));
}

# return true if root caller is a test file
sub is_from_test {
    return $0 && $0 =~ m!(^|/)t/!;
}

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    if ($AUTOLOAD eq "LJ::send_mail") {
        require "ljmail.pl";
        goto &$AUTOLOAD;
    }
    Carp::croak("Undefined subroutine: $AUTOLOAD");
}

sub pagestats_obj {
    return LJ::PageStats->new;
}

sub conf_test {
    my ($conf, @args) = @_;
    return 0 unless $conf;
    return $conf->(@args) if ref $conf eq "CODE";
    return $conf;
}

sub is_enabled {
    my $conf = shift;
    return ! LJ::conf_test($LJ::DISABLED{$conf}, @_);
}

package LJ::S1;

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    if ($AUTOLOAD eq "LJ::S1::get_public_styles") {
        require "ljviews.pl";
        goto &$AUTOLOAD;
    }
    Carp::croak("Undefined subroutine: $AUTOLOAD");
}

package LJ::CleanHTML;

use vars qw($AUTOLOAD);
sub AUTOLOAD {
    my $lib = "cleanhtml.pl";
    if ($INC{$lib}) {
        Carp::croak("Undefined subroutine: $AUTOLOAD");
    }
    require $lib;
    goto &$AUTOLOAD;
}

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
