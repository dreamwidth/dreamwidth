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
# database schema & data info
#

use strict;

mark_clustered(@LJ::USER_TABLES);

register_tablecreate( "vgift_ids", <<'EOC');
CREATE TABLE vgift_ids (
    vgiftid      INT UNSIGNED NOT NULL PRIMARY KEY,
    name         VARCHAR(255) NOT NULL,
    created_t    INT UNSIGNED NOT NULL,   #unixtime
    creatorid    INT UNSIGNED NOT NULL DEFAULT 0,
    active       ENUM('Y','N') NOT NULL DEFAULT 'N',
    featured     ENUM('Y','N') NOT NULL DEFAULT 'N',
    custom       ENUM('Y','N') NOT NULL DEFAULT 'N',
    approved     ENUM('Y','N'),
    approved_by  INT UNSIGNED,
    approved_why MEDIUMTEXT,
    description  MEDIUMTEXT,
    cost         INT UNSIGNED NOT NULL DEFAULT 0,
    mime_small   VARCHAR(255),
    mime_large   VARCHAR(255),

    UNIQUE KEY (name)
)
EOC

register_tablecreate( "vgift_counts", <<'EOC');
CREATE TABLE vgift_counts (
    vgiftid    INT UNSIGNED NOT NULL,
    count      INT UNSIGNED NOT NULL DEFAULT 0,

    PRIMARY KEY (vgiftid)
)
EOC

register_tablecreate( "vgift_tags", <<'EOC');
CREATE TABLE vgift_tags (
    tagid      INT UNSIGNED NOT NULL,
    vgiftid    INT UNSIGNED NOT NULL,

    PRIMARY KEY (tagid, vgiftid),
    INDEX (vgiftid),
    INDEX (tagid)
)
EOC

register_tablecreate( "vgift_tagpriv", <<'EOC');
CREATE TABLE vgift_tagpriv (
    tagid      INT UNSIGNED NOT NULL,
    prlid      SMALLINT UNSIGNED NOT NULL,
    arg        VARCHAR(40),

    PRIMARY KEY (tagid, prlid, arg),
    INDEX (tagid)
)
EOC

register_tablecreate( "vgift_trans", <<'EOC');
CREATE TABLE vgift_trans (
    transid    INT UNSIGNED NOT NULL,
    buyerid    INT UNSIGNED NOT NULL DEFAULT 0,
    rcptid     INT UNSIGNED NOT NULL,
    vgiftid    INT UNSIGNED NOT NULL,
    cartid     INT UNSIGNED,
    delivery_t INT UNSIGNED NOT NULL,  #unixtime
    delivered  ENUM('Y','N') NOT NULL DEFAULT 'N',
    accepted   ENUM('Y','N') NOT NULL DEFAULT 'N',
    expired    ENUM('Y','N') NOT NULL DEFAULT 'N',

    PRIMARY KEY (rcptid, transid),
    INDEX (delivery_t),
    INDEX (vgiftid)
)
EOC

register_tablecreate( "authactions", <<'EOC');
CREATE TABLE authactions (
    aaid int(10) unsigned NOT NULL auto_increment,
    userid int(10) unsigned NOT NULL default '0',
    datecreate datetime NOT NULL default '0000-00-00 00:00:00',
    authcode varchar(20) default NULL,
    action varchar(50) default NULL,
    arg1 varchar(255) default NULL,

    PRIMARY KEY  (aaid)
)
EOC

register_tablecreate( "birthdays", <<'EOC');
CREATE TABLE birthdays (
    userid INT UNSIGNED NOT NULL,
    nextbirthday INT UNSIGNED,

    PRIMARY KEY (userid),
    KEY (nextbirthday)
)
EOC

register_tablecreate( "clients", <<'EOC');
CREATE TABLE clients (
    clientid smallint(5) unsigned NOT NULL auto_increment,
    client varchar(40) default NULL,

    PRIMARY KEY  (clientid),
    KEY (client)
)
EOC

register_tablecreate( "clientusage", <<'EOC');
CREATE TABLE clientusage (
    userid int(10) unsigned NOT NULL default '0',
    clientid smallint(5) unsigned NOT NULL default '0',
    lastlogin datetime NOT NULL default '0000-00-00 00:00:00',

    PRIMARY KEY  (clientid,userid),
    UNIQUE KEY userid (userid,clientid)
)
EOC

register_tablecreate( "codes", <<'EOC');
CREATE TABLE codes (
    type varchar(10) NOT NULL default '',
    code varchar(7) NOT NULL default '',
    item varchar(80) default NULL,
    sortorder smallint(6) NOT NULL default '0',

    PRIMARY KEY  (type,code)
) PACK_KEYS=1
EOC

register_tablecreate( "community", <<'EOC');
CREATE TABLE community (
    userid int(10) unsigned NOT NULL default '0',
    ownerid int(10) unsigned NOT NULL default '0',
    membership enum('open','closed') NOT NULL default 'open',
    postlevel enum('members','select','screened') default NULL,

    PRIMARY KEY  (userid)
)
EOC

register_tablecreate( "duplock", <<'EOC');
CREATE TABLE duplock (
    realm enum('support','log','comment') NOT NULL default 'support',
    reid int(10) unsigned NOT NULL default '0',
    userid int(10) unsigned NOT NULL default '0',
    digest char(32) NOT NULL default '',
    dupid int(10) unsigned NOT NULL default '0',
    instime datetime NOT NULL default '0000-00-00 00:00:00',

    KEY (realm,reid,userid)
)
EOC

register_tablecreate( "faq", <<'EOC');
CREATE TABLE faq (
    faqid mediumint(8) unsigned NOT NULL auto_increment,
    question text,
    answer text,
    sortorder int(11) default NULL,
    faqcat varchar(20) default NULL,
    lastmodtime datetime default NULL,
    lastmoduserid int(10) unsigned NOT NULL default '0',

    PRIMARY KEY  (faqid)
)
EOC

register_tablecreate( "faqcat", <<'EOC');
CREATE TABLE faqcat (
    faqcat varchar(20) NOT NULL default '',
    faqcatname varchar(100) default NULL,
    catorder int(11) default '50',

    PRIMARY KEY  (faqcat)
)
EOC

register_tablecreate( "faquses", <<'EOC');
CREATE TABLE faquses (
    faqid MEDIUMINT UNSIGNED NOT NULL,
    userid INT UNSIGNED NOT NULL,
    dateview DATETIME NOT NULL,

    PRIMARY KEY (userid, faqid),
    KEY (faqid),
    KEY (dateview)
)
EOC

register_tablecreate( "wt_edges", <<'EOC');
CREATE TABLE wt_edges (
    from_userid int(10) unsigned NOT NULL default '0',
    to_userid int(10) unsigned NOT NULL default '0',
    fgcolor mediumint unsigned NOT NULL default '0',
    bgcolor mediumint unsigned NOT NULL default '16777215',
    groupmask bigint(20) unsigned NOT NULL default '1',
    showbydefault enum('1','0') NOT NULL default '1',

    PRIMARY KEY  (from_userid,to_userid),
    KEY (to_userid)
)
EOC

register_tablecreate( "interests", <<'EOC');
CREATE TABLE interests (
    intid int(10) unsigned NOT NULL,
    intcount mediumint(8) unsigned default NULL,

    PRIMARY KEY  (intid)
)
EOC

register_tablecreate( "logproplist", <<'EOC');
CREATE TABLE logproplist (
    propid tinyint(3) unsigned NOT NULL auto_increment,
    name varchar(50) default NULL,
    prettyname varchar(60) default NULL,
    sortorder mediumint(8) unsigned default NULL,
    datatype enum('char','num','bool') NOT NULL default 'char',
    scope enum('general', 'local') NOT NULL default 'general',
    ownership ENUM('system', 'user') NOT NULL default 'user',
    des varchar(255) default NULL,

    PRIMARY KEY  (propid),
    UNIQUE KEY name (name)
)
EOC

register_tablecreate( "moods", <<'EOC');
CREATE TABLE moods (
    moodid int(10) unsigned NOT NULL auto_increment,
    mood varchar(40) default NULL,
    parentmood int(10) unsigned NOT NULL default '0',
    weight tinyint unsigned default NULL,

    PRIMARY KEY  (moodid),
    UNIQUE KEY mood (mood)
)
EOC

register_tablecreate( "moodthemedata", <<'EOC');
CREATE TABLE moodthemedata (
    moodthemeid int(10) unsigned NOT NULL default '0',
    moodid int(10) unsigned NOT NULL default '0',
    picurl varchar(200) default NULL,
    width tinyint(3) unsigned NOT NULL default '0',
    height tinyint(3) unsigned NOT NULL default '0',

    PRIMARY KEY  (moodthemeid,moodid)
)
EOC

register_tablecreate( "moodthemes", <<'EOC');
CREATE TABLE moodthemes (
    moodthemeid int(10) unsigned NOT NULL auto_increment,
    ownerid int(10) unsigned NOT NULL default '0',
    name varchar(50) default NULL,
    des varchar(100) default NULL,
    is_public enum('Y','N') NOT NULL default 'N',

    PRIMARY KEY  (moodthemeid),
    KEY (is_public),
    KEY (ownerid)
)
EOC

register_tablecreate( "noderefs", <<'EOC');
CREATE TABLE noderefs (
    nodetype char(1) NOT NULL default '',
    nodeid int(10) unsigned NOT NULL default '0',
    urlmd5 varchar(32) NOT NULL default '',
    url varchar(120) NOT NULL default '',

    PRIMARY KEY  (nodetype,nodeid,urlmd5)
)
EOC

register_tablecreate( "pendcomments", <<'EOC');
CREATE TABLE pendcomments (
    jid int(10) unsigned NOT NULL,
    pendcid int(10) unsigned NOT NULL,
    data blob NOT NULL,
    datesubmit int(10) unsigned NOT NULL,

    PRIMARY KEY (pendcid, jid),
    KEY (datesubmit)
)
EOC

register_tablecreate( "priv_list", <<'EOC');
CREATE TABLE priv_list (
    prlid smallint(5) unsigned NOT NULL auto_increment,
    privcode varchar(20) NOT NULL default '',
    privname varchar(40) default NULL,
    des varchar(255) default NULL,
    is_public ENUM('1', '0') DEFAULT '1' NOT NULL,

    PRIMARY KEY  (prlid),
    UNIQUE KEY privcode (privcode)
)
EOC

register_tablecreate( "priv_map", <<'EOC');
CREATE TABLE priv_map (
    prmid mediumint(8) unsigned NOT NULL auto_increment,
    userid int(10) unsigned NOT NULL default '0',
    prlid smallint(5) unsigned NOT NULL default '0',
    arg varchar(40) default NULL,

    PRIMARY KEY  (prmid),
    KEY (userid),
    KEY (prlid)
)
EOC

register_tablecreate( "random_user_set", <<'EOC');
CREATE TABLE random_user_set (
    posttime INT UNSIGNED NOT NULL,
    userid INT UNSIGNED NOT NULL,
    journaltype char(1) NOT NULL default 'P',

    PRIMARY KEY (userid),
    INDEX (posttime)
)
EOC

register_tablecreate( "statkeylist", <<'EOC');
CREATE TABLE statkeylist (
    statkeyid  int unsigned NOT NULL auto_increment,
    name       varchar(255) default NULL,

    PRIMARY KEY (statkeyid),
    UNIQUE KEY (name)
)
EOC

register_tablecreate( "site_stats", <<'EOC');
CREATE TABLE site_stats (
    category_id INT UNSIGNED NOT NULL,
    key_id INT UNSIGNED NOT NULL,
    insert_time INT UNSIGNED NOT NULL,
    value INT UNSIGNED NOT NULL,

    -- FIXME: This is good for retrieving data for a single category+key, but
    -- maybe not as good if we want all keys for the category, with a limit on
    -- time (ie, last 5 entries, or last 2 weeks). Do we need an extra index?
    INDEX (category_id, key_id, insert_time)
)
EOC

register_tablecreate( "stats", <<'EOC');
CREATE TABLE stats (
    statcat varchar(30) NOT NULL,
    statkey varchar(150) NOT NULL,
    statval int(10) unsigned NOT NULL,

    UNIQUE KEY statcat_2 (statcat,statkey)
)
EOC

register_tablecreate( "blobcache", <<'EOC');
CREATE TABLE blobcache (
    bckey VARCHAR(40) NOT NULL,
    PRIMARY KEY (bckey),
    dateupdate  DATETIME,
    value    MEDIUMBLOB
)
EOC

register_tablecreate( "support", <<'EOC');
CREATE TABLE support (
    spid int(10) unsigned NOT NULL auto_increment,
    reqtype enum('user','email') default NULL,
    requserid int(10) unsigned NOT NULL default '0',
    reqname varchar(50) default NULL,
    reqemail varchar(70) default NULL,
    state enum('open','closed') default NULL,
    authcode varchar(15) NOT NULL default '',
    spcatid int(10) unsigned NOT NULL default '0',
    subject varchar(80) default NULL,
    timecreate int(10) unsigned default NULL,
    timetouched int(10) unsigned default NULL,
    timemodified int(10) unsigned default NULL,
    timeclosed int(10) unsigned default NULL,

    PRIMARY KEY  (spid),
    INDEX (state),
    INDEX (requserid),
    INDEX (reqemail)
)
EOC

register_tablecreate( "supportcat", <<'EOC');
CREATE TABLE supportcat (
    spcatid int(10) unsigned NOT NULL auto_increment,
    catkey VARCHAR(25) NOT NULL,
    catname varchar(80) default NULL,
    sortorder mediumint(8) unsigned NOT NULL default '0',
    basepoints tinyint(3) unsigned NOT NULL default '1',
    is_selectable ENUM('1','0') NOT NULL DEFAULT '1',
    public_read  ENUM('1','0') NOT NULL DEFAULT '1',
    public_help ENUM('1','0') NOT NULL DEFAULT '1',
    allow_screened ENUM('1','0') NOT NULL DEFAULT '0',
    hide_helpers ENUM('1','0') NOT NULL DEFAULT '0',
    user_closeable ENUM('1', '0') NOT NULL DEFAULT '1',
    replyaddress VARCHAR(50),
    no_autoreply ENUM('1', '0') NOT NULL DEFAULT '0',
    scope ENUM('general', 'local') NOT NULL DEFAULT 'general',

    PRIMARY KEY  (spcatid),
    UNIQUE (catkey)
)
EOC

register_tablecreate( "supportlog", <<'EOC');
CREATE TABLE supportlog (
    splid int(10) unsigned NOT NULL auto_increment,
    spid int(10) unsigned NOT NULL default '0',
    timelogged int(10) unsigned NOT NULL default '0',
    type enum('req','custom','faqref') default NULL,
    faqid mediumint(8) unsigned NOT NULL default '0',
    userid int(10) unsigned NOT NULL default '0',
    message text,

    PRIMARY KEY  (splid),
    KEY (spid)
)
EOC

register_tablecreate( "supportnotify", <<'EOC');
CREATE TABLE supportnotify (
    spcatid int(10) unsigned NOT NULL default '0',
    userid int(10) unsigned NOT NULL default '0',
    level enum('all','new') default NULL,

    KEY (spcatid),
    KEY (userid),
    PRIMARY KEY  (spcatid,userid)
)
EOC

register_tablecreate( "supportpoints", <<'EOC');
CREATE TABLE supportpoints (
    spid int(10) unsigned NOT NULL default '0',
    userid int(10) unsigned NOT NULL default '0',
    points tinyint(3) unsigned default NULL,

    KEY (spid),
    KEY (userid)
)
EOC

register_tablecreate( "supportpointsum", <<'EOC');
CREATE TABLE supportpointsum (
    userid INT UNSIGNED NOT NULL DEFAULT '0',
    PRIMARY KEY (userid),
    totpoints MEDIUMINT UNSIGNED DEFAULT 0,
    lastupdate  INT UNSIGNED NOT NULL,

    INDEX (totpoints, lastupdate),
    INDEX (lastupdate)
)
EOC

post_create( "supportpointsum",
          "sqltry" => "INSERT IGNORE INTO supportpointsum (userid, totpoints, lastupdate) "
        . "SELECT userid, SUM(points), 0 FROM supportpoints GROUP BY userid" );

register_tablecreate( "talkproplist", <<'EOC');
CREATE TABLE talkproplist (
    tpropid smallint(5) unsigned NOT NULL auto_increment,
    name varchar(50) default NULL,
    prettyname varchar(60) default NULL,
    datatype enum('char','num','bool') NOT NULL default 'char',
    scope enum('general', 'local') NOT NULL default 'general',
    ownership ENUM('system', 'user') NOT NULL default 'user',
    des varchar(255) default NULL,

    PRIMARY KEY  (tpropid),
    UNIQUE KEY name (name)
)
EOC

register_tablecreate( "user", <<'EOC');
CREATE TABLE user (
    userid int(10) unsigned NOT NULL auto_increment,
    user char(25) default NULL,
    caps SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    email char(50) default NULL,
    password char(30) default NULL,
    status char(1) NOT NULL default 'N',
    statusvis char(1) NOT NULL default 'V',
    statusvisdate datetime default NULL,
    name char(50) default NULL,
    bdate date default NULL,
    themeid int(11) NOT NULL default '1',
    moodthemeid int(10) unsigned NOT NULL default '1',
    opt_forcemoodtheme enum('Y','N') NOT NULL default 'N',
    allow_infoshow char(1) NOT NULL default 'Y',
    allow_contactshow char(1) NOT NULL default 'Y',
    allow_getljnews char(1) NOT NULL default 'N',
    opt_showtalklinks char(1) NOT NULL default 'Y',
    opt_whocanreply enum('all','reg','friends') NOT NULL default 'all',
    opt_gettalkemail char(1) NOT NULL default 'Y',
    opt_htmlemail enum('Y','N') NOT NULL default 'Y',
    opt_mangleemail char(1) NOT NULL default 'N',
    useoverrides char(1) NOT NULL default 'N',
    defaultpicid int(10) unsigned default NULL,
    has_bio enum('Y','N') NOT NULL default 'N',
    is_system enum('Y','N') NOT NULL default 'N',
    journaltype char(1) NOT NULL default 'P',
    lang char(2) NOT NULL default 'EN',

    PRIMARY KEY  (userid),
    UNIQUE KEY user (user),
    KEY (email),
    KEY (status),
    KEY (statusvis)
)  PACK_KEYS=1
EOC

register_tablecreate( "userbio", <<'EOC');
CREATE TABLE userbio (
    userid int(10) unsigned NOT NULL default '0',
    bio text,

    PRIMARY KEY  (userid)
)
EOC

register_tablecreate( "userinterests", <<'EOC');
CREATE TABLE userinterests (
    userid int(10) unsigned NOT NULL default '0',
    intid int(10) unsigned NOT NULL default '0',

    PRIMARY KEY  (userid,intid),
    KEY (intid)
)
EOC

