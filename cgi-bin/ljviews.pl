#!/usr/bin/perl
#
# <LJDEP>
# lib: cgi-bin/ljlib.pl, cgi-bin/ljconfig.pl, cgi-bin/ljlang.pl, cgi-bin/cleanhtml.pl
# </LJDEP>

use strict;

package LJ::S1;

use vars qw(@themecoltypes);

# this used to be in a table, but that was kinda useless
@themecoltypes = (
                  [ 'page_back', 'Page background' ],
                  [ 'page_text', 'Page text' ],
                  [ 'page_link', 'Page link' ],
                  [ 'page_vlink', 'Page visited link' ],
                  [ 'page_alink', 'Page active link' ],
                  [ 'page_text_em', 'Page emphasized text' ],
                  [ 'page_text_title', 'Page title' ],
                  [ 'weak_back', 'Weak accent' ],
                  [ 'weak_text', 'Text on weak accent' ],
                  [ 'strong_back', 'Strong accent' ],
                  [ 'strong_text', 'Text on strong accent' ],
                  [ 'stronger_back', 'Stronger accent' ],
                  [ 'stronger_text', 'Text on stronger accent' ],
                  );

# updated everytime new S1 style cleaning rules are added,
# so cached cleaned versions are invalidated.
$LJ::S1::CLEANER_VERSION = 13;

# PROPERTY Flags:

# /a/:
#    safe in styles as sole attributes, without any cleaning.  for
#    example: <a href="%%urlread%%"> is okay, # if we're in
#    LASTN_TALK_READLINK, because the system generates # %%urlread%%.
#    by default, if we don't declare things trusted here, # we'll
#    double-check all attributes at the end for potential XSS #
#    problems.
#
# /u/:
#    is a URL.  implies /a/.
#
#
# /d/:
#    is a number.  implies /a/.
#
# /t/:
#    tainted!  User controls via other some other variable.
#
# /s/:
#    some system string... probably safe.  but maybe possible to coerce it
#    alongside something else.

my $commonprop = {
    'dateformat' => {
        'yy' => 'd', 'yyyy' => 'd',
        'm' => 'd', 'mm' => 'd',
        'd' => 'd', 'dd' => 'd',
        'min' => 'd',
        '12h' => 'd', '12hh' => 'd',
        '24h' => 'd', '24hh' => 'd',
    },
    'talklinks' => {
        'messagecount' => 'd',
        'urlread' => 'u',
        'urlpost' => 'u',
        'itemid' => 'd',
    },
    'talkreadlink' => {
        'messagecount' => 'd',
        'urlread' => 'u',
    },
    'event' => {
        'itemid' => 'd',
    },
    'pic' => {
        'src' => 'u',
        'width' => 'd',
        'height' => 'd',
    },
    'newday' => {
        yy => 'd', yyyy => 'd', m => 'd', mm => 'd',
        d => 'd', dd => 'd',
    },
    'skip' => {
        'numitems' => 'd',
        'url' => 'u',
    },
};

$LJ::S1::PROPS = {
    'CALENDAR_DAY' => {
        'd' => 'd',
        'eventcount' => 'd',
        'dayevent' => 't',
        'daynoevent' => 't',
    },
    'CALENDAR_DAY_EVENT' => {
        'eventcount' => 'd',
        'dayurl' => 'u',
    },
    'CALENDAR_DAY_NOEVENT' => {
    },
    'CALENDAR_EMPTY_DAYS' => {
        'numempty' => 'd',
    },
    'CALENDAR_MONTH' => {
        'monlong' => 's',
        'monshort' => 's',
        'yy' => 'd',
        'yyyy' => 'd',
        'weeks' => 't',
        'urlmonthview' => 'u',
    },
    'CALENDAR_NEW_YEAR' => {
        'yy' => 'd',
        'yyyy' => 'd',
    },
    'CALENDAR_PAGE' => {
        'name' => 't',
        "name-'s" => 's',
        'yearlinks' => 't',
        'months' => 't',
        'username' => 's',
        'website' => 't',
        'head' => 't',
        'urlfriends' => 'u',
        'urllastn' => 'u',
    },
    'CALENDAR_WEBSITE' => {
        'url' => 't',
        'name' => 't',
    },
    'CALENDAR_WEEK' => {
        'days' => 't',
        'emptydays_beg' => 't',
        'emptydays_end' => 't',
    },
    'CALENDAR_YEAR_DISPLAYED' => {
        'yyyy' => 'd',
        'yy' => 'd',
    },
    'CALENDAR_YEAR_LINK' => {
        'yyyy' => 'd',
        'yy' => 'd',
        'url' => 'u',
    },
    'CALENDAR_YEAR_LINKS' => {
        'years' => 't',
    },
    'CALENDAR_SKYSCRAPER_AD' => {
        'ad' => 't',
    },
    'CALENDAR_5LINKUNIT_AD' => {
        'ad' => 't',
    },

    # day
    'DAY_DATE_FORMAT' => $commonprop->{'dateformat'},
    'DAY_EVENT' => $commonprop->{'event'},
    'DAY_EVENT_PRIVATE' => $commonprop->{'event'},
    'DAY_EVENT_PROTECTED' => $commonprop->{'event'},
    'DAY_PAGE' => {
        'prevday_url' => 'u',
        'nextday_url' => 'u',
        'yy' => 'd', 'yyyy' => 'd',
        'm' => 'd', 'mm' => 'd',
        'd' => 'd', 'dd' => 'd',
        'urllastn' => 'u',
        'urlcalendar' => 'u',
        'urlfriends' => 'u',
    },
    'DAY_TALK_LINKS' => $commonprop->{'talklinks'},
    'DAY_TALK_READLINK' => $commonprop->{'talkreadlink'},
    'DAY_SKYSCRAPER_AD' => {
        'ad' => 't',
    },
    'DAY_5LINKUNIT_AD' => {
        'ad' => 't',
    },

    # friends
    'FRIENDS_DATE_FORMAT' => $commonprop->{'dateformat'},
    'FRIENDS_EVENT' => $commonprop->{'event'},
    'FRIENDS_EVENT_PRIVATE' => $commonprop->{'event'},
    'FRIENDS_EVENT_PROTECTED' => $commonprop->{'event'},
    'FRIENDS_FRIENDPIC' => $commonprop->{'pic'},
    'FRIENDS_NEW_DAY' => $commonprop->{'newday'},
    'FRIENDS_RANGE_HISTORY' => {
        'numitems' => 'd',
        'skip' => 'd',
    },
    'FRIENDS_RANGE_MOSTRECENT' => {
        'numitems' => 'd',
    },
    'FRIENDS_SKIP_BACKWARD' => $commonprop->{'skip'},
    'FRIENDS_SKIP_FORWARD' => $commonprop->{'skip'},
    'FRIENDS_TALK_LINKS' => $commonprop->{'talklinks'},
    'FRIENDS_TALK_READLINK' => $commonprop->{'talkreadlink'},
    'FRIENDS_SKYSCRAPER_AD' => {
        'ad' => 't',
    },
    'FRIENDS_5LINKUNIT_AD' => {
        'ad' => 't',
    },

    # lastn
    'LASTN_ALTPOSTER' => {
        'poster' => 's',
        'owner' => 's',
        'pic' => 't',
    },
    'LASTN_ALTPOSTER_PIC' => $commonprop->{'pic'},
    'LASTN_CURRENT' => {
        'what' => 's',
        'value' => 't',
    },
    'LASTN_CURRENTS' => {
        'currents' => 't',
    },
    'LASTN_DATEFORMAT' => $commonprop->{'dateformat'},
    'LASTN_EVENT' => $commonprop->{'event'},
    'LASTN_EVENT_PRIVATE' => $commonprop->{'event'},
    'LASTN_EVENT_PROTECTED' => $commonprop->{'event'},
    'LASTN_NEW_DAY' => $commonprop->{'newday'},
    'LASTN_PAGE' => {
        'urlfriends' => 'u',
        'urlcalendar' => 'u',
        'skyscraper_ad' => 't',
    },
    'LASTN_RANGE_HISTORY' => {
        'numitems' => 'd',
        'skip' => 'd',
    },
    'LASTN_RANGE_MOSTRECENT' => {
        'numitems' => 'd',
    },
    'LASTN_SKIP_BACKWARD' => $commonprop->{'skip'},
    'LASTN_SKIP_FORWARD' => $commonprop->{'skip'},
    'LASTN_TALK_LINKS' => $commonprop->{'talklinks'},
    'LASTN_TALK_READLINK' => $commonprop->{'talkreadlink'},
    'LASTN_USERPIC' => {
        'src' => 'u',
        'width' => 'd',
        'height' => 'd',
    },
    'LASTN_SKYSCRAPER_AD' => {
        'ad' => 't',
    },
    'LASTN_5LINKUNIT_AD' => {
        'ad' => 't',
    },
};

sub get_public_styles {

    my $opts = shift;

    # Try process cache/memcache if no extra options are requested
    my $memkey = "s1pubstyc";
    my $pubstyc = {};

    unless ($opts) {
        # check process cache
        $pubstyc = $LJ::CACHED_S1_PUBLIC_LAYERS;
        return $pubstyc if $pubstyc;

        # check memcache, set in process cache if we got it
        $pubstyc = LJ::MemCache::get($memkey);
        $LJ::CACHED_S1_PUBLIC_LAYERS = $pubstyc;
        return $pubstyc if $pubstyc;
    }

    # not cached, build from db
    my $sysid = LJ::get_userid("system");

    # all cols *except* formatdata, which is big and unnecessary for most uses.
    # it'll be loaded by LJ::S1::get_style
    my $cols = "styleid, styledes, type, is_public, is_embedded, ".
        "is_colorfree, opt_cache, has_ads, lastupdate";
    $cols .= ", formatdata" if $opts && $opts->{'formatdata'};

    # first try new table
    my $dbh = LJ::get_db_writer();
    my $sth = $dbh->prepare("SELECT userid, $cols FROM s1style WHERE userid=? AND is_public='Y'");
    $sth->execute($sysid);
    while (my $row = $sth->fetchrow_hashref) {
        $pubstyc->{$row->{'styleid'}} = $row;
    }

    # fall back to old table
    unless (%$pubstyc) {
        $sth = $dbh->prepare("SELECT user, $cols FROM style WHERE user='system' AND is_public='Y'");
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref) {
            $pubstyc->{$row->{'styleid'}} = $row;
        }
    }
    return undef unless %$pubstyc;

    # set in process cache/memcache
    unless ($opts) {
        $LJ::CACHED_S1_PUBLIC_LAYERS = $pubstyc;

        my $expire = time() + 60*30; # 30 minutes
        LJ::MemCache::set($memkey, $pubstyc, $expire);
    }

    return $pubstyc;
}

# <LJFUNC>
# name: LJ::S1::get_themeid
# des: Loads or returns cached version of given color theme data.
# returns: Hashref with color names as keys
# args: dbarg?, themeid
# des-themeid: S1 themeid.
# </LJFUNC>
sub get_themeid
{
    &LJ::nodb;
    my $themeid = shift;
    return $LJ::S1::CACHE_THEMEID{$themeid} if $LJ::S1::CACHE_THEMEID{$themeid};
    my $dbr = LJ::get_db_reader();
    my $ret = {};
    my $sth = $dbr->prepare("SELECT coltype, color FROM themedata WHERE themeid=?");
    $sth->execute($themeid);
    $ret->{$_->{'coltype'}} = $_->{'color'} while $_ = $sth->fetchrow_hashref;
    return $LJ::S1::CACHE_THEMEID{$themeid} = $ret;
}

