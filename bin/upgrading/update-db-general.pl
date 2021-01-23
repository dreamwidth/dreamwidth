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

#
# This file has been reset to use current-real tables, to clean up many years
# of alters and other cruft.
#
# We can now begin re-accumulating them. :-)
#

register_tablecreate( "acctcode", <<'EOC' );
CREATE TABLE `acctcode` (
  `acid` int unsigned NOT NULL AUTO_INCREMENT,
  `userid` int unsigned NOT NULL,
  `rcptid` int unsigned NOT NULL DEFAULT '0',
  `auth` char(13) NOT NULL,
  `timegenerate` int unsigned DEFAULT NULL,
  `timesent` int unsigned DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `reason` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`acid`),
  KEY `userid` (`userid`),
  KEY `rcptid` (`rcptid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "acctcode_promo", <<'EOC' );
CREATE TABLE `acctcode_promo` (
  `code` varchar(20) NOT NULL,
  `max_count` int unsigned NOT NULL DEFAULT '0',
  `current_count` int unsigned NOT NULL DEFAULT '0',
  `active` enum('1','0') NOT NULL DEFAULT '1',
  `suggest_journalid` int unsigned DEFAULT NULL,
  `paid_class` varchar(100) DEFAULT NULL,
  `paid_months` tinyint unsigned DEFAULT NULL,
  `expiry_date` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "acctcode_request", <<'EOC' );
CREATE TABLE `acctcode_request` (
  `reqid` int unsigned NOT NULL AUTO_INCREMENT,
  `userid` int unsigned NOT NULL,
  `status` enum('accepted','rejected','outstanding') NOT NULL DEFAULT 'outstanding',
  `reason` varchar(255) DEFAULT NULL,
  `timegenerate` int unsigned NOT NULL,
  `timeprocessed` int unsigned DEFAULT NULL,
  PRIMARY KEY (`reqid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "active_user", <<'EOC' );