register_tablecreate( "userpicblob2", <<'EOC');
CREATE TABLE userpicblob2 (
    userid int unsigned not null,
    picid int unsigned not null,
    imagedata blob,

    PRIMARY KEY (userid, picid)
) max_rows=10000000
EOC

register_tablecreate( "userpicmap2", <<'EOC');
CREATE TABLE userpicmap2 (
    userid int(10) unsigned NOT NULL default '0',
    kwid int(10) unsigned NOT NULL default '0',
    picid int(10) unsigned NOT NULL default '0',

    PRIMARY KEY  (userid, kwid)
)
EOC

register_tablecreate( "userpicmap3", <<'EOC');
CREATE TABLE userpicmap3 (
    userid int(10) unsigned NOT NULL default '0',
    mapid int(10) unsigned NOT NULL,
    kwid int(10) unsigned,
    picid int(10) unsigned,
    redirect_mapid int(10) unsigned,

    PRIMARY KEY (userid, mapid),
    UNIQUE KEY  (userid, kwid),
    INDEX redirect (userid, redirect_mapid)
)
EOC

register_tablecreate( "userpic2", <<'EOC');
CREATE TABLE userpic2 (
    picid int(10) unsigned NOT NULL,
    userid int(10) unsigned NOT NULL default '0',
    fmt char(1) default NULL,
    width smallint(6) NOT NULL default '0',
    height smallint(6) NOT NULL default '0',
    state char(1) NOT NULL default 'N',
    picdate datetime default NULL,
    md5base64 char(22) NOT NULL default '',
    comment varchar(255) BINARY NOT NULL default '',
    description varchar(600) BINARY NOT NULL default '',
    flags tinyint(1) unsigned NOT NULL default 0,
    location enum('blob','disk','mogile','blobstore') default NULL,

    PRIMARY KEY  (userid, picid)
)
EOC

register_tablecreate( "userproplist", <<'EOC');
CREATE TABLE userproplist (
    upropid smallint(5) unsigned NOT NULL auto_increment,
    name varchar(50) default NULL,
    indexed enum('1','0') NOT NULL default '1',
    prettyname varchar(60) default NULL,
    datatype enum('char','num','bool') NOT NULL default 'char',
    des varchar(255) default NULL,

    PRIMARY KEY  (upropid),
    UNIQUE KEY name (name)
)
EOC

# global, indexed
register_tablecreate( "userprop", <<'EOC');
CREATE TABLE userprop (
    userid int(10) unsigned NOT NULL default '0',
    upropid smallint(5) unsigned NOT NULL default '0',
    value varchar(60) default NULL,

    PRIMARY KEY  (userid,upropid),
    KEY (upropid,value)
)
EOC

# global, not indexed
register_tablecreate( "userproplite", <<'EOC');
CREATE TABLE userproplite (
    userid int(10) unsigned NOT NULL default '0',
    upropid smallint(5) unsigned NOT NULL default '0',
    value varchar(255) default NULL,

    PRIMARY KEY  (userid,upropid),
    KEY (upropid)
)
EOC

# clustered, not indexed
register_tablecreate( "userproplite2", <<'EOC');
CREATE TABLE userproplite2 (
    userid int(10) unsigned NOT NULL default '0',
    upropid smallint(5) unsigned NOT NULL default '0',
    value varchar(255) default NULL,

    PRIMARY KEY  (userid,upropid),
    KEY (upropid)
)
EOC

# clustered
register_tablecreate( "userpropblob", <<'EOC');
CREATE TABLE userpropblob (
    userid INT(10) unsigned NOT NULL default '0',
    upropid SMALLINT(5) unsigned NOT NULL default '0',
    value blob,

    PRIMARY KEY (userid,upropid)
)
EOC

################# above was a snapshot.  now, changes:

register_tablecreate( "log2", <<'EOC');
CREATE TABLE log2 (
    journalid INT UNSIGNED NOT NULL default '0',
    jitemid MEDIUMINT UNSIGNED NOT NULL,
    PRIMARY KEY  (journalid, jitemid),
    posterid int(10) unsigned NOT NULL default '0',
    eventtime datetime default NULL,
    logtime datetime default NULL,
    compressed char(1) NOT NULL default 'N',
    anum TINYINT UNSIGNED NOT NULL,
    security enum('public','private','usemask') NOT NULL default 'public',
    allowmask bigint(20) unsigned NOT NULL default '0',
    replycount smallint(5) unsigned default NULL,
    year smallint(6) NOT NULL default '0',
    month tinyint(4) NOT NULL default '0',
    day tinyint(4) NOT NULL default '0',
    rlogtime int(10) unsigned NOT NULL default '0',
    revttime int(10) unsigned NOT NULL default '0',

    KEY (journalid,year,month,day),
    KEY `rlogtime` (`journalid`,`rlogtime`),
    KEY `revttime` (`journalid`,`revttime`),
    KEY `posterid` (`posterid`,`journalid`)
)
EOC

register_tablecreate( "logtext2", <<'EOC');
CREATE TABLE logtext2 (
    journalid INT UNSIGNED NOT NULL,
    jitemid MEDIUMINT UNSIGNED NOT NULL,
    subject VARCHAR(255) DEFAULT NULL,
    event MEDIUMTEXT,

    PRIMARY KEY (journalid, jitemid)
) max_rows=100000000
EOC

register_tablecreate( "logprop2", <<'EOC');
CREATE TABLE logprop2 (
    journalid  INT UNSIGNED NOT NULL,
    jitemid MEDIUMINT UNSIGNED NOT NULL,
    propid TINYINT unsigned NOT NULL,
    value VARCHAR(255) default NULL,

    PRIMARY KEY (journalid,jitemid,propid)
)
EOC

register_tablecreate( "logsec2", <<'EOC');
CREATE TABLE logsec2 (
    journalid INT UNSIGNED NOT NULL,
    jitemid MEDIUMINT UNSIGNED NOT NULL,
    allowmask BIGINT UNSIGNED NOT NULL,

    PRIMARY KEY (journalid,jitemid)
)
EOC

register_tablecreate( "talk2", <<'EOC');
CREATE TABLE talk2 (
    journalid INT UNSIGNED NOT NULL,
    jtalkid INT UNSIGNED NOT NULL,
    nodetype CHAR(1) NOT NULL DEFAULT '',
    nodeid INT UNSIGNED NOT NULL default '0',
    parenttalkid MEDIUMINT UNSIGNED NOT NULL,
    posterid INT UNSIGNED NOT NULL default '0',
    datepost DATETIME NOT NULL default '0000-00-00 00:00:00',
    state CHAR(1) default 'A',

    PRIMARY KEY  (journalid,jtalkid),
    KEY (nodetype,journalid,nodeid),
    KEY (journalid,state,nodetype),
    KEY (posterid)
)
EOC

register_tablecreate( "talkprop2", <<'EOC');
CREATE TABLE talkprop2 (
    journalid INT UNSIGNED NOT NULL,
    jtalkid INT UNSIGNED NOT NULL,
    tpropid TINYINT UNSIGNED NOT NULL,
    value VARCHAR(255) DEFAULT NULL,

    PRIMARY KEY  (journalid,jtalkid,tpropid)
)
EOC

register_tablecreate( "talktext2", <<'EOC');
CREATE TABLE talktext2 (
    journalid INT UNSIGNED NOT NULL,
    jtalkid INT UNSIGNED NOT NULL,
    subject VARCHAR(100) DEFAULT NULL,
    body TEXT,

    PRIMARY KEY (journalid, jtalkid)
) max_rows=100000000
EOC

register_tablecreate( "talkleft", <<'EOC');
CREATE TABLE talkleft (
    userid    INT UNSIGNED NOT NULL,
    posttime  INT UNSIGNED NOT NULL,
    INDEX (userid, posttime),
    journalid  INT UNSIGNED NOT NULL,
    nodetype   CHAR(1) NOT NULL,
    nodeid     INT UNSIGNED NOT NULL,
    INDEX (journalid, nodetype, nodeid),
    jtalkid    INT UNSIGNED NOT NULL,
    publicitem   ENUM('1','0') NOT NULL DEFAULT '1'
)
EOC

register_tablecreate( "talkleft_xfp", <<'EOC');
CREATE TABLE talkleft_xfp (
    userid    INT UNSIGNED NOT NULL,
    posttime  INT UNSIGNED NOT NULL,
    INDEX (userid, posttime),
    journalid  INT UNSIGNED NOT NULL,
    nodetype   CHAR(1) NOT NULL,
    nodeid     INT UNSIGNED NOT NULL,
    INDEX (journalid, nodetype, nodeid),
    jtalkid    INT UNSIGNED NOT NULL,
    publicitem   ENUM('1','0') NOT NULL DEFAULT '1'
)
EOC

register_tabledrop("ibill_codes");
register_tabledrop("paycredit");
register_tabledrop("payments");
register_tabledrop("tmp_contributed");
register_tabledrop("transferinfo");
register_tabledrop("contest1");
register_tabledrop("contest1data");
register_tabledrop("logins");
register_tabledrop("hintfriendsview");
register_tabledrop("hintlastnview");
register_tabledrop("batchdelete");
register_tabledrop("ftpusers");
register_tabledrop("ipban");
register_tabledrop("ban");
register_tabledrop("logaccess");
register_tabledrop("fvcache");
register_tabledrop("userpic_comment");
register_tabledrop("events");
register_tabledrop("randomuserset");
register_tabledrop("todo");
register_tabledrop("tododep");
register_tabledrop("todokeyword");
register_tabledrop("friends");
register_tabledrop("friendgroup");
register_tabledrop("friendgroup2");
register_tabledrop("vertical_rules");
register_tabledrop("vertical_editorials");
register_tabledrop("vertical_entries");
register_tabledrop("vertical");
register_tabledrop("news_sent");
register_tabledrop("overrides");
register_tabledrop("s1usercache");
register_tabledrop("s1overrides");
register_tabledrop("s1style");
register_tabledrop("s1stylemap");
register_tabledrop("s1stylecache");
register_tabledrop("weekuserusage");
register_tabledrop("themedata");
register_tabledrop("themelist");
register_tabledrop("style");
register_tabledrop("meme");
register_tabledrop("content_flag");
register_tabledrop("dw_payments");
register_tabledrop("dw_pp_details");
register_tabledrop("dw_pp_log");
register_tabledrop("dw_pp_notify_log");
register_tabledrop("smsusermap");
register_tabledrop("smsuniqmap");
register_tabledrop("sms_msg");
register_tabledrop("sms_msgack");
register_tabledrop("sms_msgtext");
register_tabledrop("sms_msgerror");
register_tabledrop("sms_msgprop");
register_tabledrop("sms_msgproplist");
register_tabledrop("knob");
register_tabledrop("zips");
register_tabledrop("adopt");
register_tabledrop("adoptlast");
register_tabledrop("urimap");
register_tabledrop("syndicated_hubbub");
register_tabledrop("oldids");
register_tabledrop("keywords");
register_tabledrop("poll");
register_tabledrop("pollitem");
register_tabledrop("pollquestion");
register_tabledrop("pollresult");
register_tabledrop("pollsubmission");
register_tabledrop("portal");
register_tabledrop("portal_box_prop");
register_tabledrop("portal_config");
register_tabledrop("portal_typemap");
register_tabledrop("memkeyword");
register_tabledrop("memorable");
register_tabledrop("s2source");
register_tabledrop("s2stylelayers");
register_tabledrop("userpic");
register_tabledrop("userpicmap");
register_tabledrop("schools");
register_tabledrop("schools_attended");
register_tabledrop("schools_pending");
register_tabledrop("user_schools");
register_tabledrop("userblob");
register_tabledrop("userblobcache");
register_tabledrop("commenturls");
register_tabledrop("captchas");
register_tabledrop("captcha_session");
register_tabledrop("qotd");
register_tabledrop("zip");
register_tabledrop("openid_external");
register_tabledrop("site_messages");
register_tabledrop("navtag");
register_tabledrop("syndicated_hubbub2");
register_tabledrop("openproxy");
register_tabledrop("tor_proxy_exits");
register_tabledrop("cmdbuffer");
register_tabledrop("schemacols");
register_tabledrop("schematables");
register_tabledrop("blockwatch_events");
register_tabledrop("cprodlist");
register_tabledrop("cprod");
register_tabledrop("jabroster");
register_tabledrop("jabpresence");
register_tabledrop("jabcluster");
register_tabledrop("jablastseen");
register_tabledrop("domains");
register_tabledrop("pollprop2");
register_tabledrop("pollproplist2");
register_tabledrop("dirsearchres2");
register_tabledrop("txtmsg");
register_tabledrop("comm_promo_list");
register_tabledrop("incoming_email_handle");
register_tabledrop("backupdirty");
register_tabledrop("actionhistory");
register_tabledrop("recentactions");

register_tablecreate( "infohistory", <<'EOC');
CREATE TABLE infohistory (
    userid int(10) unsigned NOT NULL default '0',
    what varchar(15) NOT NULL default '',
    timechange datetime NOT NULL default '0000-00-00 00:00:00',
    oldvalue varchar(255) default NULL,
    other varchar(30) default NULL,

    KEY userid (userid)
)
EOC

register_tablecreate( "useridmap", <<'EOC');
CREATE TABLE useridmap (
    userid int(10) unsigned NOT NULL,
    user char(25) NOT NULL,

    PRIMARY KEY  (userid),
    UNIQUE KEY user (user)
)
EOC

post_create( "useridmap",
    "sqltry" => "REPLACE INTO useridmap (userid, user) SELECT userid, user FROM user" );

register_tablecreate( "userusage", <<'EOC');
CREATE TABLE userusage (
    userid INT UNSIGNED NOT NULL,
    PRIMARY KEY (userid),
    timecreate DATETIME NOT NULL,
    timeupdate DATETIME,
    timecheck DATETIME,
    lastitemid INT UNSIGNED NOT NULL DEFAULT '0',

    INDEX (timeupdate)
)
EOC

post_create(
    "userusage",
    "sqltry" =>
"INSERT IGNORE INTO userusage (userid, timecreate, timeupdate, timecheck, lastitemid) SELECT userid, timecreate, timeupdate, timecheck, lastitemid FROM user",
    "sqltry" => "ALTER TABLE user DROP timecreate, DROP timeupdate, DROP timecheck, DROP lastitemid"
);

register_tablecreate( "acctcode", <<'EOC');
CREATE TABLE acctcode (
    acid    INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    userid  INT UNSIGNED NOT NULL,
    rcptid  INT UNSIGNED NOT NULL DEFAULT 0,
    auth    CHAR(13) NOT NULL,
    timegenerate INT UNSIGNED NOT NULL,
    timesent INT UNSIGNED,
    email   VARCHAR(255),
    reason  VARCHAR(255),

    INDEX (userid),
    INDEX (rcptid)
)
EOC

register_tablecreate( "acctcode_request", <<'EOC');
CREATE TABLE acctcode_request (
    reqid   INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    userid  INT UNSIGNED NOT NULL,
    status ENUM('accepted','rejected', 'outstanding') NOT NULL DEFAULT 'outstanding',
    reason VARCHAR(255),
    timegenerate    INT UNSIGNED NOT NULL,
    timeprocessed   INT UNSIGNED,

    INDEX (userid)
)
EOC

register_tablecreate( "statushistory", <<'EOC');
CREATE TABLE statushistory (
    userid    INT UNSIGNED NOT NULL,
    adminid   INT UNSIGNED NOT NULL,
    shtype    VARCHAR(20) NOT NULL,
    shdate    TIMESTAMP NOT NULL,
    notes     TEXT,

    INDEX (userid, shdate),
    INDEX (adminid, shdate),
    INDEX (adminid, shtype, shdate),
    INDEX (shtype, shdate)
)
EOC

register_tablecreate( "includetext", <<'EOC');
CREATE TABLE includetext (
    incname  VARCHAR(80) NOT NULL PRIMARY KEY,
    inctext  TEXT,
    updatetime   INT UNSIGNED NOT NULL,

    INDEX (updatetime)
)
EOC

register_tablecreate( "dudata", <<'EOC');
CREATE TABLE dudata (
    userid   INT UNSIGNED NOT NULL,
    area     CHAR(1) NOT NULL,
    areaid   INT UNSIGNED NOT NULL,
    bytes    MEDIUMINT UNSIGNED NOT NULL,

    PRIMARY KEY (userid, area, areaid)
)
EOC

register_tablecreate( "dbinfo", <<'EOC');
CREATE TABLE dbinfo (
    dbid    TINYINT UNSIGNED NOT NULL,
    name    VARCHAR(25),
    fdsn      VARCHAR(255),
    rootfdsn  VARCHAR(255),
    masterid  TINYINT UNSIGNED NOT NULL,

    PRIMARY KEY (dbid),
    UNIQUE (name)
)
EOC

register_tablecreate( "dbweights", <<'EOC');
CREATE TABLE dbweights (
    dbid    TINYINT UNSIGNED NOT NULL,
    role    VARCHAR(25) NOT NULL,
    PRIMARY KEY (dbid, role),
    norm    TINYINT UNSIGNED NOT NULL,
    curr    TINYINT UNSIGNED NOT NULL
)
EOC

# Begin S2 Stuff
register_tablecreate( "s2layers", <<'EOC');    # global
CREATE TABLE s2layers (
    s2lid INT UNSIGNED NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (s2lid),
    b2lid INT UNSIGNED NOT NULL,
    userid INT UNSIGNED NOT NULL,
    type ENUM('core','i18nc','layout','theme','i18n','user') NOT NULL,

    INDEX (userid),
    INDEX (b2lid, type)
)
EOC

register_tablecreate( "s2info", <<'EOC');    # global
CREATE TABLE s2info (
    s2lid INT UNSIGNED NOT NULL,
    infokey   VARCHAR(80) NOT NULL,
    value VARCHAR(255) NOT NULL,

    PRIMARY KEY (s2lid, infokey)
)
EOC

register_tablecreate( "s2source_inno", <<'EOC');    # global
CREATE TABLE s2source_inno (
    s2lid INT UNSIGNED NOT NULL,
    PRIMARY KEY (s2lid),
    s2code MEDIUMBLOB
) ENGINE=InnoDB
EOC

register_tablecreate( "s2checker", <<'EOC');        # global
CREATE TABLE s2checker (
    s2lid INT UNSIGNED NOT NULL,
    PRIMARY KEY (s2lid),
    checker MEDIUMBLOB
)
EOC

# the original global s2compiled table.  see comment below for new version.
register_tablecreate( "s2compiled", <<'EOC');       # global (compdata is not gzipped)
CREATE TABLE s2compiled (
    s2lid INT UNSIGNED NOT NULL,
    PRIMARY KEY (s2lid),
    comptime INT UNSIGNED NOT NULL,
    compdata MEDIUMBLOB
)
EOC