# returns: hashref of vars (cleaned)
sub load_style
{
    &LJ::nodb;
    my ($styleid, $viewref) = @_;

    # first try local cache for this process
    my $cch = $LJ::S1::CACHE_STYLE{$styleid};
    if ($cch && $cch->{'cachetime'} > time() - 300) {
        $$viewref = $cch->{'type'} if ref $viewref eq "SCALAR";
        return $cch->{'style'};
    }

    # try memcache
    my $memkey = [$styleid, "s1styc:$styleid"];
    my $styc = LJ::MemCache::get($memkey);

    # database handle we'll use if we have to rebuild the cache
    my $db;

    # function to return a given a styleid
    my $find_db = sub {
        my $sid = shift;

        # should we work with a global or clustered table?
        my $userid = LJ::S1::get_style_userid($sid);

        # if the user's style is clustered, need to get a $u
        my $u = $userid ? LJ::load_userid($userid) : undef;

        # return appropriate db handle
        if ($u && $u->{'dversion'} >= 5) {    # users' styles are clustered
            return LJ::S1::get_s1style_writer($u);
        }

        return @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
    };

    # get database stylecache
    unless ($styc) {

        $db = $find_db->($styleid);
        $styc = $db->selectrow_hashref("SELECT * FROM s1stylecache WHERE styleid=?",
                                       undef, $styleid);
        LJ::MemCache::set($memkey, $styc, time()+60*30) if $styc;
    }

    # no stylecache in db, built a new one
    if (! $styc || $styc->{'vars_cleanver'} < $LJ::S1::CLEANER_VERSION) {
        my $style = LJ::S1::get_style($styleid);
        return {} unless $style;

        $db ||= $find_db->($styleid);

        $styc = {
            'type' => $style->{'type'},
            'opt_cache' => $style->{'opt_cache'},
            'vars_stor' => LJ::CleanHTML::clean_s1_style($style->{'formatdata'}),
            'vars_cleanver' => $LJ::S1::CLEANER_VERSION,
        };

        # do this query on the db handle we used above
        $db->do("REPLACE INTO s1stylecache (styleid, cleandate, type, opt_cache, vars_stor, vars_cleanver) ".
                "VALUES (?,NOW(),?,?,?,?)", undef, $styleid,
                map { $styc->{$_} } qw(type opt_cache vars_stor vars_cleanver));
    }

    my $ret = Storable::thaw($styc->{'vars_stor'});
    $$viewref = $styc->{'type'} if ref $viewref eq "SCALAR";

    if ($styc->{'opt_cache'} eq "Y") {
        $LJ::S1::CACHE_STYLE{$styleid} = {
            'style' => $ret,
            'cachetime' => time(),
            'type' => $styc->{'type'},
        };
    }

    return $ret;
}

# LJ::S1::get_public_styles
#
# LJ::load_user_props calls LJ::S1::get_public_styles and since
# a lot of cron jobs call LJ::load_user_props, we've moved
# LJ::S1::get_public_styles to ljlib so that it can be used
# without including ljviews.pl

sub get_s1style_writer {
    my $u = shift;
    return undef unless LJ::isu($u);

    # special case system, its styles live on
    # the global master's s1style table alone
    if ($u->{'user'} eq 'system') {
        return LJ::get_db_writer();
    }

    return $u->writer;
}

sub get_s1style_reader {
    my $u = shift;
    return undef unless LJ::isu($u);

    # special case system, its styles live on
    # the global master's s1style table alone
    if ($u->{'user'} eq 'system') {
        return @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
    }

    return @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
}

# takes either $u object or userid
sub get_user_styles {
    my $u = shift;
    $u = LJ::isu($u) ? $u : LJ::load_user($u);
    return undef unless $u;

    my %styles;

    # all cols *except* formatdata, which is big and unnecessary for most uses.
    # it'll be loaded by LJ::S1::get_style
    my $cols = "styleid, styledes, type, is_public, is_embedded, ".
        "is_colorfree, opt_cache, has_ads, lastupdate";

    # new clustered table
    my ($db, $sth);
    if ($u->{'dversion'} >= 5) {
        $db = LJ::S1::get_s1style_reader($u);
        $sth = $db->prepare("SELECT userid, $cols FROM s1style WHERE userid=?");
        $sth->execute($u->{'userid'});

    # old global table
    } else {
        $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        $sth = $db->prepare("SELECT user, $cols FROM style WHERE user=?");
        $sth->execute($u->{'user'});
    }

    # build data structure
    while (my $row = $sth->fetchrow_hashref) {

        # fix up both userid and user values for consistency
        $row->{'userid'} = $u->{'userid'};
        $row->{'user'} = $u->{'user'};

        $styles{$row->{'styleid'}} = $row;
        next unless @LJ::MEMCACHE_SERVERS;

        # now update memcache while we have this data?
        LJ::MemCache::set([$row->{'styleid'}, "s1style:$row->{'styleid'}"], $row);
    }

    return \%styles;
}

# includes formatdata row.
sub get_style {
    my $styleid = shift;
    return unless $styleid;

    my $memkey = [$styleid, "s1style_all:$styleid"];
    my $style = LJ::MemCache::get($memkey);
    return $style if $style;

    # query global mapping table, returns undef if style isn't clustered
    my $userid = LJ::S1::get_style_userid($styleid);

    my $u;
    $u = LJ::load_userid($userid) if $userid;

    # new clustered table
    if ($u && $u->{'dversion'} >= 5) {
        my $db = LJ::S1::get_s1style_reader($u);
        $style = $db->selectrow_hashref("SELECT * FROM s1style WHERE styleid=?", undef, $styleid);

        # fill in user since the caller may expect it
        $style->{'user'} = $u->{'user'};

    # old global table
    } else {
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        $style = $db->selectrow_hashref("SELECT * FROM style WHERE styleid=?", undef, $styleid);

        # fill in userid since the caller may expect it
        $style->{'userid'} = LJ::get_userid($style->{'user'});
    }
    return unless $style;

    LJ::MemCache::set($memkey, $style);

    return $style;
}

sub check_dup_style {
    my ($u, $type, $styledes) = @_;
    return unless $type && $styledes;

    $u = LJ::isu($u) ? $u : LJ::load_user($u);

    # new clustered table
    if ($u && $u->{'dversion'} >= 5) {
        # get writer since this function is to check duplicates.  as such,
        # the write action we're checking for probably happened recently
        my $db = LJ::S1::get_s1style_writer($u);
        return $db->selectrow_hashref("SELECT * FROM s1style WHERE userid=? AND type=? AND styledes=?",
                                        undef, $u->{'userid'}, $type, $styledes);

    # old global table
    } else {
        my $dbh = LJ::get_db_writer();
        return $dbh->selectrow_hashref("SELECT * FROM style WHERE user=? AND type=? AND styledes=?",
                                       undef, $u->{'user'}, $type, $styledes);
    }
}

# returns userid of styleid, regardless of it being clusterd or not
sub get_style_userid_always {
    my $styleid = shift;

    my $uid = get_style_userid($styleid);
    return $uid if $uid;

    my $style = get_style($styleid)
        or return 0;

    return $style->{userid} or
        die "S1 style \#$styleid has no userid field?";
}

# returns undef if style isn't clustered
sub get_style_userid {
    my $styleid = shift;

    # check cache
    my $userid = $LJ::S1::REQ_CACHE_STYLEMAP{$styleid};
    return $userid if $userid;

    my $memkey = [$styleid, "s1stylemap:$styleid"];
    my $style = LJ::MemCache::get($memkey);
    return $style if $style;

    # fetch from db
    my $dbr = LJ::get_db_reader();
    $userid = $dbr->selectrow_array("SELECT userid FROM s1stylemap WHERE styleid=?",
                                    undef, $styleid);
    return unless $userid;

    # set cache
    $LJ::S1::REQ_CACHE_STYLEMAP{$styleid} = $userid;
    LJ::MemCache::set($memkey, $userid);

    return $userid;
}

sub create_style {
    my ($u, $opts) = @_;
    return unless LJ::isu($u) && ref $opts eq 'HASH';

    my $dbh = LJ::get_db_writer();
    return undef unless $dbh;

    my $styleid = LJ::alloc_global_counter('S');
    return undef unless $styleid;

    my (@cols, @bind, @vals);
    foreach (qw(styledes type formatdata is_public is_embedded is_colorfree opt_cache has_ads)) {
        next unless $opts->{$_};

        push @cols, $_;
        push @bind, "?";
        push @vals, $opts->{$_};
    }
    my $cols = join(",", @cols);
    my $bind = join(",", @bind);
    return unless @cols;

    if ($u->{'dversion'} >= 5) {
        my $db = LJ::S1::get_s1style_writer($u);
        $db->do("INSERT INTO s1style (styleid,userid,$cols) VALUES (?,?,$bind)",
                undef, $styleid, $u->{'userid'}, @vals);
        my $insertid = LJ::User::mysql_insertid($db);
        die "Couldn't allocate insertid for s1style for userid $u->{userid}" unless $insertid;

        $dbh->do("INSERT INTO s1stylemap (styleid, userid) VALUES (?,?)", undef, $insertid, $u->{'userid'});
        return $insertid;

    } else {
        $dbh->do("INSERT INTO style (styleid, user,$cols) VALUES (?,?,$bind)",
                 undef, $styleid, $u->{'user'}, @vals);
        return $dbh->{'mysql_insertid'};
    }
}

sub update_style {
    my ($styleid, $opts) = @_;
    return unless $styleid && ref $opts eq 'HASH';

    # query global mapping table, returns undef if style isn't clustered
    my $userid = LJ::S1::get_style_userid($styleid);

    my $u;
    $u = LJ::load_userid($userid) if $userid;

    my @cols = qw(styledes type formatdata is_public is_embedded
                  is_colorfree opt_cache has_ads lastupdate);

    # what table to operate on ?
    my ($db, $table);

    # clustered table
    if ($u && $u->{'dversion'} >= 5) {
        $db = LJ::S1::get_s1style_writer($u);
        $table = "s1style";

    # global table
    } else {
        $db = LJ::get_db_writer();
        $table = "style";
    }

    my (@sets, @vals);
    foreach (@cols) {
        if ($opts->{$_}) {
            push @sets, "$_=?";
            push @vals, $opts->{$_};
        }
    }

    # update style
    my $now_lastupdate = $opts->{'lastupdate'} ? ", lastupdate=NOW()" : '';
    my $rows = $db->do("UPDATE $table SET " . join(", ", @sets) . "$now_lastupdate WHERE styleid=?",
                       undef, @vals, $styleid);

    # clear out stylecache
    $db->do("UPDATE s1stylecache SET vars_stor=NULL, vars_cleanver=0 WHERE styleid=?",
            undef, $styleid);

    # update memcache keys
    LJ::MemCache::delete([$styleid, "s1style:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1style_all:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1styc:$styleid"]);

    return $rows;
}

sub delete_style {
    my $styleid = shift;
    return unless $styleid;

    # query global mapping table, returns undef if style isn't clustered
    my $userid = LJ::S1::get_style_userid($styleid);

    my $u;
    $u = LJ::load_userid($userid) if $userid;

    my $dbh = LJ::get_db_writer();

    # new clustered table
    if ($u && $u->{'dversion'} >= 5) {
        $dbh->do("DELETE FROM s1stylemap WHERE styleid=?", undef, $styleid);

        my $db = LJ::S1::get_s1style_writer($u);
        $db->do("DELETE FROM s1style WHERE styleid=?", undef, $styleid);
        $db->do("DELETE FROM s1stylecache WHERE styleid=?", undef, $styleid);

    # old global table
    } else {
        # they won't have an s1stylemap entry

        $dbh->do("DELETE FROM style WHERE styleid=?", undef, $styleid);
        $dbh->do("DELETE FROM s1stylecache WHERE styleid=?", undef, $styleid);
    }

    # clear out some memcache space
    LJ::MemCache::delete([$styleid, "s1style:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1style_all:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1stylemap:$styleid"]);
    LJ::MemCache::delete([$styleid, "s1styc:$styleid"]);

    return;
}