CREATE TABLE `active_user` (
  `year` smallint NOT NULL,
  `month` tinyint NOT NULL,
  `day` tinyint NOT NULL,
  `hour` tinyint NOT NULL,
  `userid` int unsigned NOT NULL,
  `type` char(1) NOT NULL,
  PRIMARY KEY (`year`,`month`,`day`,`hour`,`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "active_user_summary", <<'EOC' );
CREATE TABLE `active_user_summary` (
  `year` smallint NOT NULL,
  `month` tinyint NOT NULL,
  `day` tinyint NOT NULL,
  `hour` tinyint NOT NULL,
  `clusterid` tinyint unsigned NOT NULL,
  `type` char(1) NOT NULL,
  `count` int unsigned NOT NULL DEFAULT '0',
  KEY `year` (`year`,`month`,`day`,`hour`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "api_key", <<'EOC' );
CREATE TABLE `api_key` (
  `userid` int unsigned NOT NULL,
  `keyid` int unsigned NOT NULL,
  `hash` char(32) NOT NULL,
  `state` char(1) NOT NULL DEFAULT 'A',
  PRIMARY KEY (`userid`,`keyid`),
  UNIQUE KEY `hash` (`hash`),
  KEY `hash_2` (`hash`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "authactions", <<'EOC' );
CREATE TABLE `authactions` (
  `aaid` int unsigned NOT NULL AUTO_INCREMENT,
  `userid` int unsigned NOT NULL DEFAULT '0',
  `datecreate` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `authcode` varchar(20) DEFAULT NULL,
  `action` varchar(50) DEFAULT NULL,
  `arg1` varchar(255) DEFAULT NULL,
  `used` enum('Y','N') DEFAULT 'N',
  PRIMARY KEY (`aaid`),
  KEY `userid` (`userid`),
  KEY `datecreate` (`datecreate`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "bannotes", <<'EOC' );
CREATE TABLE `bannotes` (
  `journalid` int unsigned NOT NULL,
  `banid` int unsigned NOT NULL,
  `remoteid` int unsigned DEFAULT NULL,
  `notetext` mediumtext,
  PRIMARY KEY (`journalid`,`banid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "birthdays", <<'EOC' );
CREATE TABLE `birthdays` (
  `userid` int unsigned NOT NULL,
  `nextbirthday` int unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `nextbirthday` (`nextbirthday`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "blobcache", <<'EOC' );
CREATE TABLE `blobcache` (
  `bckey` varchar(255) NOT NULL,
  `dateupdate` datetime DEFAULT NULL,
  `value` mediumblob,
  PRIMARY KEY (`bckey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "captcha_cache", <<'EOC' );
CREATE TABLE `captcha_cache` (
  `captcha_id` int unsigned NOT NULL AUTO_INCREMENT,
  `question` varchar(255) NOT NULL,
  `answer` varchar(255) NOT NULL,
  `issuetime` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`captcha_id`),
  KEY `issuetime` (`issuetime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "cc_log", <<'EOC' );
CREATE TABLE `cc_log` (
  `cartid` int unsigned NOT NULL,
  `ip` varchar(15) DEFAULT NULL,
  `transtime` int unsigned NOT NULL,
  `req_content` text NOT NULL,
  `res_content` text NOT NULL,
  KEY `cartid` (`cartid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "cc_trans", <<'EOC' );
CREATE TABLE `cc_trans` (
  `cctransid` int unsigned NOT NULL AUTO_INCREMENT,
  `cartid` int unsigned NOT NULL,
  `gctaskref` varchar(255) DEFAULT NULL,
  `dispatchtime` int unsigned DEFAULT NULL,
  `jobstate` varchar(255) DEFAULT NULL,
  `joberr` varchar(255) DEFAULT NULL,
  `response` char(1) DEFAULT NULL,
  `responsetext` varchar(255) DEFAULT NULL,
  `authcode` varchar(255) DEFAULT NULL,
  `transactionid` varchar(255) DEFAULT NULL,
  `avsresponse` char(1) DEFAULT NULL,
  `cvvresponse` char(1) DEFAULT NULL,
  `responsecode` mediumint unsigned DEFAULT NULL,
  `ccnumhash` varchar(32) NOT NULL,
  `expmon` tinyint NOT NULL,
  `expyear` smallint NOT NULL,
  `firstname` varchar(25) NOT NULL,
  `lastname` varchar(25) NOT NULL,
  `street1` varchar(100) NOT NULL,
  `street2` varchar(100) DEFAULT NULL,
  `city` varchar(40) NOT NULL,
  `state` varchar(40) NOT NULL,
  `country` char(2) NOT NULL,
  `zip` varchar(20) NOT NULL,
  `phone` varchar(40) DEFAULT NULL,
  `ipaddr` varchar(15) NOT NULL,
  PRIMARY KEY (`cctransid`),
  KEY `cartid` (`cartid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "challenges", <<'EOC' );
CREATE TABLE `challenges` (
  `ctime` int unsigned NOT NULL DEFAULT '0',
  `challenge` char(80) NOT NULL DEFAULT '',
  `count` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`challenge`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "clients", <<'EOC' );
CREATE TABLE `clients` (
  `clientid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `client` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`clientid`),
  KEY `client` (`client`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "clientusage", <<'EOC' );
CREATE TABLE `clientusage` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `clientid` smallint unsigned NOT NULL DEFAULT '0',
  `lastlogin` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`clientid`,`userid`),
  UNIQUE KEY `userid` (`userid`,`clientid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "clustermove", <<'EOC' );
CREATE TABLE `clustermove` (
  `cmid` int unsigned NOT NULL AUTO_INCREMENT,
  `userid` int unsigned NOT NULL,
  `sclust` tinyint unsigned NOT NULL,
  `dclust` tinyint unsigned NOT NULL,
  `timestart` int unsigned DEFAULT NULL,
  `timedone` int unsigned DEFAULT NULL,
  `sdeleted` enum('1','0') DEFAULT NULL,
  PRIMARY KEY (`cmid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "clustermove_inprogress", <<'EOC' );
CREATE TABLE `clustermove_inprogress` (
  `userid` int unsigned NOT NULL,
  `locktime` int unsigned NOT NULL,
  `dstclust` smallint unsigned NOT NULL,
  `moverhost` int unsigned NOT NULL,
  `moverport` smallint unsigned NOT NULL,
  `moverinstance` char(22) NOT NULL,
  PRIMARY KEY (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "clustertrack2", <<'EOC' );
CREATE TABLE `clustertrack2` (
  `userid` int unsigned NOT NULL,
  `timeactive` int unsigned NOT NULL,
  `clusterid` smallint unsigned DEFAULT NULL,
  `accountlevel` smallint unsigned DEFAULT NULL,
  `journaltype` char(1) DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `timeactive` (`timeactive`,`clusterid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "codes", <<'EOC' );
CREATE TABLE `codes` (
  `type` varchar(10) NOT NULL DEFAULT '',
  `code` varchar(7) NOT NULL DEFAULT '',
  `item` varchar(80) DEFAULT NULL,
  `sortorder` smallint NOT NULL DEFAULT '0',
  PRIMARY KEY (`type`,`code`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "collection_items", <<'EOC' );
CREATE TABLE `collection_items` (
  `userid` int unsigned NOT NULL,
  `colitemid` int unsigned NOT NULL,
  `colid` int unsigned NOT NULL,
  `itemtype` tinyint unsigned NOT NULL,
  `itemownerid` int unsigned NOT NULL,
  `itemid` int unsigned NOT NULL,
  `logtime` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`colid`,`colitemid`),
  UNIQUE KEY `userid` (`userid`,`colid`,`itemtype`,`itemownerid`,`itemid`),
  KEY `itemtype` (`itemtype`,`itemownerid`,`itemid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "collections", <<'EOC' );
CREATE TABLE `collections` (
  `userid` int unsigned NOT NULL,
  `colid` int unsigned NOT NULL,
  `paruserid` int unsigned NOT NULL,
  `parcolid` int unsigned NOT NULL,
  `anum` tinyint unsigned NOT NULL,
  `state` char(1) NOT NULL DEFAULT 'A',
  `security` enum('public','private','usemask') NOT NULL DEFAULT 'public',
  `allowmask` bigint unsigned NOT NULL DEFAULT '0',
  `logtime` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`colid`),
  KEY `paruserid` (`paruserid`,`parcolid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "comminterests", <<'EOC' );
CREATE TABLE `comminterests` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `intid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`intid`),
  KEY `intid` (`intid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "community", <<'EOC' );
CREATE TABLE `community` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `membership` enum('open','closed','moderated') NOT NULL DEFAULT 'open',
  `postlevel` enum('members','select','screened') DEFAULT NULL,
  PRIMARY KEY (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "content_filter_data", <<'EOC' );
CREATE TABLE `content_filter_data` (
  `userid` int unsigned NOT NULL,
  `filterid` int unsigned NOT NULL,
  `data` mediumblob NOT NULL,
  PRIMARY KEY (`userid`,`filterid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "content_filters", <<'EOC' );
CREATE TABLE `content_filters` (
  `userid` int unsigned NOT NULL,
  `filterid` int unsigned NOT NULL,
  `filtername` varchar(255) NOT NULL,
  `is_public` enum('0','1') NOT NULL DEFAULT '0',
  `sortorder` smallint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`filterid`),
  UNIQUE KEY `userid` (`userid`,`filtername`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "counter", <<'EOC' );
CREATE TABLE `counter` (
  `journalid` int unsigned NOT NULL,
  `area` char(1) NOT NULL,
  `max` int unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`area`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "dbinfo", <<'EOC' );
CREATE TABLE `dbinfo` (
  `dbid` tinyint unsigned NOT NULL,
  `name` varchar(25) DEFAULT NULL,
  `fdsn` varchar(255) DEFAULT NULL,
  `rootfdsn` varchar(255) DEFAULT NULL,
  `masterid` tinyint unsigned NOT NULL,
  PRIMARY KEY (`dbid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "dbnotes", <<'EOC' );
CREATE TABLE `dbnotes` (
  `dbnote` varchar(40) NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`dbnote`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "dbweights", <<'EOC' );
CREATE TABLE `dbweights` (
  `dbid` tinyint unsigned NOT NULL,
  `role` varchar(25) NOT NULL,
  `norm` tinyint unsigned NOT NULL,
  `curr` tinyint unsigned NOT NULL,
  PRIMARY KEY (`dbid`,`role`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "debug_notifymethod", <<'EOC' );
CREATE TABLE `debug_notifymethod` (
  `userid` int unsigned NOT NULL,
  `subid` int unsigned DEFAULT NULL,
  `ntfytime` int unsigned DEFAULT NULL,
  `origntypeid` int unsigned DEFAULT NULL,
  `etypeid` int unsigned DEFAULT NULL,
  `ejournalid` int unsigned DEFAULT NULL,
  `earg1` int DEFAULT NULL,
  `earg2` int DEFAULT NULL,
  `schjobid` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "dirmogsethandles", <<'EOC' );
CREATE TABLE `dirmogsethandles` (
  `conskey` char(40) NOT NULL,
  `exptime` int unsigned NOT NULL,
  PRIMARY KEY (`conskey`),
  KEY `exptime` (`exptime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "dudata", <<'EOC' );
CREATE TABLE `dudata` (
  `userid` int unsigned NOT NULL,
  `area` char(1) NOT NULL,
  `areaid` int unsigned NOT NULL,
  `bytes` mediumint unsigned NOT NULL,
  PRIMARY KEY (`userid`,`area`,`areaid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "duplock", <<'EOC' );
CREATE TABLE `duplock` (
  `realm` enum('support','log','comment','payments') NOT NULL DEFAULT 'support',
  `reid` int unsigned NOT NULL DEFAULT '0',
  `userid` int unsigned NOT NULL DEFAULT '0',
  `digest` char(32) NOT NULL DEFAULT '',
  `dupid` int unsigned NOT NULL DEFAULT '0',
  `instime` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `realm` (`realm`,`reid`,`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "dw_paidstatus", <<'EOC' );
CREATE TABLE `dw_paidstatus` (
  `userid` int unsigned NOT NULL,
  `typeid` smallint unsigned NOT NULL,
  `expiretime` int unsigned DEFAULT NULL,
  `permanent` tinyint unsigned NOT NULL,
  `lastemail` int unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `expiretime` (`expiretime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "email", <<'EOC' );
CREATE TABLE `email` (
  `userid` int unsigned NOT NULL,
  `email` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "email_aliases", <<'EOC' );
CREATE TABLE `email_aliases` (
  `alias` varchar(255) NOT NULL,
  `rcpt` varchar(255) NOT NULL,
  PRIMARY KEY (`alias`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "embedcontent", <<'EOC' );
CREATE TABLE `embedcontent` (
  `userid` int unsigned NOT NULL,
  `moduleid` int unsigned NOT NULL,
  `content` mediumblob,
  `linktext` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`moduleid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "embedcontent_preview", <<'EOC' );
CREATE TABLE `embedcontent_preview` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `moduleid` int NOT NULL DEFAULT '0',
  `content` mediumblob,
  `linktext` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`moduleid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "eventtypelist", <<'EOC' );
CREATE TABLE `eventtypelist` (
  `etypeid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `class` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`etypeid`),
  UNIQUE KEY `class` (`class`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "expunged_users", <<'EOC' );
CREATE TABLE `expunged_users` (
  `userid` int unsigned NOT NULL,
  `user` varchar(25) NOT NULL DEFAULT '',
  `expunge_time` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`user`),
  KEY `expunge_time` (`expunge_time`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "external_site_moods", <<'EOC' );
CREATE TABLE `external_site_moods` (
  `siteid` int unsigned NOT NULL,
  `mood` varchar(40) NOT NULL,
  `moodid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`siteid`,`mood`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "externalaccount", <<'EOC' );
CREATE TABLE `externalaccount` (
  `userid` int unsigned NOT NULL,
  `acctid` int unsigned NOT NULL,
  `username` varchar(64) NOT NULL,
  `password` varchar(64) DEFAULT NULL,
  `siteid` int unsigned DEFAULT NULL,
  `servicename` varchar(128) DEFAULT NULL,
  `servicetype` varchar(32) DEFAULT NULL,
  `serviceurl` varchar(128) DEFAULT NULL,
  `xpostbydefault` enum('1','0') NOT NULL DEFAULT '0',
  `recordlink` enum('1','0') NOT NULL DEFAULT '0',
  `active` enum('1','0') NOT NULL DEFAULT '1',
  `options` blob,
  PRIMARY KEY (`userid`,`acctid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "externaluserinfo", <<'EOC' );
CREATE TABLE `externaluserinfo` (
  `site` int unsigned NOT NULL,
  `user` varchar(50) NOT NULL,
  `last` int unsigned DEFAULT NULL,
  `type` char(1) DEFAULT NULL,
  PRIMARY KEY (`site`,`user`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "extuser", <<'EOC' );
CREATE TABLE `extuser` (
  `userid` int unsigned NOT NULL,
  `siteid` int unsigned NOT NULL,
  `extuser` varchar(50) DEFAULT NULL,
  `extuserid` int unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  UNIQUE KEY `extuser` (`siteid`,`extuser`),
  UNIQUE KEY `extuserid` (`siteid`,`extuserid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "faq", <<'EOC' );
CREATE TABLE `faq` (
  `faqid` mediumint unsigned NOT NULL AUTO_INCREMENT,
  `question` text,
  `summary` text,
  `answer` text,
  `sortorder` int DEFAULT NULL,
  `faqcat` varchar(20) DEFAULT NULL,
  `lastmodtime` datetime DEFAULT NULL,
  `lastmoduserid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`faqid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "faqcat", <<'EOC' );
CREATE TABLE `faqcat` (
  `faqcat` varchar(20) NOT NULL DEFAULT '',
  `faqcatname` varchar(100) DEFAULT NULL,
  `catorder` int DEFAULT '50',
  PRIMARY KEY (`faqcat`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "faquses", <<'EOC' );
CREATE TABLE `faquses` (
  `faqid` mediumint unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `dateview` datetime NOT NULL,
  PRIMARY KEY (`userid`,`faqid`),
  KEY `faqid` (`faqid`),
  KEY `dateview` (`dateview`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "gco_log", <<'EOC' );
CREATE TABLE `gco_log` (
  `gcoid` bigint unsigned NOT NULL,
  `ip` varchar(15) NOT NULL,
  `transtime` int unsigned NOT NULL,
  `req_content` text NOT NULL,
  KEY `gcoid` (`gcoid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "gco_map", <<'EOC' );
CREATE TABLE `gco_map` (
  `gcoid` bigint unsigned NOT NULL,
  `cartid` int unsigned NOT NULL,
  `email` varchar(255) DEFAULT NULL,
  `contactname` varchar(255) DEFAULT NULL,
  UNIQUE KEY `cartid` (`cartid`),
  KEY `gcoid` (`gcoid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "identitymap", <<'EOC' );
CREATE TABLE `identitymap` (
  `idtype` char(1) NOT NULL,
  `identity` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL,
  `userid` int unsigned NOT NULL,
  PRIMARY KEY (`idtype`,`identity`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "import_data", <<'EOC' );
CREATE TABLE `import_data` (
  `userid` int unsigned NOT NULL,
  `import_data_id` int unsigned NOT NULL,
  `hostname` varchar(255) DEFAULT NULL,
  `username` varchar(255) DEFAULT NULL,
  `usejournal` varchar(255) DEFAULT NULL,
  `password_md5` varchar(255) DEFAULT NULL,
  `groupmap` blob,
  `options` blob,
  PRIMARY KEY (`userid`,`import_data_id`),
  KEY `import_data_id` (`import_data_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "import_items", <<'EOC' );
CREATE TABLE `import_items` (
  `userid` int unsigned NOT NULL,
  `item` varchar(255) NOT NULL,
  `status` enum('init','ready','queued','failed','succeeded','aborted') NOT NULL DEFAULT 'init',
  `created` int unsigned NOT NULL,
  `last_touch` int unsigned NOT NULL,
  `import_data_id` int unsigned NOT NULL,
  `priority` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`item`,`import_data_id`),
  KEY `priority` (`priority`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "import_status", <<'EOC' );
CREATE TABLE `import_status` (
  `userid` int unsigned NOT NULL,
  `import_status_id` int unsigned NOT NULL,
  `status` blob,
  PRIMARY KEY (`userid`,`import_status_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "import_usermap", <<'EOC' );
CREATE TABLE `import_usermap` (
  `hostname` varchar(255) NOT NULL,
  `username` varchar(255) NOT NULL,
  `identity_userid` int unsigned DEFAULT NULL,
  `feed_userid` int unsigned DEFAULT NULL,
  PRIMARY KEY (`hostname`,`username`),
  KEY `identity_userid` (`identity_userid`),
  KEY `feed_userid` (`feed_userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "includetext", <<'EOC' );
CREATE TABLE `includetext` (
  `incname` varchar(80) NOT NULL,
  `inctext` mediumtext,
  `updatetime` int unsigned NOT NULL,
  PRIMARY KEY (`incname`),
  KEY `updatetime` (`updatetime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "infohistory", <<'EOC' );
CREATE TABLE `infohistory` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `what` varchar(15) NOT NULL DEFAULT '',
  `timechange` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `oldvalue` varchar(255) DEFAULT NULL,
  `other` varchar(30) DEFAULT NULL,
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "interests", <<'EOC' );
CREATE TABLE `interests` (
  `intid` int unsigned NOT NULL,
  `intcount` mediumint unsigned DEFAULT NULL,
  PRIMARY KEY (`intid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "inviterecv", <<'EOC' );
CREATE TABLE `inviterecv` (
  `userid` int unsigned NOT NULL,
  `commid` int unsigned NOT NULL,
  `maintid` int unsigned NOT NULL,
  `recvtime` int unsigned NOT NULL,
  `args` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`commid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "invitesent", <<'EOC' );
CREATE TABLE `invitesent` (
  `commid` int unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `maintid` int unsigned NOT NULL,
  `recvtime` int unsigned NOT NULL,
  `status` enum('accepted','rejected','outstanding') NOT NULL,
  `args` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`commid`,`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "jobstatus", <<'EOC' );
CREATE TABLE `jobstatus` (
  `handle` varchar(100) NOT NULL,
  `result` blob,
  `start_time` int unsigned NOT NULL,
  `end_time` int unsigned NOT NULL,
  `status` enum('running','success','error') DEFAULT NULL,
  `userid` int unsigned DEFAULT NULL,
  PRIMARY KEY (`handle`),
  KEY `end_time` (`end_time`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "key_prop_list", <<'EOC' );
CREATE TABLE `key_prop_list` (
  `propid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `ownership` enum('system','user') NOT NULL DEFAULT 'user',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  `des` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "key_props", <<'EOC' );
CREATE TABLE `key_props` (
  `userid` int unsigned NOT NULL,
  `keyid` int unsigned NOT NULL,
  `propid` tinyint unsigned NOT NULL,
  `value` mediumblob NOT NULL,
  PRIMARY KEY (`userid`,`keyid`,`propid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "links", <<'EOC' );
CREATE TABLE `links` (
  `journalid` int unsigned NOT NULL DEFAULT '0',
  `ordernum` tinyint unsigned NOT NULL DEFAULT '0',
  `parentnum` tinyint unsigned NOT NULL DEFAULT '0',
  `url` varchar(255) DEFAULT NULL,
  `title` varchar(255) NOT NULL DEFAULT '',
  `hover` varchar(255) DEFAULT NULL,
  KEY `journalid` (`journalid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "log2", <<'EOC' );
CREATE TABLE `log2` (
  `journalid` int unsigned NOT NULL DEFAULT '0',
  `jitemid` mediumint unsigned NOT NULL,
  `posterid` int unsigned NOT NULL DEFAULT '0',
  `eventtime` datetime DEFAULT NULL,
  `logtime` datetime DEFAULT NULL,
  `compressed` char(1) NOT NULL DEFAULT 'N',
  `anum` tinyint unsigned NOT NULL,
  `security` enum('public','private','usemask') NOT NULL DEFAULT 'public',
  `allowmask` bigint unsigned NOT NULL DEFAULT '0',
  `replycount` smallint unsigned DEFAULT NULL,
  `year` smallint NOT NULL DEFAULT '0',
  `month` tinyint NOT NULL DEFAULT '0',
  `day` tinyint NOT NULL DEFAULT '0',
  `rlogtime` int unsigned NOT NULL DEFAULT '0',
  `revttime` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`journalid`,`jitemid`),
  KEY `journalid` (`journalid`,`year`,`month`,`day`),
  KEY `rlogtime` (`journalid`,`rlogtime`),
  KEY `revttime` (`journalid`,`revttime`),
  KEY `posterid` (`posterid`,`journalid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "loginlog", <<'EOC' );
CREATE TABLE `loginlog` (
  `userid` int unsigned NOT NULL,
  `logintime` int unsigned NOT NULL,
  `sessid` mediumint unsigned NOT NULL,
  `ip` varchar(45) DEFAULT NULL,
  `ua` varchar(100) DEFAULT NULL,
  KEY `userid` (`userid`,`logintime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "loginstall", <<'EOC' );
CREATE TABLE `loginstall` (
  `userid` int unsigned NOT NULL,
  `ip` int unsigned NOT NULL,
  `time` int unsigned NOT NULL,
  UNIQUE KEY `userid` (`userid`,`ip`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logkwsum", <<'EOC' );
CREATE TABLE `logkwsum` (
  `journalid` int unsigned NOT NULL,
  `kwid` int unsigned NOT NULL,
  `security` bigint unsigned NOT NULL,
  `entryct` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`journalid`,`kwid`,`security`),
  KEY `journalid` (`journalid`,`security`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logprop2", <<'EOC' );
CREATE TABLE `logprop2` (
  `journalid` int unsigned NOT NULL,
  `jitemid` mediumint unsigned NOT NULL,
  `propid` tinyint unsigned NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`jitemid`,`propid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logprop_history", <<'EOC' );
CREATE TABLE `logprop_history` (
  `journalid` int unsigned NOT NULL,
  `jitemid` mediumint unsigned NOT NULL,
  `propid` tinyint unsigned NOT NULL,
  `change_time` int unsigned NOT NULL DEFAULT '0',
  `old_value` varchar(255) DEFAULT NULL,
  `new_value` varchar(255) DEFAULT NULL,
  `note` varchar(255) DEFAULT NULL,
  KEY `journalid` (`journalid`,`jitemid`,`propid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logproplist", <<'EOC' );
CREATE TABLE `logproplist` (
  `propid` tinyint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `sortorder` mediumint unsigned DEFAULT NULL,
  `datatype` enum('char','num','bool','blobchar') NOT NULL DEFAULT 'char',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  `ownership` enum('system','user') NOT NULL DEFAULT 'user',
  `des` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logsec2", <<'EOC' );
CREATE TABLE `logsec2` (
  `journalid` int unsigned NOT NULL,
  `jitemid` mediumint unsigned NOT NULL,
  `allowmask` bigint unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`jitemid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logslugs", <<'EOC' );
CREATE TABLE `logslugs` (
  `journalid` int unsigned NOT NULL DEFAULT '0',
  `jitemid` mediumint unsigned NOT NULL,
  `slug` varchar(255) NOT NULL,
  PRIMARY KEY (`journalid`,`jitemid`),
  UNIQUE KEY `journalid` (`journalid`,`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logtags", <<'EOC' );
CREATE TABLE `logtags` (
  `journalid` int unsigned NOT NULL,
  `jitemid` mediumint unsigned NOT NULL,
  `kwid` int unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`jitemid`,`kwid`),
  KEY `journalid` (`journalid`,`kwid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logtagsrecent", <<'EOC' );
CREATE TABLE `logtagsrecent` (
  `journalid` int unsigned NOT NULL,
  `jitemid` mediumint unsigned NOT NULL,
  `kwid` int unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`kwid`,`jitemid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "logtext2", <<'EOC' );
CREATE TABLE `logtext2` (
  `journalid` int unsigned NOT NULL,
  `jitemid` mediumint unsigned NOT NULL,
  `subject` tinyblob DEFAULT NULL,
  `event` mediumblob,
  PRIMARY KEY (`journalid`,`jitemid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "media", <<'EOC' );
CREATE TABLE `media` (
  `userid` int unsigned NOT NULL,
  `mediaid` int unsigned NOT NULL,
  `anum` tinyint unsigned NOT NULL,
  `ext` varchar(10) NOT NULL,
  `state` char(1) NOT NULL DEFAULT 'A',
  `mediatype` tinyint unsigned NOT NULL,
  `security` enum('public','private','usemask') NOT NULL DEFAULT 'public',
  `allowmask` bigint unsigned NOT NULL DEFAULT '0',
  `logtime` int unsigned NOT NULL,
  `mimetype` varchar(60) NOT NULL,
  `filesize` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`mediaid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "media_prop_list", <<'EOC' );
CREATE TABLE `media_prop_list` (
  `propid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `ownership` enum('system','user') NOT NULL DEFAULT 'user',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  `des` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "media_props", <<'EOC' );
CREATE TABLE `media_props` (
  `userid` int unsigned NOT NULL,
  `mediaid` int unsigned NOT NULL,
  `propid` tinyint unsigned NOT NULL,
  `value` mediumblob NOT NULL,
  PRIMARY KEY (`userid`,`mediaid`,`propid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "media_versions", <<'EOC' );
CREATE TABLE `media_versions` (
  `userid` int unsigned NOT NULL,
  `mediaid` int unsigned NOT NULL,
  `versionid` int unsigned NOT NULL,
  `width` smallint unsigned NOT NULL,
  `height` smallint unsigned NOT NULL,
  `filesize` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`mediaid`,`versionid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "memkeyword2", <<'EOC' );
CREATE TABLE `memkeyword2` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `memid` int unsigned NOT NULL DEFAULT '0',
  `kwid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`memid`,`kwid`),
  KEY `userid` (`userid`,`kwid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "memorable2", <<'EOC' );
CREATE TABLE `memorable2` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `memid` int unsigned NOT NULL DEFAULT '0',
  `journalid` int unsigned NOT NULL DEFAULT '0',
  `ditemid` int unsigned NOT NULL DEFAULT '0',
  `des` varchar(150) DEFAULT NULL,
  `security` enum('public','friends','private') NOT NULL DEFAULT 'public',
  PRIMARY KEY (`userid`,`journalid`,`ditemid`),
  UNIQUE KEY `userid` (`userid`,`memid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ml_domains", <<'EOC' );
CREATE TABLE `ml_domains` (
  `dmid` tinyint unsigned NOT NULL,
  `type` varchar(30) NOT NULL,
  `args` varchar(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`dmid`),
  UNIQUE KEY `type` (`type`,`args`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ml_items", <<'EOC' );
CREATE TABLE `ml_items` (
  `dmid` tinyint unsigned NOT NULL,
  `itid` mediumint unsigned NOT NULL DEFAULT '0',
  `itcode` varchar(120) CHARACTER SET ascii COLLATE ascii_general_ci NOT NULL,
  `proofed` tinyint NOT NULL DEFAULT '0',
  `updated` tinyint NOT NULL DEFAULT '0',
  `visible` tinyint NOT NULL DEFAULT '0',
  `notes` mediumtext,
  PRIMARY KEY (`dmid`,`itid`),
  UNIQUE KEY `dmid` (`dmid`,`itcode`),
  KEY `proofed` (`proofed`),
  KEY `updated` (`updated`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ml_langdomains", <<'EOC' );
CREATE TABLE `ml_langdomains` (
  `lnid` smallint unsigned NOT NULL,
  `dmid` tinyint unsigned NOT NULL,
  `dmmaster` enum('0','1') NOT NULL,
  `lastgetnew` datetime DEFAULT NULL,
  `lastpublish` datetime DEFAULT NULL,
  `countokay` smallint unsigned NOT NULL,
  `counttotal` smallint unsigned NOT NULL,
  PRIMARY KEY (`lnid`,`dmid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ml_langs", <<'EOC' );
CREATE TABLE `ml_langs` (
  `lnid` smallint unsigned NOT NULL,
  `lncode` varchar(16) NOT NULL,
  `lnname` varchar(60) NOT NULL,
  `parenttype` enum('diff','sim') NOT NULL,
  `parentlnid` smallint unsigned NOT NULL,
  `lastupdate` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `lnid` (`lnid`),
  UNIQUE KEY `lncode` (`lncode`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ml_latest", <<'EOC' );
CREATE TABLE `ml_latest` (
  `lnid` smallint unsigned NOT NULL,
  `dmid` tinyint unsigned NOT NULL,
  `itid` smallint unsigned NOT NULL,
  `txtid` int unsigned NOT NULL,
  `chgtime` datetime NOT NULL,
  `staleness` tinyint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`lnid`,`dmid`,`itid`),
  KEY `lnid` (`lnid`,`staleness`),
  KEY `dmid` (`dmid`,`itid`),
  KEY `lnid_2` (`lnid`,`dmid`,`chgtime`),
  KEY `chgtime` (`chgtime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ml_text", <<'EOC' );
CREATE TABLE `ml_text` (
  `dmid` tinyint unsigned NOT NULL,
  `txtid` mediumint unsigned NOT NULL DEFAULT '0',
  `lnid` smallint unsigned NOT NULL,
  `itid` smallint unsigned NOT NULL,
  `text` text NOT NULL,
  `userid` int unsigned NOT NULL,
  PRIMARY KEY (`dmid`,`txtid`),
  KEY `lnid` (`lnid`,`dmid`,`itid`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
EOC

register_tablecreate( "modblob", <<'EOC' );
CREATE TABLE `modblob` (
  `journalid` int unsigned NOT NULL,
  `modid` int unsigned NOT NULL,
  `request_stor` mediumblob,
  PRIMARY KEY (`journalid`,`modid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "modlog", <<'EOC' );
CREATE TABLE `modlog` (
  `journalid` int unsigned NOT NULL,
  `modid` mediumint unsigned NOT NULL,
  `posterid` int unsigned NOT NULL,
  `subject` char(30) DEFAULT NULL,
  `logtime` datetime DEFAULT NULL,
  PRIMARY KEY (`journalid`,`modid`),
  KEY `journalid` (`journalid`,`logtime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "moods", <<'EOC' );
CREATE TABLE `moods` (
  `moodid` int unsigned NOT NULL AUTO_INCREMENT,
  `mood` varchar(40) DEFAULT NULL,
  `parentmood` int unsigned NOT NULL DEFAULT '0',
  `weight` tinyint unsigned DEFAULT NULL,
  PRIMARY KEY (`moodid`),
  UNIQUE KEY `mood` (`mood`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "moodthemedata", <<'EOC' );
CREATE TABLE `moodthemedata` (
  `moodthemeid` int unsigned NOT NULL DEFAULT '0',
  `moodid` int unsigned NOT NULL DEFAULT '0',
  `picurl` varchar(200) DEFAULT NULL,
  `width` tinyint unsigned NOT NULL DEFAULT '0',
  `height` tinyint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`moodthemeid`,`moodid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "moodthemes", <<'EOC' );
CREATE TABLE `moodthemes` (
  `moodthemeid` int unsigned NOT NULL AUTO_INCREMENT,
  `ownerid` int unsigned NOT NULL DEFAULT '0',
  `name` varchar(50) DEFAULT NULL,
  `des` varchar(100) DEFAULT NULL,
  `is_public` enum('Y','N') NOT NULL DEFAULT 'N',
  PRIMARY KEY (`moodthemeid`),
  KEY `is_public` (`is_public`),
  KEY `ownerid` (`ownerid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "noderefs", <<'EOC' );
CREATE TABLE `noderefs` (
  `nodetype` char(1) NOT NULL DEFAULT '',
  `nodeid` int unsigned NOT NULL DEFAULT '0',
  `urlmd5` varchar(32) NOT NULL DEFAULT '',
  `url` varchar(120) NOT NULL DEFAULT '',
  PRIMARY KEY (`nodetype`,`nodeid`,`urlmd5`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "notifyarchive", <<'EOC' );
CREATE TABLE `notifyarchive` (
  `userid` int unsigned NOT NULL,
  `qid` int unsigned NOT NULL,
  `createtime` int unsigned NOT NULL,
  `journalid` int unsigned NOT NULL,
  `etypeid` smallint unsigned NOT NULL,
  `arg1` int unsigned DEFAULT NULL,
  `arg2` int unsigned DEFAULT NULL,
  `state` char(1) DEFAULT NULL,
  PRIMARY KEY (`userid`,`qid`),
  KEY `userid` (`userid`,`createtime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "notifybookmarks", <<'EOC' );
CREATE TABLE `notifybookmarks` (
  `userid` int unsigned NOT NULL,
  `qid` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`qid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "notifyqueue", <<'EOC' );
CREATE TABLE `notifyqueue` (
  `userid` int unsigned NOT NULL,
  `qid` int unsigned NOT NULL,
  `journalid` int unsigned NOT NULL,
  `etypeid` smallint unsigned NOT NULL,
  `arg1` int unsigned DEFAULT NULL,
  `arg2` int unsigned DEFAULT NULL,
  `state` char(1) NOT NULL DEFAULT 'N',
  `createtime` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`qid`),
  KEY `state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "notifytypelist", <<'EOC' );
CREATE TABLE `notifytypelist` (
  `ntypeid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `class` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`ntypeid`),
  UNIQUE KEY `class` (`class`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "oauth_access_token", <<'EOC' );
CREATE TABLE `oauth_access_token` (
  `consumer_id` int unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `token` varchar(20) DEFAULT NULL,
  `secret` varchar(50) DEFAULT NULL,
  `createtime` int unsigned NOT NULL,
  `lastaccess` int unsigned DEFAULT NULL,
  PRIMARY KEY (`consumer_id`,`userid`),
  UNIQUE KEY `token` (`token`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "oauth_consumer", <<'EOC' );
CREATE TABLE `oauth_consumer` (
  `consumer_id` int unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `communityid` int unsigned DEFAULT NULL,
  `token` varchar(20) NOT NULL,
  `secret` varchar(50) NOT NULL,
  `name` varchar(255) NOT NULL DEFAULT '',
  `website` varchar(255) NOT NULL,
  `createtime` int unsigned NOT NULL,
  `updatetime` int unsigned DEFAULT NULL,
  `invalidatedtime` int unsigned DEFAULT NULL,
  `approved` enum('1','0') NOT NULL DEFAULT '1',
  `active` enum('1','0') NOT NULL DEFAULT '1',
  PRIMARY KEY (`consumer_id`),
  UNIQUE KEY `token` (`token`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "openid_claims", <<'EOC' );
CREATE TABLE `openid_claims` (
  `userid` int unsigned NOT NULL,
  `claimed_userid` int unsigned NOT NULL,
  PRIMARY KEY (`userid`),
  KEY `claimed_userid` (`claimed_userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "openid_endpoint", <<'EOC' );
CREATE TABLE `openid_endpoint` (
  `endpoint_id` int unsigned NOT NULL AUTO_INCREMENT,
  `url` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `last_assert_time` int unsigned DEFAULT NULL,
  PRIMARY KEY (`endpoint_id`),
  UNIQUE KEY `url` (`url`),
  KEY `last_assert_time` (`last_assert_time`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "openid_trust", <<'EOC' );
CREATE TABLE `openid_trust` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `endpoint_id` int unsigned NOT NULL DEFAULT '0',
  `trust_time` int unsigned NOT NULL DEFAULT '0',
  `duration` enum('always','once') NOT NULL DEFAULT 'always',
  `last_assert_time` int unsigned DEFAULT NULL,
  `flags` tinyint unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`,`endpoint_id`),
  KEY `endpoint_id` (`endpoint_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "partialstats", <<'EOC' );
CREATE TABLE `partialstats` (
  `jobname` varchar(50) NOT NULL,
  `clusterid` mediumint NOT NULL DEFAULT '0',
  `calctime` int unsigned DEFAULT NULL,
  PRIMARY KEY (`jobname`,`clusterid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "partialstatsdata", <<'EOC' );
CREATE TABLE `partialstatsdata` (
  `statname` varchar(50) NOT NULL,
  `arg` varchar(50) NOT NULL,
  `clusterid` int unsigned NOT NULL DEFAULT '0',
  `value` int DEFAULT NULL,
  PRIMARY KEY (`statname`,`arg`,`clusterid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "password", <<'EOC' );
CREATE TABLE `password` (
  `userid` int unsigned NOT NULL,
  `password` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "password2", <<'EOC' );
CREATE TABLE `password2` (
  `userid` int unsigned NOT NULL,
  `version` int unsigned NOT NULL,
  `password` varchar(255) NOT NULL,
  `totp_secret` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pendcomments", <<'EOC' );
CREATE TABLE `pendcomments` (
  `jid` int unsigned NOT NULL,
  `pendcid` int unsigned NOT NULL,
  `data` blob NOT NULL,
  `datesubmit` int unsigned NOT NULL,
  PRIMARY KEY (`pendcid`,`jid`),
  KEY `datesubmit` (`datesubmit`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "persistent_queue", <<'EOC' );
CREATE TABLE `persistent_queue` (
  `qkey` varchar(255) NOT NULL,
  `idx` int unsigned NOT NULL,
  `value` blob,
  PRIMARY KEY (`qkey`,`idx`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "poll2", <<'EOC' );
CREATE TABLE `poll2` (
  `journalid` int unsigned NOT NULL,
  `pollid` int unsigned NOT NULL,
  `posterid` int unsigned NOT NULL,
  `ditemid` int unsigned NOT NULL,
  `whovote` enum('all','trusted','ofentry') NOT NULL DEFAULT 'all',
  `whoview` enum('all','trusted','ofentry','none') NOT NULL DEFAULT 'all',
  `isanon` enum('yes','no') NOT NULL DEFAULT 'no',
  `name` varchar(255) DEFAULT NULL,
  `status` char(1) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`pollid`),
  KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pollitem2", <<'EOC' );
CREATE TABLE `pollitem2` (
  `journalid` int unsigned NOT NULL,
  `pollid` int unsigned NOT NULL,
  `pollqid` tinyint unsigned NOT NULL,
  `pollitid` tinyint unsigned NOT NULL,
  `sortorder` tinyint unsigned NOT NULL DEFAULT '0',
  `item` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`pollid`,`pollqid`,`pollitid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pollowner", <<'EOC' );
CREATE TABLE `pollowner` (
  `pollid` int unsigned NOT NULL,
  `journalid` int unsigned NOT NULL,
  PRIMARY KEY (`pollid`),
  KEY `journalid` (`journalid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pollquestion2", <<'EOC' );
CREATE TABLE `pollquestion2` (
  `journalid` int unsigned NOT NULL,
  `pollid` int unsigned NOT NULL,
  `pollqid` tinyint unsigned NOT NULL,
  `sortorder` tinyint unsigned NOT NULL DEFAULT '0',
  `type` enum('check','radio','drop','text','scale') NOT NULL,
  `opts` varchar(255) DEFAULT NULL,
  `qtext` text,
  PRIMARY KEY (`journalid`,`pollid`,`pollqid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pollresult2", <<'EOC' );
CREATE TABLE `pollresult2` (
  `journalid` int unsigned NOT NULL,
  `pollid` int unsigned NOT NULL,
  `pollqid` tinyint unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `value` varchar(1024) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`pollid`,`pollqid`,`userid`),
  KEY `userid` (`userid`,`pollid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pollsubmission2", <<'EOC' );
CREATE TABLE `pollsubmission2` (
  `journalid` int unsigned NOT NULL,
  `pollid` int unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `datesubmit` datetime NOT NULL,
  PRIMARY KEY (`journalid`,`pollid`,`userid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pp_log", <<'EOC' );
CREATE TABLE `pp_log` (
  `ppid` int unsigned NOT NULL,
  `ip` varchar(15) NOT NULL,
  `transtime` int unsigned NOT NULL,
  `req_content` text NOT NULL,
  `res_content` text NOT NULL,
  KEY `ppid` (`ppid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pp_tokens", <<'EOC' );
CREATE TABLE `pp_tokens` (
  `ppid` int unsigned NOT NULL AUTO_INCREMENT,
  `inittime` int unsigned NOT NULL,
  `touchtime` int unsigned NOT NULL,
  `cartid` int unsigned NOT NULL,
  `status` varchar(20) NOT NULL,
  `token` varchar(20) NOT NULL,
  `email` varchar(255) DEFAULT NULL,
  `firstname` varchar(255) DEFAULT NULL,
  `lastname` varchar(255) DEFAULT NULL,
  `payerid` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`ppid`),
  UNIQUE KEY `cartid` (`cartid`),
  KEY `token` (`token`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "pp_trans", <<'EOC' );
CREATE TABLE `pp_trans` (
  `ppid` int unsigned NOT NULL,
  `cartid` int unsigned NOT NULL,
  `transactionid` varchar(19) DEFAULT NULL,
  `transactiontype` varchar(15) DEFAULT NULL,
  `paymenttype` varchar(7) DEFAULT NULL,
  `ordertime` int unsigned DEFAULT NULL,
  `amt` decimal(10,2) DEFAULT NULL,
  `currencycode` varchar(3) DEFAULT NULL,
  `feeamt` decimal(10,2) DEFAULT NULL,
  `settleamt` decimal(10,2) DEFAULT NULL,
  `taxamt` decimal(10,2) DEFAULT NULL,
  `paymentstatus` varchar(20) DEFAULT NULL,
  `pendingreason` varchar(20) DEFAULT NULL,
  `reasoncode` varchar(20) DEFAULT NULL,
  `ack` varchar(20) DEFAULT NULL,
  `timestamp` int unsigned DEFAULT NULL,
  `build` varchar(20) DEFAULT NULL,
  KEY `ppid` (`ppid`),
  KEY `cartid` (`cartid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "priv_list", <<'EOC' );
CREATE TABLE `priv_list` (
  `prlid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `privcode` varchar(20) NOT NULL DEFAULT '',
  `privname` varchar(40) DEFAULT NULL,
  `des` varchar(255) DEFAULT NULL,
  `is_public` enum('1','0') NOT NULL DEFAULT '1',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`prlid`),
  UNIQUE KEY `privcode` (`privcode`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "priv_map", <<'EOC' );
CREATE TABLE `priv_map` (
  `prmid` mediumint unsigned NOT NULL AUTO_INCREMENT,
  `userid` int unsigned NOT NULL DEFAULT '0',
  `prlid` smallint unsigned NOT NULL DEFAULT '0',
  `arg` varchar(40) DEFAULT NULL,
  PRIMARY KEY (`prmid`),
  KEY `userid` (`userid`),
  KEY `prlid` (`prlid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "priv_packages", <<'EOC' );
CREATE TABLE `priv_packages` (
  `pkgid` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL DEFAULT '',
  `lastmoduserid` int unsigned NOT NULL DEFAULT '0',
  `lastmodtime` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`pkgid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "priv_packages_content", <<'EOC' );
CREATE TABLE `priv_packages_content` (
  `pkgid` int unsigned NOT NULL AUTO_INCREMENT,
  `privname` varchar(20) NOT NULL,
  `privarg` varchar(40) NOT NULL,
  PRIMARY KEY (`pkgid`,`privname`,`privarg`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "procnotify", <<'EOC' );
CREATE TABLE `procnotify` (
  `nid` int unsigned NOT NULL AUTO_INCREMENT,
  `cmd` varchar(50) DEFAULT NULL,
  `args` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`nid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "random_user_set", <<'EOC' );
CREATE TABLE `random_user_set` (
  `posttime` int unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `journaltype` char(1) NOT NULL DEFAULT 'P',
  PRIMARY KEY (`userid`),
  KEY `posttime` (`posttime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "rateabuse", <<'EOC' );
CREATE TABLE `rateabuse` (
  `rlid` tinyint unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `evttime` int unsigned NOT NULL,
  `ip` int unsigned NOT NULL,
  `enum` enum('soft','hard') NOT NULL,
  KEY `rlid` (`rlid`,`evttime`),
  KEY `userid` (`userid`),
  KEY `ip` (`ip`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ratelist", <<'EOC' );
CREATE TABLE `ratelist` (
  `rlid` tinyint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  `des` varchar(255) NOT NULL,
  PRIMARY KEY (`rlid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "ratelog", <<'EOC' );
CREATE TABLE `ratelog` (
  `userid` int unsigned NOT NULL,
  `rlid` tinyint unsigned NOT NULL,
  `evttime` int unsigned NOT NULL,
  `ip` int unsigned NOT NULL,
  `quantity` smallint unsigned NOT NULL,
  KEY `userid` (`userid`,`rlid`,`evttime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "readonly_user", <<'EOC' );
CREATE TABLE `readonly_user` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "reluser", <<'EOC' );
CREATE TABLE `reluser` (
  `userid` int unsigned NOT NULL,
  `targetid` int unsigned NOT NULL,
  `type` char(1) NOT NULL,
  PRIMARY KEY (`userid`,`type`,`targetid`),
  KEY `targetid` (`targetid`,`type`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "reluser2", <<'EOC' );
CREATE TABLE `reluser2` (
  `userid` int unsigned NOT NULL,
  `type` smallint unsigned NOT NULL,
  `targetid` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`type`,`targetid`),
  KEY `userid` (`userid`,`targetid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "renames", <<'EOC' );
CREATE TABLE `renames` (
  `renid` int unsigned NOT NULL AUTO_INCREMENT,
  `auth` char(13) NOT NULL,
  `cartid` int unsigned DEFAULT NULL,
  `ownerid` int unsigned DEFAULT NULL,
  `renuserid` int unsigned DEFAULT NULL,
  `fromuser` char(25) DEFAULT NULL,
  `touser` char(25) DEFAULT NULL,
  `rendate` int unsigned DEFAULT NULL,
  `status` char(1) NOT NULL DEFAULT 'A',
  PRIMARY KEY (`renid`),
  KEY `ownerid` (`ownerid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2categories", <<'EOC' );
CREATE TABLE `s2categories` (
  `s2lid` int unsigned NOT NULL,
  `kwid` int unsigned NOT NULL,
  `active` tinyint unsigned NOT NULL DEFAULT '1',
  PRIMARY KEY (`s2lid`,`kwid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2checker", <<'EOC' );
CREATE TABLE `s2checker` (
  `s2lid` int unsigned NOT NULL,
  `checker` mediumblob,
  PRIMARY KEY (`s2lid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2compiled", <<'EOC' );
CREATE TABLE `s2compiled` (
  `s2lid` int unsigned NOT NULL,
  `comptime` int unsigned NOT NULL,
  `compdata` mediumblob,
  PRIMARY KEY (`s2lid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2compiled2", <<'EOC' );
CREATE TABLE `s2compiled2` (
  `userid` int unsigned NOT NULL,
  `s2lid` int unsigned NOT NULL,
  `comptime` int unsigned NOT NULL,
  `compdata` mediumblob,
  PRIMARY KEY (`userid`,`s2lid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2info", <<'EOC' );
CREATE TABLE `s2info` (
  `s2lid` int unsigned NOT NULL,
  `infokey` varchar(80) NOT NULL,
  `value` varchar(255) NOT NULL,
  PRIMARY KEY (`s2lid`,`infokey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2layers", <<'EOC' );
CREATE TABLE `s2layers` (
  `s2lid` int unsigned NOT NULL AUTO_INCREMENT,
  `b2lid` int unsigned NOT NULL,
  `userid` int unsigned NOT NULL,
  `type` enum('core','i18nc','layout','theme','i18n','user') NOT NULL,
  PRIMARY KEY (`s2lid`),
  KEY `userid` (`userid`),
  KEY `b2lid` (`b2lid`,`type`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2source_inno", <<'EOC' );
CREATE TABLE `s2source_inno` (
  `s2lid` int unsigned NOT NULL,
  `s2code` mediumblob,
  PRIMARY KEY (`s2lid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2stylelayers2", <<'EOC' );
CREATE TABLE `s2stylelayers2` (
  `userid` int unsigned NOT NULL,
  `styleid` int unsigned NOT NULL,
  `type` enum('core','i18nc','layout','theme','i18n','user') NOT NULL,
  `s2lid` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`styleid`,`type`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "s2styles", <<'EOC' );
CREATE TABLE `s2styles` (
  `styleid` int unsigned NOT NULL AUTO_INCREMENT,
  `userid` int unsigned NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `modtime` int unsigned NOT NULL,
  PRIMARY KEY (`styleid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_error", <<'EOC' );
CREATE TABLE `sch_error` (
  `error_time` int unsigned NOT NULL,
  `jobid` bigint unsigned NOT NULL,
  `message` varchar(255) NOT NULL,
  `funcid` int unsigned NOT NULL DEFAULT '0',
  KEY `error_time` (`error_time`),
  KEY `jobid` (`jobid`),
  KEY `funcid` (`funcid`,`error_time`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_exitstatus", <<'EOC' );
CREATE TABLE `sch_exitstatus` (
  `jobid` bigint unsigned NOT NULL,
  `status` smallint unsigned DEFAULT NULL,
  `completion_time` int unsigned DEFAULT NULL,
  `delete_after` int unsigned DEFAULT NULL,
  `funcid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`jobid`),
  KEY `delete_after` (`delete_after`),
  KEY `funcid` (`funcid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_funcmap", <<'EOC' );
CREATE TABLE `sch_funcmap` (
  `funcid` int unsigned NOT NULL AUTO_INCREMENT,
  `funcname` varchar(255) NOT NULL,
  PRIMARY KEY (`funcid`),
  UNIQUE KEY `funcname` (`funcname`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_job", <<'EOC' );
CREATE TABLE `sch_job` (
  `jobid` bigint unsigned NOT NULL AUTO_INCREMENT,
  `funcid` int unsigned NOT NULL,
  `arg` mediumblob,
  `uniqkey` varchar(255) DEFAULT NULL,
  `insert_time` int unsigned DEFAULT NULL,
  `run_after` int unsigned NOT NULL,
  `grabbed_until` int unsigned DEFAULT NULL,
  `priority` smallint unsigned DEFAULT NULL,
  `coalesce` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`jobid`),
  UNIQUE KEY `funcid_2` (`funcid`,`uniqkey`),
  KEY `funcid` (`funcid`,`run_after`),
  KEY `funcid_3` (`funcid`,`coalesce`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_mass_error", <<'EOC' );
CREATE TABLE `sch_mass_error` (
  `error_time` int unsigned NOT NULL,
  `jobid` bigint unsigned NOT NULL,
  `message` varchar(255) NOT NULL,
  KEY `error_time` (`error_time`),
  KEY `jobid` (`jobid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_mass_exitstatus", <<'EOC' );
CREATE TABLE `sch_mass_exitstatus` (
  `jobid` bigint unsigned NOT NULL,
  `status` smallint unsigned DEFAULT NULL,
  `completion_time` int unsigned DEFAULT NULL,
  `delete_after` int unsigned DEFAULT NULL,
  PRIMARY KEY (`jobid`),
  KEY `delete_after` (`delete_after`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_mass_funcmap", <<'EOC' );
CREATE TABLE `sch_mass_funcmap` (
  `funcid` int unsigned NOT NULL AUTO_INCREMENT,
  `funcname` varchar(255) NOT NULL,
  PRIMARY KEY (`funcid`),
  UNIQUE KEY `funcname` (`funcname`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_mass_job", <<'EOC' );
CREATE TABLE `sch_mass_job` (
  `jobid` bigint unsigned NOT NULL AUTO_INCREMENT,
  `funcid` int unsigned NOT NULL,
  `arg` mediumblob,
  `uniqkey` varchar(255) DEFAULT NULL,
  `insert_time` int unsigned DEFAULT NULL,
  `run_after` int unsigned NOT NULL,
  `grabbed_until` int unsigned DEFAULT NULL,
  `priority` smallint unsigned DEFAULT NULL,
  `coalesce` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`jobid`),
  UNIQUE KEY `funcid_2` (`funcid`,`uniqkey`),
  KEY `funcid` (`funcid`,`run_after`),
  KEY `funcid_3` (`funcid`,`coalesce`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_mass_note", <<'EOC' );
CREATE TABLE `sch_mass_note` (
  `jobid` bigint unsigned NOT NULL,
  `notekey` varchar(255) NOT NULL,
  `value` mediumblob,
  PRIMARY KEY (`jobid`,`notekey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sch_note", <<'EOC' );
CREATE TABLE `sch_note` (
  `jobid` bigint unsigned NOT NULL,
  `notekey` varchar(255) NOT NULL,
  `value` mediumblob,
  PRIMARY KEY (`jobid`,`notekey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "secrets", <<'EOC' );
CREATE TABLE `secrets` (
  `stime` int unsigned NOT NULL,
  `secret` char(32) NOT NULL,
  PRIMARY KEY (`stime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sessions", <<'EOC' );
CREATE TABLE `sessions` (
  `userid` int unsigned NOT NULL,
  `sessid` mediumint unsigned NOT NULL,
  `auth` char(10) NOT NULL,
  `exptype` enum('short','long','once') NOT NULL,
  `timecreate` int unsigned NOT NULL,
  `timeexpire` int unsigned NOT NULL,
  `ipfixed` char(15) DEFAULT NULL,
  PRIMARY KEY (`userid`,`sessid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sessions_data", <<'EOC' );
CREATE TABLE `sessions_data` (
  `userid` mediumint unsigned NOT NULL,
  `sessid` mediumint unsigned NOT NULL,
  `skey` varchar(30) NOT NULL,
  `sval` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`sessid`,`skey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "shop_carts", <<'EOC' );
CREATE TABLE `shop_carts` (
  `cartid` int unsigned NOT NULL,
  `starttime` int unsigned NOT NULL,
  `userid` int unsigned DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `uniq` varchar(15) NOT NULL,
  `state` int unsigned NOT NULL,
  `paymentmethod` int unsigned NOT NULL,
  `nextscan` int unsigned NOT NULL DEFAULT '0',
  `authcode` varchar(20) NOT NULL,
  `cartblob` mediumblob NOT NULL,
  PRIMARY KEY (`cartid`),
  KEY `userid` (`userid`),
  KEY `uniq` (`uniq`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "shop_cmo", <<'EOC' );
CREATE TABLE `shop_cmo` (
  `cartid` int unsigned NOT NULL,
  `paymentmethod` varchar(255) NOT NULL,
  `notes` text,
  PRIMARY KEY (`cartid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "shop_codes", <<'EOC' );
CREATE TABLE `shop_codes` (
  `acid` int unsigned NOT NULL,
  `cartid` int unsigned NOT NULL,
  `itemid` int unsigned NOT NULL,
  PRIMARY KEY (`acid`),
  UNIQUE KEY `cartid` (`cartid`,`itemid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "site_stats", <<'EOC' );
CREATE TABLE `site_stats` (
  `category_id` int unsigned NOT NULL,
  `key_id` int unsigned NOT NULL,
  `insert_time` int unsigned NOT NULL,
  `value` int unsigned NOT NULL,
  KEY `category_id` (`category_id`,`key_id`,`insert_time`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "siteadmin_email_history", <<'EOC' );
CREATE TABLE `siteadmin_email_history` (
  `msgid` int unsigned NOT NULL,
  `remoteid` int unsigned NOT NULL,
  `time_sent` int unsigned NOT NULL,
  `account` varchar(255) NOT NULL,
  `sendto` varchar(255) NOT NULL,
  `subject` varchar(255) NOT NULL,
  `request` int unsigned DEFAULT NULL,
  `message` mediumtext NOT NULL,
  `notes` mediumtext,
  PRIMARY KEY (`msgid`),
  KEY `account` (`account`),
  KEY `sendto` (`sendto`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sitekeywords", <<'EOC' );
CREATE TABLE `sitekeywords` (
  `kwid` int unsigned NOT NULL,
  `keyword` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL,
  PRIMARY KEY (`kwid`),
  UNIQUE KEY `keyword` (`keyword`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "spamreports", <<'EOC' );
CREATE TABLE `spamreports` (
  `srid` mediumint unsigned NOT NULL AUTO_INCREMENT,
  `reporttime` int unsigned NOT NULL,
  `posttime` int unsigned NOT NULL,
  `state` enum('open','closed') NOT NULL DEFAULT 'open',
  `ip` varchar(45) DEFAULT NULL,
  `journalid` int unsigned NOT NULL,
  `posterid` int unsigned NOT NULL DEFAULT '0',
  `report_type` enum('entry','comment','message') NOT NULL DEFAULT 'comment',
  `subject` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `body` blob NOT NULL,
  `client` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`srid`),
  KEY `ip` (`ip`),
  KEY `posterid` (`posterid`),
  KEY `client` (`client`),
  KEY `reporttime` (`reporttime`,`journalid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "statkeylist", <<'EOC' );
CREATE TABLE `statkeylist` (
  `statkeyid` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`statkeyid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "stats", <<'EOC' );
CREATE TABLE `stats` (
  `statcat` varchar(30) NOT NULL,
  `statkey` varchar(150) NOT NULL,
  `statval` int unsigned NOT NULL,
  UNIQUE KEY `statcat_2` (`statcat`,`statkey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "statushistory", <<'EOC' );
CREATE TABLE `statushistory` (
  `userid` int unsigned NOT NULL,
  `adminid` int unsigned NOT NULL,
  `shtype` varchar(20) NOT NULL,
  `shdate` timestamp NOT NULL,
  `notes` text,
  KEY `userid` (`userid`,`shdate`),
  KEY `adminid` (`adminid`,`shdate`),
  KEY `adminid_2` (`adminid`,`shtype`,`shdate`),
  KEY `shtype` (`shtype`,`shdate`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "subs", <<'EOC' );
CREATE TABLE `subs` (
  `userid` int unsigned NOT NULL,
  `subid` int unsigned NOT NULL,
  `is_dirty` tinyint unsigned DEFAULT NULL,
  `journalid` int unsigned NOT NULL,
  `etypeid` smallint unsigned NOT NULL,
  `arg1` int unsigned NOT NULL,
  `arg2` int unsigned NOT NULL,
  `ntypeid` smallint unsigned NOT NULL,
  `createtime` int unsigned NOT NULL,
  `expiretime` int unsigned NOT NULL DEFAULT '0',
  `flags` smallint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`subid`),
  KEY `is_dirty` (`is_dirty`),
  KEY `etypeid` (`etypeid`,`journalid`,`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "support", <<'EOC' );
CREATE TABLE `support` (
  `spid` int unsigned NOT NULL AUTO_INCREMENT,
  `reqtype` enum('user','email') DEFAULT NULL,
  `requserid` int unsigned NOT NULL DEFAULT '0',
  `reqname` varchar(50) DEFAULT NULL,
  `reqemail` varchar(70) DEFAULT NULL,
  `state` enum('open','closed') DEFAULT NULL,
  `authcode` varchar(15) NOT NULL DEFAULT '',
  `spcatid` int unsigned NOT NULL DEFAULT '0',
  `subject` varchar(80) DEFAULT NULL,
  `timecreate` int unsigned DEFAULT NULL,
  `timetouched` int unsigned DEFAULT NULL,
  `timemodified` int unsigned DEFAULT NULL,
  `timeclosed` int unsigned DEFAULT NULL,
  `timelasthelp` int unsigned DEFAULT NULL,
  PRIMARY KEY (`spid`),
  KEY `state` (`state`),
  KEY `requserid` (`requserid`),
  KEY `reqemail` (`reqemail`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "support_answers", <<'EOC' );
CREATE TABLE `support_answers` (
  `ansid` int unsigned NOT NULL,
  `spcatid` int unsigned NOT NULL,
  `lastmodtime` int unsigned NOT NULL,
  `lastmoduserid` int unsigned NOT NULL,
  `subject` varchar(255) DEFAULT NULL,
  `body` text,
  PRIMARY KEY (`ansid`),
  KEY `spcatid` (`spcatid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "support_youreplied", <<'EOC' );
CREATE TABLE `support_youreplied` (
  `userid` int unsigned NOT NULL,
  `spid` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`spid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "supportcat", <<'EOC' );
CREATE TABLE `supportcat` (
  `spcatid` int unsigned NOT NULL AUTO_INCREMENT,
  `catkey` varchar(25) NOT NULL,
  `catname` varchar(80) DEFAULT NULL,
  `sortorder` mediumint unsigned NOT NULL DEFAULT '0',
  `basepoints` tinyint unsigned NOT NULL DEFAULT '1',
  `is_selectable` enum('1','0') NOT NULL DEFAULT '1',
  `public_read` enum('1','0') NOT NULL DEFAULT '1',
  `public_help` enum('1','0') NOT NULL DEFAULT '1',
  `allow_screened` enum('1','0') NOT NULL DEFAULT '0',
  `hide_helpers` enum('1','0') NOT NULL DEFAULT '0',
  `user_closeable` enum('1','0') NOT NULL DEFAULT '1',
  `replyaddress` varchar(50) DEFAULT NULL,
  `no_autoreply` enum('1','0') NOT NULL DEFAULT '0',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`spcatid`),
  UNIQUE KEY `catkey` (`catkey`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "supportlog", <<'EOC' );
CREATE TABLE `supportlog` (
  `splid` int unsigned NOT NULL AUTO_INCREMENT,
  `spid` int unsigned NOT NULL DEFAULT '0',
  `timelogged` int unsigned NOT NULL DEFAULT '0',
  `type` enum('req','answer','comment','internal','screened') NOT NULL,
  `faqid` mediumint unsigned NOT NULL DEFAULT '0',
  `userid` int unsigned NOT NULL DEFAULT '0',
  `message` text,
  `tier` tinyint unsigned DEFAULT NULL,
  PRIMARY KEY (`splid`),
  KEY `spid` (`spid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "supportnotify", <<'EOC' );
CREATE TABLE `supportnotify` (
  `spcatid` int unsigned NOT NULL DEFAULT '0',
  `userid` int unsigned NOT NULL DEFAULT '0',
  `level` enum('all','new') DEFAULT NULL,
  PRIMARY KEY (`spcatid`,`userid`),
  KEY `spcatid` (`spcatid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "supportpoints", <<'EOC' );
CREATE TABLE `supportpoints` (
  `spid` int unsigned NOT NULL DEFAULT '0',
  `userid` int unsigned NOT NULL DEFAULT '0',
  `points` tinyint unsigned DEFAULT NULL,
  KEY `spid` (`spid`),
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "supportpointsum", <<'EOC' );
CREATE TABLE `supportpointsum` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `totpoints` mediumint unsigned DEFAULT '0',
  `lastupdate` int unsigned NOT NULL,
  PRIMARY KEY (`userid`),
  KEY `totpoints` (`totpoints`,`lastupdate`),
  KEY `lastupdate` (`lastupdate`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "supportprop", <<'EOC' );
CREATE TABLE `supportprop` (
  `spid` int unsigned NOT NULL DEFAULT '0',
  `prop` varchar(30) NOT NULL,
  `value` varchar(255) NOT NULL,
  PRIMARY KEY (`spid`,`prop`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "syndicated", <<'EOC' );
CREATE TABLE `syndicated` (
  `userid` int unsigned NOT NULL,
  `synurl` varchar(255) DEFAULT NULL,
  `checknext` datetime NOT NULL,
  `lastcheck` datetime DEFAULT NULL,
  `lastmod` int unsigned DEFAULT NULL,
  `etag` varchar(80) DEFAULT NULL,
  `fuzzy_token` varchar(255) DEFAULT NULL,
  `laststatus` varchar(80) DEFAULT NULL,
  `lastnew` datetime DEFAULT NULL,
  `oldest_ourdate` datetime DEFAULT NULL,
  `numreaders` mediumint DEFAULT NULL,
  PRIMARY KEY (`userid`),
  UNIQUE KEY `synurl` (`synurl`),
  KEY `checknext` (`checknext`),
  KEY `fuzzy_token` (`fuzzy_token`),
  KEY `numreaders` (`numreaders`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "synitem", <<'EOC' );
CREATE TABLE `synitem` (
  `userid` int unsigned NOT NULL,
  `item` char(22) DEFAULT NULL,
  `dateadd` datetime NOT NULL,
  KEY `userid` (`userid`,`item`(3)),
  KEY `userid_2` (`userid`,`dateadd`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "sysban", <<'EOC' );
CREATE TABLE `sysban` (
  `banid` mediumint unsigned NOT NULL AUTO_INCREMENT,
  `status` enum('active','expired') NOT NULL DEFAULT 'active',
  `bandate` datetime DEFAULT NULL,
  `banuntil` datetime DEFAULT NULL,
  `what` varchar(20) NOT NULL,
  `value` varchar(80) DEFAULT NULL,
  `note` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`banid`),
  KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "talk2", <<'EOC' );
CREATE TABLE `talk2` (
  `journalid` int unsigned NOT NULL,
  `jtalkid` int unsigned NOT NULL,
  `nodetype` char(1) NOT NULL DEFAULT '',
  `nodeid` int unsigned NOT NULL DEFAULT '0',
  `parenttalkid` mediumint unsigned NOT NULL,
  `posterid` int unsigned NOT NULL DEFAULT '0',
  `datepost` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `state` char(1) DEFAULT 'A',
  PRIMARY KEY (`journalid`,`jtalkid`),
  KEY `nodetype` (`nodetype`,`journalid`,`nodeid`),
  KEY `journalid` (`journalid`,`state`,`nodetype`),
  KEY `posterid` (`posterid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "talkleft", <<'EOC' );
CREATE TABLE `talkleft` (
  `userid` int unsigned NOT NULL,
  `posttime` int unsigned NOT NULL,
  `journalid` int unsigned NOT NULL,
  `nodetype` char(1) NOT NULL,
  `nodeid` int unsigned NOT NULL,
  `jtalkid` int unsigned NOT NULL,
  `publicitem` enum('1','0') NOT NULL DEFAULT '1',
  KEY `userid` (`userid`,`posttime`),
  KEY `journalid` (`journalid`,`nodetype`,`nodeid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "talkleft_xfp", <<'EOC' );
CREATE TABLE `talkleft_xfp` (
  `userid` int unsigned NOT NULL,
  `posttime` int unsigned NOT NULL,
  `journalid` int unsigned NOT NULL,
  `nodetype` char(1) NOT NULL,
  `nodeid` int unsigned NOT NULL,
  `jtalkid` int unsigned NOT NULL,
  `publicitem` enum('1','0') NOT NULL DEFAULT '1',
  KEY `userid` (`userid`,`posttime`),
  KEY `journalid` (`journalid`,`nodetype`,`nodeid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "talkprop2", <<'EOC' );
CREATE TABLE `talkprop2` (
  `journalid` int unsigned NOT NULL,
  `jtalkid` int unsigned NOT NULL,
  `tpropid` tinyint unsigned NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`journalid`,`jtalkid`,`tpropid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "talkproplist", <<'EOC' );
CREATE TABLE `talkproplist` (
  `tpropid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `prettyname` varchar(60) DEFAULT NULL,
  `datatype` enum('char','num','bool','blobchar') NOT NULL DEFAULT 'char',
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  `ownership` enum('system','user') NOT NULL DEFAULT 'user',
  `des` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`tpropid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "talktext2", <<'EOC' );
CREATE TABLE `talktext2` (
  `journalid` int unsigned NOT NULL,
  `jtalkid` int unsigned NOT NULL,
  `subject` tinyblob DEFAULT NULL,
  `body` mediumblob,
  PRIMARY KEY (`journalid`,`jtalkid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "tempanonips", <<'EOC' );
CREATE TABLE `tempanonips` (
  `reporttime` int unsigned NOT NULL,
  `ip` varchar(45) NOT NULL,
  `journalid` int unsigned NOT NULL,
  `jtalkid` int unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`jtalkid`),
  KEY `reporttime` (`reporttime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "totp_recovery_codes", <<'EOC' );
CREATE TABLE `totp_recovery_codes` (
  `userid` int unsigned NOT NULL,
  `code` varchar(255) NOT NULL,
  `status` char(1) NOT NULL,
  `used_ip` varchar(15) DEFAULT NULL,
  `used_time` int unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`,`code`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "trust_groups", <<'EOC' );
CREATE TABLE `trust_groups` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `groupnum` tinyint unsigned NOT NULL DEFAULT '0',
  `groupname` varchar(90) NOT NULL DEFAULT '',
  `sortorder` tinyint unsigned NOT NULL DEFAULT '50',
  `is_public` enum('0','1') NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`groupnum`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "underage", <<'EOC' );
CREATE TABLE `underage` (
  `uniq` char(15) NOT NULL,
  `timeof` int NOT NULL,
  PRIMARY KEY (`uniq`),
  KEY `timeof` (`timeof`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "uniqmap", <<'EOC' );
CREATE TABLE `uniqmap` (
  `uniq` varchar(15) NOT NULL,
  `userid` int unsigned NOT NULL,
  `modtime` int unsigned NOT NULL,
  PRIMARY KEY (`userid`,`uniq`),
  KEY `userid` (`userid`,`modtime`),
  KEY `uniq` (`uniq`,`modtime`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "user", <<'EOC' );
CREATE TABLE `user` (
  `userid` int unsigned NOT NULL AUTO_INCREMENT,
  `user` varchar(25) DEFAULT NULL,
  `caps` smallint unsigned NOT NULL DEFAULT '0',
  `clusterid` tinyint unsigned NOT NULL,
  `dversion` tinyint unsigned NOT NULL,
  `email` varchar(50) DEFAULT NULL,
  `password` char(30) DEFAULT NULL,
  `status` char(1) NOT NULL DEFAULT 'N',
  `statusvis` char(1) NOT NULL DEFAULT 'V',
  `statusvisdate` datetime DEFAULT NULL,
  `name` varchar(80) NOT NULL,
  `bdate` date DEFAULT NULL,
  `themeid` int NOT NULL DEFAULT '1',
  `moodthemeid` int unsigned NOT NULL DEFAULT '1',
  `opt_forcemoodtheme` enum('Y','N') NOT NULL DEFAULT 'N',
  `allow_infoshow` char(1) NOT NULL DEFAULT 'Y',
  `allow_contactshow` char(1) NOT NULL DEFAULT 'Y',
  `allow_getljnews` char(1) NOT NULL DEFAULT 'N',
  `opt_showtalklinks` char(1) NOT NULL DEFAULT 'Y',
  `opt_whocanreply` enum('all','reg','friends') NOT NULL DEFAULT 'all',
  `opt_gettalkemail` char(1) NOT NULL DEFAULT 'Y',
  `opt_htmlemail` enum('Y','N') NOT NULL DEFAULT 'Y',
  `opt_mangleemail` char(1) NOT NULL DEFAULT 'N',
  `useoverrides` char(1) NOT NULL DEFAULT 'N',
  `defaultpicid` int unsigned DEFAULT NULL,
  `has_bio` enum('Y','N') NOT NULL DEFAULT 'N',
  `is_system` enum('Y','N') NOT NULL DEFAULT 'N',
  `journaltype` char(1) NOT NULL DEFAULT 'P',
  `lang` char(2) NOT NULL DEFAULT 'EN',
  `oldenc` tinyint NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`),
  UNIQUE KEY `user` (`user`),
  KEY `email` (`email`),
  KEY `status` (`status`),
  KEY `statusvis` (`statusvis`),
  KEY `idxcluster` (`clusterid`),
  KEY `idxversion` (`dversion`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userbio", <<'EOC' );
CREATE TABLE `userbio` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `bio` text,
  PRIMARY KEY (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usercounter", <<'EOC' );
CREATE TABLE `usercounter` (
  `journalid` int unsigned NOT NULL,
  `area` char(1) NOT NULL,
  `max` int unsigned NOT NULL,
  PRIMARY KEY (`journalid`,`area`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "useridmap", <<'EOC' );
CREATE TABLE `useridmap` (
  `userid` int unsigned NOT NULL,
  `user` char(25) NOT NULL,
  PRIMARY KEY (`userid`),
  UNIQUE KEY `user` (`user`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userinterests", <<'EOC' );
CREATE TABLE `userinterests` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `intid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`intid`),
  KEY `intid` (`intid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userkeywords", <<'EOC' );
CREATE TABLE `userkeywords` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `kwid` int unsigned NOT NULL DEFAULT '0',
  `keyword` varchar(80) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL,
  PRIMARY KEY (`userid`,`kwid`),
  UNIQUE KEY `userid` (`userid`,`keyword`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userlog", <<'EOC' );
CREATE TABLE `userlog` (
  `userid` int unsigned NOT NULL,
  `logtime` int unsigned NOT NULL,
  `action` varchar(30) NOT NULL,
  `actiontarget` int unsigned DEFAULT NULL,
  `remoteid` int unsigned DEFAULT NULL,
  `ip` varchar(45) DEFAULT NULL,
  `uniq` varchar(15) DEFAULT NULL,
  `extra` varchar(255) DEFAULT NULL,
  KEY `userid` (`userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usermsg", <<'EOC' );
CREATE TABLE `usermsg` (
  `journalid` int unsigned NOT NULL,
  `msgid` int unsigned NOT NULL,
  `type` enum('in','out') NOT NULL,
  `parent_msgid` int unsigned DEFAULT NULL,
  `otherid` int unsigned NOT NULL,
  `timesent` int unsigned DEFAULT NULL,
  `state` char(1) DEFAULT 'A',
  PRIMARY KEY (`journalid`,`msgid`),
  KEY `journalid` (`journalid`,`type`,`otherid`),
  KEY `journalid_2` (`journalid`,`timesent`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usermsgprop", <<'EOC' );
CREATE TABLE `usermsgprop` (
  `journalid` int unsigned NOT NULL,
  `msgid` int unsigned NOT NULL,
  `propid` smallint unsigned NOT NULL,
  `propval` varchar(255) NOT NULL,
  PRIMARY KEY (`journalid`,`msgid`,`propid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usermsgproplist", <<'EOC' );
CREATE TABLE `usermsgproplist` (
  `propid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`propid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usermsgtext", <<'EOC' );
CREATE TABLE `usermsgtext` (
  `journalid` int unsigned NOT NULL,
  `msgid` int unsigned NOT NULL,
  `subject` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `body` blob NOT NULL,
  PRIMARY KEY (`journalid`,`msgid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userpic2", <<'EOC' );
CREATE TABLE `userpic2` (
  `picid` int unsigned NOT NULL,
  `userid` int unsigned NOT NULL DEFAULT '0',
  `fmt` char(1) DEFAULT NULL,
  `width` smallint NOT NULL DEFAULT '0',
  `height` smallint NOT NULL DEFAULT '0',
  `state` char(1) NOT NULL DEFAULT 'N',
  `picdate` datetime DEFAULT NULL,
  `md5base64` char(22) NOT NULL DEFAULT '',
  `comment` varchar(255) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `description` varchar(600) CHARACTER SET latin1 COLLATE latin1_bin NOT NULL DEFAULT '',
  `flags` tinyint unsigned NOT NULL DEFAULT '0',
  `location` enum('blob','disk','mogile','blobstore') DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`picid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userpicblob2", <<'EOC' );
CREATE TABLE `userpicblob2` (
  `userid` int unsigned NOT NULL,
  `picid` int unsigned NOT NULL,
  `imagedata` blob,
  PRIMARY KEY (`userid`,`picid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userpicmap2", <<'EOC' );
CREATE TABLE `userpicmap2` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `kwid` int unsigned NOT NULL DEFAULT '0',
  `picid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`,`kwid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userpicmap3", <<'EOC' );
CREATE TABLE `userpicmap3` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `mapid` int unsigned NOT NULL,
  `kwid` int unsigned DEFAULT NULL,
  `picid` int unsigned DEFAULT NULL,
  `redirect_mapid` int unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`,`mapid`),
  UNIQUE KEY `userid` (`userid`,`kwid`),
  KEY `redirect` (`userid`,`redirect_mapid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userprop", <<'EOC' );
CREATE TABLE `userprop` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `upropid` smallint unsigned NOT NULL DEFAULT '0',
  `value` varchar(60) DEFAULT NULL,
  PRIMARY KEY (`userid`,`upropid`),
  KEY `upropid` (`upropid`,`value`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userpropblob", <<'EOC' );
CREATE TABLE `userpropblob` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `upropid` smallint unsigned NOT NULL DEFAULT '0',
  `value` blob,
  PRIMARY KEY (`userid`,`upropid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userproplist", <<'EOC' );
CREATE TABLE `userproplist` (
  `upropid` smallint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `indexed` enum('1','0') NOT NULL DEFAULT '1',
  `cldversion` tinyint unsigned NOT NULL,
  `multihomed` enum('1','0') NOT NULL DEFAULT '0',
  `prettyname` varchar(60) DEFAULT NULL,
  `datatype` enum('char','num','bool','blobchar') NOT NULL DEFAULT 'char',
  `des` varchar(255) DEFAULT NULL,
  `scope` enum('general','local') NOT NULL DEFAULT 'general',
  PRIMARY KEY (`upropid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userproplite", <<'EOC' );
CREATE TABLE `userproplite` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `upropid` smallint unsigned NOT NULL DEFAULT '0',
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`upropid`),
  KEY `upropid` (`upropid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userproplite2", <<'EOC' );
CREATE TABLE `userproplite2` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `upropid` smallint unsigned NOT NULL DEFAULT '0',
  `value` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`userid`,`upropid`),
  KEY `upropid` (`upropid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "users_for_paid_accounts", <<'EOC' );
CREATE TABLE `users_for_paid_accounts` (
  `userid` int unsigned NOT NULL,
  `time_inserted` int unsigned NOT NULL DEFAULT '0',
  `points` int unsigned NOT NULL DEFAULT '0',
  `journaltype` char(1) NOT NULL DEFAULT 'P',
  PRIMARY KEY (`userid`,`time_inserted`),
  KEY `time_inserted` (`time_inserted`),
  KEY `journaltype` (`journaltype`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usersearch_packdata", <<'EOC' );
CREATE TABLE `usersearch_packdata` (
  `userid` int unsigned NOT NULL,
  `packed` char(8) CHARACTER SET latin1 COLLATE latin1_bin DEFAULT NULL,
  `mtime` int unsigned NOT NULL,
  `good_until` int unsigned DEFAULT NULL,
  PRIMARY KEY (`userid`),
  KEY `mtime` (`mtime`),
  KEY `good_until` (`good_until`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usertags", <<'EOC' );
CREATE TABLE `usertags` (
  `journalid` int unsigned NOT NULL,
  `kwid` int unsigned NOT NULL,
  `parentkwid` int unsigned DEFAULT NULL,
  `display` enum('0','1') NOT NULL DEFAULT '1',
  PRIMARY KEY (`journalid`,`kwid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "usertrans", <<'EOC' );
CREATE TABLE `usertrans` (
  `userid` int unsigned NOT NULL DEFAULT '0',
  `time` int unsigned NOT NULL DEFAULT '0',
  `what` varchar(25) NOT NULL DEFAULT '',
  `before` varchar(25) NOT NULL DEFAULT '',
  `after` varchar(25) NOT NULL DEFAULT '',
  KEY `userid` (`userid`),
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "userusage", <<'EOC' );
CREATE TABLE `userusage` (
  `userid` int unsigned NOT NULL,
  `timecreate` datetime NOT NULL,
  `timeupdate` datetime DEFAULT NULL,
  `timecheck` datetime DEFAULT NULL,
  `lastitemid` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`userid`),
  KEY `timeupdate` (`timeupdate`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "vgift_counts", <<'EOC' );
CREATE TABLE `vgift_counts` (
  `vgiftid` int unsigned NOT NULL,
  `count` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`vgiftid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "vgift_ids", <<'EOC' );
CREATE TABLE `vgift_ids` (
  `vgiftid` int unsigned NOT NULL,
  `name` varchar(255) NOT NULL,
  `created_t` int unsigned NOT NULL,
  `creatorid` int unsigned NOT NULL DEFAULT '0',
  `active` enum('Y','N') NOT NULL DEFAULT 'N',
  `featured` enum('Y','N') NOT NULL DEFAULT 'N',
  `custom` enum('Y','N') NOT NULL DEFAULT 'N',
  `approved` enum('Y','N') DEFAULT NULL,
  `approved_by` int unsigned DEFAULT NULL,
  `approved_why` mediumtext,
  `description` mediumtext,
  `cost` int unsigned NOT NULL DEFAULT '0',
  `mime_small` varchar(255) DEFAULT NULL,
  `mime_large` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`vgiftid`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "vgift_tagpriv", <<'EOC' );
CREATE TABLE `vgift_tagpriv` (
  `tagid` int unsigned NOT NULL,
  `prlid` smallint unsigned NOT NULL,
  `arg` varchar(40) NOT NULL,
  PRIMARY KEY (`tagid`,`prlid`,`arg`),
  KEY `tagid` (`tagid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "vgift_tags", <<'EOC' );
CREATE TABLE `vgift_tags` (
  `tagid` int unsigned NOT NULL,
  `vgiftid` int unsigned NOT NULL,
  PRIMARY KEY (`tagid`,`vgiftid`),
  KEY `vgiftid` (`vgiftid`),
  KEY `tagid` (`tagid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "vgift_trans", <<'EOC' );
CREATE TABLE `vgift_trans` (
  `transid` int unsigned NOT NULL,
  `buyerid` int unsigned NOT NULL DEFAULT '0',
  `rcptid` int unsigned NOT NULL,
  `vgiftid` int unsigned NOT NULL,
  `cartid` int unsigned DEFAULT NULL,
  `delivery_t` int unsigned NOT NULL,
  `delivered` enum('Y','N') NOT NULL DEFAULT 'N',
  `accepted` enum('Y','N') NOT NULL DEFAULT 'N',
  `expired` enum('Y','N') NOT NULL DEFAULT 'N',
  PRIMARY KEY (`rcptid`,`transid`),
  KEY `delivery_t` (`delivery_t`),
  KEY `vgiftid` (`vgiftid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

register_tablecreate( "wt_edges", <<'EOC' );
CREATE TABLE `wt_edges` (
  `from_userid` int unsigned NOT NULL DEFAULT '0',
  `to_userid` int unsigned NOT NULL DEFAULT '0',
  `fgcolor` mediumint unsigned NOT NULL DEFAULT '0',
  `bgcolor` mediumint unsigned NOT NULL DEFAULT '16777215',
  `groupmask` bigint unsigned NOT NULL DEFAULT '1',
  `showbydefault` enum('1','0') NOT NULL DEFAULT '1',
  PRIMARY KEY (`from_userid`,`to_userid`),
  KEY `to_userid` (`to_userid`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
EOC

1;    # return true