# s2compiled2 is only for user S2 layers (not system) and is lazily
# migrated.  new saves go here.  loads try this table first (unless
# system) and if miss, then try the s2compiled table on the global.
register_tablecreate( "s2compiled2", <<'EOC');    # clustered (compdata is gzipped)
CREATE TABLE s2compiled2 (
    userid INT UNSIGNED NOT NULL,
    s2lid INT UNSIGNED NOT NULL,
    PRIMARY KEY (userid, s2lid),

    comptime INT UNSIGNED NOT NULL,
    compdata MEDIUMBLOB
)
EOC

register_tablecreate( "s2styles", <<'EOC');       # global
CREATE TABLE s2styles (
    styleid INT UNSIGNED NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (styleid),
    userid  INT UNSIGNED NOT NULL,
    name    VARCHAR(255),
    modtime INT UNSIGNED NOT NULL,

    INDEX (userid)
)
EOC

register_tablecreate( "s2stylelayers2", <<'EOC'); # clustered
CREATE TABLE s2stylelayers2 (
    userid  INT UNSIGNED NOT NULL,
    styleid INT UNSIGNED NOT NULL,
    type ENUM('core','i18nc','layout','theme','i18n','user') NOT NULL,
    PRIMARY KEY (userid, styleid, type),
    s2lid INT UNSIGNED NOT NULL
)
EOC

register_tablecreate( "s2categories", <<'EOC');   # global
CREATE TABLE s2categories (
    s2lid INT UNSIGNED NOT NULL,
    kwid INT(10) UNSIGNED NOT NULL,
    active TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,

    PRIMARY KEY (s2lid, kwid)
)
EOC

register_tablecreate( "ml_domains", <<'EOC');
CREATE TABLE ml_domains (
    dmid TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (dmid),
    type VARCHAR(30) NOT NULL,
    args VARCHAR(255) NOT NULL DEFAULT '',

    UNIQUE (type,args)
)
EOC

register_tablecreate( "ml_items", <<'EOC');
CREATE TABLE ml_items (
    dmid    TINYINT UNSIGNED NOT NULL,
    itid    MEDIUMINT UNSIGNED AUTO_INCREMENT NOT NULL,
    PRIMARY KEY (dmid, itid),
    itcode  VARCHAR(120) CHARACTER SET ascii NOT NULL,
    UNIQUE  (dmid, itcode),
    proofed TINYINT NOT NULL DEFAULT 0, -- boolean, really
    INDEX   (proofed),
    updated TINYINT NOT NULL DEFAULT 0, -- boolean, really
    INDEX   (updated),
    visible TINYINT NOT NULL DEFAULT 0, -- also boolean
    notes   MEDIUMTEXT
) ENGINE=MYISAM
EOC

register_tablecreate( "ml_langs", <<'EOC');
CREATE TABLE ml_langs (
    lnid      SMALLINT UNSIGNED NOT NULL,
    UNIQUE (lnid),
    lncode   VARCHAR(16) NOT NULL,  # en_US en_LJ en ch_HK ch_B5 etc... de_DE
    UNIQUE (lncode),
    lnname   VARCHAR(60) NOT NULL,   # "Deutsch"
    parenttype   ENUM('diff','sim') NOT NULL,
    parentlnid   SMALLINT UNSIGNED NOT NULL,
    lastupdate  DATETIME NOT NULL
)
EOC

register_tablecreate( "ml_langdomains", <<'EOC');
CREATE TABLE ml_langdomains (
    lnid   SMALLINT UNSIGNED NOT NULL,
    dmid   TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (lnid, dmid),
    dmmaster ENUM('0','1') NOT NULL,
    lastgetnew DATETIME,
    lastpublish DATETIME,
    countokay    SMALLINT UNSIGNED NOT NULL,
    counttotal   SMALLINT UNSIGNED NOT NULL
)
EOC

register_tablecreate( "ml_latest", <<'EOC');
CREATE TABLE ml_latest (
    lnid     SMALLINT UNSIGNED NOT NULL,
    dmid     TINYINT UNSIGNED NOT NULL,
    itid     SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (lnid, dmid, itid),
    txtid    INT UNSIGNED NOT NULL,
    chgtime  DATETIME NOT NULL,
    staleness  TINYINT UNSIGNED DEFAULT 0 NOT NULL, # better than ENUM('0','1','2');
    INDEX (lnid, staleness),
    INDEX (dmid, itid),
    INDEX (lnid, dmid, chgtime),
    INDEX (chgtime)
)
EOC

register_tablecreate( "ml_text", <<'EOC');
CREATE TABLE ml_text (
    dmid  TINYINT UNSIGNED NOT NULL,
    txtid  INT UNSIGNED AUTO_INCREMENT NOT NULL,
    PRIMARY KEY (dmid, txtid),
    lnid   SMALLINT UNSIGNED NOT NULL,
    itid   SMALLINT UNSIGNED NOT NULL,
    INDEX (lnid, dmid, itid),
    text    TEXT NOT NULL,
    userid  INT UNSIGNED NOT NULL
) ENGINE=MYISAM
EOC

register_tablecreate( "procnotify", <<'EOC');
CREATE TABLE procnotify (
    nid   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (nid),
    cmd   VARCHAR(50),
    args  VARCHAR(255)
)
EOC

register_tablecreate( "syndicated", <<'EOC');
CREATE TABLE syndicated (
    userid  INT UNSIGNED NOT NULL,
    synurl  VARCHAR(255),
    checknext  DATETIME NOT NULL,
    lastcheck  DATETIME,
    lastmod    INT UNSIGNED, # unix time
    etag       VARCHAR(80),
    fuzzy_token  VARCHAR(255),

    PRIMARY KEY (userid),
    UNIQUE (synurl),
    INDEX (checknext),
    INDEX (fuzzy_token)
)
EOC

register_tablecreate( "synitem", <<'EOC');
CREATE TABLE synitem (
    userid  INT UNSIGNED NOT NULL,
    item   CHAR(22),    # base64digest of rss $item
    dateadd DATETIME NOT NULL,

    INDEX (userid, item(3)),
    INDEX (userid, dateadd)
)
EOC

register_tablecreate( "ratelist", <<'EOC');
CREATE TABLE ratelist (
    rlid TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name  varchar(50) not null,
    des varchar(255) not null,

    PRIMARY KEY (rlid),
    UNIQUE KEY (name)
)
EOC

register_tablecreate( "ratelog", <<'EOC');
CREATE TABLE ratelog (
    userid   INT UNSIGNED NOT NULL,
    rlid  TINYINT UNSIGNED NOT NULL,
    evttime  INT UNSIGNED NOT NULL,
    ip       INT UNSIGNED NOT NULL,
    index (userid, rlid, evttime),
    quantity SMALLINT UNSIGNED NOT NULL
)
EOC

register_tablecreate( "rateabuse", <<'EOC');
CREATE TABLE rateabuse (
    rlid     TINYINT UNSIGNED NOT NULL,
    userid   INT UNSIGNED NOT NULL,
    evttime  INT UNSIGNED NOT NULL,
    ip       INT UNSIGNED NOT NULL,
    enum     ENUM('soft','hard') NOT NULL,

    index (rlid, evttime),
    index (userid),
    index (ip)
)
EOC

register_tablecreate( "loginstall", <<'EOC');
CREATE TABLE loginstall (
    userid   INT UNSIGNED NOT NULL,
    ip       INT UNSIGNED NOT NULL,
    time     INT UNSIGNED NOT NULL,

    UNIQUE (userid, ip)
)
EOC

# web sessions.  optionally tied to ips and with expiration times.
# whenever a session is okayed, expired ones are deleted, or ones
# created over 30 days ago.  a live session can't change email address
# or password.  digest authentication will be required for that,
# or javascript md5 challenge/response.
register_tablecreate( "sessions", <<'EOC');    # user cluster
CREATE TABLE sessions (
    userid     MEDIUMINT UNSIGNED NOT NULL,
    sessid     MEDIUMINT UNSIGNED NOT NULL,
    PRIMARY KEY (userid, sessid),
    auth       CHAR(10) NOT NULL,
    exptype    ENUM('short','long') NOT NULL,  # browser closed or "infinite"
    timecreate INT UNSIGNED NOT NULL,
    timeexpire INT UNSIGNED NOT NULL,
    ipfixed    CHAR(15)  # if null, not fixed at IP.
)
EOC

register_tablecreate( "sessions_data", <<'EOC');    # user cluster
CREATE TABLE sessions_data (
    userid     MEDIUMINT UNSIGNED NOT NULL,
    sessid     MEDIUMINT UNSIGNED NOT NULL,
    skey       VARCHAR(30) NOT NULL,
    PRIMARY KEY (userid, sessid, skey),
    sval       VARCHAR(255)
)
EOC

# what:  ip, email, ljuser, ua, emailnopay
# emailnopay means don't allow payments from that email
register_tablecreate( "sysban", <<'EOC');
CREATE TABLE sysban (
    banid     MEDIUMINT UNSIGNED NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (banid),
    status    ENUM('active','expired') NOT NULL DEFAULT 'active',
    INDEX     (status),
    bandate   DATETIME,
    banuntil  DATETIME,
    what      VARCHAR(20) NOT NULL,
    value     VARCHAR(80),
    note      VARCHAR(255)
)
EOC

# clustered relationship types are defined in ljlib.pl and ljlib-local.pl in
# the LJ::get_reluser_id function
register_tablecreate( "reluser2", <<'EOC');
CREATE TABLE reluser2 (
    userid    INT UNSIGNED NOT NULL,
    type      SMALLINT UNSIGNED NOT NULL,
    targetid  INT UNSIGNED NOT NULL,

    PRIMARY KEY (userid,type,targetid),
    INDEX (userid,targetid)
)
EOC

# relationship types:
# 'A' means targetid can administrate userid as a community maintainer
# 'B' means targetid is banned in userid
# 'P' means targetid can post to userid
# 'M' means targetid can moderate the community userid
# 'N' means targetid is preapproved to post to community userid w/o moderation
# 'I' means targetid invited userid to the site
# 'S' means targetid will have comments automatically screened in userid
# new types to be added here

register_tablecreate( "reluser", <<'EOC');
CREATE TABLE reluser (
    userid     INT UNSIGNED NOT NULL,
    targetid   INT UNSIGNED NOT NULL,
    type       char(1) NOT NULL,
    PRIMARY KEY (userid,type,targetid),
    KEY (targetid,type)
)
EOC

post_create(
    "reluser",
    "sqltry" =>
"INSERT IGNORE INTO reluser (userid, targetid, type) SELECT userid, banneduserid, 'B' FROM ban",
    "sqltry" =>
"INSERT IGNORE INTO reluser (userid, targetid, type) SELECT u.userid, p.userid, 'A' FROM priv_map p, priv_list l, user u WHERE l.privcode='sharedjournal' AND l.prlid=p.prlid AND p.arg=u.user AND p.arg<>'all'",
    "code" => sub {

        # logaccess has been dead for a long time.  In fact, its table
        # definition has been removed from this file.  No need to try
        # and upgrade if the source table doesn't even exist.
        unless ( column_type( 'logaccess', 'userid' ) ) {
            print "# No logaccess source table found, skipping...\n";
            return;
        }

        my $dbh = shift;
        print "# Converting logaccess rows to reluser...\n";
        my $sth = $dbh->prepare("SELECT MAX(userid) FROM user");
        $sth->execute;
        my ($maxid) = $sth->fetchrow_array;
        return unless $maxid;

        my $from = 1;
        my $to   = $from + 10000 - 1;
        while ( $from <= $maxid ) {
            printf "#  logaccess status: (%0.1f%%)\n", ( $from * 100 / $maxid );
            do_sql(   "INSERT IGNORE INTO reluser (userid, targetid, type) "
                    . "SELECT ownerid, posterid, 'P' "
                    . "FROM logaccess "
                    . "WHERE ownerid BETWEEN $from AND $to" );
            $from += 10000;
            $to   += 10000;
        }
        print "# Finished converting logaccess.\n";
    }
);

register_tablecreate( "clustermove", <<'EOC');
CREATE TABLE clustermove (
    cmid      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (cmid),
    userid    INT UNSIGNED NOT NULL,
    KEY (userid),
    sclust    TINYINT UNSIGNED NOT NULL,
    dclust    TINYINT UNSIGNED NOT NULL,
    timestart INT UNSIGNED,
    timedone  INT UNSIGNED,
    sdeleted  ENUM('1','0')
)
EOC

# moderated community post summary info
register_tablecreate( "modlog", <<'EOC');
CREATE TABLE modlog (
    journalid  INT UNSIGNED NOT NULL,
    modid      MEDIUMINT UNSIGNED NOT NULL,
    PRIMARY KEY (journalid, modid),
    posterid   INT UNSIGNED NOT NULL,
    subject    CHAR(30),
    logtime    DATETIME,

    KEY (journalid, logtime)
)
EOC

# moderated community post Storable object (all props/options)
register_tablecreate( "modblob", <<'EOC');
CREATE TABLE modblob (
    journalid  INT UNSIGNED NOT NULL,
    modid      INT UNSIGNED NOT NULL,
    PRIMARY KEY (journalid, modid),
    request_stor    MEDIUMBLOB
)
EOC

# user counters
register_tablecreate( "counter", <<'EOC');
CREATE TABLE counter (
    journalid  INT UNSIGNED NOT NULL,
    area       CHAR(1) NOT NULL,
    PRIMARY KEY (journalid, area),
    max        INT UNSIGNED NOT NULL
)
EOC

# user counters on the global (contrary to the name)
register_tablecreate( "usercounter", <<'EOC');
CREATE TABLE usercounter (
    journalid  INT UNSIGNED NOT NULL,
    area       CHAR(1) NOT NULL,
    PRIMARY KEY (journalid, area),
    max        INT UNSIGNED NOT NULL
)
EOC

# community interests
register_tablecreate( "comminterests", <<'EOC');
CREATE TABLE comminterests (
    userid int(10) unsigned NOT NULL default '0',
    intid int(10) unsigned NOT NULL default '0',

    PRIMARY KEY  (userid,intid),
    KEY (intid)
)
EOC

# links
register_tablecreate( "links", <<'EOC');    # clustered
CREATE TABLE links (
    journalid int(10) unsigned NOT NULL default '0',
    ordernum tinyint(4) unsigned NOT NULL default '0',
    parentnum tinyint(4) unsigned NOT NULL default '0',
    url varchar(255) default NULL,
    title varchar(255) NOT NULL default '',
    hover varchar(255) default NULL,

    KEY  (journalid)
)
EOC

# supportprop
register_tablecreate( "supportprop", <<'EOC');
CREATE TABLE supportprop (
    spid int(10) unsigned NOT NULL default '0',
    prop varchar(30) NOT NULL,
    value varchar(255) NOT NULL,

    PRIMARY KEY (spid, prop)
)
EOC

post_create(
    "comminterests",
    "code" => sub {
        my $dbh = shift;
        print "# Populating community interests...\n";

        my $BLOCK = 1_000;

        my @ids   = @{ $dbh->selectcol_arrayref("SELECT userid FROM community") || [] };
        my $total = @ids;

        while (@ids) {
            my @set = grep { $_ } splice( @ids, 0, $BLOCK );

            printf( "# community interests status: (%0.1f%%)\n",
                ( ( ( $total - @ids ) / $total ) * 100 ) )
                if $total > $BLOCK;

            local $" = ",";
            do_sql(   "INSERT IGNORE INTO comminterests (userid, intid) "
                    . "SELECT userid, intid FROM userinterests "
                    . "WHERE userid IN (@set)" );
        }

        print "# Finished converting community interests.\n";
    }
);

# tracking where users are active
# accountlevel is the account level at time of activity
# (may be NULL for transition period or long-term inactive
# accounts that were active earlier - but not all inactive accounts will be in
# there, so we won't be looking here for their account levels anyway, so this
# shouldn't be a problem)
register_tablecreate( "clustertrack2", <<'EOC');    # clustered
CREATE TABLE clustertrack2 (
    userid INT UNSIGNED NOT NULL,
    PRIMARY KEY (userid),
    timeactive INT UNSIGNED NOT NULL,
    clusterid SMALLINT UNSIGNED,
    accountlevel SMALLINT UNSIGNED,
    journaltype char(1),

    INDEX (timeactive, clusterid)
)
EOC

# rotating site secret values
register_tablecreate( "secrets", <<'EOC');    # global
CREATE TABLE secrets  (
    stime   INT UNSIGNED NOT NULL,
    secret  CHAR(32) NOT NULL,

    PRIMARY KEY (stime)
)
EOC

# Challenges table (for non-memcache support)
register_tablecreate( "challenges", <<'EOC');
CREATE TABLE challenges (
    ctime int(10) unsigned NOT NULL DEFAULT 0,
    challenge char(80) NOT NULL DEFAULT '',

    PRIMARY KEY (challenge)
)
EOC

register_tablecreate( "clustermove_inprogress", <<'EOC');
CREATE TABLE clustermove_inprogress (
    userid      INT UNSIGNED NOT NULL,
    locktime    INT UNSIGNED NOT NULL,
    dstclust    SMALLINT UNSIGNED NOT NULL,
    moverhost   INT UNSIGNED NOT NULL,
    moverport   SMALLINT UNSIGNED NOT NULL,
    moverinstance CHAR(22) NOT NULL, # base64ed MD5 hash

    PRIMARY KEY (userid)
)
EOC

register_tablecreate( "spamreports", <<'EOC');    # global
CREATE TABLE spamreports (
    reporttime  INT(10) UNSIGNED NOT NULL,
    ip          VARCHAR(15),
    journalid   INT(10) UNSIGNED NOT NULL,
    posterid    INT(10) UNSIGNED NOT NULL DEFAULT 0,
    subject     VARCHAR(255) BINARY,
    body        BLOB NOT NULL,
    client      VARCHAR(255),

    PRIMARY KEY (reporttime, journalid),
    INDEX       (ip),
    INDEX       (posterid),
    INDEX       (client)
)
EOC

register_tablecreate( "tempanonips", <<'EOC');    # clustered
CREATE TABLE tempanonips (
    reporttime  INT(10) UNSIGNED NOT NULL,
    ip          VARCHAR(15) NOT NULL,
    journalid   INT(10) UNSIGNED NOT NULL,
    jtalkid     INT(10) UNSIGNED NOT NULL,

    PRIMARY KEY (journalid, jtalkid),
    INDEX       (reporttime)
)
EOC

# partialstats - stores calculation times:
#    jobname = 'calc_country'
#    clusterid = '1'
#    calctime = time()
register_tablecreate( "partialstats", <<'EOC');
CREATE TABLE partialstats (
    jobname  VARCHAR(50) NOT NULL,
    clusterid MEDIUMINT NOT NULL DEFAULT 0,
    calctime  INT(10) UNSIGNED,

    PRIMARY KEY (jobname, clusterid)
)
EOC