sub get_overrides {
    my $u = shift;
    return unless LJ::isu($u);

    # try memcache
    my $memkey = [$u->{'userid'}, "s1overr:$u->{'userid'}"];
    my $overr = LJ::MemCache::get($memkey);
    return $overr if $overr;

    # new clustered table
    if ($u->{'dversion'} >= 5) {
        my $db = @LJ::MEMCACHE_SERVERS ? LJ::get_cluster_def_reader($u) : LJ::get_cluster_reader($u);
        $overr = $db->selectrow_array("SELECT override FROM s1overrides WHERE userid=?", undef, $u->{'userid'});

    # old global table
    } else {
        my $dbh = @LJ::MEMCACHE_SERVERS ? LJ::get_db_writer() : LJ::get_db_reader();
        $overr = $dbh->selectrow_array("SELECT override FROM overrides WHERE user=?", undef, $u->{'user'});
    }

    # set in memcache
    LJ::MemCache::set($memkey, $overr);

    return $overr;
}

sub clear_overrides {
    my $u = shift;
    return unless LJ::isu($u);

    my $overr;
    my $db;

    # new clustered table
    if ($u->{'dversion'} >= 5) {
        $overr = $u->do("DELETE FROM s1overrides WHERE userid=?", undef, $u->{'userid'});
        $db = $u;

    # old global table
    } else {
        my $dbh = LJ::get_db_writer();
        $overr = $dbh->do("DELETE FROM overrides WHERE user=?", undef, $u->{'user'});
        $db = $dbh;
    }

    # update s1usercache
    $db->do("UPDATE s1usercache SET override_stor=NULL WHERE userid=?",
            undef, $u->{'userid'});

    LJ::MemCache::delete([$u->{'userid'}, "s1uc:$u->{'userid'}"]);
    LJ::MemCache::delete([$u->{'userid'}, "s1overr:$u->{'userid'}"]);

    return $overr;
}

sub save_overrides {
    my ($u, $overr) = @_;
    return unless LJ::isu($u) && $overr;

    # new clustered table
    my $insertid;
    if ($u->{'dversion'} >= 5) {
        $u->do("REPLACE INTO s1overrides (userid, override) VALUES (?, ?)",
               undef, $u->{'userid'}, $overr);
        $insertid = $u->mysql_insertid;

    # old global table
    } else {
        my $dbh = LJ::get_db_writer();
        $dbh->do("REPLACE INTO overrides (user, override) VALUES (?, ?)",
                 undef, $u->{'user'}, $overr);
        $insertid = $dbh->{'mysql_insertid'};
    }

    # update s1usercache
    my $override_stor = LJ::CleanHTML::clean_s1_style($overr);
    $u->do("UPDATE s1usercache SET override_stor=?, override_cleanver=? WHERE userid=?",
           undef, $override_stor, $LJ::S1::CLEANER_VERSION, $u->{'userid'});

    LJ::MemCache::delete([$u->{'userid'}, "s1uc:$u->{'userid'}"]);
    LJ::MemCache::delete([$u->{'userid'}, "s1overr:$u->{'userid'}"]);

    return $insertid;
}

package LJ;

# <LJFUNC>
# name: LJ::alldateparts_to_hash
# class: s1
# des: Given a date/time format from MySQL, breaks it into a hash.
# info: This is used by S1.
# args: alldatepart
# des-alldatepart: The output of the MySQL function
#                  DATE_FORMAT(sometime, "%a %W %b %M %y %Y %c %m %e %d
#                  %D %p %i %l %h %k %H")
# returns: Hash (whole, not reference), with keys: dayshort, daylong,
#          monshort, monlong, yy, yyyy, m, mm, d, dd, dth, ap, AP,
#          ampm, AMPM, min, 12h, 12hh, 24h, 24hh

# </LJFUNC>
sub alldateparts_to_hash
{
    my $alldatepart = shift;
    my @dateparts = split(/ /, $alldatepart);
    return (
            'dayshort' => $dateparts[0],
            'daylong' => $dateparts[1],
            'monshort' => $dateparts[2],
            'monlong' => $dateparts[3],
            'yy' => $dateparts[4],
            'yyyy' => $dateparts[5],
            'm' => $dateparts[6],
            'mm' => $dateparts[7],
            'd' => $dateparts[8],
            'dd' => $dateparts[9],
            'dth' => $dateparts[10],
            'ap' => substr(lc($dateparts[11]),0,1),
            'AP' => substr(uc($dateparts[11]),0,1),
            'ampm' => lc($dateparts[11]),
            'AMPM' => $dateparts[11],
            'min' => $dateparts[12],
            '12h' => $dateparts[13],
            '12hh' => $dateparts[14],
            '24h' => $dateparts[15],
            '24hh' => $dateparts[16],
            );
}

# <LJFUNC>
# class: s1
# name: LJ::fill_var_props
# args: vars, key, hashref
# des: S1 utility function to interpolate %%variables%% in a variable.  If
#      a modifier is given like %%foo:var%%, then [func[LJ::fvp_transform]]
#      is called.
# des-vars: hashref with keys being S1 vars
# des-key: the variable in the vars hashref we're expanding
# des-hashref: hashref of values that could interpolate.
# returns: Expanded string.
# </LJFUNC>
sub fill_var_props
{
    my ($vars, $key, $hashref) = @_;
    $_ = $vars->{$key};
    s/%%([\w:]+:)?([\w\-\']+)%%/$1 ? LJ::fvp_transform(lc($1), $vars, $hashref, $2) : $hashref->{$2}/eg;
    return $_;
}

# <LJFUNC>
# class: s1
# name: LJ::fvp_transform
# des: Called from [func[LJ::fill_var_props]] to do transformations.
# args: transform, vars, hashref, attr
# des-transform: The transformation type.
# des-vars: hashref with keys being S1 vars
# des-hashref: hashref of values that could interpolate. (see
#              [func[LJ::fill_var_props]])
# des-attr: the attribute name that's being interpolated.
# returns: Transformed interpolated variable.
# </LJFUNC>
sub fvp_transform
{
    my ($transform, $vars, $hashref, $attr) = @_;
    my $ret = $hashref->{$attr};
    while ($transform =~ s/(\w+):$//) {
        my $trans = $1;
        if ($trans eq "color") {
            return $vars->{"color-$attr"};
        }
        elsif ($trans eq "ue") {
            $ret = LJ::eurl($ret);
        }
        elsif ($trans eq "cons") {
            if ($attr eq "img") { return $LJ::IMGPREFIX; }
            if ($attr eq "siteroot") { return $LJ::SITEROOT; }
            if ($attr eq "sitename") { return $LJ::SITENAME; }
        }
        elsif ($trans eq "attr") {
            $ret =~ s/\"/&quot;/g;
            $ret =~ s/\'/&\#39;/g;
            $ret =~ s/</&lt;/g;
            $ret =~ s/>/&gt;/g;
            $ret =~ s/\]\]//g;  # so they can't end the parent's [attr[..]] wrapper
        }
        elsif ($trans eq "lc") {
            $ret = lc($ret);
        }
        elsif ($trans eq "uc") {
            $ret = uc($ret);
        }
        elsif ($trans eq "xe") {
            $ret = LJ::exml($ret);
        }
        elsif ($trans eq 'ljuser' or $trans eq 'ljcomm') {
            my $user = LJ::canonical_username($ret);
            $ret = LJ::ljuser($user);
        }
        elsif ($trans eq 'userurl') {
            my $u = LJ::load_user($ret);
            $ret = LJ::journal_base($u) if $u;
        }
    }
    return $ret;
}

# <LJFUNC>
# class: s1
# name: LJ::parse_vars
# des: Parses S1 style data into hashref.
# returns: Nothing.  Modifies a hashref.
# args: dataref, hashref
# des-dataref: Reference to scalar with data to parse. Format is
#              a BML-style full block, as used in the S1 style system.
# des-hashref: Hashref to populate with data.
# </LJFUNC>
sub parse_vars
{
    my ($dataref, $hashref) = @_;
    my @data = split(/\n/, $$dataref);
    my $curitem = "";

    foreach (@data)
    {
        $_ .= "\n";
        s/\r//g;
        if ($curitem eq "" && /^([A-Z0-9\_]+)=>([^\n\r]*)/)
        {
            $hashref->{$1} = $2;
        }
        elsif ($curitem eq "" && /^([A-Z0-9\_]+)<=\s*$/)
        {
            $curitem = $1;
            $hashref->{$curitem} = "";
        }
        elsif ($curitem && /^<=$curitem\s*$/)
        {
            chop $hashref->{$curitem};  # remove the false newline
            $curitem = "";
        }
        else
        {
            $hashref->{$curitem} .= $_ if ($curitem =~ /\S/);
        }
    }
}

sub current_mood_str {
    my ($themeid, $moodid, $mood) = @_;

    # ideal behavior: if there is a moodid, that defines the picture.
    # if there is a current_mood, that overrides as the mood name,
    # otherwise show the mood name associated with current_moodid

    my $moodname;
    my $moodpic;

    # favor custom mood over system mood
    if (my $val = $mood) {
        LJ::CleanHTML::clean_subject(\$val);
        $moodname = $val;
    }

    if (my $val = $moodid) {
        $moodname ||= LJ::mood_name($val);
        my %pic;
        if (LJ::get_mood_picture($themeid, $val, \%pic)) {
            $moodpic = "<img src=\"$pic{'pic'}\" align='absmiddle' width='$pic{'w'}' " .
                       "height='$pic{'h'}' vspace='1' alt='' /> ";
        }
    }

    my $extra = LJ::run_hook("current_mood_extra", $themeid) || "";
    return $moodpic || $moodname ? "$moodpic$moodname$extra" : "";
}

sub current_music_str {
    my $val = shift;

    LJ::CleanHTML::clean_subject(\$val);
    return $val;
}

# <LJFUNC>
# class: s1
# name: LJ::prepare_currents
# des: do all the current music/mood/weather/whatever stuff.  only used by ljviews.pl.
# args: dbarg, args
# des-args: hashref with keys: 'props' (a hashref with itemid keys), 'vars' hashref with
#           keys being S1 variables.
# </LJFUNC>
sub prepare_currents
{
    my $args = shift;

    my $datakey = $args->{'datakey'} || $args->{'itemid'}; # new || old

    my %currents = ();
    my $val;
    if ($val = $args->{'props'}->{$datakey}->{'current_music'}) {
        $currents{'Music'} = LJ::current_music_str($val);
    }

    $currents{'Mood'} = LJ::current_mood_str($args->{'user'}->{'moodthemeid'},
                                             $args->{'props'}->{$datakey}->{'current_moodid'},
                                             $args->{'props'}->{$datakey}->{'current_mood'});
    delete $currents{'Mood'} unless $currents{'Mood'};

    if (%currents) {
        if ($args->{'vars'}->{$args->{'prefix'}.'_CURRENTS'})
        {
            ### PREFIX_CURRENTS is defined, so use the correct style vars

            my $fvp = { 'currents' => "" };
            foreach (sort keys %currents) {
                $fvp->{'currents'} .= LJ::fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENT', {
                    'what' => $_,
                    'value' => $currents{$_},
                });
            }
            $args->{'event'}->{'currents'} =
                LJ::fill_var_props($args->{'vars'}, $args->{'prefix'}.'_CURRENTS', $fvp);
        } else
        {
            ### PREFIX_CURRENTS is not defined, so just add to %%events%%
            $args->{'event'}->{'event'} .= "<br />&nbsp;";
            foreach (sort keys %currents) {
                $args->{'event'}->{'event'} .= "<br /><b>Current $_</b>: " . $currents{$_} . "\n";
            }
        }
    }
}


package LJ::S1;
use strict;
use LJ::Config;
LJ::Config->load;

use lib "$LJ::HOME/cgi-bin";

require "ljlang.pl";
require "cleanhtml.pl";

# the creator for the 'lastn' view:
sub create_view_lastn
{
    my ($ret, $u, $vars, $remote, $opts) = @_;

    my $user = $u->{'user'};

    foreach ("name", "url", "urlname", "journaltitle") { LJ::text_out(\$u->{$_}); }

    my $get = $opts->{'getargs'};

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }

    LJ::load_user_props($remote, "opt_ljcut_disable_lastn");

    my %lastn_page = ();
    $lastn_page{'name'} = LJ::ehtml($u->{'name'});
    $lastn_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $lastn_page{'username'} = $user;
    $lastn_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                     $u->{'name'} . $lastn_page{'name-\'s'} . " Journal");
    $lastn_page{'numitems'} = $vars->{'LASTN_OPT_ITEMS'} || 20;

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    $lastn_page{'urlfriends'} = "$journalbase/friends";
    $lastn_page{'urlcalendar'} = "$journalbase/calendar";

    if ($u->{'url'} =~ m!^https?://!) {
        $lastn_page{'website'} =
            LJ::fill_var_props($vars, 'LASTN_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    $lastn_page{'events'} = "";
    $lastn_page{'head'} = "";

    if (LJ::are_hooks('s2_head_content_extra')) {
        $lastn_page{'head'} .= LJ::run_hook('s2_head_content_extra', $remote, $opts->{r});
    }

    # if user has requested, or a skip back link has been followed, don't index or follow
    if ($u->should_block_robots || $get->{'skip'}) {
        $lastn_page{'head'} .= LJ::robot_meta_tags()
    }
    if ($LJ::UNICODE) {
        $lastn_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\" />\n";
    }

    # Automatic Discovery of RSS/Atom
    unless ($u->is_syndicated) {
        # don't show RSS/Atom of something we're syndicating.
        $lastn_page{'head'} .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$journalbase/data/rss" />\n};
        $lastn_page{'head'} .= qq{<link rel="alternate" type="application/atom+xml" title="Atom" href="$journalbase/data/atom" />\n};
    }

    $lastn_page{'head'} .= qq{<link rel="service.feed" type="application/atom+xml" title="AtomAPI-enabled feed" href="$LJ::SITEROOT/interface/atom/feed" />\n};
    $lastn_page{'head'} .= qq{<link rel="service.post" type="application/atom+xml" title="Create a new post" href="$LJ::SITEROOT/interface/atom/post" />\n};

    $lastn_page{'head'} .= $u->openid_tags;

    # Link to the friends page as a "group", for use with OpenID "Group Membership Protocol"
    {
        my $is_comm = $u->is_community;
        my $friendstitle = $LJ::SITENAMESHORT." ".($is_comm ? "members" : "friends");
        my $rel = "group ".($is_comm ? "members" : "friends made");
        my $friendsurl = $u->journal_base."/friends"; # We want the canonical form here, not the vhost form
        $lastn_page{'head'} .= '<link rel="'.$rel.'" title="'.LJ::ehtml($friendstitle).'" href="'.LJ::ehtml($friendsurl)."\" />\n";
    }

    my $show_ad = LJ::run_hook('should_show_ad', {
        ctx  => "journal",
        user => $u->{user},
    });
    $lastn_page{'head'} .= qq{<link rel='stylesheet' href='$LJ::STATPREFIX/ad_base.css' type='text/css' />\n} if $show_ad;
    my $show_control_strip = LJ::run_hook('show_control_strip', {
        user => $u->{user},
    });
    if ($show_control_strip) {
        LJ::run_hook('control_strip_stylesheet_link', {
            user => $u->{user},
        });
        $lastn_page{'head'} .= LJ::control_strip_js_inject( user => $u->{user} );
    }

    LJ::run_hooks("need_res_for_journals", $u);
    $lastn_page{'head'} .= LJ::res_includes();

    # FOAF autodiscovery
    my $foafurl = $u->{external_foaf_url} ? LJ::eurl($u->{external_foaf_url}) : "$journalbase/data/foaf";
    $lastn_page{head} .= qq{<link rel="meta" type="application/rdf+xml" title="FOAF" href="$foafurl" />\n};

    if ($u->email_visible($remote)) {
        my $digest = Digest::SHA1::sha1_hex('mailto:' . $u->email_raw);
        $lastn_page{head} .= qq{<meta name="foaf:maker" content="foaf:mbox_sha1sum '$digest'" />\n};
    }

    $lastn_page{'head'} .=
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'LASTN_HEAD'};

    my $events = \$lastn_page{'events'};

    # to show
    my $itemshow = $vars->{'LASTN_OPT_ITEMS'} + 0;
    if ($itemshow < 1) { $itemshow = 20; }
    if ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{'skip'}+0;
    my $maxskip = $LJ::MAX_SCROLLBACK_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # do they have the viewall priv?
    my $viewall = 0;
    my $viewsome = 0;
    if ($get->{'viewall'} && LJ::check_priv($remote, "canview", "suspended")) {
        LJ::statushistory_add($u->{'userid'}, $remote->{'userid'},
                              "viewall", "lastn: $user, statusvis: $u->{'statusvis'}");
        $viewall = LJ::check_priv($remote, 'canview', '*');
        $viewsome = $viewall || LJ::check_priv($remote, 'canview', 'suspended');
    }

    ## load the itemids
    my @itemids;
    my $err;
    my @items = LJ::get_recent_items({
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'viewall' => $viewall,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'itemids' => \@itemids,
        'order' => ($u->{'journaltype'} eq "C" || $u->{'journaltype'} eq "Y")  # community or syndicated
            ? "logtime" : "",
        'err' => \$err,
    });

    if ($err) {
        $opts->{'errcode'} = $err;
        $$ret = "";
        return 0;
    }

    ### load the log properties
    my %logprops = ();
    my $logtext;
    LJ::load_log_props2($u->{'userid'}, \@itemids, \%logprops);
    $logtext = LJ::get_logtext2($u, @itemids);

    my $lastday = -1;
    my $lastmonth = -1;
    my $lastyear = -1;
    my $eventnum = 0;

    my %posteru = ();  # map posterids to u objects
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$posteru{$_->{'posterid'}} }
                               @items], [$u]);

    # pre load things in a batch (like userpics) to minimize db calls
    my @userpic_load;
    push @userpic_load, [ $u, $u->{'defaultpicid'} ] if $u->{'defaultpicid'};
    foreach my $item (@items) {
        next if $item->{'posterid'} == $u->{'userid'};
        my $itemid = $item->{'itemid'};
        my $pu = $posteru{$item->{'posterid'}};

        my $pickw = LJ::Entry->userpic_kw_from_props($logprops{$itemid});
        my $picid = LJ::get_picid_from_keyword($pu, $pickw);
        $item->{'_picid'} = $picid;
        push @userpic_load, [ $pu, $picid ] if ($picid && ! grep { $_ eq $picid } @userpic_load);
    }
    my %userpics;
    LJ::load_userpics(\%userpics, \@userpic_load);

    if (my $picid = $u->{'defaultpicid'}) {
        $lastn_page{'userpic'} =
            LJ::fill_var_props($vars, 'LASTN_USERPIC', {
                "src" => "$LJ::USERPIC_ROOT/$picid/$u->{'userid'}",
                "width" => $userpics{$picid}->{'width'},
                "height" => $userpics{$picid}->{'height'},
            });
    }

    # spit out the S1

  ENTRY:
    foreach my $item (@items)
    {
        my ($posterid, $itemid, $security, $alldatepart) =
            map { $item->{$_} } qw(posterid itemid security alldatepart);

        my $pu = $posteru{$posterid};
        next ENTRY if $pu && $pu->{'statusvis'} eq 'S' && !$viewsome;

        my $replycount = $logprops{$itemid}->{'replycount'};
        my $subject = $logtext->{$itemid}->[0];
        my $event = $logtext->{$itemid}->[1];
        if ($get->{'nohtml'}) {
            # quote all non-LJ tags
            $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            $event   =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        }

        if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$subject, \$event, $logprops{$itemid});
        }

        my %lastn_date_format = LJ::alldateparts_to_hash($alldatepart);

        if ($lastday != $lastn_date_format{'d'} ||
            $lastmonth != $lastn_date_format{'m'} ||
            $lastyear != $lastn_date_format{'yyyy'})
        {
          my %lastn_new_day = ();
          foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth))
          {
              $lastn_new_day{$_} = $lastn_date_format{$_};
          }
          unless ($lastday==-1) {
              $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});
          }
          $$events .= LJ::fill_var_props($vars, 'LASTN_NEW_DAY', \%lastn_new_day);

          $lastday = $lastn_date_format{'d'};
          $lastmonth = $lastn_date_format{'m'};
          $lastyear = $lastn_date_format{'yyyy'};
        }

        my %lastn_event = ();
        $eventnum++;
        $lastn_event{'eventnum'} = $eventnum;
        $lastn_event{'itemid'} = $itemid;
        $lastn_event{'datetime'} = LJ::fill_var_props($vars, 'LASTN_DATE_FORMAT', \%lastn_date_format);
        if ($subject ne "") {
            LJ::CleanHTML::clean_subject(\$subject);
            $lastn_event{'subject'} = LJ::fill_var_props($vars, 'LASTN_SUBJECT', {
                "subject" => $subject,
            });
        }

        my $ditemid = $itemid * 256 + $item->{'anum'};
        my $itemargs = "journal=$user&amp;itemid=$ditemid";
        $lastn_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                               'cuturl' => LJ::item_link($u, $itemid, $item->{'anum'}),
                                               'ljcut_disable' => $remote->{'opt_ljcut_disable_lastn'}, });
        LJ::expand_embedded($u, $ditemid, $remote, \$event);

        my $entry_obj = LJ::Entry->new($u, ditemid => $ditemid);
        $event = LJ::ContentFlag->transform_post(post => $event, journal => $u,
                                                 remote => $remote, entry => $entry_obj);
        $lastn_event{'event'} = $event;

        my $permalink = "$journalbase/$ditemid.html";
        $lastn_event{'permalink'} = $permalink;

        if ($u->{'opt_showtalklinks'} eq "Y" &&
            ! $logprops{$itemid}->{'opt_nocomments'}
            )
        {

            my $nc;
            $nc = "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

            my $posturl = LJ::Talk::talkargs($permalink, "mode=reply");
            my $readurl = LJ::Talk::talkargs($permalink, $nc);

            my $dispreadlink = $replycount ||
                ($logprops{$itemid}->{'hasscreened'} &&
                 ($remote->{'user'} eq $user
                  || LJ::can_manage($remote, $u)));

            $lastn_event{'talklinks'} = LJ::fill_var_props($vars, 'LASTN_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => $posturl,
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $dispreadlink ? LJ::fill_var_props($vars, 'LASTN_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents({
            'props' => \%logprops,
            'itemid' => $itemid,
            'vars' => $vars,
            'prefix' => "LASTN",
            'event' => \%lastn_event,
            'user' => $u,
        });

        if ($u->{'userid'} != $posterid)
        {
            my %lastn_altposter = ();

            my $poster = $pu->{'user'};
            $lastn_altposter{'poster'} = $poster;
            $lastn_altposter{'owner'} = $user;

            if (my $picid = $item->{'_picid'}) {
                my $pic = $userpics{$picid};
                $lastn_altposter{'pic'} = LJ::fill_var_props($vars, 'LASTN_ALTPOSTER_PIC', {
                    "src" => "$LJ::USERPIC_ROOT/$picid/$pic->{'userid'}",
                    "width" => $pic->{'width'},
                    "height" => $pic->{'height'},
                });
            }
            $lastn_event{'altposter'} =
                LJ::fill_var_props($vars, 'LASTN_ALTPOSTER', \%lastn_altposter);
        }

        if ($security eq "public") {
            $LJ::REQ_GLOBAL{'text_of_first_public_post'} ||= $event;
        }

        my $var = 'LASTN_EVENT';
        if ($security eq "private" &&
            $vars->{'LASTN_EVENT_PRIVATE'}) { $var = 'LASTN_EVENT_PRIVATE'; }
        if ($security eq "usemask" &&
            $vars->{'LASTN_EVENT_PROTECTED'}) { $var = 'LASTN_EVENT_PROTECTED'; }
        $$events .= LJ::fill_var_props($vars, $var, \%lastn_event);
        LJ::run_hook('notify_event_displayed', $entry_obj);
    } # end huge while loop

    $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});

    my $item_shown = $eventnum;
    my $item_total = @items;
    my $item_hidden = $item_total - $item_shown;

    if ($skip) {
        $lastn_page{'range'} =
            LJ::fill_var_props($vars, 'LASTN_RANGE_HISTORY', {
                "numitems" => $item_shown,
                "skip" => $skip,
            });
    } else {
        $lastn_page{'range'} =
            LJ::fill_var_props($vars, 'LASTN_RANGE_MOSTRECENT', {
                "numitems" => $item_shown,
            });
    }

    #### make the skip links
    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    ### if we've skipped down, then we can skip back up

    if ($skip) {
        $skip_f = 1;
        my $newskip = $skip - $itemshow;
        if ($newskip <= 0) { $newskip = ""; }
        else { $newskip = "?skip=$newskip"; }

        $skiplinks{'skipforward'} =
            LJ::fill_var_props($vars, 'LASTN_SKIP_FORWARD', {
                "numitems" => $itemshow,
                "url" => "$journalbase/$newskip",
            });
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown
    ## on the page, but who cares about that)

    unless ($item_total != $itemshow) {
        $skip_b = 1;

        if ($skip==$maxskip) {
            $skiplinks{'skipbackward'} =
                LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
                    "numitems" => "Day",
                    "url" => "$journalbase/" . sprintf("%04d/%02d/%02d/", $lastyear, $lastmonth, $lastday),
                });
        } else {
            my $newskip = $skip + $itemshow;
            $newskip = "?skip=$newskip";
            $skiplinks{'skipbackward'} =
                LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
                    "numitems" => $itemshow,
                    "url" => "$journalbase/$newskip",
                });
        }
    }

    ### if they're both on, show a spacer
    if ($skip_b && $skip_f) {
        $skiplinks{'skipspacer'} = $vars->{'LASTN_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $lastn_page{'skiplinks'} =
            LJ::fill_var_props($vars, 'LASTN_SKIP_LINKS', \%skiplinks);
    }

    # ads and control strip
    if ($LJ::USE_ADS && $show_ad) {
        $lastn_page{'skyscraper_ad'} = LJ::fill_var_props($vars, 'LASTN_SKYSCRAPER_AD',
                                                          { "ad" => LJ::ads( type => "journal",
                                                                             orient => 'Journal-Badge',
                                                                             pubtext => $LJ::REQ_GLOBAL{'text_of_first_public_post'},
                                                                             user => $u->{user}) .
                                                                    LJ::ads( type => "journal",
                                                                             orient => 'Journal-Skyscraper',
                                                                             pubtext => $LJ::REQ_GLOBAL{'text_of_first_public_post'},
                                                                             user => $u->{user}), });
        $lastn_page{'5linkunit_ad'} = LJ::fill_var_props($vars, 'LASTN_5LINKUNIT_AD',
                                                         { "ad" => LJ::ads( type => "journal",
                                                                            orient => 'Journal-5LinkUnit',
                                                                            user => $u->{user}), });
        $lastn_page{'open_skyscraper_ad'}  = $vars->{'LASTN_OPEN_SKYSCRAPER_AD'};
        $lastn_page{'close_skyscraper_ad'} = $vars->{'LASTN_CLOSE_SKYSCRAPER_AD'};
    }
    if ($LJ::USE_CONTROL_STRIP && $show_control_strip) {
        my $control_strip = LJ::control_strip(user => $u->{user});
        $lastn_page{'control_strip'} = $control_strip;
    }


    $$ret = LJ::fill_var_props($vars, 'LASTN_PAGE', \%lastn_page);

    return 1;
}