# partialstatsdata - stores data per cluster:
#    statname = 'country'
#    arg = 'US'
#    clusterid = '1'
#    value = '500'
register_tablecreate( "partialstatsdata", <<'EOC');
CREATE TABLE partialstatsdata (
    statname  VARCHAR(50) NOT NULL,
    arg       VARCHAR(50) NOT NULL,
    clusterid INT(10) UNSIGNED NOT NULL DEFAULT 0,
    value     INT(11),

    PRIMARY KEY (statname, arg, clusterid)
)
EOC

# inviterecv -- stores community invitations received
register_tablecreate( "inviterecv", <<'EOC');
CREATE TABLE inviterecv (
    userid      INT(10) UNSIGNED NOT NULL,
    commid      INT(10) UNSIGNED NOT NULL,
    maintid     INT(10) UNSIGNED NOT NULL,
    recvtime    INT(10) UNSIGNED NOT NULL,
    args        VARCHAR(255),

    PRIMARY KEY (userid, commid)
)
EOC

# invitesent -- stores community invitations sent
register_tablecreate( "invitesent", <<'EOC');
CREATE TABLE invitesent (
    commid      INT(10) UNSIGNED NOT NULL,
    userid      INT(10) UNSIGNED NOT NULL,
    maintid     INT(10) UNSIGNED NOT NULL,
    recvtime    INT(10) UNSIGNED NOT NULL,
    status      ENUM('accepted', 'rejected', 'outstanding') NOT NULL,
    args        VARCHAR(255),

    PRIMARY KEY (commid, userid)
)
EOC

# memorable2 -- clustered memories
register_tablecreate( "memorable2", <<'EOC');
CREATE TABLE memorable2 (
    userid      INT(10) UNSIGNED NOT NULL DEFAULT '0',
    memid       INT(10) UNSIGNED NOT NULL DEFAULT '0',
    journalid   INT(10) UNSIGNED NOT NULL DEFAULT '0',
    ditemid     INT(10) UNSIGNED NOT NULL DEFAULT '0',
    des         VARCHAR(150) DEFAULT NULL,
    security    ENUM('public','friends','private') NOT NULL DEFAULT 'public',

    PRIMARY KEY (userid, journalid, ditemid),
    UNIQUE KEY  (userid, memid)
)
EOC

# memkeyword2 -- clustered memory keyword map
register_tablecreate( "memkeyword2", <<'EOC');
CREATE TABLE memkeyword2 (
    userid      INT(10) UNSIGNED NOT NULL DEFAULT '0',
    memid       INT(10) UNSIGNED NOT NULL DEFAULT '0',
    kwid        INT(10) UNSIGNED NOT NULL DEFAULT '0',

    PRIMARY KEY (userid, memid, kwid),
    KEY         (userid, kwid)
)
EOC

# userkeywords -- clustered keywords
register_tablecreate( "userkeywords", <<'EOC');
CREATE TABLE userkeywords (
    userid      INT(10) UNSIGNED NOT NULL DEFAULT '0',
    kwid        INT(10) UNSIGNED NOT NULL DEFAULT '0',
    keyword     VARCHAR(80) BINARY NOT NULL,

    PRIMARY KEY (userid, kwid),
    UNIQUE KEY  (userid, keyword)
)
EOC

# trust_groups -- clustered
register_tablecreate( "trust_groups", <<'EOC');
CREATE TABLE trust_groups (
    userid      INT(10) UNSIGNED NOT NULL DEFAULT '0',
    groupnum    TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
    groupname   VARCHAR(90) NOT NULL DEFAULT '',
    sortorder   TINYINT(3) UNSIGNED NOT NULL DEFAULT '50',
    is_public   ENUM('0','1') NOT NULL DEFAULT '0',

    PRIMARY KEY (userid, groupnum)
)
EOC

register_tablecreate( "readonly_user", <<'EOC');
CREATE TABLE readonly_user (
    userid      INT(10) UNSIGNED NOT NULL DEFAULT '0',

    PRIMARY KEY (userid)
)
EOC

register_tablecreate( "underage", <<'EOC');
CREATE TABLE underage (
    uniq        CHAR(15) NOT NULL,
    timeof      INT(10) NOT NULL,

    PRIMARY KEY (uniq),
    KEY         (timeof)
)
EOC

register_tablecreate( "support_youreplied", <<'EOC');
CREATE TABLE support_youreplied (
    userid  INT UNSIGNED NOT NULL,
    spid    INT UNSIGNED NOT NULL,

    PRIMARY KEY (userid, spid)
)
EOC

register_tablecreate( "support_answers", <<'EOC');
CREATE TABLE support_answers (
    ansid INT UNSIGNED NOT NULL,
    spcatid INT UNSIGNED NOT NULL,
    lastmodtime INT UNSIGNED NOT NULL,
    lastmoduserid INT UNSIGNED NOT NULL,
    subject VARCHAR(255),
    body TEXT,

    PRIMARY KEY (ansid),
    KEY         (spcatid)
)
EOC

register_tablecreate( "userlog", <<'EOC');
CREATE TABLE userlog (
    userid        INT UNSIGNED NOT NULL,
    logtime       INT UNSIGNED NOT NULL,
    action        VARCHAR(30) NOT NULL,
    actiontarget  INT UNSIGNED,
    remoteid      INT UNSIGNED,
    ip            VARCHAR(45),
    uniq          VARCHAR(15),
    extra         VARCHAR(255),

    INDEX (userid)
)
EOC

# external user mappings
# note: extuser/extuserid are expected to sometimes be NULL, even
# though they are keyed.  (Null values are not taken into account when
# using indexes)
register_tablecreate( "extuser", <<'EOC');
CREATE TABLE extuser (
    userid  INT UNSIGNED NOT NULL PRIMARY KEY,
    siteid  INT UNSIGNED NOT NULL,
    extuser    VARCHAR(50),
    extuserid  INT UNSIGNED,

    UNIQUE KEY `extuser` (siteid, extuser),
    UNIQUE KEY `extuserid` (siteid, extuserid)
)
EOC

# table showing what tags a user has; parentkwid can be null
register_tablecreate( "usertags", <<'EOC');
CREATE TABLE usertags (
    journalid   INT UNSIGNED NOT NULL,
    kwid        INT UNSIGNED NOT NULL,
    parentkwid  INT UNSIGNED,
    display     ENUM('0','1') DEFAULT '1' NOT NULL,

    PRIMARY KEY (journalid, kwid)
)
EOC

# mapping of tags applied to an entry
register_tablecreate( "logtags", <<'EOC');
CREATE TABLE logtags (
    journalid INT UNSIGNED NOT NULL,
    jitemid   MEDIUMINT UNSIGNED NOT NULL,
    kwid      INT UNSIGNED NOT NULL,

    PRIMARY KEY (journalid, jitemid, kwid),
    KEY (journalid, kwid)
)
EOC

# logtags but only for the most recent 100 tags-to-entry
register_tablecreate( "logtagsrecent", <<'EOC');
CREATE TABLE logtagsrecent (
    journalid INT UNSIGNED NOT NULL,
    jitemid   MEDIUMINT UNSIGNED NOT NULL,
    kwid      INT UNSIGNED NOT NULL,

    PRIMARY KEY (journalid, kwid, jitemid)
)
EOC

# summary counts for security on entry keywords
register_tablecreate( "logkwsum", <<'EOC');
CREATE TABLE logkwsum (
    journalid INT UNSIGNED NOT NULL,
    kwid      INT UNSIGNED NOT NULL,
    security  BIGINT UNSIGNED NOT NULL,
    entryct   INT UNSIGNED NOT NULL DEFAULT 0,

    PRIMARY KEY (journalid, kwid, security),
    KEY (journalid, security)
)
EOC

# external identities
#
#   idtype ::=
#      "O" - OpenID
#      "L" - LID (netmesh)
#      "T" - TypeKey
#       ?  - etc
register_tablecreate( "identitymap", <<'EOC');
CREATE TABLE identitymap (
    idtype    CHAR(1) NOT NULL,
    identity  VARCHAR(255) BINARY NOT NULL,
    userid    INT unsigned NOT NULL,

    PRIMARY KEY  (idtype, identity),
    KEY          userid (userid)
)
EOC

register_tablecreate( "openid_trust", <<'EOC');
CREATE TABLE openid_trust (
    userid int(10) unsigned NOT NULL default '0',
    endpoint_id int(10) unsigned NOT NULL default '0',
    trust_time int(10) unsigned NOT NULL default '0',
    duration enum('always','once') NOT NULL default 'always',
    last_assert_time int(10) unsigned default NULL,
    flags tinyint(3) unsigned default NULL,

    PRIMARY KEY  (userid,endpoint_id),
    KEY endpoint_id (endpoint_id)
)
EOC

register_tablecreate( "openid_endpoint", <<'EOC');
CREATE TABLE openid_endpoint (
    endpoint_id int(10) unsigned NOT NULL auto_increment,
    url varchar(255) BINARY NOT NULL default '',
    last_assert_time int(10) unsigned default NULL,

    PRIMARY KEY  (endpoint_id),
    UNIQUE KEY url (url),
    KEY last_assert_time (last_assert_time)
)
EOC

register_tablecreate( "oauth_consumer", <<'EOC');
CREATE TABLE oauth_consumer (
    consumer_id int(10) UNSIGNED NOT NULL,
    userid int(10) UNSIGNED NOT NULL,

    communityid int(10) UNSIGNED NULL,

    token VARCHAR(20) NOT NULL,
    secret VARCHAR(50) NOT NULL,

    name VARCHAR(255) NOT NULL DEFAULT '',
    website VARCHAR(255) NOT NULL,

    createtime INT UNSIGNED NOT NULL,
    updatetime INT UNSIGNED NULL,
    invalidatedtime INT UNSIGNED NULL,

    approved ENUM('1','0') NOT NULL DEFAULT 1,
    active ENUM('1','0') NOT NULL DEFAULT 1,

    PRIMARY KEY (consumer_id),
    UNIQUE KEY (token),
    KEY (userid)
)
EOC

register_tablecreate( "oauth_access_token", <<'EOC');
CREATE TABLE oauth_access_token (
    consumer_id int(10) UNSIGNED NOT NULL,
    userid int(10) UNSIGNED NOT NULL,

    token VARCHAR(20) NULL,
    secret VARCHAR(50) NULL,

    createtime INT UNSIGNED NOT NULL,
    lastaccess INT UNSIGNED,

    PRIMARY KEY consumer_user (consumer_id, userid),
    UNIQUE KEY (token),
    KEY (userid)
)
EOC

register_tablecreate( "priv_packages", <<'EOC');
CREATE TABLE priv_packages (
    pkgid int(10) unsigned NOT NULL auto_increment,
    name varchar(255) NOT NULL default '',
    lastmoduserid int(10) unsigned NOT NULL default 0,
    lastmodtime int(10) unsigned NOT NULL default 0,

    PRIMARY KEY (pkgid),
    UNIQUE KEY (name)
)
EOC

register_tablecreate( "priv_packages_content", <<'EOC');
CREATE TABLE priv_packages_content (
    pkgid int(10) unsigned NOT NULL auto_increment,
    privname varchar(20) NOT NULL,
    privarg varchar(40),

    PRIMARY KEY (pkgid, privname, privarg)
)
EOC

register_tablecreate( "active_user", <<'EOC');
CREATE TABLE active_user (
    userid INT UNSIGNED NOT NULL,
    type   CHAR(1) NOT NULL,
    time   INT UNSIGNED NOT NULL,

    KEY (userid),
    KEY (time)
)
EOC

register_tablecreate( "active_user_summary", <<'EOC');
CREATE TABLE active_user_summary (
    year      SMALLINT NOT NULL,
    month     TINYINT NOT NULL,
    day       TINYINT NOT NULL,
    hour      TINYINT NOT NULL,
    clusterid TINYINT UNSIGNED NOT NULL,
    type      CHAR(1) NOT NULL,
    count     INT UNSIGNED NOT NULL DEFAULT 0,

    PRIMARY KEY (year, month, day, hour, clusterid, type)
)
EOC

register_tablecreate( "loginlog", <<'EOC');
CREATE TABLE loginlog (
    userid    INT UNSIGNED NOT NULL,
    logintime INT UNSIGNED NOT NULL,
    INDEX     (userid, logintime),
    sessid    MEDIUMINT UNSIGNED NOT NULL,
    ip        VARCHAR(15),
    ua        VARCHAR(100)
)
EOC

# global
register_tablecreate( "usertrans", <<'EOC');
CREATE TABLE `usertrans` (
    `userid` int(10) unsigned NOT NULL default '0',
    `time` int(10) unsigned NOT NULL default '0',
    `what` varchar(25) NOT NULL default '',
    `before` varchar(25) NOT NULL default '',
    `after` varchar(25) NOT NULL default '',

    KEY `userid` (`userid`),
    KEY `time` (`time`)
)
EOC

# global
register_tablecreate( "eventtypelist", <<'EOC');
CREATE TABLE eventtypelist (
    etypeid  SMALLINT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
    class    VARCHAR(100),

    UNIQUE (class)
)
EOC

# global
register_tablecreate( "notifytypelist", <<'EOC');
CREATE TABLE notifytypelist (
    ntypeid   SMALLINT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
    class     VARCHAR(100),

    UNIQUE (class)
)
EOC

# partitioned:  ESN subscriptions:  flag on event target (a journal) saying
#               whether there are known listeners out there.
#
# verifytime is unixtime we last checked that this has_subs caching row
# is still accurate and people do in fact still subscribe to this.
# then maintenance tasks can background prune this table and fix
# up verifytimes.
register_tablecreate( "has_subs", <<'EOC');
CREATE TABLE has_subs (
    journalid  INT UNSIGNED NOT NULL,
    etypeid    INT UNSIGNED NOT NULL,
    arg1       INT UNSIGNED NOT NULL,
    arg2       INT UNSIGNED NOT NULL,
    PRIMARY KEY (journalid, etypeid, arg1, arg2),
    verifytime   INT UNSIGNED NOT NULL
)
EOC

# partitioned:  ESN subscriptions:  details of a user's subscriptions
#  subid: alloc_user_counter
#  is_dirty:  either 1 (indexed) or NULL (not in index).  means we have
#             to go update the target's etypeid
#  userid is OWNER of the subscription,
#  journalid is the journal in which the event took place.
#  ntypeid is the notification type from notifytypelist
#  times are unixtimes
#  expiretime can be 0 to mean "never"
#  flags is a bitmask of flags, where:
#     bit 0 = is digest?  (off means live?)
#     rest undefined for now.
register_tablecreate( "subs", <<'EOC');
CREATE TABLE subs (
    userid   INT UNSIGNED NOT NULL,
    subid    INT UNSIGNED NOT NULL,
    PRIMARY KEY (userid, subid),

    is_dirty   TINYINT UNSIGNED NULL,
    INDEX (is_dirty),

    journalid  INT UNSIGNED NOT NULL,
    etypeid    SMALLINT UNSIGNED NOT NULL,
    arg1       INT UNSIGNED NOT NULL,
    arg2       INT UNSIGNED NOT NULL,

    ntypeid    SMALLINT UNSIGNED NOT NULL,

    createtime INT UNSIGNED NOT NULL,
    expiretime INT UNSIGNED NOT NULL,
    flags      SMALLINT UNSIGNED NOT NULL
)
EOC

# unlike other *proplist tables, this one is auto-populated by app
register_tablecreate( "subsproplist", <<'EOC');
CREATE TABLE subsproplist (
    subpropid  SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name       VARCHAR(255) DEFAULT NULL,

    PRIMARY KEY (subpropid),
    UNIQUE KEY (name)
)
EOC

# partitioned:  ESN subscriptions:  metadata on a user's subscriptions
register_tablecreate( "subsprop", <<'EOC');
CREATE TABLE subsprop (
    userid    INT      UNSIGNED NOT NULL,
    subid     INT      UNSIGNED NOT NULL,
    subpropid SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (userid, subid, subpropid),
    value     VARCHAR(255) BINARY DEFAULT NULL
)
EOC

# partitioned:  ESN event queue notification method
register_tablecreate( "notifyqueue", <<'EOC');
CREATE TABLE notifyqueue (
    userid     INT UNSIGNED NOT NULL,
    qid        INT UNSIGNED NOT NULL,
    journalid  INT UNSIGNED NOT NULL,
    etypeid    SMALLINT UNSIGNED NOT NULL,
    arg1       INT UNSIGNED,
    arg2       INT UNSIGNED,

    state      CHAR(1) NOT NULL DEFAULT 'N',

    createtime INT UNSIGNED NOT NULL,

    PRIMARY KEY (userid, qid),
    INDEX       (state)
)
EOC

register_tablecreate( "sch_funcmap", <<'EOC');
CREATE TABLE sch_funcmap (
    funcid         INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    funcname       VARCHAR(255) NOT NULL,

    UNIQUE(funcname)
)
EOC

register_tablecreate( "sch_job", <<'EOC');
CREATE TABLE sch_job (
    jobid           BIGINT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    funcid          INT UNSIGNED NOT NULL,
    arg             MEDIUMBLOB,
    uniqkey         VARCHAR(255) NULL,
    insert_time     INTEGER UNSIGNED,
    run_after       INTEGER UNSIGNED NOT NULL,
    grabbed_until   INTEGER UNSIGNED,
    priority        SMALLINT UNSIGNED,
    coalesce        VARCHAR(255),

    INDEX (funcid, run_after),
    UNIQUE(funcid, uniqkey),
    INDEX (funcid, coalesce)
)
EOC

register_tablecreate( "sch_note", <<'EOC');
CREATE TABLE sch_note (
    jobid           BIGINT UNSIGNED NOT NULL,
    notekey         VARCHAR(255),
    PRIMARY KEY (jobid, notekey),
    value           MEDIUMBLOB
)
EOC

register_tablecreate( "sch_error", <<'EOC');
CREATE TABLE sch_error (
    error_time      INTEGER UNSIGNED NOT NULL,
    jobid           BIGINT UNSIGNED NOT NULL,
    message         VARCHAR(255) NOT NULL,

    INDEX (error_time),
    INDEX (jobid)
)
EOC

register_tablecreate( "sch_exitstatus", <<'EOC');
CREATE TABLE sch_exitstatus (
    jobid           BIGINT UNSIGNED PRIMARY KEY NOT NULL,
    status          SMALLINT UNSIGNED,
    completion_time INTEGER UNSIGNED,
    delete_after    INTEGER UNSIGNED,

    INDEX (delete_after)
)
EOC

register_tablecreate( "usersearch_packdata", <<'EOC');
CREATE TABLE usersearch_packdata (
    userid      INT UNSIGNED NOT NULL PRIMARY KEY,
    packed      CHAR(8) BINARY,
    mtime       INT UNSIGNED NOT NULL,
    good_until  INT UNSIGNED,

    INDEX (mtime),
    INDEX (good_until)
)
EOC