# the creator for the 'friends' view:
sub create_view_friends
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $sth;
    my $user = $u->{'user'};

    # Check if we should redirect due to a bad password
    $opts->{'redir'} = LJ::bad_password_redirect({ 'returl' => 1 });
    return 1 if $opts->{'redir'};

    # see how often the remote user can reload this page.
    # "friendsviewupdate" time determines what granularity time
    # increments by for checking for new updates
    my $nowtime = time();

    # update delay specified by "friendsviewupdate"
    my $newinterval = LJ::get_cap_min($remote, "friendsviewupdate") || 1;

    # when are we going to say page was last modified?  back up to the
    # most recent time in the past where $time % $interval == 0
    my $lastmod = $nowtime;
    $lastmod -= $lastmod % $newinterval;

    # see if they have a previously cached copy of this page they
    # might be able to still use.
    if ($opts->{'header'}->{'If-Modified-Since'}) {
        my $theirtime = LJ::http_to_time($opts->{'header'}->{'If-Modified-Since'});

        # send back a 304 Not Modified if they say they've reloaded this
        # document in the last $newinterval seconds:
        my $uniq = BML::get_request()->notes('uniq');
        if ($theirtime > $lastmod && !($uniq && LJ::MemCache::get("loginout:$uniq"))) {
            $opts->{'handler_return'} = 304;
            return 1;
        }
    }
    $opts->{'headers'}->{'Last-Modified'} = LJ::time_to_http($lastmod);

    $$ret = "";

    my $get = $opts->{'getargs'};
    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    foreach ("name", "url", "urlname", "friendspagetitle") { LJ::text_out(\$u->{$_}); }

    my %friends_page = ();
    $friends_page{'name'} = LJ::ehtml($u->{'name'});
    $friends_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $friends_page{'username'} = $user;
    $friends_page{'title'} = LJ::ehtml($u->{'friendspagetitle'} ||
                                       $u->{'name'} . $friends_page{'name-\'s'} . " Friends");
    $friends_page{'numitems'} = $vars->{'FRIENDS_OPT_ITEMS'} || 20;

    $friends_page{'head'} = "";

    if (LJ::are_hooks('s2_head_content_extra')) {
        $friends_page{'head'} .= LJ::run_hook('s2_head_content_extra', $remote, $opts->{r});
    }

    ## never have spiders index friends pages (change too much, and some
    ## people might not want to be indexed)
    $friends_page{'head'} .= LJ::robot_meta_tags();
    if ($LJ::UNICODE) {
        $friends_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'" />';
    }
    # Add a friends-specific XRDS reference
    $friends_page{'head'} .= qq{<meta http-equiv="X-XRDS-Location" content="}.LJ::ehtml($u->journal_base).qq{/data/yadis/friends" />\n};

    my $show_ad = LJ::run_hook('should_show_ad', {
        ctx  => "journal",
        user => $u->{user},
    });
    $friends_page{'head'} .= qq{<link rel='stylesheet' href='$LJ::STATPREFIX/ad_base.css' type='text/css' />\n} if $show_ad;
    my $show_control_strip = LJ::run_hook('show_control_strip', {
        user => $u->{user},
    });
    if ($show_control_strip) {
        LJ::run_hook('control_strip_stylesheet_link', {
            user => $u->{user},
        });
        $friends_page{'head'} .= LJ::control_strip_js_inject( user => $u->{user} );
    }

    LJ::run_hooks("need_res_for_journals", $u);
    $friends_page{'head'} .= LJ::res_includes();

    $friends_page{'head'} .=
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'FRIENDS_HEAD'};

    if ($u->{'url'} =~ m!^https?://!) {
        $friends_page{'website'} =
            LJ::fill_var_props($vars, 'FRIENDS_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    $friends_page{'urlcalendar'} = "$journalbase/calendar";
    $friends_page{'urllastn'} = "$journalbase/";

    $friends_page{'events'} = "";

    my $itemshow = $vars->{'FRIENDS_OPT_ITEMS'} + 0;
    if ($itemshow < 1) { $itemshow = 20; }
    if ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{'skip'}+0;
    my $maxskip = ($LJ::MAX_SCROLLBACK_FRIENDS || 1000) - $itemshow;
    if ($skip > $maxskip) { $skip = $maxskip; }
    if ($skip < 0) { $skip = 0; }
    my $itemload = $itemshow+$skip;

    my $filter;
    my $group;
    my $common_filter = 1;

    if (defined $get->{'filter'} && $remote && $remote->{'user'} eq $user) {
        $filter = $get->{'filter'};
        $common_filter = 0;
    } else {
        if ($opts->{'pathextra'}) {
            $group = $opts->{'pathextra'};
            $group =~ s!^/!!;
            $group =~ s!/$!!;
            if ($group) { $group = LJ::durl($group); $common_filter = 0;}
        }
        my $grp = LJ::get_friend_group($u, { 'name' => $group || "Default View" });
        my $bit = $grp ? $grp->{'groupnum'} : 0;
        my $public = $grp ? $grp->{'is_public'} : 0;
        if ($bit && ($public || ($remote && $remote->{'user'} eq $user))) {
            $filter = (1 << $bit);
        } elsif ($group) {
            $opts->{'badfriendgroup'} = 1;
            return 1;
        }
    }

    ## load the itemids
    my %friends;
    my %friends_row;
    my %idsbycluster;
    my @items = LJ::get_friend_items({
        'u' => $u,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'filter' => $filter,
        'common_filter' => $common_filter,
        'friends_u' => \%friends,
        'friends' => \%friends_row,
        'idsbycluster' => \%idsbycluster,
        'showtypes' => $get->{'show'},
        'friendsoffriends' => $opts->{'view'} eq "friendsfriends",
    });

    while ($_ = each %friends) {
        # we expect fgcolor/bgcolor to be in here later
        $friends{$_}->{'fgcolor'} = $friends_row{$_}->{'fgcolor'} || '#000000';
        $friends{$_}->{'bgcolor'} = $friends_row{$_}->{'bgcolor'} || '#ffffff';
    }

    unless (%friends)
    {
        $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_NOFRIENDS', {
          "name" => LJ::ehtml($u->{'name'}),
          "name-\'s" => ($u->{'name'} =~ /s$/i) ? "'" : "'s",
          "username" => $user,
        });

        $$ret .= "<base target='_top'>" if ($get->{'mode'} eq "framed");
        $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);
        return 1;
    }

    my %aposter;  # alt-posterid -> u object (if not in friends already)
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$aposter{$_->{'posterid'}} }
                               grep { $friends{$_->{'ownerid'}} &&
                                          ! $friends{$_->{'posterid'}} } @items],
                              [ $u, $remote ]);

    ### load the log properties
    my %logprops = ();  # key is "$owneridOrZero $[j]itemid"
    LJ::load_log_props2multi(\%idsbycluster, \%logprops);

    # load the pictures for the user
    my %userpics;
    my @picids = map { [$friends{$_}, $friends{$_}->{'defaultpicid'}] } keys %friends;
    LJ::load_userpics(\%userpics, [ @picids, map { [ $_, $_->{'defaultpicid'} ] } values %aposter ]);

    # load the text of the entries
    my $logtext = LJ::get_logtext2multi(\%idsbycluster);

    # load 'opt_stylemine' prop for $remote.  don't need to load opt_nctalklinks
    # because that was already faked in LJ::make_journal previously
    LJ::load_user_props($remote, "opt_stylemine", "opt_imagelinks", "opt_ljcut_disable_friends");

    # load options for image links
    my ($maximgwidth, $maximgheight) = (undef, undef);
    ($maximgwidth, $maximgheight) = ($1, $2)
        if ($remote && $remote->{'userid'} == $u->{'userid'} &&
            $remote->{'opt_imagelinks'} =~ m/^(\d+)\|(\d+)$/);

    my %friends_events = ();
    my $events = \$friends_events{'events'};

    my $lastday = -1;
    my $eventnum = 0;

  ENTRY:
    foreach my $item (@items)
    {
        my ($friendid, $posterid, $itemid, $security, $alldatepart) =
            map { $item->{$_} } qw(ownerid posterid itemid security alldatepart);

        my $pu = $friends{$posterid} || $aposter{$posterid};
        next ENTRY if $pu && $pu->{'statusvis'} eq 'S';

        # counting excludes skipped entries
        $eventnum++;

        my $clusterid = $item->{'clusterid'}+0;

        my $datakey = "$friendid $itemid";

        my $replycount = $logprops{$datakey}->{'replycount'};
        my $subject = $logtext->{$datakey}->[0];
        my $event = $logtext->{$datakey}->[1];
        if ($get->{'nohtml'}) {
            # quote all non-LJ tags
            $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            $event   =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        }

        if ($LJ::UNICODE && $logprops{$datakey}->{'unknown8bit'}) {
            LJ::item_toutf8($friends{$friendid}, \$subject, \$event, $logprops{$datakey});
        }

        my ($friend, $poster);
        $friend = $poster = $friends{$friendid}->{'user'};
        $poster = $pu->{'user'};

        my %friends_date_format = LJ::alldateparts_to_hash($alldatepart);

        if ($lastday != $friends_date_format{'d'})
        {
            my %friends_new_day = ();
            foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth))
            {
                $friends_new_day{$_} = $friends_date_format{$_};
            }
            unless ($lastday==-1) {
                $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
            }
            $$events .= LJ::fill_var_props($vars, 'FRIENDS_NEW_DAY', \%friends_new_day);
            $lastday = $friends_date_format{'d'};
        }

        my %friends_event = ();
        $friends_event{'itemid'} = $itemid;
        $friends_event{'datetime'} = LJ::fill_var_props($vars, 'FRIENDS_DATE_FORMAT', \%friends_date_format);
        if ($subject ne "") {
            LJ::CleanHTML::clean_subject(\$subject);
            $friends_event{'subject'} = LJ::fill_var_props($vars, 'FRIENDS_SUBJECT', {
                "subject" => $subject,
            });
        } else {
            $friends_event{'subject'} = LJ::fill_var_props($vars, 'FRIENDS_NO_SUBJECT', {
                "friend" => $friend,
                "name" => $friends{$friendid}->{'name'},
            });
        }

        my $ditemid = $itemid * 256 + $item->{'anum'};
        my $itemargs = "journal=$friend&amp;itemid=$ditemid";
        $friends_event{'itemargs'} = $itemargs;

        my $stylemine = "";
        $stylemine .= "style=mine" if $remote && $remote->{'opt_stylemine'} &&
                                      $remote->{'userid'} != $friendid;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$datakey}->{'opt_preformatted'},
                                              'cuturl' => LJ::item_link($friends{$friendid}, $itemid, $item->{'anum'}, $stylemine),
                                              'maximgwidth' => $maximgwidth,
                                              'maximgheight' => $maximgheight,
                                              'ljcut_disable' => $remote->{'opt_ljcut_disable_friends'}, });
        LJ::expand_embedded($friends{$friendid}, $ditemid, $remote, \$event);

        my $entry_obj = LJ::Entry->new($friends{$friendid}, ditemid => $ditemid);
        $event = LJ::ContentFlag->transform_post(post => $event, journal => $friends{$friendid},
                                                 remote => $remote, entry => $entry_obj);
        $friends_event{'event'} = $event;

        # do the picture
        {
            my $picid = $friends{$friendid}->{'defaultpicid'};  # this could be the shared journal pic
            my $picuserid = $friendid;
            if ($friendid != $posterid && ! $u->{'opt_usesharedpic'}) {
                if ($pu->{'defaultpicid'}) {
                    $picid = $pu->{'defaultpicid'};
                    $picuserid = $posterid;
                }
            }

            if (! $u->{'opt_usesharedpic'} || ($posterid == $friendid)) {
                my $pickw = LJ::Entry->userpic_kw_from_props($logprops{$datakey});
                my $alt_picid = LJ::get_picid_from_keyword($posterid, $pickw);
                if ($alt_picid) {
                    LJ::load_userpics(\%userpics, [ $pu, $alt_picid ]);
                    $picid = $alt_picid;
                    $picuserid = $posterid;
                }
            }
            if ($picid) {
                $friends_event{'friendpic'} =
                    LJ::fill_var_props($vars, 'FRIENDS_FRIENDPIC', {
                        "src" => "$LJ::USERPIC_ROOT/$picid/$picuserid",
                        "width" => $userpics{$picid}->{'width'},
                        "height" => $userpics{$picid}->{'height'},
                    });
            }
        }

        if ($friend ne $poster) {
            $friends_event{'altposter'} =
                LJ::fill_var_props($vars, 'FRIENDS_ALTPOSTER', {
                    "poster" => $poster,
                    "owner" => $friend,
                    "fgcolor" => $friends{$friendid}->{'fgcolor'} || "#000000",
                    "bgcolor" => $friends{$friendid}->{'bgcolor'} || "#ffffff",
                });
        }

        # friends view specific:
        $friends_event{'user'} = $friend;
        $friends_event{'fgcolor'} = $friends{$friendid}->{'fgcolor'} || "#000000";
        $friends_event{'bgcolor'} = $friends{$friendid}->{'bgcolor'} || "#ffffff";

        my $journalbase = LJ::journal_base($friends{$friendid});
        my $permalink = "$journalbase/$ditemid.html";
        $friends_event{'permalink'} = $permalink;

        if ($friends{$friendid}->{'opt_showtalklinks'} eq "Y" &&
            ! $logprops{$datakey}->{'opt_nocomments'}
            )
        {
            my $dispreadlink = $replycount ||
                ($logprops{$datakey}->{'hasscreened'} &&
                 ($remote->{'user'} eq $friend
                  || LJ::can_manage($remote, $friendid)));

            my $nc = "";
            $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

            my $readurl = LJ::Talk::talkargs($permalink, $nc, $stylemine);
            my $posturl = LJ::Talk::talkargs($permalink, "mode=reply", $stylemine);

            $friends_event{'talklinks'} = LJ::fill_var_props($vars, 'FRIENDS_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => $posturl,
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $dispreadlink ? LJ::fill_var_props($vars, 'FRIENDS_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents({
            'props' => \%logprops,
            'datakey' => $datakey,
            'vars' => $vars,
            'prefix' => "FRIENDS",
            'event' => \%friends_event,
            'user' => ($u->{'opt_forcemoodtheme'} eq "Y" ? $u :
                       $friends{$friendid}),
        });

        if ($security eq "public") {
            $LJ::REQ_GLOBAL{'text_of_first_public_post'} ||= $event;
        }

        my $var = 'FRIENDS_EVENT';
        if ($security eq "private" &&
            $vars->{'FRIENDS_EVENT_PRIVATE'}) { $var = 'FRIENDS_EVENT_PRIVATE'; }
        if ($security eq "usemask" &&
            $vars->{'FRIENDS_EVENT_PROTECTED'}) { $var = 'FRIENDS_EVENT_PROTECTED'; }

        $$events .= LJ::fill_var_props($vars, $var, \%friends_event);
        LJ::run_hook('notify_event_displayed', $entry_obj);
    } # end while

    $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
    $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_EVENTS', \%friends_events);

    my $item_shown = $eventnum;
    my $item_total = @items;
    my $item_hidden = $item_total - $item_shown;

    ### set the range property (what entries are we looking at)

    if ($skip) {
        $friends_page{'range'} =
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_HISTORY', {
                "numitems" => $item_shown,
                "skip" => $skip,
            });
    } else {
        $friends_page{'range'} =
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_MOSTRECENT', {
                "numitems" => $item_shown,
            });
    }

    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;
    my $base = "$journalbase/$opts->{'view'}";
    if ($group) {
        $base .= "/" . LJ::eurl($group);
    }

    # $linkfilter is distinct from $filter: if user has a default view,
    # $filter is now set according to it but we don't want it to show in the links.
    # $incfilter may be true even if $filter is 0: user may use filter=0 to turn
    # off the default group
    my $linkfilter = $get->{'filter'} + 0;
    my $incfilter = defined $get->{'filter'};

    # if we've skipped down, then we can skip back up
    if ($skip) {
        $skip_f = 1;
        my %linkvars;

        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;

        my $newskip = $skip - $itemshow;
        if ($newskip > 0) { $linkvars{'skip'} = $newskip; }

        $skiplinks{'skipforward'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_FORWARD', {
                "numitems" => $itemshow,
                "url" => LJ::make_link($base, \%linkvars),
            });
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown
    ## on the page, but who cares about that)

    unless ($item_total != $itemshow || $skip == $maxskip) {
        $skip_b = 1;
        my %linkvars;

        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;

        my $newskip = $skip + $itemshow;
        $linkvars{'skip'} = $newskip;

        $skiplinks{'skipbackward'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_BACKWARD', {
                "numitems" => $itemshow,
                "url" => LJ::make_link($base, \%linkvars),
            });
    }

    ### if they're both on, show a spacer
    if ($skip_f && $skip_b) {
        $skiplinks{'skipspacer'} = $vars->{'FRIENDS_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $friends_page{'skiplinks'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_LINKS', \%skiplinks);
    }

    ## ads and control strip
    if ($LJ::USE_ADS && $show_ad) {
        $friends_page{'skyscraper_ad'} = LJ::fill_var_props($vars, 'FRIENDS_SKYSCRAPER_AD',
                                                            { "ad" => LJ::ads( type => "journal",
                                                                               orient => 'Journal-Badge',
                                                                               pubtext => $LJ::REQ_GLOBAL{'text_of_first_public_post'},
                                                                               user => $u->{user}) .
                                                                      LJ::ads( type => "journal",
                                                                               orient => 'Journal-Skyscraper',
                                                                               pubtext => $LJ::REQ_GLOBAL{'text_of_first_public_post'},
                                                                               user => $u->{user}), });
        $friends_page{'5linkunit_ad'} = LJ::fill_var_props($vars, 'FRIENDS_5LINKUNIT_AD',
                                                           { "ad" => LJ::ads( type => "journal",
                                                                              orient => 'Journal-5LinkUnit',
                                                                              user => $u->{user}), });
        $friends_page{'open_skyscraper_ad'}  = $vars->{'FRIENDS_OPEN_SKYSCRAPER_AD'};
        $friends_page{'close_skyscraper_ad'} = $vars->{'FRIENDS_CLOSE_SKYSCRAPER_AD'};
    }
    if ($LJ::USE_CONTROL_STRIP && $show_control_strip) {
        my $control_strip = LJ::control_strip(user => $u->{user});
        $friends_page{'control_strip'} = $control_strip;
    }


    $$ret .= "<base target='_top' />" if ($get->{'mode'} eq "framed");
    $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);

    return 1;
}

# the creator for the 'calendar' view:
sub create_view_calendar
{
    my ($ret, $u, $vars, $remote, $opts) = @_;

    my $user = $u->{'user'};

    foreach ("name", "url", "urlname", "journaltitle") { LJ::text_out(\$u->{$_}); }

    my $get = $opts->{'getargs'};

    my %calendar_page = ();
    $calendar_page{'name'} = LJ::ehtml($u->{'name'});
    $calendar_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $calendar_page{'username'} = $user;
    $calendar_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                        $u->{'name'} . $calendar_page{'name-\'s'} . " Journal");

    $calendar_page{'head'} = "";

    if (LJ::are_hooks('s2_head_content_extra')) {
        $calendar_page{'head'} .= LJ::run_hook('s2_head_content_extra', $remote, $opts->{r});
    }

    if ($u->should_block_robots) {
        $calendar_page{'head'} .= LJ::robot_meta_tags();
    }
    if ($LJ::UNICODE) {
        $calendar_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'" />';
    }

    my $show_ad = LJ::run_hook('should_show_ad', {
        ctx  => "journal",
        user => $u->{user},
    });
    $calendar_page{'head'} .= qq{<link rel='stylesheet' href='$LJ::STATPREFIX/ad_base.css' type='text/css' />\n} if $show_ad;
    my $show_control_strip = LJ::run_hook('show_control_strip', {
        user => $u->{user},
    });
    if ($show_control_strip) {
        LJ::run_hook('control_strip_stylesheet_link', {
            user => $u->{user},
        });
        $calendar_page{'head'} .= LJ::control_strip_js_inject( user => $u->{user} );
    }
    $calendar_page{'head'} .=
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'CALENDAR_HEAD'};

    LJ::run_hooks("need_res_for_journals", $u);
    $calendar_page{'head'} .= LJ::res_includes();

    $calendar_page{'months'} = "";

    if ($u->{'url'} =~ m!^https?://!) {
        $calendar_page{'website'} =
            LJ::fill_var_props($vars, 'CALENDAR_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});

    $calendar_page{'urlfriends'} = "$journalbase/friends";
    $calendar_page{'urllastn'} = "$journalbase/";

    if ($LJ::USE_ADS && $show_ad) {
        $calendar_page{'skyscraper_ad'} = LJ::fill_var_props($vars, 'CALENDAR_SKYSCRAPER_AD',
                                                             { "ad" => LJ::ads( type => "journal",
                                                                                orient => 'Journal-Badge',
                                                                                user => $u->{user}) .
                                                                       LJ::ads( type => "journal",
                                                                                orient => 'Journal-Skyscraper',
                                                                                user => $u->{user} ) });
        $calendar_page{'5linkunit_ad'} = LJ::fill_var_props($vars, 'CALENDAR_5LINKUNIT_AD',
                                                            { "ad" => LJ::ads( type => "journal",
                                                                               orient => 'Journal-5LinkUnit',
                                                                               user => $u->{user} ) });
        $calendar_page{'open_skyscraper_ad'}  = $vars->{'CALENDAR_OPEN_SKYSCRAPER_AD'};
        $calendar_page{'close_skyscraper_ad'} = $vars->{'CALENDAR_CLOSE_SKYSCRAPER_AD'};
    }
    if ($LJ::USE_CONTROL_STRIP && $show_control_strip) {
        my $control_strip = LJ::control_strip(user => $u->{user});
        $calendar_page{'control_strip'} = $control_strip;
    }

    my $months = \$calendar_page{'months'};

    my $quserid = int($u->{'userid'});
    my $maxyear = 0;

    my $daycts = LJ::get_daycounts($u, $remote);
    unless ($daycts) {
        $opts->{'errcode'} = "nodb";
        $$ret = "";
        return 0;
    }

    my (%count, %dayweek);
    foreach my $dy (@$daycts) {
        my ($year, $month, $day, $count) = @$dy;

        # calculate day of week
        my $time = eval { Time::Local::timegm(0, 0, 0, $day, $month-1, $year) } ||
            eval { Time::Local::timegm(0, 0, 0, LJ::days_in_month($month, $year), $month-1, $year) } ||
            0;
        next unless $time;

        my $dayweek = (gmtime($time))[6] + 1;

        $count{$year}->{$month}->{$day} = $count;
        $dayweek{$year}->{$month}->{$day} = $dayweek;
        if ($year > $maxyear) { $maxyear = $year; }
    }

    my @allyears = sort { $b <=> $a } keys %count;
    if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @allyears = reverse @allyears; }

    my @years = ();
    my $dispyear = $get->{'year'};  # old form was /users/<user>/calendar?year=1999

    # but the new form is purtier:  */calendar/2001
    # but the NEWER form is purtier:  */2001
    unless ($dispyear) {
        if ($opts->{'pathextra'} =~ m!^/(\d\d\d\d)/?\b!) {
            $dispyear = $1;
        }
    }

    # else... default to the year they last posted.
    $dispyear ||= $maxyear;

    # we used to show multiple years.  now we only show one at a time:  (hence the @years confusion)
    if ($dispyear) { push @years, $dispyear; }

    if (scalar(@allyears) > 1) {
        my $yearlinks = "";
        foreach my $year (@allyears) {
            my $yy = sprintf("%02d", $year % 100);
            my $url = "$journalbase/$year/";
            if ($year != $dispyear) {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINK', {
                    "url" => $url, "yyyy" => $year, "yy" => $yy });
            } else {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_DISPLAYED', {
                    "yyyy" => $year, "yy" => $yy });
            }
        }
        $calendar_page{'yearlinks'} =
            LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINKS', { "years" => $yearlinks });
    }

    foreach my $year (@years)
    {
        $$months .= LJ::fill_var_props($vars, 'CALENDAR_NEW_YEAR', {
          'yyyy' => $year,
          'yy' => substr($year, 2, 2),
        });

        my @months = sort { $b <=> $a } keys %{$count{$year}};
        if ($vars->{'CALENDAR_SORT_MODE'} eq "forward") { @months = reverse @months; }
        foreach my $month (@months)
        {
          my $daysinmonth = LJ::days_in_month($month, $year);

          # this picks a random day there were journal entries (thus, we know
          # the %dayweek from above)  from that we go backwards and forwards
          # to find the rest of the days of week
          my $firstday = (%{$count{$year}->{$month}})[0];

          # go backwards from first day
          my $dayweek = $dayweek{$year}->{$month}->{$firstday};
          for (my $i=$firstday-1; $i>0; $i--)
          {
              if (--$dayweek < 1) { $dayweek = 7; }
              $dayweek{$year}->{$month}->{$i} = $dayweek;
          }
          # go forwards from first day
          $dayweek = $dayweek{$year}->{$month}->{$firstday};
          for (my $i=$firstday+1; $i<=$daysinmonth; $i++)
          {
              if (++$dayweek > 7) { $dayweek = 1; }
              $dayweek{$year}->{$month}->{$i} = $dayweek;
          }

          my %calendar_month = ();
          $calendar_month{'monlong'} = LJ::Lang::month_long($month);
          $calendar_month{'monshort'} = LJ::Lang::month_short($month);
          $calendar_month{'yyyy'} = $year;
          $calendar_month{'yy'} = substr($year, 2, 2);
          $calendar_month{'weeks'} = "";
          $calendar_month{'urlmonthview'} = sprintf("$journalbase/%04d/%02d/", $year, $month);
          my $weeks = \$calendar_month{'weeks'};

          my %calendar_week = ();
          $calendar_week{'emptydays_beg'} = "";
          $calendar_week{'emptydays_end'} = "";
          $calendar_week{'days'} = "";

          # start the first row and check for its empty spaces
          my $rowopen = 1;
          if ($dayweek{$year}->{$month}->{1} != 1)
          {
              my $spaces = $dayweek{$year}->{$month}->{1} - 1;
              $calendar_week{'emptydays_beg'} =
                  LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS',
                                  { 'numempty' => $spaces });
          }

          # make the days!
          my $days = \$calendar_week{'days'};

          for (my $i=1; $i<=$daysinmonth; $i++)
          {
              $count{$year}->{$month}->{$i} += 0;
              if (! $rowopen) { $rowopen = 1; }

              my %calendar_day = ();
              $calendar_day{'d'} = $i;
              $calendar_day{'eventcount'} = $count{$year}->{$month}->{$i};
              if ($count{$year}->{$month}->{$i})
              {
                $calendar_day{'dayevent'} = LJ::fill_var_props($vars, 'CALENDAR_DAY_EVENT', {
                    'eventcount' => $count{$year}->{$month}->{$i},
                    'dayurl' => "$journalbase/" . sprintf("%04d/%02d/%02d/", $year, $month, $i),
                });
              }
              else
              {
                $calendar_day{'daynoevent'} = $vars->{'CALENDAR_DAY_NOEVENT'};
              }

              $$days .= LJ::fill_var_props($vars, 'CALENDAR_DAY', \%calendar_day);

              if ($dayweek{$year}->{$month}->{$i} == 7)
              {
                $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
                $rowopen = 0;
                $calendar_week{'emptydays_beg'} = "";
                $calendar_week{'emptydays_end'} = "";
                $calendar_week{'days'} = "";
              }
          }

          # if rows is still open, we have empty spaces
          if ($rowopen)
          {
              if ($dayweek{$year}->{$month}->{$daysinmonth} != 7)
              {
                  my $spaces = 7 - $dayweek{$year}->{$month}->{$daysinmonth};
                  $calendar_week{'emptydays_end'} =
                      LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS',
                                         { 'numempty' => $spaces });
              }
              $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
          }

          $$months .= LJ::fill_var_props($vars, 'CALENDAR_MONTH', \%calendar_month);
        } # end foreach months

    } # end foreach years

    ######## new code

    $$ret .= LJ::fill_var_props($vars, 'CALENDAR_PAGE', \%calendar_page);

    return 1;
}