register_tablecreate( "debug_notifymethod", <<'EOC');
CREATE TABLE debug_notifymethod (
    userid       int unsigned not null,
    subid        int unsigned,
    ntfytime     int unsigned,
    origntypeid  int unsigned,
    etypeid      int unsigned,
    ejournalid   int unsigned,
    earg1        int,
    earg2        int,
    schjobid     varchar(50) null
)
EOC

register_tablecreate( "password", <<'EOC');
CREATE TABLE password (
    userid    INT UNSIGNED NOT NULL PRIMARY KEY,
    password  VARCHAR(50)
)
EOC

register_tablecreate( "email", <<'EOC');
CREATE TABLE email (
    userid    INT UNSIGNED NOT NULL PRIMARY KEY,
    email     VARCHAR(50),

    INDEX     (email)
)
EOC

register_tablecreate( "dirmogsethandles", <<'EOC');
CREATE TABLE dirmogsethandles (
    conskey  char(40) PRIMARY KEY,
    exptime  INT UNSIGNED NOT NULL,

    INDEX    (exptime)
)
EOC

# global pollid -> userid map
register_tablecreate( "pollowner", <<'EOC');
CREATE TABLE pollowner (
    pollid    INT UNSIGNED NOT NULL PRIMARY KEY,
    journalid INT UNSIGNED NOT NULL,

    INDEX (journalid)
)
EOC

# clustereds
register_tablecreate( "poll2", <<'EOC');
CREATE TABLE poll2 (
    journalid INT UNSIGNED NOT NULL,
    pollid INT UNSIGNED NOT NULL,
    posterid INT UNSIGNED NOT NULL,
    ditemid INT UNSIGNED NOT NULL,
    whovote ENUM('all','friends','ofentry') NOT NULL DEFAULT 'all',
    whoview ENUM('all','friends','ofentry','none') NOT NULL DEFAULT 'all',
    isanon enum('yes','no') NOT NULL default 'no',
    name VARCHAR(255) DEFAULT NULL,

    PRIMARY KEY  (journalid,pollid)
)
EOC

register_tablecreate( "pollitem2", <<'EOC');
CREATE TABLE pollitem2 (
    journalid INT UNSIGNED NOT NULL,
    pollid INT UNSIGNED NOT NULL,
    pollqid TINYINT UNSIGNED NOT NULL,
    pollitid TINYINT UNSIGNED NOT NULL,
    sortorder TINYINT UNSIGNED NOT NULL DEFAULT '0',
    item VARCHAR(255) DEFAULT NULL,

    PRIMARY KEY  (journalid,pollid,pollqid,pollitid)
)
EOC

register_tablecreate( "pollquestion2", <<'EOC');
CREATE TABLE pollquestion2 (
    journalid INT UNSIGNED NOT NULL,
    pollid INT UNSIGNED NOT NULL,
    pollqid TINYINT UNSIGNED NOT NULL,
    sortorder TINYINT UNSIGNED NOT NULL DEFAULT '0',
    type ENUM('check','radio','drop','text','scale') NOT NULL,
    opts VARCHAR(255) DEFAULT NULL,
    qtext TEXT,

    PRIMARY KEY  (journalid,pollid,pollqid)
)
EOC

register_tablecreate( "pollresult2", <<'EOC');
CREATE TABLE pollresult2 (
    journalid INT UNSIGNED NOT NULL,
    pollid INT UNSIGNED NOT NULL,
    pollqid TINYINT UNSIGNED NOT NULL,
    userid INT UNSIGNED NOT NULL,
    value VARCHAR(1024) DEFAULT NULL,

    PRIMARY KEY  (journalid,pollid,pollqid),
    KEY (userid,pollid)
)
EOC

register_tablecreate( "pollsubmission2", <<'EOC');
CREATE TABLE pollsubmission2 (
    journalid INT UNSIGNED NOT NULL,
    pollid INT UNSIGNED NOT NULL,
    userid INT UNSIGNED NOT NULL,
    datesubmit DATETIME NOT NULL,

    PRIMARY KEY  (journalid,pollid),
    KEY (userid)
)
EOC

# clustered
# clustered
register_tablecreate( "embedcontent", <<'EOC');
CREATE TABLE embedcontent (
    userid     INT UNSIGNED NOT NULL,
    moduleid   INT UNSIGNED NOT NULL,
    content    TEXT,
    linktext   VARCHAR(255),
    url        VARCHAR(255),

    PRIMARY KEY  (userid, moduleid)
)
EOC

register_tablecreate( "jobstatus", <<'EOC');
CREATE TABLE jobstatus (
    handle VARCHAR(100) PRIMARY KEY,
    result BLOB,
    start_time INT(10) UNSIGNED NOT NULL,
    end_time INT(10) UNSIGNED NOT NULL,
    status ENUM('running', 'success', 'error'),

    KEY (end_time)
)
EOC

register_tablecreate( "expunged_users", <<'EOC');
CREATE TABLE `expunged_users` (
    user varchar(25) NOT NULL default '',
    expunge_time int(10) unsigned NOT NULL default '0',

    PRIMARY KEY  (user),
    KEY expunge_time (expunge_time)
)
EOC

register_tablecreate( "uniqmap", <<'EOC');
CREATE TABLE uniqmap (
    uniq VARCHAR(15) NOT NULL,
    userid INT UNSIGNED NOT NULL,
    modtime INT UNSIGNED NOT NULL,

    PRIMARY KEY (userid, uniq),
    INDEX(userid, modtime),
    INDEX(uniq, modtime)
)
EOC

# clustered
register_tablecreate( "usermsg", <<'EOC');
CREATE TABLE usermsg (
    journalid    INT UNSIGNED NOT NULL,
    msgid        INT UNSIGNED NOT NULL,
    type         ENUM('in','out') NOT NULL,
    parent_msgid INT UNSIGNED,
    otherid      INT UNSIGNED NOT NULL,
    timesent     INT UNSIGNED,
    state        CHAR(1) default 'A',

    PRIMARY KEY  (journalid,msgid),
    INDEX (journalid,type,otherid),
    INDEX (journalid,timesent)
)
EOC

# clustered
register_tablecreate( "usermsgtext", <<'EOC');
CREATE TABLE usermsgtext (
    journalid    INT UNSIGNED NOT NULL,
    msgid        INT UNSIGNED NOT NULL,
    subject      VARCHAR(255) BINARY,
    body         BLOB NOT NULL,

    PRIMARY KEY  (journalid,msgid)
)
EOC

# clustered
register_tablecreate( "usermsgprop", <<'EOC');
CREATE TABLE usermsgprop (
    journalid    INT UNSIGNED NOT NULL,
    msgid        INT UNSIGNED NOT NULL,
    propid       SMALLINT UNSIGNED NOT NULL,
    propval      VARCHAR(255) NOT NULL,

    PRIMARY KEY (journalid,msgid,propid)
)
EOC

register_tablecreate( "usermsgproplist", <<'EOC');
CREATE TABLE usermsgproplist (
    propid  SMALLINT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT,
    name    VARCHAR(255) DEFAULT NULL,
    des     VARCHAR(255) DEFAULT NULL,

    UNIQUE KEY (name)
)
EOC

# clustered
register_tablecreate( "notifyarchive", <<'EOC');
CREATE TABLE notifyarchive (
    userid     INT UNSIGNED NOT NULL,
    qid        INT UNSIGNED NOT NULL,
    createtime INT UNSIGNED NOT NULL,
    journalid  INT UNSIGNED NOT NULL,
    etypeid    SMALLINT UNSIGNED NOT NULL,
    arg1       INT UNSIGNED,
    arg2       INT UNSIGNED,
    state      CHAR(1),

    PRIMARY KEY (userid, qid),
    INDEX       (userid, createtime)
)
EOC

# clustered
register_tablecreate( "notifybookmarks", <<'EOC');
CREATE TABLE notifybookmarks (
    userid     INT UNSIGNED NOT NULL,
    qid        INT UNSIGNED NOT NULL,

    PRIMARY KEY  (userid, qid)
)
EOC

# global table for persistent queues
register_tablecreate( "persistent_queue", <<'EOC');
CREATE TABLE persistent_queue (
    qkey VARCHAR(255) NOT NULL,
    idx INTEGER UNSIGNED NOT NULL,
    value BLOB,

    PRIMARY KEY (qkey, idx)
)
EOC

## --
## -- embedconten previews
## --
register_tablecreate( "embedcontent_preview", <<'EOC');
CREATE TABLE embedcontent_preview (
    userid      int(10) unsigned NOT NULL default '0',
    moduleid    int(10) NOT NULL default '0',
    content     text,
    linktext    VARCHAR(255),
    url         VARCHAR(255),

    PRIMARY KEY  (userid,moduleid)
) ENGINE=InnoDB
EOC

register_tablecreate( "dw_paidstatus", <<'EOC');
CREATE TABLE dw_paidstatus (
    userid int unsigned NOT NULL,
    typeid smallint unsigned NOT NULL,
    expiretime int unsigned,
    permanent tinyint unsigned NOT NULL,
    lastemail int unsigned,

    PRIMARY KEY (userid),
    INDEX (expiretime)
)
EOC

register_tablecreate( "logprop_history", <<'EOC');
CREATE TABLE logprop_history (
    journalid  INT UNSIGNED NOT NULL,
    jitemid    MEDIUMINT UNSIGNED NOT NULL,
    propid     TINYINT unsigned NOT NULL,
    change_time  INT UNSIGNED NOT NULL DEFAULT '0',
    old_value  VARCHAR(255) default NULL,
    new_value  VARCHAR(255) default NULL,
    note       VARCHAR(255) default NULL,

    INDEX (journalid,jitemid,propid)
)
EOC

register_tablecreate( "sch_mass_funcmap", <<'EOC');
CREATE TABLE sch_mass_funcmap (
    funcid         INT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    funcname       VARCHAR(255) NOT NULL,

    UNIQUE(funcname)
)
EOC

register_tablecreate( "sch_mass_job", <<'EOC');
CREATE TABLE sch_mass_job (
    jobid           BIGINT UNSIGNED PRIMARY KEY NOT NULL AUTO_INCREMENT,
    funcid          INT UNSIGNED NOT NULL,
    arg             MEDIUMBLOB,
    uniqkey         VARCHAR(255) NULL,
    insert_time     INTEGER UNSIGNED,
    run_after       INTEGER UNSIGNED NOT NULL,
    grabbed_until   INTEGER UNSIGNED,
    priority        SMALLINT UNSIGNED,
    coalesce        VARCHAR(255),

    INDEX (funcid, run_after),
    UNIQUE(funcid, uniqkey),
    INDEX (funcid, coalesce)
)
EOC

register_tablecreate( "sch_mass_note", <<'EOC');
CREATE TABLE sch_mass_note (
    jobid           BIGINT UNSIGNED NOT NULL,
    notekey         VARCHAR(255),
    PRIMARY KEY (jobid, notekey),
    value           MEDIUMBLOB
)
EOC

register_tablecreate( "sch_mass_error", <<'EOC');
CREATE TABLE sch_mass_error (
    error_time      INTEGER UNSIGNED NOT NULL,
    jobid           BIGINT UNSIGNED NOT NULL,
    message         VARCHAR(255) NOT NULL,

    INDEX (error_time),
    INDEX (jobid)
)
EOC

register_tablecreate( "sch_mass_exitstatus", <<'EOC');
CREATE TABLE sch_mass_exitstatus (
    jobid           BIGINT UNSIGNED PRIMARY KEY NOT NULL,
    status          SMALLINT UNSIGNED,
    completion_time INTEGER UNSIGNED,
    delete_after    INTEGER UNSIGNED,

    INDEX (delete_after)
)
EOC

register_tablecreate( "import_items", <<'EOC');
CREATE TABLE import_items (
    userid INT UNSIGNED NOT NULL,
    item VARCHAR(255) NOT NULL,
    status ENUM('init', 'ready', 'queued', 'failed', 'succeeded', 'aborted') NOT NULL DEFAULT 'init',
    created INT UNSIGNED NOT NULL,
    last_touch INT UNSIGNED NOT NULL,
    import_data_id INT UNSIGNED NOT NULL,
    priority INT UNSIGNED NOT NULL,

    PRIMARY KEY (userid, item, import_data_id),
    INDEX (priority, status)
)
EOC

register_tablecreate( "import_data", <<'EOC');
CREATE TABLE import_data (
    userid INT UNSIGNED NOT NULL,
    import_data_id INT UNSIGNED NOT NULL,
    hostname VARCHAR(255),
    username VARCHAR(255),
    usejournal VARCHAR(255),
    password_md5 VARCHAR(255),
    groupmap BLOB,
    options BLOB,

    PRIMARY KEY (userid, import_data_id),
    INDEX (import_data_id)
)
EOC

# we don't store this in userprops because we need to index this
# backwards and load it easily...
register_tablecreate( "import_usermap", <<'EOC');
CREATE TABLE import_usermap (
    hostname VARCHAR(255),
    username VARCHAR(255),
    identity_userid INT UNSIGNED,
    feed_userid INT UNSIGNED,

    PRIMARY KEY (hostname, username),
    INDEX (identity_userid),
    INDEX (feed_userid)
)
EOC

# whenever we fire off a status event we have to store this in a table
# for the user so they can get the data later
register_tablecreate( "import_status", <<'EOC');
CREATE TABLE import_status (
    userid INT UNSIGNED NOT NULL,
    import_status_id INT UNSIGNED NOT NULL,
    status BLOB,

    PRIMARY KEY (userid, import_status_id)
)
EOC

register_tablecreate( 'email_aliases', <<'EOC');
CREATE TABLE email_aliases (
    alias VARCHAR(255) NOT NULL,
    rcpt VARCHAR(255) NOT NULL,

    PRIMARY KEY (alias)
)
EOC

# shopping cart list
register_tablecreate( 'shop_carts', <<'EOC');
CREATE TABLE shop_carts (
    cartid INT UNSIGNED NOT NULL,
    starttime INT UNSIGNED NOT NULL,
    userid INT UNSIGNED,
    email VARCHAR(255),
    uniq VARCHAR(15) NOT NULL,
    state INT UNSIGNED NOT NULL,
    paymentmethod INT UNSIGNED NOT NULL,
    nextscan INT UNSIGNED NOT NULL DEFAULT 0,
    authcode VARCHAR(20) NOT NULL,

    cartblob MEDIUMBLOB NOT NULL,

    PRIMARY KEY (cartid),
    INDEX (userid),
    INDEX (uniq)
)
EOC

# invite code->shopping cart list
register_tablecreate( 'shop_codes', <<'EOC');
CREATE TABLE shop_codes (
    acid INT UNSIGNED NOT NULL,
    cartid INT UNSIGNED NOT NULL,
    itemid INT UNSIGNED NOT NULL,

    PRIMARY KEY (acid),
    UNIQUE (cartid, itemid)
)
EOC

# received check/money order payment info
register_tablecreate( 'shop_cmo', <<'EOC');
CREATE TABLE shop_cmo (
    cartid INT UNSIGNED NOT NULL,
    paymentmethod VARCHAR(255) NOT NULL,
    notes TEXT DEFAULT NULL,

    PRIMARY KEY (cartid)
)
EOC

register_tablecreate( 'externalaccount', << 'EOC');
CREATE table externalaccount (
    userid int unsigned NOT NULL,
    acctid int unsigned NOT NULL,
    username varchar(64) NOT NULL,
    password varchar(64),
    siteid int unsigned,
    servicename varchar(128),
    servicetype varchar(32),
    serviceurl varchar(128),
    xpostbydefault enum('1','0') NOT NULL default '0',
    recordlink enum('1','0') NOT NULL default '0',
    active enum('1', '0') NOT NULL default '1',
    options blob,
    primary key (userid, acctid),
    index (userid)
)
EOC

register_tablecreate( 'gco_log', <<'EOC');
CREATE TABLE gco_log (
    gcoid bigint unsigned not null,
    ip varchar(15) not null,
    transtime int unsigned not null,
    req_content text not null,

    index (gcoid)
)
EOC

register_tablecreate( 'gco_map', <<'EOC');
CREATE TABLE gco_map (
    gcoid bigint unsigned not null,
    cartid int unsigned not null,

    email varchar(255),
    contactname varchar(255),

    index (gcoid),
    unique (cartid)
)
EOC

register_tablecreate( 'pp_tokens', <<'EOC');
CREATE TABLE pp_tokens (
    ppid int unsigned not null auto_increment,
    inittime int unsigned not null,
    touchtime int unsigned not null,
    cartid int unsigned not null,
    status varchar(20) not null,

    token varchar(20) not null,
    email varchar(255),
    firstname varchar(255),
    lastname varchar(255),
    payerid varchar(255),

    primary key (ppid),
    unique (cartid),
    index (token)
)
EOC

register_tablecreate( 'pp_log', <<'EOC');
CREATE TABLE pp_log (
    ppid int unsigned not null,
    ip varchar(15) not null,
    transtime int unsigned not null,
    req_content text not null,
    res_content text not null,

    index (ppid)
)
EOC

register_tablecreate( 'pp_trans', <<'EOC');
CREATE TABLE pp_trans (
    ppid int unsigned not null,
    cartid int unsigned not null,

    transactionid varchar(19),
    transactiontype varchar(15),
    paymenttype varchar(7),
    ordertime int unsigned,
    amt decimal(10,2),
    currencycode varchar(3),
    feeamt decimal(10,2),
    settleamt decimal(10,2),
    taxamt decimal(10,2),
    paymentstatus varchar(20),
    pendingreason varchar(20),
    reasoncode varchar(20),
    ack varchar(20),
    timestamp int unsigned,
    build varchar(20),

    index (ppid),
    index (cartid)
)
EOC

register_tablecreate( 'external_site_moods', <<'EOC');
CREATE TABLE external_site_moods (
    siteid int unsigned not null,
    mood varchar(40) not null,
    moodid int(10) unsigned not null default '0',

    PRIMARY KEY (siteid, mood)
)
EOC

register_tablecreate( 'acctcode_promo', <<'EOC');
CREATE TABLE acctcode_promo (
    code varchar(20) not null,
    max_count int(10) unsigned not null default 0,
    current_count int(10) unsigned not null default 0,
    active enum('1','0') not null default 1,
    suggest_journalid int unsigned,
    paid_class varchar(100),
    paid_months tinyint unsigned,
    expiry_date int(10) unsigned not null default 0,

    PRIMARY KEY ( code )
)
EOC

register_tablecreate( 'users_for_paid_accounts', <<'EOC');
CREATE TABLE users_for_paid_accounts (
    userid int unsigned not null,
    time_inserted int unsigned not null default 0,
    points int(5) unsigned not null default 0,
    journaltype char(1) NOT NULL DEFAULT 'P',

    PRIMARY KEY ( userid, time_inserted ),
    INDEX ( time_inserted ),
    INDEX ( journaltype )
)
EOC

register_tablecreate( 'content_filters', <<'EOC');
CREATE TABLE content_filters (
  userid int(10) unsigned NOT NULL,
  filterid int(10) unsigned NOT NULL,
  filtername varchar(255) NOT NULL,
  is_public enum('0','1') NOT NULL default '0',
  sortorder smallint(5) unsigned NOT NULL default '0',

  PRIMARY KEY (userid,filterid),
  UNIQUE KEY userid (userid,filtername)
)
EOC

register_tablecreate( 'content_filter_data', <<'EOC');
CREATE TABLE content_filter_data (
  userid int(10) unsigned NOT NULL,
  filterid int(10) unsigned NOT NULL,
  data mediumblob NOT NULL,

  PRIMARY KEY (userid,filterid)
)
EOC

register_tablecreate( 'sitekeywords', <<'EOC');
CREATE TABLE sitekeywords (
    kwid INT(10) UNSIGNED NOT NULL,
    keyword VARCHAR(255) BINARY NOT NULL,

    PRIMARY KEY (kwid),
    UNIQUE KEY (keyword)
)
EOC

# this table is included, even though it's not used in the stock dw-free
# installation.  but if you want to use it, you can, or you can ignore it
# and make your own which you might have to do.
register_tablecreate( 'cc_trans', <<'EOC');
CREATE TABLE cc_trans (
    cctransid int unsigned not null auto_increment,
    cartid int unsigned not null,

    gctaskref varchar(255),
    dispatchtime int unsigned,
    jobstate varchar(255),
    joberr varchar(255),

    response char(1),
    responsetext varchar(255),
    authcode varchar(255),
    transactionid varchar(255),
    avsresponse char(1),
    cvvresponse char(1),
    responsecode mediumint unsigned,

    ccnumhash varchar(32) not null,
    expmon tinyint not null,
    expyear smallint not null,
    firstname varchar(25) not null,
    lastname varchar(25) not null,
    street1 varchar(100) not null,
    street2 varchar(100),
    city varchar(40) not null,
    state varchar(40) not null,
    country char(2) not null,
    zip varchar(20) not null,
    phone varchar(40),
    ipaddr varchar(15) not null,

    primary key (cctransid),
    index (cartid)
)
EOC

# same as the above
register_tablecreate( 'cc_log', <<'EOC');
CREATE TABLE cc_log (
    cartid int unsigned not null,
    ip varchar(15),
    transtime int unsigned not null,
    req_content text not null,
    res_content text not null,

    index (cartid)
)
EOC

register_tablecreate( 'externaluserinfo', <<'EOC');
CREATE TABLE externaluserinfo (
    site INT UNSIGNED NOT NULL,
    user VARCHAR(50) NOT NULL,
    last INT UNSIGNED,
    type CHAR(1),

    PRIMARY KEY (site, user)
)
EOC

register_tablecreate( 'renames', <<'EOC');
CREATE TABLE renames (
    renid INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    auth CHAR(13) NOT NULL,
    cartid INT UNSIGNED,
    ownerid INT UNSIGNED NOT NULL,
    renuserid INT UNSIGNED NOT NULL,
    fromuser CHAR(25),
    touser CHAR(25),
    rendate INT UNSIGNED,
    status CHAR(1) NOT NULL DEFAULT 'A',

    INDEX (ownerid)
)
EOC

register_tablecreate( "bannotes", <<'EOC');
CREATE TABLE bannotes (
    journalid    INT UNSIGNED NOT NULL,
    banid        INT UNSIGNED NOT NULL,
    remoteid     INT UNSIGNED,
    notetext     MEDIUMTEXT,

    PRIMARY KEY (journalid,banid)
)
EOC

register_tablecreate( "openid_claims", <<'EOC');
CREATE TABLE openid_claims (
    userid          INT UNSIGNED NOT NULL,
    claimed_userid  INT UNSIGNED NOT NULL,

    PRIMARY KEY (userid),
    INDEX (claimed_userid)
)
EOC

register_tablecreate( "siteadmin_email_history", <<'EOC');
CREATE TABLE siteadmin_email_history (
    msgid        INT UNSIGNED NOT NULL,
    remoteid     INT UNSIGNED NOT NULL,
    time_sent    INT UNSIGNED NOT NULL,   #unixtime
    account      VARCHAR(255) NOT NULL,
    sendto       VARCHAR(255) NOT NULL,
    subject      VARCHAR(255) NOT NULL,
    request      INT UNSIGNED,
    message      MEDIUMTEXT NOT NULL,
    notes        MEDIUMTEXT,

    PRIMARY KEY (msgid),
    INDEX (account),
    INDEX (sendto)
)
EOC

# FIXME: add alt text, etc. mediaprops?
register_tablecreate( "media", <<'EOC');
CREATE TABLE `media` (
  `userid` int(10) unsigned NOT NULL,
  `mediaid` int(10) unsigned NOT NULL,
  `anum` tinyint(3) unsigned NOT NULL,
  `ext` varchar(10) NOT NULL,
  `state` char(1) NOT NULL DEFAULT 'A',
  `mediatype` tinyint(3) unsigned NOT NULL,
  `security` enum('public','private','usemask') NOT NULL DEFAULT 'public',
  `allowmask` bigint(20) unsigned NOT NULL DEFAULT '0',
  `logtime` int(10) unsigned NOT NULL,
  `mimetype` varchar(60) NOT NULL,
  `filesize` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`mediaid`)
)
EOC

# versionid = is a mediaid, same numberspace
register_tablecreate( "media_versions", <<'EOC');
CREATE TABLE `media_versions` (
  `userid` int(10) unsigned NOT NULL,
  `mediaid` int(10) unsigned NOT NULL,
  `versionid` int(10) unsigned NOT NULL,
  `width` smallint(5) unsigned NOT NULL,
  `height` smallint(5) unsigned NOT NULL,
  `filesize` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`mediaid`,`versionid`)
)
EOC

register_tablecreate( "media_props", <<'EOC');
CREATE TABLE `media_props` (
  `userid` int(10) unsigned NOT NULL,
  `mediaid` int(10) unsigned NOT NULL,
  `propid` tinyint(3) unsigned NOT NULL,
  `value` MEDIUMBLOB NOT NULL,
  PRIMARY KEY (`userid`, `mediaid`, `propid`)
)
EOC

register_tablecreate( "media_prop_list", <<'EOC');
CREATE TABLE `media_prop_list` (
  `propid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `ownership` enum('system','user') NOT NULL DEFAULT 'user',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  `des` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
)
EOC

register_tablecreate( "collections", <<'EOC');
CREATE TABLE `collections` (
  `userid` int(10) unsigned NOT NULL,
  `colid` int(10) unsigned NOT NULL,
  `paruserid` int(10) unsigned NOT NULL,
  `parcolid` int(10) unsigned NOT NULL,
  `anum` tinyint(3) unsigned NOT NULL,
  `state` char(1) NOT NULL DEFAULT 'A',
  `security` enum('public','private','usemask') NOT NULL DEFAULT 'public',
  `allowmask` bigint(20) unsigned NOT NULL DEFAULT '0',
  `logtime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`colid`),
  INDEX (`paruserid`,`parcolid`)
)
EOC

# FIXME: the indexes here are totally whack
register_tablecreate( "collection_items", <<'EOC');
CREATE TABLE `collection_items` (
  `userid` int(10) unsigned NOT NULL,
  `colitemid` int(10) unsigned NOT NULL,
  `colid` int(10) unsigned NOT NULL,
  `itemtype` tinyint(3) unsigned NOT NULL,
  `itemownerid` int(10) unsigned NOT NULL,
  `itemid` int(10) unsigned NOT NULL,
  `logtime` int(10) unsigned NOT NULL,
  PRIMARY KEY (`userid`,`colid`,`colitemid`),
  UNIQUE (`userid`,`colid`,`itemtype`,`itemownerid`,`itemid`),
  INDEX (`itemtype`,`itemownerid`,`itemid`)
)
EOC

register_tablecreate( "dbnotes", <<'EOC');
CREATE TABLE dbnotes (
    dbnote VARCHAR(40) NOT NULL,
    PRIMARY KEY (dbnote),
    value VARCHAR(255)
)
EOC

register_tablecreate( "captcha_cache", <<'EOC');
CREATE TABLE captcha_cache (
    `captcha_id` INT UNSIGNED NOT NULL auto_increment,
    `question`   VARCHAR(255) NOT NULL,
    `answer`     VARCHAR(255) NOT NULL,
    `issuetime`  INT UNSIGNED NOT NULL DEFAULT 0,

    PRIMARY KEY (`captcha_id`),
    INDEX(`issuetime`)
)
EOC

register_tablecreate( "logslugs", <<'EOC');
CREATE TABLE `logslugs` (
  `journalid` int(10) unsigned NOT NULL DEFAULT '0',
  `jitemid` mediumint(8) unsigned NOT NULL,
  `slug` varchar(255) NOT NULL,
  PRIMARY KEY (`journalid`,`jitemid`),
  UNIQUE KEY `journalid` (`journalid`,`slug`)
)
EOC

register_tablecreate( "api_key", <<'EOC');
CREATE TABLE `api_key` (
  `userid` int(10) unsigned NOT NULL,
  `keyid` int(10) unsigned NOT NULL,
  `hash` char(32) UNIQUE NOT NULL,
  `state` char(1) NOT NULL DEFAULT 'A',
  PRIMARY KEY (`userid`,`keyid`),
  INDEX(`hash`)
)
EOC

register_tablecreate( "key_props", <<'EOC');
CREATE TABLE `key_props` (
  `userid` int(10) unsigned NOT NULL,
  `keyid` int(10) unsigned NOT NULL,
  `propid` tinyint(3) unsigned NOT NULL,
  `value` MEDIUMBLOB NOT NULL,
  PRIMARY KEY (`userid`, `keyid`, `propid`)
)
EOC

register_tablecreate( "key_prop_list", <<'EOC');
CREATE TABLE `key_prop_list` (
  `propid` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `ownership` enum('system','user') NOT NULL DEFAULT 'user',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  `des` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
)
EOC

# NOTE: new table declarations go ABOVE here ;)

### changes