# the creator for the 'day' view:
sub create_view_day
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $sth;

    my $user = $u->{'user'};

    foreach ("name", "url", "urlname", "journaltitle") { LJ::text_out(\$u->{$_}); }

    my %day_page = ();
    $day_page{'username'} = $user;
    $day_page{'head'} = "";

    if (LJ::are_hooks('s2_head_content_extra')) {
        $day_page{'head'} .= LJ::run_hook('s2_head_content_extra', $remote, $opts->{r});
    }

    if ($u->should_block_robots) {
        $day_page{'head'} .= LJ::robot_meta_tags();
    }
    if ($LJ::UNICODE) {
        $day_page{'head'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}.'" />';
    }

    my $show_ad = LJ::run_hook('should_show_ad', {
        ctx  => "journal",
        user => $u->{user},
    });
    $day_page{'head'} .= qq{<link rel='stylesheet' href='$LJ::STATPREFIX/ad_base.css' type='text/css' />\n} if $show_ad;
    my $show_control_strip = LJ::run_hook('show_control_strip', {
        user => $u->{user},
    });
    if ($show_control_strip) {
        LJ::run_hook('control_strip_stylesheet_link', {
            user => $u->{user},
        });
        $day_page{'head'} .= LJ::control_strip_js_inject( user => $u->{user} );
    }

    LJ::run_hooks("need_res_for_journals", $u);
    $day_page{'head'} .= LJ::res_includes();

    $day_page{'head'} .=
        $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'DAY_HEAD'};
    $day_page{'name'} = LJ::ehtml($u->{'name'});
    $day_page{'name-\'s'} = ($u->{'name'} =~ /s$/i) ? "'" : "'s";
    $day_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                   $u->{'name'} . $day_page{'name-\'s'} . " Journal");

    if ($u->{'url'} =~ m!^https?://!) {
        $day_page{'website'} =
            LJ::fill_var_props($vars, 'DAY_WEBSITE', {
                "url" => LJ::ehtml($u->{'url'}),
                "name" => LJ::ehtml($u->{'urlname'} || "My Website"),
            });
    }

    my $journalbase = LJ::journal_base($user, $opts->{'vhost'});
    $day_page{'urlfriends'} = "$journalbase/friends";
    $day_page{'urlcalendar'} = "$journalbase/calendar";
    $day_page{'urllastn'} = "$journalbase/";

    if ($LJ::USE_ADS && $show_ad) {
        $day_page{'skyscraper_ad'} = LJ::fill_var_props($vars, 'DAY_SKYSCRAPER_AD',
                                                        { "ad" => LJ::ads( type => "journal",
                                                                           orient => 'Journal-Badge',
                                                                           user => $u->{user}) .
                                                                  LJ::ads( type => "journal",
                                                                           orient => 'Journal-Skyscraper',
                                                                           user => $u->{user}), });
        $day_page{'5linkunit_ad'} = LJ::fill_var_props($vars, 'DAY_5LINKUNIT_AD',
                                                       { "ad" => LJ::ads( type => "journal",
                                                                          orient => 'Journal-5LinkUnit',
                                                                          user => $u->{user}), });
        $day_page{'open_skyscraper_ad'}  = $vars->{'DAY_OPEN_SKYSCRAPER_AD'};
        $day_page{'close_skyscraper_ad'} = $vars->{'DAY_CLOSE_SKYSCRAPER_AD'};
    }
    if ($LJ::USE_CONTROL_STRIP && $show_control_strip) {
        my $control_strip = LJ::control_strip(user => $u->{user});
        $day_page{'control_strip'} = $control_strip;
    }

    my $initpagedates = 0;

    my $get = $opts->{'getargs'};

    my $month = $get->{'month'};
    my $day = $get->{'day'};
    my $year = $get->{'year'};
    my @errors = ();

    if ($opts->{'pathextra'} =~ m!^(?:/day)?/(\d\d\d\d)/(\d\d)/(\d\d)\b!) {
        ($month, $day, $year) = ($2, $3, $1);
    }

    if ($year !~ /^\d+$/) { push @errors, "Corrupt or non-existant year."; }
    if ($month !~ /^\d+$/) { push @errors, "Corrupt or non-existant month."; }
    if ($day !~ /^\d+$/) { push @errors, "Corrupt or non-existant day."; }
    if ($month < 1 || $month > 12 || int($month) != $month) { push @errors, "Invalid month."; }
    if ($year < 1970 || $year > 2038 || int($year) != $year) { push @errors, "Invalid year: $year"; }
    if ($day < 1 || $day > 31 || int($day) != $day) { push @errors, "Invalid day."; }
    if (scalar(@errors)==0 && $day > LJ::days_in_month($month, $year)) { push @errors, "That month doesn't have that many days."; }

    if (@errors) {
        $$ret .= "Errors occurred processing this page:\n<ul>\n";
        foreach (@errors) {
          $$ret .= "<li>$_</li>\n";
        }
        $$ret .= "</ul>\n";
        return 0;
    }

    my $logdb = LJ::get_cluster_reader($u);
    unless ($logdb) {
        $opts->{'errcode'} = "nodb";
        $$ret = "";
        return 0;
    }

    my $optDESC = $vars->{'DAY_SORT_MODE'} eq "reverse" ? "DESC" : "";

    my $secwhere = "AND security='public'";
    my $viewall = 0;
    my $viewsome = 0;
    if ($remote) {

        # do they have the viewall priv?
        if ($get->{'viewall'} && LJ::check_priv($remote, "canview", "suspended")) {
            LJ::statushistory_add($u->{'userid'}, $remote->{'userid'},
                                  "viewall", "day: $user, statusvis: $u->{'statusvis'}");
            $viewall = LJ::check_priv($remote, 'canview', '*');
            $viewsome = $viewall || LJ::check_priv($remote, 'canview', 'suspended');
        }

        if ($remote->{'userid'} == $u->{'userid'} || $viewall) {
            $secwhere = "";   # see everything
        } elsif ($remote->{'journaltype'} eq 'P') {
            my $gmask = LJ::get_groupmask($u, $remote);
            $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $gmask))"
                if $gmask;
        }
    }

    # load the log items
    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    $sth = $logdb->prepare("SELECT jitemid AS itemid, posterid, security, ".
                           "       DATE_FORMAT(eventtime, \"$dateformat\") AS 'alldatepart', anum " .
                           "FROM log2 " .
                           "WHERE journalid=? AND year=? AND month=? AND day=? $secwhere " .
                           "ORDER BY eventtime $optDESC, logtime $optDESC LIMIT 200");
    $sth->execute($u->{'userid'}, $year, $month, $day);
    my @items;
    push @items, $_ while $_ = $sth->fetchrow_hashref;
    my @itemids = map { $_->{'itemid'} } @items;

    # load 'opt_ljcut_disable_lastn' prop for $remote.
    LJ::load_user_props($remote, "opt_ljcut_disable_lastn");

    ### load the log properties
    my %logprops = ();
    LJ::load_log_props2($logdb, $u->{'userid'}, \@itemids, \%logprops);
    my $logtext = LJ::get_logtext2($u, @itemids);

    my %posteru = ();  # map posterids to u objects
    LJ::load_userids_multiple([map { $_->{'posterid'}, \$posteru{$_->{'posterid'}} } @items], [$u]);

    my $events = "";

  ENTRY:
    foreach my $item (@items) {
        my ($itemid, $posterid, $security, $alldatepart, $anum) =
            map { $item->{$_} } qw(itemid posterid security alldatepart anum);

        next ENTRY if $posteru{$posterid} && $posteru{$posterid}->{'statusvis'} eq 'S' && !$viewsome;

        my $replycount = $logprops{$itemid}->{'replycount'};
        my $subject = $logtext->{$itemid}->[0];
        my $event = $logtext->{$itemid}->[1];

        if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
            LJ::item_toutf8($u, \$subject, \$event, $logprops{$itemid});
        }

        my %day_date_format = LJ::alldateparts_to_hash($alldatepart);

        unless ($initpagedates++) {
            foreach (qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth)) {
                $day_page{$_} = $day_date_format{$_};
            }
        }

        my %day_event = ();
        $day_event{'itemid'} = $itemid;
        $day_event{'datetime'} = LJ::fill_var_props($vars, 'DAY_DATE_FORMAT', \%day_date_format);
        if ($subject ne "") {
            LJ::CleanHTML::clean_subject(\$subject);
            $day_event{'subject'} = LJ::fill_var_props($vars, 'DAY_SUBJECT', {
                "subject" => $subject,
            });
        }

        my $ditemid = $itemid*256 + $anum;
        my $itemargs = "journal=$user&amp;itemid=$ditemid";
        $day_event{'itemargs'} = $itemargs;

        LJ::CleanHTML::clean_event(\$event, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                              'cuturl' => LJ::item_link($u, $itemid, $anum),
                                              'ljcut_disable' => $remote->{'opt_ljcut_disable_lastn'}, });
        LJ::expand_embedded($u, $ditemid, $remote, \$event);

        my $entry_obj = LJ::Entry->new($u, ditemid => $ditemid);
        $event = LJ::ContentFlag->transform_post(post => $event, journal => $u,
                                                 remote => $remote, entry => $entry_obj);
        $day_event{'event'} = $event;

        my $permalink = "$journalbase/$ditemid.html";
        $day_event{'permalink'} = $permalink;

        if ($u->{'opt_showtalklinks'} eq "Y" &&
            ! $logprops{$itemid}->{'opt_nocomments'}
            )
        {
            my $nc;
            $nc = "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

            my $posturl = LJ::Talk::talkargs($permalink, "mode=reply");
            my $readurl = LJ::Talk::talkargs($permalink, $nc);

            my $dispreadlink = $replycount ||
                ($logprops{$itemid}->{'hasscreened'} &&
                 ($remote->{'user'} eq $user
                  || LJ::can_manage($remote, $u)));
            $day_event{'talklinks'} = LJ::fill_var_props($vars, 'DAY_TALK_LINKS', {
                'itemid' => $ditemid,
                'itemargs' => $itemargs,
                'urlpost' => $posturl,
                'urlread' => $readurl,
                'messagecount' => $replycount,
                'readlink' => $dispreadlink ? LJ::fill_var_props($vars, 'DAY_TALK_READLINK', {
                    'urlread' => $readurl,
                    'messagecount' => $replycount,
                    'mc-plural-s' => $replycount == 1 ? "" : "s",
                    'mc-plural-es' => $replycount == 1 ? "" : "es",
                    'mc-plural-ies' => $replycount == 1 ? "y" : "ies",
                }) : "",
            });
        }

        ## current stuff
        LJ::prepare_currents({
            'props' => \%logprops,
            'itemid' => $itemid,
            'vars' => $vars,
            'prefix' => "DAY",
            'event' => \%day_event,
            'user' => $u,
        });

        my $var = 'DAY_EVENT';
        if ($security eq "private" &&
            $vars->{'DAY_EVENT_PRIVATE'}) { $var = 'DAY_EVENT_PRIVATE'; }
        if ($security eq "usemask" &&
            $vars->{'DAY_EVENT_PROTECTED'}) { $var = 'DAY_EVENT_PROTECTED'; }

        $events .= LJ::fill_var_props($vars, $var, \%day_event);
        LJ::run_hook('notify_event_displayed', $entry_obj);
    }

    if (! $initpagedates)
    {
        # if no entries were on that day, we haven't populated the time shit!
        # FIXME: don't use the database for this.  it can be done in Perl.
        my $dbr = LJ::get_db_reader();
        $sth = $dbr->prepare("SELECT DATE_FORMAT('$year-$month-$day', '%a %W %b %M %y %Y %c %m %e %d %D') AS 'alldatepart'");
        $sth->execute;
        my @dateparts = split(/ /, $sth->fetchrow_arrayref->[0]);
        foreach (qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth))
        {
          $day_page{$_} = shift @dateparts;
        }

        $day_page{'events'} = LJ::fill_var_props($vars, 'DAY_NOEVENTS', {});
    }
    else
    {
        $day_page{'events'} = LJ::fill_var_props($vars, 'DAY_EVENTS', { 'events' => $events });
        $events = "";  # free some memory maybe
    }

    # calculate previous day
    my $pdyear = $year;
    my $pdmonth = $month;
    my $pdday = $day-1;
    if ($pdday < 1)
    {
        if (--$pdmonth < 1)
        {
          $pdmonth = 12;
          $pdyear--;
        }
        $pdday = LJ::days_in_month($pdmonth, $pdyear);
    }

    # calculate next day
    my $nxyear = $year;
    my $nxmonth = $month;
    my $nxday = $day+1;
    if ($nxday > LJ::days_in_month($nxmonth, $nxyear))
    {
        $nxday = 1;
        if (++$nxmonth > 12) { ++$nxyear; $nxmonth=1; }
    }

    $day_page{'prevday_url'} = "$journalbase/" . sprintf("%04d/%02d/%02d/", $pdyear, $pdmonth, $pdday);
    $day_page{'nextday_url'} = "$journalbase/" . sprintf("%04d/%02d/%02d/", $nxyear, $nxmonth, $nxday);

    $$ret .= LJ::fill_var_props($vars, 'DAY_PAGE', \%day_page);
    return 1;
}

1;