register_alter(
    sub {

        my $dbh    = shift;
        my $runsql = shift;

        if ( column_type( "users_for_paid_accounts", "journaltype" ) eq "" ) {
            do_alter( "users_for_paid_accounts",
                "ALTER TABLE users_for_paid_accounts ADD journaltype CHAR(1) NOT NULL DEFAULT 'P', "
                    . "ADD INDEX(journaltype)" );
        }

        if ( column_type( "supportcat", "is_selectable" ) eq "" ) {
            do_alter( "supportcat",
                      "ALTER TABLE supportcat ADD is_selectable ENUM('1','0') "
                    . "NOT NULL DEFAULT '1', ADD public_read  ENUM('1','0') NOT "
                    . "NULL DEFAULT '1', ADD public_help ENUM('1','0') NOT NULL "
                    . "DEFAULT '1', ADD allow_screened ENUM('1','0') NOT NULL "
                    . "DEFAULT '0', ADD replyaddress VARCHAR(50), ADD hide_helpers "
                    . "ENUM('1','0') NOT NULL DEFAULT '0' AFTER allow_screened" );

        }

        if ( column_type( "supportlog", "type" ) =~ /faqref/ ) {
            do_alter( "supportlog",
                      "ALTER TABLE supportlog MODIFY type ENUM('req', 'answer', "
                    . "'custom', 'faqref', 'comment', 'internal', 'screened') "
                    . "NOT NULL" );
            do_sql("UPDATE supportlog SET type='answer' WHERE type='custom'");
            do_sql("UPDATE supportlog SET type='answer' WHERE type='faqref'");
            do_alter( "supportlog",
                      "ALTER TABLE supportlog MODIFY type ENUM('req', 'answer', "
                    . "'comment', 'internal', 'screened') NOT NULL" );

        }

        if ( table_relevant("supportcat") && column_type( "supportcat", "catkey" ) eq "" ) {
            do_alter( "supportcat", "ALTER TABLE supportcat ADD catkey VARCHAR(25) AFTER spcatid" );
            do_sql("UPDATE supportcat SET catkey=spcatid WHERE catkey IS NULL");
            do_alter( "supportcat", "ALTER TABLE supportcat MODIFY catkey VARCHAR(25) NOT NULL" );
        }

        if ( column_type( "supportcat", "no_autoreply" ) eq "" ) {
            do_alter( "supportcat",
                      "ALTER TABLE supportcat ADD no_autoreply ENUM('1', '0') "
                    . "NOT NULL DEFAULT '0'" );
        }

        if ( column_type( "support", "timelasthelp" ) eq "" ) {
            do_alter( "supportlog", "ALTER TABLE supportlog ADD INDEX (userid)" );
            do_alter( "support",    "ALTER TABLE support ADD timelasthelp INT UNSIGNED" );
        }

        if ( column_type( "duplock", "realm" ) !~ /payments/ ) {
            do_alter( "duplock",
                      "ALTER TABLE duplock MODIFY realm ENUM('support','log',"
                    . "'comment','payments') NOT NULL default 'support'" );
        }

        # upgrade people to the new capabilities system.  if they're
        # using the paidfeatures column already, we'll assign them
        # the same capability bits that ljcom will be using.
        if ( table_relevant("user") && column_type( "user", "caps" ) eq "" ) {
            do_alter( "user",
                "ALTER TABLE user ADD " . "caps SMALLINT UNSIGNED NOT NULL DEFAULT 0 AFTER user" );
            try_sql("UPDATE user SET caps=16|8|2 WHERE paidfeatures='on'");
            try_sql("UPDATE user SET caps=8|2    WHERE paidfeatures='paid'");
            try_sql("UPDATE user SET caps=4|2    WHERE paidfeatures='early'");
            try_sql("UPDATE user SET caps=2      WHERE paidfeatures='off'");
        }

        # axe this column (and its two related ones) if it exists.
        if ( column_type( "user", "paidfeatures" ) ) {
            try_sql(  "REPLACE INTO paiduser (userid, paiduntil, paidreminder) "
                    . "SELECT userid, paiduntil, paidreminder FROM user WHERE paidfeatures='paid'"
            );
            try_sql(  "REPLACE INTO paiduser (userid, paiduntil, paidreminder) "
                    . "SELECT userid, COALESCE(paiduntil,'0000-00-00'), NULL FROM user WHERE paidfeatures='on'"
            );
            do_alter( "user",
                "ALTER TABLE user DROP paidfeatures, DROP paiduntil, DROP paidreminder" );
        }

        # add scope columns to proplist tables
        if ( column_type( "userproplist", "scope" ) eq "" ) {
            do_alter( "userproplist",
                      "ALTER TABLE userproplist ADD scope ENUM('general', 'local') "
                    . "DEFAULT 'general' NOT NULL" );
        }

        if ( column_type( "logproplist", "scope" ) eq "" ) {
            do_alter( "logproplist",
                      "ALTER TABLE logproplist ADD scope ENUM('general', 'local') "
                    . "DEFAULT 'general' NOT NULL" );
        }

        if ( column_type( "talkproplist", "scope" ) eq "" ) {
            do_alter( "talkproplist",
                      "ALTER TABLE talkproplist ADD scope ENUM('general', 'local') "
                    . "DEFAULT 'general' NOT NULL" );
        }

        if ( column_type( "priv_list", "scope" ) eq "" ) {
            do_alter( "priv_list",
                      "ALTER TABLE priv_list ADD scope ENUM('general', 'local') "
                    . "DEFAULT 'general' NOT NULL" );
        }

        # change size of stats table to accomodate meme data, and shrink statcat,
        # since it's way too big
        if ( column_type( "stats", "statcat" ) eq "varchar(100)" ) {
            do_alter( "stats",
                      "ALTER TABLE stats "
                    . "MODIFY statcat VARCHAR(30) NOT NULL, "
                    . "MODIFY statkey VARCHAR(150) NOT NULL, "
                    . "MODIFY statval INT UNSIGNED NOT NULL, "
                    . "DROP INDEX statcat" );
        }

        if ( column_type( "priv_list", "is_public" ) eq "" ) {
            do_alter( "priv_list",
                "ALTER TABLE priv_list " . "ADD is_public ENUM('1', '0') DEFAULT '1' NOT NULL" );
        }

        if ( column_type( "user", "clusterid" ) eq "" ) {
            do_alter( "user",
                      "ALTER TABLE user "
                    . "ADD clusterid TINYINT UNSIGNED NOT NULL AFTER caps, "
                    . "ADD dversion TINYINT UNSIGNED NOT NULL AFTER clusterid, "
                    . "ADD INDEX idxcluster (clusterid), "
                    . "ADD INDEX idxversion (dversion)" );
        }

        # add the default encoding field, for recoding older pre-Unicode stuff

        if ( column_type( "user", "oldenc" ) eq "" ) {
            do_alter( "user",
                      "ALTER TABLE user "
                    . "ADD oldenc TINYINT DEFAULT 0 NOT NULL, "
                    . "MODIFY name CHAR(80) NOT NULL" );
        }

        if ( column_type( "user", "allow_getpromos" ) ne "" ) {
            do_alter( "user", "ALTER TABLE user DROP allow_getpromos" );
        }

        #allow longer moodtheme pic URLs
        if ( column_type( "moodthemedata", "picurl" ) eq "varchar(100)" ) {
            do_alter( "moodthemedata", "ALTER TABLE moodthemedata MODIFY picurl VARCHAR(200)" );
        }

        # change interest.interest key to being unique, if it's not already
        {
            my $sth = $dbh->prepare("SHOW INDEX FROM interests");
            $sth->execute;
            while ( my $i = $sth->fetchrow_hashref ) {
                if ( $i->{'Key_name'} eq "interest" && $i->{'Non_unique'} ) {
                    do_alter( "interests",
                              "ALTER IGNORE TABLE interests "
                            . "DROP INDEX interest, ADD UNIQUE interest (interest)" );
                    last;
                }
            }
        }

        if ( column_type( "supportcat", "scope" ) eq "" ) {
            do_alter( "supportcat",
                      "ALTER IGNORE TABLE supportcat ADD scope ENUM('general', 'local') "
                    . "NOT NULL DEFAULT 'general', ADD UNIQUE (catkey)" );
        }

        # convert 'all' arguments to '*'
        if ( table_relevant("priv_map") && !check_dbnote("privcode_all_to_*") ) {

            # arg isn't keyed, but this table is only a couple thousand rows
            do_sql("UPDATE priv_map SET arg='*' WHERE arg='all'");

            set_dbnote( "privcode_all_to_*", 1 );
        }

        # this never ended up being useful, and just freaked people out unnecessarily.
        if ( column_type( "user", "track" ) ) {
            do_alter( "user", "ALTER TABLE user DROP track" );
        }

        # need more choices (like "Y" for sYndicated journals)
        if ( column_type( "user", "journaltype" ) =~ /enum/i ) {
            do_alter( "user", "ALTER TABLE user MODIFY journaltype CHAR(1) NOT NULL DEFAULT 'P'" );
        }

        unless ( column_type( "syndicated", "laststatus" ) ) {
            do_alter( "syndicated",
                "ALTER TABLE syndicated ADD laststatus VARCHAR(80), ADD lastnew DATETIME" );
        }

        unless ( column_type( "syndicated", "numreaders" ) ) {
            do_alter( "syndicated",
                "ALTER TABLE syndicated " . "ADD numreaders MEDIUMINT, ADD INDEX (numreaders)" );
        }

        if ( column_type( "community", "ownerid" ) ) {
            do_alter( "community", "ALTER TABLE community DROP ownerid" );
        }

        unless ( column_type( "userproplist", "cldversion" ) ) {
            do_alter( "userproplist",
                "ALTER TABLE userproplist ADD cldversion TINYINT UNSIGNED NOT NULL AFTER indexed" );
        }

        unless ( column_type( "authactions", "used" )
            && index_name( "authactions", "INDEX:userid" )
            && index_name( "authactions", "INDEX:datecreate" ) )
        {

            do_alter( "authactions",
                      "ALTER TABLE authactions "
                    . "ADD used enum('Y', 'N') DEFAULT 'N' AFTER arg1, "
                    . "ADD INDEX(userid), ADD INDEX(datecreate)" );
        }

        unless ( column_type( "s2styles", "modtime" ) ) {
            do_alter( "s2styles",
                "ALTER TABLE s2styles ADD modtime INT UNSIGNED NOT NULL AFTER name" );
        }

        # Add BLOB flag to proplist
        unless ( column_type( "userproplist", "datatype" ) =~ /blobchar/ ) {
            if ( column_type( "userproplist", "is_blob" ) ) {
                do_alter( "userproplist", "ALTER TABLE userproplist DROP is_blob" );
            }
            do_alter( "userproplist",
"ALTER TABLE userproplist MODIFY datatype ENUM('char','num','bool','blobchar') NOT NULL DEFAULT 'char'"
            );
        }

        if ( column_type( "challenges", "count" ) eq "" ) {
            do_alter( "challenges",
                      "ALTER TABLE challenges ADD "
                    . "count int(5) UNSIGNED NOT NULL DEFAULT 0 AFTER challenge" );
        }

        unless ( index_name( "support", "INDEX:requserid" ) ) {
            do_alter( "support",
                "ALTER IGNORE TABLE support ADD INDEX (requserid), ADD INDEX (reqemail)" );
        }

        unless ( column_type( "community", "membership" ) =~ /moderated/i ) {
            do_alter( "community",
                      "ALTER TABLE community MODIFY COLUMN "
                    . "membership ENUM('open','closed','moderated') DEFAULT 'open' NOT NULL" );
        }

        if ( column_type( "userproplist", "multihomed" ) eq '' ) {
            do_alter( "userproplist",
                      "ALTER TABLE userproplist "
                    . "ADD multihomed ENUM('1', '0') NOT NULL DEFAULT '0' AFTER cldversion" );
        }

        if ( index_name( "moodthemedata", "INDEX:moodthemeid" ) ) {
            do_alter( "moodthemedata", "ALTER IGNORE TABLE moodthemedata DROP KEY moodthemeid" );
        }

        if ( column_type( "userpic2", "flags" ) eq '' ) {
            do_alter( "userpic2",
                      "ALTER TABLE userpic2 "
                    . "ADD flags tinyint(1) unsigned NOT NULL default 0 AFTER comment, "
                    . "ADD location enum('blob','disk','mogile') default NULL AFTER flags" );
        }

        if ( column_type( "counter", "max" ) =~ /mediumint/ ) {
            do_alter( "counter", "ALTER TABLE counter MODIFY max INT UNSIGNED NOT NULL DEFAULT 0" );
        }

        if ( column_type( "userpic2", "url" ) eq '' ) {
            do_alter( "userpic2",
                "ALTER TABLE userpic2 " . "ADD url VARCHAR(255) default NULL AFTER location" );
        }

        unless ( column_type( "spamreports", "posttime" ) ne '' ) {
            do_alter( "spamreports",
                      "ALTER TABLE spamreports ADD COLUMN posttime INT(10) UNSIGNED "
                    . "NOT NULL AFTER reporttime, ADD COLUMN state ENUM('open', 'closed') DEFAULT 'open' "
                    . "NOT NULL AFTER posttime" );
        }

        if ( column_type( "spamreports", "report_type" ) eq '' ) {
            do_alter( "spamreports",
                      "ALTER TABLE spamreports "
                    . "ADD report_type ENUM('entry','comment') NOT NULL DEFAULT 'comment' "
                    . "AFTER posterid" );
        }

        if ( column_type( "sessions", "exptype" ) !~ /once/ ) {
            do_alter( "sessions",
                      "ALTER TABLE sessions CHANGE COLUMN exptype "
                    . "exptype ENUM('short', 'long', 'once') NOT NULL" );
        }

        # TODO: fix initial definition to match this, make table innodb
        if ( column_type( "ml_items", "itid" ) =~ /auto_increment/ ) {
            do_alter( "ml_items",
                      "ALTER TABLE ml_items MODIFY COLUMN "
                    . "itid MEDIUMINT UNSIGNED NOT NULL DEFAULT 0" );
        }

        # TODO: fix initial definition to match this, make table innodb
        if ( column_type( "ml_text", "txtid" ) =~ /auto_increment/ ) {
            do_alter( "ml_text",
                      "ALTER TABLE ml_text MODIFY COLUMN "
                    . "txtid MEDIUMINT UNSIGNED NOT NULL DEFAULT 0" );
        }

        unless ( column_type( "syndicated", "oldest_ourdate" ) ) {
            do_alter( "syndicated",
                "ALTER TABLE syndicated ADD oldest_ourdate DATETIME AFTER lastnew" );
        }

        if ( column_type( "sessions", "userid" ) =~ /mediumint/ ) {
            do_alter( "sessions",
                "ALTER TABLE sessions MODIFY COLUMN userid INT UNSIGNED NOT NULL" );
        }

        if ( column_type( "faq", "summary" ) eq '' ) {
            do_alter( "faq", "ALTER TABLE faq ADD summary TEXT AFTER question" );
        }

        if ( column_type( "spamreports", "srid" ) eq '' ) {
            do_alter( "spamreports", "ALTER TABLE spamreports DROP PRIMARY KEY" );

            do_alter( "spamreports",
"ALTER TABLE spamreports ADD srid MEDIUMINT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT FIRST"
            );

            do_alter( "spamreports", "ALTER TABLE spamreports ADD INDEX (reporttime, journalid)" );
        }

        if ( column_type( "includetext", "inctext" ) !~ /mediumtext/ ) {
            do_alter( "includetext", "ALTER TABLE includetext MODIFY COLUMN inctext MEDIUMTEXT" );
        }

        # table format totally changed, we'll just truncate and modify
        # all of the columns since the data is just summary anyway
        if ( index_name( "active_user", "INDEX:time" ) ) {
            do_sql("TRUNCATE TABLE active_user");
            do_alter( "active_user",
                      "ALTER TABLE active_user "
                    . "DROP time, DROP KEY userid, "
                    . "ADD year SMALLINT NOT NULL FIRST, "
                    . "ADD month TINYINT NOT NULL AFTER year, "
                    . "ADD day TINYINT NOT NULL AFTER month, "
                    . "ADD hour TINYINT NOT NULL AFTER day, "
                    . "ADD PRIMARY KEY (year, month, day, hour, userid)" );
        }

        if ( index_name( "active_user_summary", "UNIQUE:year-month-day-hour-clusterid-type" ) ) {
            do_alter( "active_user_summary",
                      "ALTER TABLE active_user_summary DROP PRIMARY KEY, "
                    . "ADD INDEX (year, month, day, hour)" );
        }

        if ( column_type( "blobcache", "bckey" ) =~ /40/ ) {
            do_alter( "blobcache", "ALTER TABLE blobcache MODIFY bckey VARCHAR(255) NOT NULL" );
        }

        if ( column_type( "eventtypelist", "eventtypeid" ) ) {
            do_alter( "eventtypelist",
"ALTER TABLE eventtypelist CHANGE eventtypeid etypeid SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT"
            );
        }

        # add index on journalid, etypeid to subs
        unless ( index_name( "subs", "INDEX:etypeid-journalid" )
            || index_name( "subs", "INDEX:etypeid-journalid-userid" ) )
        {
            # This one is deprecated by the one below, which adds a userid
            # at the end.  hence the double if above.
            do_alter( "subs", "ALTER TABLE subs " . "ADD INDEX (etypeid, journalid)" );
        }

        unless ( column_type( "sch_error", "funcid" ) ) {
            do_alter( "sch_error",
"alter table sch_error add funcid int(10) unsigned NOT NULL default 0, add index (funcid, error_time)"
            );
        }

        unless ( column_type( "sch_exitstatus", "funcid" ) ) {
            do_alter( "sch_exitstatus",
"alter table sch_exitstatus add funcid INT UNSIGNED NOT NULL DEFAULT 0, add index (funcid)"
            );
        }

        # add an index
        unless ( index_name( "subs", "INDEX:etypeid-journalid-userid" ) ) {
            do_alter( "subs",
"ALTER TABLE subs DROP INDEX etypeid, ADD INDEX etypeid (etypeid, journalid, userid)"
            );
        }

        # fix primary key
        unless ( index_name( "pollresult2", "UNIQUE:journalid-pollid-pollqid-userid" ) ) {
            do_alter( "pollresult2",
"ALTER TABLE pollresult2 DROP PRIMARY KEY, ADD PRIMARY KEY (journalid,pollid,pollqid,userid)"
            );
        }

        # fix primary key
        unless ( index_name( "pollsubmission2", "UNIQUE:journalid-pollid-userid" ) ) {
            do_alter( "pollsubmission2",
"ALTER TABLE pollsubmission2 DROP PRIMARY KEY, ADD PRIMARY KEY (journalid,pollid,userid)"
            );
        }

        # add an indexed 'userid' column
        unless ( column_type( "expunged_users", "userid" ) ) {
            do_alter( "expunged_users",
                      "ALTER TABLE expunged_users ADD userid INT UNSIGNED NOT NULL FIRST, "
                    . "ADD INDEX (userid)" );
        }

        unless ( column_type( "usermsgproplist", "scope" ) ) {
            do_alter( "usermsgproplist",
                      "ALTER TABLE usermsgproplist ADD scope ENUM('general', 'local') "
                    . "DEFAULT 'general' NOT NULL" );
        }

        if (   table_relevant("spamreports")
            && column_type( "spamreports", "report_type" ) !~ /message/ )
        {
            # cache table by running select
            do_sql("SELECT COUNT(*) FROM spamreports");

            # add 'message' enum
            do_alter( "spamreports",
                      "ALTER TABLE spamreports "
                    . "CHANGE COLUMN report_type report_type "
                    . "ENUM('entry','comment','message') NOT NULL DEFAULT 'comment'" );
        }

        if ( column_type( "supportcat", "user_closeable" ) eq "" ) {
            do_alter( "supportcat",
                      "ALTER TABLE supportcat ADD "
                    . "user_closeable ENUM('1', '0') NOT NULL DEFAULT '1' "
                    . "AFTER hide_helpers" );
        }

        # add a status column to polls
        unless ( column_type( "poll2", "status" ) ) {
            do_alter( "poll2",
                "ALTER TABLE poll2 ADD status CHAR(1) AFTER name, " . "ADD INDEX (status)" );
        }

        unless ( column_type( "log2", "allowmask" ) =~ /^bigint/ ) {
            do_alter( "log2",
                q{ ALTER TABLE log2 MODIFY COLUMN allowmask BIGINT UNSIGNED NOT NULL } );
        }

        unless ( column_type( "logsec2", "allowmask" ) =~ /^bigint/ ) {
            do_alter( "logsec2",
                q{ ALTER TABLE logsec2 MODIFY COLUMN allowmask BIGINT UNSIGNED NOT NULL } );
        }

        unless ( column_type( "logkwsum", "security" ) =~ /^bigint/ ) {
            do_alter( "logkwsum",
                q{ ALTER TABLE logkwsum MODIFY COLUMN security BIGINT UNSIGNED NOT NULL } );
        }

        unless ( column_type( "logproplist", "ownership" ) ) {
            do_alter( "logproplist",
                      "ALTER TABLE logproplist ADD ownership ENUM('system', 'user') "
                    . "DEFAULT 'user' NOT NULL" );
        }

        unless ( column_type( "jobstatus", "userid" ) ) {
            do_alter( "jobstatus",
                "ALTER TABLE jobstatus " . "ADD userid INT UNSIGNED DEFAULT NULL" )
                ;    # yes, we allow userid to be NULL - it means no userid checking
        }

        unless ( column_type( "supportlog", "tier" ) ) {
            do_alter( "supportlog",
                "ALTER TABLE supportlog " . "ADD tier TINYINT UNSIGNED DEFAULT NULL" );
        }

        unless ( column_type( "logproplist", "ownership" ) ) {
            do_alter( "logproplist",
                      "ALTER TABLE logproplist ADD ownership ENUM('system', 'user') "
                    . "DEFAULT 'user' NOT NULL" );
        }

        if ( column_type( "acctcode", "auth" ) =~ /^\Qchar(5)\E/ ) {
            do_alter( "acctcode", "ALTER TABLE acctcode MODIFY auth CHAR(13)" );
        }

        unless ( column_type( "acctcode", "reason" ) ) {
            do_alter( "acctcode", "ALTER TABLE acctcode ADD reason VARCHAR(255)" );
        }

        unless ( column_type( "acctcode", "timegenerate" ) ) {
            do_alter( "acctcode", "ALTER TABLE acctcode ADD timegenerate TIMESTAMP" );
        }

        unless ( column_type( "userpic2", "description" ) ) {
            do_alter( "userpic2",
                "ALTER TABLE userpic2 ADD description varchar(255) BINARY NOT NULL default ''" );

        }

        unless ( column_type( 'user', 'user' ) =~ /25/ ) {
            do_alter( 'user', "ALTER TABLE user MODIFY COLUMN user CHAR(25)" );
        }

        unless ( column_type( 'useridmap', 'user' ) =~ /25/ ) {
            do_alter( 'useridmap', "ALTER TABLE useridmap MODIFY COLUMN user CHAR(25) NOT NULL" );
        }

        unless ( column_type( 'expunged_users', 'user' ) =~ /25/ ) {
            do_alter( 'expunged_users',
                "ALTER TABLE expunged_users MODIFY COLUMN user VARCHAR(25) NOT NULL" );
        }

        unless ( column_type( "acctcode", "timegenerate" ) =~ /^\Qint(10) unsigned\E/ ) {
            do_alter( "acctcode", "ALTER TABLE acctcode MODIFY COLUMN timegenerate INT UNSIGNED" );
        }

        unless ( column_type( "logtext2", "event" ) =~ /^mediumtext/ ) {
            do_alter( "logtext2", "ALTER TABLE logtext2 MODIFY COLUMN event MEDIUMTEXT" );
        }

        if ( column_type( "random_user_set", "journaltype" ) eq '' ) {
            do_code(
                "changing random_user_set primary key",
                sub {
                    # We're changing the primary key, so we need to make sure we don't have
                    # any duplicates of the old primary key lying around to trip us up.
                    my $sth = $dbh->prepare(
                        "SELECT posttime, userid FROM random_user_set ORDER BY posttime desc");
                    $sth->execute();
                    my %found = ();
                    while ( my $rowh = $sth->fetchrow_hashref ) {
                        $dbh->do( "DELETE FROM random_user_set WHERE userid=? AND posttime=?",
                            undef, $rowh->{'userid'}, $rowh->{'posttime'} )
                            if $found{ $rowh->{'userid'} }++;
                    }
                }
            );

            do_alter( "random_user_set",
                "ALTER TABLE random_user_set ADD COLUMN journaltype CHAR(1) NOT NULL DEFAULT 'P'" );
            do_alter( "random_user_set",
                "ALTER TABLE random_user_set DROP PRIMARY KEY, ADD PRIMARY KEY (userid)" );
            do_alter( "random_user_set", "ALTER TABLE random_user_set ADD INDEX (posttime)" );
        }

        unless ( column_type( "acctcode", "timesent" ) ) {
            do_alter( "acctcode", "ALTER TABLE acctcode ADD timesent INT UNSIGNED" );
        }

        unless ( column_type( "poll2", "whovote" ) =~ /trusted/ ) {
            do_alter( "poll2",
"ALTER TABLE poll2 MODIFY COLUMN whovote ENUM('all','trusted','ofentry') NOT NULL default 'all'"
            );
            do_alter( "poll2",
"ALTER TABLE poll2 MODIFY COLUMN whoview ENUM('all','trusted','ofentry','none') NOT NULL default 'all'"
            );
        }

        unless ( column_type( 'ml_items', 'proofed' ) ) {
            do_alter( 'ml_items',
                "ALTER TABLE ml_items ADD COLUMN proofed TINYINT NOT NULL DEFAULT 0 AFTER itcode" );
            do_alter( 'ml_items', "ALTER TABLE ml_items ADD INDEX (proofed)" );
            do_alter( 'ml_items',
                "ALTER TABLE ml_items ADD COLUMN updated TINYINT NOT NULL DEFAULT 0 AFTER proofed"
            );
            do_alter( 'ml_items', "ALTER TABLE ml_items ADD INDEX (updated)" );
        }

        unless ( column_type( 'ml_items', 'visible' ) ) {
            do_alter( 'ml_items',
                "ALTER TABLE ml_items ADD COLUMN visible TINYINT NOT NULL DEFAULT 0 AFTER updated"
            );
        }

        unless ( column_type( 'import_items', 'status' ) =~ /aborted/ ) {
            do_alter(
                'import_items',
                q{ALTER TABLE import_items MODIFY COLUMN
                    status ENUM('init', 'ready', 'queued', 'failed', 'succeeded', 'aborted')
                    NOT NULL DEFAULT 'init'}
            );
        }

        unless ( column_type( 'shop_carts', 'nextscan' ) =~ /int/ ) {
            do_alter( 'shop_carts',
q{ALTER TABLE shop_carts ADD COLUMN nextscan INT UNSIGNED NOT NULL DEFAULT 0 AFTER state}
            );
        }

        unless ( column_type( 'shop_carts', 'authcode' ) =~ /varchar/ ) {
            do_alter( 'shop_carts',
                q{ALTER TABLE shop_carts ADD COLUMN authcode VARCHAR(20) NOT NULL AFTER nextscan} );
        }

        unless ( column_type( 'shop_carts', 'paymentmethod' ) =~ /int/ ) {
            do_alter( 'shop_carts',
                q{ALTER TABLE shop_carts ADD COLUMN paymentmethod INT UNSIGNED NOT NULL AFTER state}
            );
        }

        unless ( column_type( 'shop_carts', 'email' ) =~ /varchar/ ) {
            do_alter( 'shop_carts',
                q{ALTER TABLE shop_carts ADD COLUMN email VARCHAR(255) AFTER userid} );
        }

        unless ( column_type( 'pp_log', 'ip' ) =~ /varchar/ ) {
            do_alter( 'pp_log',
                q{ALTER TABLE pp_log ADD COLUMN ip VARCHAR(15) NOT NULL AFTER ppid} );
        }

        unless ( column_type( 'acctcode', 'email' ) ) {
            do_alter( 'acctcode',
                q{ALTER TABLE acctcode ADD COLUMN email VARCHAR(255) AFTER timesent} );
        }

        # convert 'ljcut' userprops
        if ( table_relevant("userproplist") && !check_dbnote("userprop_ljcut_to_cut") ) {
            do_sql(
"UPDATE userproplist SET name='opt_cut_disable_reading' WHERE name='opt_ljcut_disable_friends'"
            );
            do_sql(
"UPDATE userproplist SET name='opt_cut_disable_journal' WHERE name='opt_ljcut_disable_lastn'"
            );
            set_dbnote( "userprop_ljcut_to_cut", 1 );
        }

        unless ( column_type( 'import_data', 'usejournal' ) ) {
            do_alter( 'import_data',
                q{ALTER TABLE import_data ADD COLUMN usejournal VARCHAR(255) AFTER username} );
        }

     # FIXME: This should be moved into a maint script or something,
     #   but if someone ever does remove the " 0 && " from here, this whole body needs to be wrapped
     #   in a do_code block ( To prevent the warning message from delaying things )
        if ( 0 && table_relevant("logkwsum") && !check_dbnote("logkwsum_fix_filtered_counts_2010") )
        {
  # this is a very, very racy situation ... we want to do an update of this data, but if anybody
  # else is actively using this table, they're going to be inserting bad data on top of us which
  # will leave SOMEONE in an inconsistent state.  let's warn the user that they should have the site
  # turned off for this update.
            unless ( $::_warn_logkwsum++ > 0 ) {
                warn <<EOF;

* * * * * * * * * WARNING * * * * * * * *

We need to do an update of tag security metadata.  This is an UNSAFE update
and we request that you shut off your site.

Please turn off TheSchwartz workers, Gearman workers, Apache processes, and
anything else that can touch the database.

Once you are done doing that, please press ENTER to proceed.

Press Ctrl+C to cancel this operation now.

* * * * * * * * * WARNING * * * * * * * *
EOF
                $_ = <>;
            }

            do_sql('LOCK TABLES logkwsum WRITE, logtags WRITE, log2 WRITE');
            do_sql('DELETE FROM logkwsum');

            do_sql(
                q{INSERT INTO logkwsum
                  SELECT logtags.journalid, logtags.kwid, log2.allowmask, COUNT(*)
                  FROM log2, logtags
                  WHERE logtags.journalid = log2.journalid
                    AND logtags.jitemid = log2.jitemid
                    AND log2.security = 'usemask'
                    AND log2.allowmask > 0
                  GROUP BY journalid, kwid, allowmask
            }
            );

            do_sql(
                q{INSERT INTO logkwsum
                  SELECT logtags.journalid, logtags.kwid, 0, COUNT(*)
                  FROM log2, logtags
                  WHERE logtags.journalid = log2.journalid
                    AND logtags.jitemid = log2.jitemid
                    AND ( log2.security = 'private'
                          OR ( log2.security = 'usemask'
                               AND log2.allowmask = 0 ) )
                  GROUP BY journalid, kwid
            }
            );

            do_sql(
                q{INSERT INTO logkwsum
                  SELECT logtags.journalid, logtags.kwid, 1 << 63, COUNT(*)
                  FROM log2, logtags
                  WHERE logtags.journalid = log2.journalid
                    AND logtags.jitemid = log2.jitemid
                    AND log2.security = 'public'
                  GROUP BY journalid, kwid
            }
            );

            do_sql('UNLOCK TABLES');
            set_dbnote( "logkwsum_fix_filtered_counts_2010", 1 );
        }

        unless ( column_type( 'clustertrack2', 'accountlevel' ) ) {
            do_alter( 'clustertrack2',
q{ALTER TABLE clustertrack2 ADD COLUMN accountlevel SMALLINT UNSIGNED AFTER clusterid}
            );
        }

        unless ( column_type( 'clustertrack2', 'journaltype' ) ) {
            do_alter( 'clustertrack2',
                q{ALTER TABLE clustertrack2 ADD COLUMN journaltype char(1) AFTER accountlevel} );
        }

        unless ( column_type( 'acctcode_promo', 'suggest_journalid' ) ) {
            do_alter( 'acctcode_promo',
                q{ALTER TABLE acctcode_promo ADD COLUMN suggest_journalid INT UNSIGNED} );
        }

        # migrate interest names to sitekeywords
        if (   table_relevant("sitekeywords")
            && table_relevant("interests")
            && column_type( "interests", "interest" ) )
        {
            do_sql('LOCK TABLES sitekeywords WRITE, interests WRITE');
            do_sql(   "REPLACE INTO sitekeywords (kwid, keyword) "
                    . "SELECT intid, interest FROM interests" );
            do_alter( "interests", "ALTER TABLE interests DROP interest" );
            do_sql('UNLOCK TABLES');
        }

        # convert xpost-footer-update from char to blobchar
        if ( table_relevant('userproplite2') ) {
            my $uprop = LJ::get_prop( user => 'crosspost_footer_text' );
            if ( defined($uprop) ) {
                my $upropid = $uprop->{upropid};

                my $testresult = $dbh->selectrow_array(
                    "SELECT upropid FROM userproplite2 WHERE upropid = $upropid LIMIT 1");
                if ( $testresult > 0 ) {
                    do_sql(   "INSERT IGNORE INTO userpropblob (userid, upropid, value) "
                            . "    SELECT userid, upropid, value FROM userproplite2 WHERE upropid = $upropid"
                    );
                    do_sql("DELETE FROM userproplite2 WHERE upropid = $upropid");
                }
            }
        }
        if ( table_relevant("userproplist") && !check_dbnote("xpost_footer_update") ) {
            do_sql(
                "UPDATE userproplist SET datatype = 'blobchar' WHERE name = 'crosspost_footer_text'"
            );
            set_dbnote( "xpost_footer_update", 1 );
        }

        unless ( column_type( 'externalaccount', 'recordlink' ) ) {
            do_alter( 'externalaccount',
"ALTER TABLE externalaccount ADD COLUMN recordlink enum('1','0') NOT NULL default '0'"
            );
        }

        unless ( column_type( 'import_data', 'options' ) ) {
            do_alter( 'import_data', q{ALTER TABLE import_data ADD COLUMN options BLOB} );
        }

        unless ( column_type( 'moods', 'weight' ) ) {
            do_alter( 'moods',
                q{ALTER TABLE moods ADD COLUMN weight tinyint unsigned default NULL} );
        }

        unless ( column_type( 'poll2', 'isanon' ) ) {
            do_alter( 'poll2',
                "ALTER TABLE poll2 ADD COLUMN isanon enum('yes','no') NOT NULL default 'no'" );
        }

        # Merge within-category split timestamps
        if ( table_relevant("site_stats")
            && !check_dbnote("unsplit_stats_timestamps") )
        {
            # Because category+key+time is a UNIQUE key, there's no need to check
            # for duplicates or inconsistencies. Instead, just rely on mysql
            # complaining. Update is idempotent, interruptible, and restartable.
            my $stats = $dbh->selectall_hashref(
                qq{ SELECT category_id, insert_time, COUNT(*)
                                      FROM site_stats
                                      GROUP BY category_id, insert_time
                                      ORDER BY category_id ASC,
                                               insert_time ASC; },
                [qw( category_id insert_time )]
            );
            die $dbh->errstr if $dbh->err || !defined $stats;
            foreach my $cat ( keys %$stats ) {
                my $lasttime;
                foreach my $time ( sort { $a <=> $b } keys %{ $stats->{$cat} } ) {

                    # Arbitrary limit is arbitrary
                    if ( defined $lasttime and $time - $lasttime < 60 ) {
                        do_sql(
                            qq{ UPDATE site_stats SET insert_time = $lasttime
                                     WHERE category_id = $cat
                                           AND insert_time = $time }
                        );
                    }
                    else {
                        $lasttime = $time;
                    }
                }
            }
            set_dbnote( "unsplit_stats_timestamps", 1 );
        }

        unless ( column_type( 'externalaccount', 'options' ) ) {
            do_alter( 'externalaccount', "ALTER TABLE externalaccount ADD COLUMN options blob" );
        }

        unless ( column_type( 'acctcode_promo', 'paid_class' ) ) {
            do_alter( 'acctcode_promo',
                "ALTER TABLE acctcode_promo ADD COLUMN paid_class varchar(100)" );
        }

        unless ( column_type( 'acctcode_promo', 'paid_months' ) ) {
            do_alter( 'acctcode_promo',
                "ALTER TABLE acctcode_promo ADD COLUMN paid_months tinyint unsigned" );
        }

        unless ( column_type( 'acctcode_promo', 'expiry_date' ) ) {
            do_alter( 'acctcode_promo',
"ALTER TABLE acctcode_promo ADD COLUMN expiry_date int(10) unsigned NOT NULL default '0'"
            );
        }

        if ($LJ::IS_DEV_SERVER) {

            # strip constant definitions from user layers
            if ( table_relevant("s2compiled2") && !check_dbnote("no_layer_constants") ) {
                my $uses =
q{ 'use constant VTABLE => 0;\nuse constant STATIC => 1;\nuse constant PROPS => 2;\n' };
                do_sql("UPDATE s2compiled2 SET compdata = REPLACE(compdata,$uses,'')");
                set_dbnote( "no_layer_constants", 1 );
            }
        }

        unless ( check_dbnote('sitekeywords_binary') ) {
            do_alter( 'sitekeywords',
                q{ALTER TABLE sitekeywords MODIFY keyword VARCHAR(255) BINARY NOT NULL} );
            set_dbnote( "sitekeywords_binary", 1 );
        }

        if ( table_relevant("vgift_counts") && !check_dbnote("init_vgift_counts") ) {
            do_sql("INSERT IGNORE INTO vgift_counts (vgiftid) SELECT vgiftid FROM vgift_ids");
            set_dbnote( "init_vgift_counts", 1 );
        }

        unless ( column_type( 'acctcode_promo', 'paid_class' ) =~ /^\Qvarchar(100)\E/ ) {
            do_alter( 'acctcode_promo',
                "ALTER TABLE acctcode_promo MODIFY COLUMN paid_class varchar(100)" );
        }

        # Add the hover text field in 'links' for existing installations

        unless ( column_type( 'links', 'hover' ) ) {
            do_alter( 'links', "ALTER TABLE links ADD COLUMN hover varchar(255) default NULL" );
        }

        if ( table_relevant("wt_edges") && !check_dbnote("fix_redirect_edges") ) {
            do_code(
                "fixing edges leading to a redirect account",
                sub {
                    my $sth = $dbh->prepare(
                        qq{ SELECT from_userid, to_userid FROM wt_edges INNER JOIN user
                                    ON user.journaltype="R" AND user.userid=wt_edges.to_userid;
                                    }
                    );
                    $sth->execute();
                    die $sth->errstr if $sth->err;

                    while ( my ( $from_userid, $to_userid ) = $sth->fetchrow_array ) {
                        my $from_u = LJ::load_userid($from_userid);
                        my $to_u   = LJ::load_userid($to_userid);

                        my $redir_u = $to_u->get_renamed_user;

                        warn
"transferring edge of $from_u->{user}=>$to_u->{user} to $from_u->{user}=>$redir_u->{user}";
                        if ( $from_u->trusts($to_u) ) {
                            if ( $from_u->trusts($redir_u) ) {
                                warn "...already trusted";
                            }
                            else {
                                warn "...adding trust edge";
                                $from_u->add_edge( $redir_u, trust => { nonotify => 1 } );
                            }

                            $from_u->remove_edge( $to_u, trust => { nonotify => 1 } );
                        }
                        if ( $from_u->watches($to_u) ) {
                            if ( $from_u->watches($redir_u) ) {
                                warn "...already watched";
                            }
                            else {
                                warn "...adding trust edge";
                                $from_u->add_edge( $redir_u, watch => { nonotify => 1 } );
                            }

                            $from_u->remove_edge( $to_u, watch => { nonotify => 1 } );
                        }
                    }

                    set_dbnote( "fix_redirect_edges", 1 );
                }
            );
        }

        # accommodate more poll answers by widening value
        if ( column_type( "pollresult2", "value" ) eq "varchar(255)" ) {
            do_alter( "pollresult2",
                "ALTER TABLE pollresult2 " . "MODIFY COLUMN value VARCHAR(1024) DEFAULT NULL" );
        }

        # changes opts size of pollquestion2 to 255 in order to accommodate labels
        if ( column_type( 'pollquestion2', 'opts' ) eq "varchar(20)" ) {
            do_alter( 'pollquestion2',
                "ALTER TABLE pollquestion2 MODIFY COLUMN opts VARCHAR(255) DEFAULT NULL" );
        }

        if ( column_type( "syndicated", "fuzzy_token" ) eq '' ) {
            do_alter( 'syndicated',
                      "ALTER TABLE syndicated "
                    . "ADD COLUMN fuzzy_token VARCHAR(255), "
                    . "ADD INDEX (fuzzy_token);" );
        }

        if ( column_type( "support", "timemodified" ) eq '' ) {
            do_alter( 'support',
                "ALTER TABLE support ADD COLUMN timemodified int(10) unsigned default NULL" );
        }

        if ( column_type( "externalaccount", "active" ) eq '' ) {
            do_alter( 'externalaccount',
                      "ALTER TABLE externalaccount "
                    . "ADD COLUMN active enum('1', '0') NOT NULL default '1'" );
        }

        if ( column_type( "spamreports", "client" ) eq '' ) {
            do_alter( "spamreports",
                      "ALTER TABLE spamreports "
                    . "ADD COLUMN client VARCHAR(255), "
                    . "ADD INDEX (client)" );
        }

        # Needed to cache embed linktext to minimize external API calls
        if ( column_type( "embedcontent", "linktext" ) eq '' ) {
            do_alter( 'embedcontent',
                      "ALTER TABLE embedcontent "
                    . "ADD COLUMN linktext VARCHAR(255), "
                    . "ADD COLUMN url VARCHAR(255);" );
        }

        if ( column_type( "embedcontent_preview", "linktext" ) eq '' ) {
            do_alter( 'embedcontent_preview',
                      "ALTER TABLE embedcontent_preview "
                    . "ADD COLUMN linktext VARCHAR(255), "
                    . "ADD COLUMN url VARCHAR(255);" );

        }

        if ( table_relevant("media_versions") && !check_dbnote("init_media_versions_dimensions") ) {
            do_sql('LOCK TABLES media_versions WRITE, media WRITE');

            do_code(
                "populate media_versions using existing data in media",
                sub {
                    my $sth = $dbh->prepare(
                        q{SELECT media.userid, media.mediaid, media.filesize
                                    FROM media LEFT JOIN media_versions
                                        ON media.userid=media_versions.userid AND media.mediaid=media_versions.mediaid
                                        WHERE media_versions.mediaid IS NULL}
                    );
                    $sth->execute;
                    die $sth->errstr if $sth->err;

                    eval "use DW::Media::Photo; use Image::Size; 1;"
                        or die "Unable to load media libraries";
                    my $failed = 0;
                    while ( my $row = $sth->fetchrow_hashref ) {
                        my $media_file = DW::Media::Photo->new_from_row(
                            userid    => $row->{userid},
                            versionid => $row->{mediaid}
                        );
                        my $imagedata = DW::BlobStore->retrieve( media => $media_file->mogkey );
                        my ( $width, $height ) = Image::Size::imgsize($imagedata);
                        unless ( defined $width && defined $height ) {
                            $failed++;
                            next;
                        }

                        $dbh->do(
q{INSERT INTO media_versions (userid, mediaid, versionid, width, height, filesize)
                    VALUES (?, ?, ?, ?, ?, ?)},
                            undef,   $row->{userid}, $row->{mediaid}, $row->{mediaid}, $width,
                            $height, $row->{filesize}
                        );
                        die $dbh->errstr if $dbh->err;
                    }
                    warn "Failed: $failed" if $failed;
                }
            );

            do_sql('UNLOCK TABLES');
            set_dbnote( "init_media_versions_dimensions", 1 );
        }

        if ( table_relevant("renames") && column_type( "renames", "status" ) eq '' ) {
            do_alter( 'renames',
                "ALTER TABLE renames " . "ADD COLUMN status CHAR(1) NOT NULL DEFAULT 'A'" );
            do_sql('UPDATE renames SET status="U" WHERE renuserid = 0');
        }

        if ( table_relevant("codes") && !check_dbnote('remove_countries_from_codes') ) {
            do_sql('DELETE FROM codes WHERE type = "country"');
            set_dbnote( 'remove_countries_from_codes', 1 );
        }

        # widen ip column for IPv6 addresses
        if ( column_type( "spamreports", "ip" ) eq "varchar(15)" ) {
            do_alter( "spamreports", "ALTER TABLE spamreports " . "MODIFY ip VARCHAR(45)" );
        }

        unless ( column_type( 'ml_items', 'itcode' ) =~ /120/ ) {
            do_alter( 'ml_items',
"ALTER TABLE ml_items MODIFY COLUMN itcode VARCHAR(120) CHARACTER SET ascii NOT NULL"
            );
        }

        if ( column_type( 'user', 'txtmsg_status' ) ) {
            do_alter( 'user', "ALTER TABLE user DROP COLUMN txtmsg_status" );
        }

        unless ( column_type( 'userpic2', 'location' ) =~ /blobstore/ ) {
            do_alter(
                'userpic2',
                q{ALTER TABLE userpic2
            MODIFY COLUMN location ENUM('blob', 'disk', 'mogile', 'blobstore')
            DEFAULT NULL}
            );
        }

        # widen the description field for userpics
        if ( column_type( 'userpic2', 'description' ) eq "varchar(255)" ) {
            do_alter( 'userpic2',
"ALTER TABLE userpic2 MODIFY COLUMN description VARCHAR(600) BINARY NOT NULL default ''"
            );
        }

        # widen ip column for IPv6 addresses
        if ( column_type( "userlog", "ip" ) eq "varchar(15)" ) {
            do_alter( "spamreports", "ALTER TABLE userlog MODIFY ip VARCHAR(45)" );
        }

    }
);

1;    # return true
