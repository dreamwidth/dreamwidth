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
# These are descriptions of various configuration options for the site.
# See also etc/config.pl.
#

package LJ::ConfCheck;

use strict;

add_singletons(qw(
                  @USER_TABLES $PROTOCOL_VER $MAX_DVERSION
                  $CLEAR_CACHES $BIN $HTDOCS $SSLDOCS
                  $ACTIVE_CRUMB $IMGPREFIX_BAK $IS_SSL
                  $IP_BANNED_LOADED $_XFER_REMOTE_IP
                  %LIB_MOD_TIME %MEMCACHE_ARRAYFMT
                  $STATPREFIX_BAK $UNIQ_BANNED_LOADED
                  @LJ::CLEANUP_HANDLERS
                  ));

add_conf('$ADMIN_EMAIL',
         required => 1,
         des      => "Email address of the installation's webmaster.",
         type     => "email",
         );

add_conf('$BLOCKED_BOT_SUBJECT',
         required => 0,
         des      => "Subject/title shown to people suspected to be bots.",
         type     => "text",
         );

add_conf('$BLOCKED_BOT_URI',
         required => 0,
         des      => "Path (e.g. /bots) at which a informational page about your acceptable bot policies are documented.  This URI is excluded from anti-bot measures, so make sure it's as permissive as possible to allow humans in who may be lazy in their typing.  For example, leave off the trailing slash (/bots instead of /bots/) if your URI is a directory.",
         type     => "uri",
         );

add_conf('$BLOCKED_BOT_MESSAGE',
         required => 0,
         des      => "Message shown to people suspected to be bots, informing them they've been banned, and where/what the rules are.",
         type     => "html",
         );

add_conf('$BML_DENY_CONFIG',
         required => 0,
         des      => "Comma-separated list of directories under htdocs which should be served without parsing their _config.bml files.  For example, directories that might be under a lesser-trusted person's control.",
         validate => qr/^\w+(\s*,\s*\w+)*$/,
         );

add_conf('$BOGUS_EMAIL',
         required => 1,
         des      => "Email address which comments and other notifications come from, but which cannot accept incoming email itself.",
         type => "email",
         );

add_conf('$COMMUNITY_EMAIL',
         required => 0,
         des      => "Email address which comments and other notifications regarding communities come from.  If unspecified, defaults to \$ADMIN_EMAIL .",
         type => "email",
         );

add_conf('$COMPRESS_TEXT',
         required => 0,
         type => "bool",
         des => "If set, text is gzip-compressed when put in the database.  When reading from the database, this configuration means nothing, as the code automatically determines to uncompress or not.",
         );

add_conf('$COOKIE_DOMAIN',
         required => 1,
         des => "The 'domain' value set on cookies sent to users.  By default, value is \".\$DOMAIN\".  Note the leading period, which is a wildcard for everything at or under \$DOMAIN.",
         );

add_conf('$DB_LOG_HOST',
         required => 0,
         type => "hostport",
         des => "An optional host:port to send UDP packets to with blocking reports.  See LJ::blocking_report(..)",
         );

add_conf('$DB_TIMEOUT',
         required => 0,
         type => "int",
         des => "Integer number of seconds to wait for database handles before timing out.  By default, zero, which means no timeout.",
         );

add_conf('$DEFAULT_CLUSTER',
         required => 0,
         des => "Integer of a user cluster number or arrayref of cluster numbers, for where new users are assigned after account creation.  In the case of an arrayref, you can weight one particular cluster over another by place it in the arrayref more often.  For instance, [1, 2, 2, 2] would make users go onto cluster #2 75% of the time, and cluster #1 25% of the time.",
         );

add_conf('$DEFAULT_EDITOR',
         des => "Editor for new entries if the user hasn\'t overridden it.  Should be \'rich\' or \'plain\'.",
         );

add_conf('$DEFAULT_LANG',
         required => 0,
         des => "Default language (code) to show site in, for users that haven't set their langauge.  Defaults to the first item in \@LANGS, which is usually \"en\", for English.",
         );

add_conf('@LANGS',
         des => "Array of language codes to make available for users to select between.  Also, if they haven't selected a language, it's auto-detected from their browser.");

add_conf('@LANGS_IN_PROGRESS',
         des => "Array of additional language codes to allow users to select, if they know about them.  These ones are actively being translated, but aren't yet ready to be publicly available.");

add_conf('@CLUSTERS',
         des => "Array of cluster numbers in operation.");

add_conf('@QBUFFERD_CLUSTERS',
         des => "If defined, list of clusters that qbufferd should use when retrieving and processing outstanding jobs.  Defaults to \@CLUSTERS");

add_conf('$DEFAULT_STYLE',
         required => 0,
         des => "Hashref describing default S2 style.  Keys are layer types, values being the S2 redist_uniqs.",
         type => "hashref",
         allowed_keys => qw(core layout theme i18n i81nc),
         );

add_conf('$DISABLE_MASTER',
         type => 'bool',
         des => "If set to true, access to the 'master' DB role is prevented, by breaking the get_dbh function.  Useful during master database migrations.",
         );

add_conf('$DISABLE_MEDIA_UPLOADS',
         type => 'bool',
         des => "If set to true, all media uploads that would go to MogileFS are disabled.",
         );

add_conf('$DISCONNECT_DBS',
         type => 'bool',
         des => "If set to true, all database connections (except those for logging) are disconnected at the end of each request.  Recommended for high-performance sites with lots of database clusters.  See also: \$DISCONNECT_DB_LOG",
         );

add_conf('$DISCONNECT_MEMCACHE',
         type => 'bool',
         des => "If set to true, memcached connections are disconnected at the end of each request.  Not recommended if your memcached instances are Linux 2.6.",
         );

add_conf('$DOMAIN',
         required => 1,
         des => "The base domain name for your installation.  This value is used to auto-set a bunch of other configuration values.",
         type => 'hostname,'
         );

add_conf('$DOMAIN_WEB',
         required => 0,
         des => "The preferred domain name for your installation's web root.  For instance, if your \$DOMAIN is 'foo.com', your \$DOMAIN_WEB might be 'www.foo.com', so any user who goes to foo.com will be redirected to www.foo.com.",
         type => 'hostname,'
         );

add_conf('$EMAIL_POST_DOMAIN',
         type => 'hostname',
         des => "Domain name for incoming emails.  For instance, user 'bob' might post by sending email to 'bob\@post.service.com', where 'post.service.com' is the value of \$EMAIL_POST_DOMAIN",
         );

add_conf('$EXAMPLE_USER_ACCOUNT',
         required => 0,
         type => "string",
         des => "The username of the example user account, for use in Support and documentation.  Must be an actual account on the site.",
         );

add_conf('$HOME',
         type => 'directory',
         no_trailing_slash => 1,
         des => "The root of your LJ installation.  This directory should contain, for example, 'htdocs' and 'cgi-bin', etc.",
         );

add_conf('$IMGPREFIX',
         type => 'url',
         no_trailing_slash => 1,
         des => "Prefix on (static) image URLs.  By default, it's '\$SITEROOT/img', but your load balancing may dictate another hostname or port for efficiency.  See also: \$IMGPREFIX",
         );

add_conf('$JSPREFIX',
         type => 'url',
         no_trailing_slash => 1,
         des => "Prefix on (static) javascript URLs.  By default, it's '\$SITEROOT/js', but your load balancing may dictate another hostname or port for efficiency.  See also: \$IMGPREFIX",
         );

add_conf('$PALIMGROOT',
         type => 'url',
         no_trailing_slash => 1,
         des => "Prefix on GIF/PNGs with dynamically generated palettes.  By default, it's '\$SITEROOT/palimg\', and there's little reason to change it.  Somewhat related: note that Perlbal has a plugin to handle these before it gets to mod_perl, if you'd like to relieve some load on your backend mod_perls.   But you don't necessarily need this option for using Perlbal to do it.  Depends on your config.",
         );

add_conf('$MAILLOCK',
         type => ["hostname", "none", "ddlockd"],
         des => "Locking method that mailgated.pl should use when processing incoming emails from the Maildir.  You can safely use 'none' if you have a single host processing mail, otherwise 'ddlockd' or 'hostname' is recommended, though 'hostname' means mail that arrived on a host that then crashes won't be processed until it comes back up.  ddlockd is recommended, if you're using multiple mailgated processes.",
         );

add_conf('$MAX_ATOM_UPLOAD',
         type => 'int',
         des => "Max number of bytes that users are allowed to upload via Atom.  Note that this upload path isn't ideal, so the entire upload must fit in memory.  Default is 25MB until path is optimized.",
         );

add_conf('$MAX_FOAF_FRIENDS',
         type => 'int',
         des => "The maximum number of friends that users' FOAF files will show.  Defaults to 1000.  If they have more than the configured amount, some friends will be omitted.",
         );

add_conf('$MAX_FRIENDOF_LOAD',
         type => 'int',
         des => "The maximum number of friend-ofs ('fans'/'followers') to load for a given user.  Defaults to 5000.  Beyond that, a user is just too popular and saying 5,000 is usually sufficient because people aren't actually reading the list.",
         );

add_conf('$MAX_WT_EDGES_LOAD',
        type => 'int',
        des => "The maximum number of users to load for watch/trust edges when we can afford to be sloppy about the results returned. It is possible to override this limit to get the full list, but most of the time, you won't need to. Defaults to 50,000.",
        );

add_conf('$MAX_SCROLLBACK_LASTN',
         type => 'int',
         des => "The recent items (lastn view)'s max scrollback depth.  That is, how far you can skip back with the ?skip= URL argument.  Defaults to 100.  After that, the 'previous' links go to day views, which are stable URLs.  ?skip= URLs aren't stable, and there are inefficiencies making this value too large, so you're advised to not go too far above the default of 100.",
         );

add_conf('$MAX_SCROLLBACK_FRIENDS',
         type => 'int',
         des => "The friends page' max scrollback depth.  That is, how far you can skip back with the ?skip= URL argument.  Defaults to 1000.",
         );

add_conf('$MAX_REPL_LAG',
         type => 'int',
         des => "The max number of bytes that a MySQL database slave can be behind in replication and still be considered usable.  Note that slave databases are never used for any 'important' read operations (and especially never writes, because writes only go to the master), so in general MySQL's async replication won't bite you.  This mostly controls how fresh of data a visitor would see, not a content owner.  But in reality, the default of 100k is pretty much real-time, so you can safely ignore this setting.",
         );

add_conf('$MAX_S2COMPILED_CACHE_SIZE',
         type => 'int',
         des => "Threshold (in bytes) under which compiled S2 layers are cached in memcached.  Default is 7500 bytes.  If you have a lot of free memcached memory and a loaded database server with lots of queries to the s2compiled table, turn this up.",
         );

add_conf('$MAX_USERPIC_KEYWORDS',
         type => 'int',
         des => "Max number of keywords allowed per userpic.  Default is 10.",
         );

add_conf('$MINIMAL_BML_SCHEME',
         type => "string",
         des => "The name of the BML scheme that implements the site's 'lite' interface for minimally capable devices such as cellphones/etc.  See also %MINIMAL_USERAGENT.");

add_conf('%MINIMAL_USERAGENT',
         des => "Set of user-agent prefixes (the part before the slash) that should be considered 'lite' devices and thus be given the site's minimal interface.  Keys are prefixes, value is a boolean.  See also \$MINIMAL_BML_SCHEME.",
         );

add_conf('$MSG_DB_UNAVAILABLE',
         type => "html",
         des => "Message to show users on a database unavailable error.",
         );

add_conf('$MSG_NO_COMMENT',
         type => "html",
         des => "Message to show users when they're not allowed to comment due to either their 'get_comments' or 'leave_comments' capability being disabled, probably by the admin to lower activity after a hardware rotation.",
         );

add_conf('$MSG_NO_POST',
         type => "html",
         des => "Message to show users when they're not allowed to post due to their 'can_post' capability being disabled, probably by the admin to lower activity after a hardware rotation.",
         );

add_conf('$MSG_READONLY_USER',
         type => "string",
         des => "Message to show users when their journal (or a journal they're visting) is in read-only mode due to maintenance.",
         );

add_conf('$NEWUSER_CAPS',
         type => 'int',
         des => "Bitmask of capability classes that new users begin their accounts with.  By default users aren't in any capability classes and get only the default site-wide capabilities.  See also \%CAP.",
         );

add_conf('$QBUFFERD_DELAY',
         type => 'int',
         des => "Time to sleep between runs of qbuffered tasks.  Default is 15 seconds.",
         );

add_conf('$RATE_COMMENT_AUTH',
         des => "Arrayref of rate rules to apply incoming comments from authenticated users .  Each rate rule is an arrayref of two items:  number of comments, and period of time.  If user makes more comments in period of time, comment is denied, at least without a captcha.",
         );

add_conf('$RATE_COMMENT_ANON',
         des => "Arrayref of rate rules to apply incoming comments from anonymous users .  Each rate rule is an arrayref of two items:  number of comments, and period of time.  If user makes more comments in period of time, comment is denied, at least without a captcha.",
         );

add_conf('$SENDMAIL',
         type => 'program+args',
         des => "System path to sendmail, with arguments.  Default is: '/usr/sbin/sendmail -t -oi'.  This option is ignored if you've defined the higher-precedence option: \@MAIL_TRANSPORTS.",
         );

add_conf('$SMTP_SERVER',
         type => "hostip",
         des => "Host/IP to outgoing SMTP server.  Takes precedence over \$SENDMAIL.",
         );

add_conf('$DMTP_SERVER',
         type => "hostip:port",
         des => "Host/IP with port number to outgoing DMTP server.  Takes precedence over \$SMTP_SERVER.  Note: the DMTP protocol and server is a dumb hack.  If you have a good outgoing SMTP server, use that instead.",
         );

add_conf('$SERVER_DOWN_SUBJECT',
         type => "text",
         des => "The error message subject/title to show when \$SERVER_DOWN is set.",
         );

add_conf('$SERVER_DOWN_MESSAGE',
         type => "html",
         des => "The error message to show when \$SERVER_DOWN is set.",
         );

add_conf('$SERVER_NAME',
         des => "System's hostname.  In a massive LJ webfarm, each node has its own value of this.  The default is to query the local machine's hostname at runtime, so you don't need to set this.  It's not used for anything too important anyway.");

add_conf('$SITENAME',
         required => 1,
         des => "Full name of your site.  For instance, 'LiveJournal.com'.  See also \$SITENAMESHORT and \$SITENAMEABBREV.");

add_conf('$SITENAMESHORT',
         des => "Medium-length name of your site.  For instance, 'LiveJournal'.  See also \$SITENAME and \$SITENAMEABBREV.  Defaults to \$SITENAME without any '.*' suffix");

add_conf('$SITENAMEABBREV',
         required => 1,
         des => "Shorted possible slang name of your site.  For instance, 'LJ'.");

add_conf('$SITEROOT',
         required => 1,
         type => 'url',
         no_trailing_slash => 1,
         des => "URL prefix for the base of the site, including 'http://'.  This can't be auto-detected because of reverse-proxies, etc.  See also \$SSLROOT.");

add_conf('$SSLROOT',
         required => 0,
         type => 'url',
         no_trailing_slash => 1,
         des => "URL prefix for the base of the SSL-portion of the site, including 'https://'.  This can't be auto-detected because of reverse-proxies, etc.  See also \$SITEROOT.");


add_conf('$STATPREFIX',
         required => 0,
         type => 'url',
         no_trailing_slash => 1,
         des => "URL prefix for the static files.  Defaults to \$SITEROOT/stc.",
         );

add_conf('$WSTATPREFIX',
         required => 0,
         type => 'url',
         no_trailing_slash => 1,
         des => "URL prefix for the static files.  Must be located on the same domain as \$DOMAIN_WEB.",
         );

add_conf('$SPELLER',
         type => 'program+args',
         des => "If set, spell checking is enabled.  Value is the full path plus arguments to an ispell-compatible spell checker.  aspell is recommended, using:  '/usr/bin/aspell pipe --sug-mode=fast --ignore-case'.");


add_conf('$STATS_BLOCK_SIZE',
         des => "");
add_conf('$SUICIDE_UNDER',
         des => "");
add_conf('%SUICIDE_UNDER',
         des => "");

add_conf('$SYNSUCK_MAX_THREADS',
         des => "");

add_conf('$SYND_CLUSTER',
         type => 'integer',
         des => "If defined, all syndication (RSS/Atom) 'users' are put on this cluster number.  If undefined, syndication users are assigned to user clusters (partitions) in the normal way.");

add_conf('$SUPPORT_EMAIL',
         type => 'email',
         des => "The customer support email address.");

add_conf('@SUPPORT_SLOW_ROLES',
         type => 'array',
         des => "Array of database roles to be used for slow support queries, in order of precedence.");
    
add_conf('$TALK_ABORT_REGEXP',
         type => 'regexp',
         des => "Regular expression which, when matched on incoming comment bodies, kills the comment.");

add_conf('$TOOLS_RECENT_COMMENTS_MAX',
         type => 'int',
         des => "Number of recent comments to show on /tools/recent_comments.bml");

add_conf('$USERPIC_ROOT',
         type => 'url',
         no_trailing_slash => 1,
         des => "URL prefix for userpics.  Defaults to \$SITEROOT/userpic.  See \%SUBDOMAIN_FUNCTION to use something else.");

add_conf('$USER_DOMAIN',
         type => 'domain',
         des => "Domain for user email aliases and user virtual host domains.  See \$USER_EMAIL and \$USER_VHOSTS.\n");

add_conf('%ALIAS_TO_SUPPORTCAT',
         des => "This provides a way to declare more than one email address which is routed to a support category.  The primary incoming email address for a support category is in the 'supportcat' table.  If you need more than one, this hash maps from the email address you want to accept mail, to the primary email address of that support category.  For instance:  %ALIAS_TO_SUPPORTCAT = ('dmca\@example.com' => 'webmaster\@example.com') would mean that dmca\@ would go to the same support category that webmaster\@ would otherwise go to.");

add_conf('@SCHEMES',
         des => "An array of hashrefs describing the available site BML schemes (skins).  Each hashref must contain the keys 'scheme' (the BML scheme to use), 'title', and optionally 'thumb', which should be an arrayref of [ partial URL, width, height ].  where partial URL is relative to \$IMGPREFIX.");

add_conf('$BIN_SOX',
         type => "program",
         des => "Path to sox.  Needed for audio captcas.");

add_conf('$LOCKDIR',
         type => "directory",
         des => "A directory to use for lock files if you're not using ddlockd for locking.");

add_conf('$MAX_BANS',
         type => "int",
         des => "Maximum number of people that users are allowed to ban.  Defaults to 5000.");

add_conf('$AUTOSAVE_DRAFT_INTERVAL',
         type => 'int',
         default => 10,
         des => "Number of seconds to use as interval to saving drafts back to the server.  Defaults to 10.");

add_conf('$MEMCACHE_CB_CONNECT_FAIL',
         type => "subref",
         des => "Callback when a connection to a memcached instance fails.  Subref gets the IP address that was being connected to, but without the port number.");

add_conf('%REPROXY_DISABLE',
         des => "Set of file classes that shouldn't be internally redirected to mogstored nodes.  Values are true, keys are one of 'userpics', or site-local file types like 'phoneposts' for ljcom.  Seee also \%USERPIC_REPROXY_DISABLE");

add_conf('%DEBUG',
         type => '',
         des => "");
add_conf('@MEMCACHE_SERVERS',
         type => '',
         des => "");
add_conf('$SQUAT_URL',
         type => '',
         des => "");
add_conf('$FRONTPAGE_JOURNAL',
         type => '',
         des => "");
add_conf('%PERLBAL_ROOT',
         type => '',
         des => "");
add_conf('@DINSERTD_HOSTS',
         type => '',
         des => "");
add_conf('%DB_REPORT_HANDLES',
         type => '',
         des => "");
add_conf('$FREECHILDREN_BCAST',
         type => '',
         des => "");
add_conf('$SENDSTATS_BCAST',
         type => '',
         des => "");
add_conf('$MAX_FRIENDS_VIEW_AGE',
         type => '',
         des => "");
add_conf('%COMMON_CODE',
         type => '',
         des => "");
add_conf('%FORCE_EMPTY_FRIENDS',
         type => '',
         des => "");
add_conf('@CLEANUP_HANDLERS',
         type => '',
         des => "");
add_conf('%EXTERNAL_NAMESPACE',
         type => '',
         des => "");
add_conf('%MEMCACHE_PREF_IP',
         type => '',
         des => "");
add_conf('$MEMCACHE_COMPRESS_THRESHOLD',
         type => '',
         des => "");
add_conf('$MEMCACHE_CONNECT_TIMEOUT',
         type => '',
         des => "");
add_conf('%CRUMBS',
         type => '',
         des => "");
add_conf('%READONLY_CLUSTER',
         type => '',
         des => "");
add_conf('%READONLY_CLUSTER_ADVISORY',
         type => '',
         des => "");
add_conf('%LOCKY_CACHE',
         type => '',
         des => "");
add_conf('$WHEN_NEEDED_THRES',
         type => '',
         des => "");
add_conf('%CLUSTER_PAIR_ACTIVE',
         type => '',
         des => "");
add_conf('%DEF_READER_ACTUALLY_SLAVE',
         type => '',
         des => "");
add_conf('%LOCK_OUT',
         type => '',
         des => "");
add_conf('$LANG_CACHE_BYTES',
         type => '',
         des => "");
add_conf('%DISABLE_PROTOCOL',
         type => '',
         des => "");
add_conf('@TESTACCTS',
         type => '',
         des => "");
add_conf('%POST_WITHOUT_AUTH',
         type => '',
         des => "");
add_conf('$ALLOW_PICS_OVER_QUOTA',
         type => '',
         des => "");
add_conf('$SYSBAN_IP_REFRESH',
         type => '',
         des => "");
add_conf('%IP_BANNED',
         type => '',
         des => "");
add_conf('%UNIQ_BANNED',
         type => '',
         des => "");
add_conf('%NEEDED_RES',
         type => '',
         des => "");
add_conf('$TALK_PAGE_SIZE',
         type => '',
         des => "");
add_conf('$TALK_MAX_SUBJECTS',
         type => '',
         des => "");
add_conf('$TALK_THREAD_POINT',
         type => '',
         des => "");
add_conf('$ANTI_TALKSPAM',
         type => '',
         des => "");
add_conf('%FORM_DOMAIN_BANNED',
         type => '',
         des => "");
add_conf('$LOCKER_OBJ',
         type => '',
         des => "");
add_conf('@LOCK_SERVERS',
         type => '',
         des => "");
add_conf('%MOGILEFS_PREF_IP',
         type => '',
         des => "");
add_conf('$SLOPPY_FRIENDS_THRESHOLD',
         type => '',
         des => "");
add_conf('$WORK_REPORT_HOST',
         type => '',
         des => "");
add_conf('$FILEEDIT_VIA_DB',
         type => '',
         des => "");
add_conf('$BML_INC_DIR_ADMIN',
         type => '',
         des => "");
add_conf('$BML_INC_DIR',
         type => '',
         des => "");
add_conf('%USERPROP_INIT',
         type => '',
         des => "");
add_conf('$SYND_CAPS',
         type => '',
         des => "");
add_conf('%CLUSTER_DOWN',
         type => '',
         des => "");
add_conf('@TALKSPAM',
         type => '',
         des => "");
add_conf('%HELP_URL',
         type => '',
         des => "");
add_conf('@INITIAL_FRIENDS',
         type => '',
         des => "");
add_conf('%DBCACHE',
         type => '',
         des => "");
add_conf('$LJMAINT_VERBOSE',
         type => '',
         des => "");
add_conf('$MAILSPOOL',
         type => '',
         des => "");
add_conf('$DENY_REQUEST_FROM_EMAIL',
         type => '',
         des => "");
add_conf('%DENY_REQUEST_FROM_EMAIL',
         type => '',
         des => "");
add_conf('@PRIVATE_STATS',
         type => '',
         des => "");
add_conf('$QBUFFERD_PIDFILE',
         type => '',
         des => "");
add_conf('%SUPPORT_DIAGNOSTICS',
         type => '',
         des => "");
add_conf('%CAP',
         type => '',
         des => "");
add_conf('@MAIL_TRANSPORTS',
         type => '',
         des => "");
add_conf('%MOGILEFS_CONFIG',
         type => '',
         des => "");
add_conf('%SUPPORT_ABSTRACTS',
         type => '',
         des => "");
add_conf('%MINIMAL_STYLE',
         type => '',
         des => "");
add_conf('%USERPROP_DEF',
         type => '',
         des => "");
add_conf('@RBL_LIST',
         type => '',
         des => "");
add_conf('@INITIAL_OPTOUT_FRIENDS',
         type => '',
         des => "");
add_conf('%CAP_DEF',
         type => '',
         des => "");
add_conf('%DISABLED',
         type => '',
         des => "");
add_conf('%HELPURL',
         type => '',
         des => "");
add_conf('@INITIAL_OPTIONAL_FRIENDS',
         type => '',
         des => "");
add_conf('%FILEEDIT_VIA_DB',
         type => '',
         des => "");
add_conf('%SETTER',
         type => '',
         des => "");
add_conf('%SUBDOMAIN_FUNCTION',
         type => '',
         des => "");
add_conf('%REDIRECT_ALLOWED',
         type => '',
         des => "");
add_conf('%HOOKS',
         type => '',
         des => "");
add_conf('%GZIP_OKAY',
         type => '',
         des => "");
add_conf('%CAPTCHA_FOR',
         type => 'hash',
         des => '$captcha_type => 1 if we should display a captcha on this page; $captcha_type => 0, or leave out of the hash, if we shouldn\'t display a captcha on this page.');
add_conf('%DBINFO',
         type => '',
         des => "");
add_conf('@QBUFFERD_ISOLATE',
         type => '',
         des => "");
add_conf('%BLOBINFO',
         type => '',
         des => "");

add_conf('$CSSPROXY',
         type => 'url',
         des => "If set, external CSS should be proxied through this URL (URL is given a ?u= argument with the escaped URL of CSS to clean.  If unset, remote CSS is blocked.",
         );

add_conf('$PROFILE_BML_FILE',
         type => 'file',
         des => "The file (relative to htdocs) to use for the profile URL.  Defaults to profile.bml",
         );


my %bools = (
             'USE_ACCT_CODES' => "Make joining the site require an 'invite code'.  Note that this code might've bitrotted, so perhaps it should be kept off.",
             'USER_VHOSTS' => "Let (at least some) users get *.\$USER_DOMAIN URLs.  They'll also need the 'userdomain' cap.",
             'USER_EMAIL' => "Let (at least some) users get email aliases on the site.  They'll also need the 'useremail' cap.  See also \$USER_DOMAIN",
             'USERPIC_BLOBSERVER' => "Store userpics on the 'blobserver'.  This is old.  MogileFS is the future.  You might want to use this option, though, for development, as blobserver in local-filesystem-mode is easy to setup.",
             'TRACK_URL_ACTIVE' => "record in memcached what URL a given host/pid is working on",
             'TRUST_X_HEADERS' => "LiveJournal should trust the upstream's X-Forwarded-For and similar headers.  Default is off (for direct connection to the net).  If behind your own reverse proxies, you should enable this.",
             'UNICODE' => "Unicode support is enabled.  The default has been 'on' for ages, and turning it off is nowadays not recommended or even known to be working/reliable.  Keep it enabled.",
             'SUICIDE' => "Large processes should voluntarily kill themselves at the end of requests.",
             'STATS_FORCE_SLOW' => "Make all stats hit the 'slow' database role, never using 'slave' or 'master'",
             'SERVER_DOWN' => "The site is globally marked as 'down' and users get an error message, as defined by \$SERVER_DOWN_MESSAGE and \$SERVER_DOWN_SUBJECT.  It's not clear why this should ever be used instead of \$SERVER_TOTALLY_DOWN",
             'SERVER_TOTALLY_DOWN' => "The site is globally marked as 'down' and users get an error message, as defined by \$SERVER_DOWN_MESSAGE and \$SERVER_DOWN_SUBJECT.  But compared to \$SERVER_DOWN, this error message is done incredibly early before any dispatch to different modules.",
             "REQUIRE_TALKHASH" => "Require submitted comments to include a signed hidden value provided by the server.  Slows down comment-spammers, at least, in that they have to fetch pages first, instead of just blasting away POSTs.  Defaults to off.",
             "REQUIRE_TALKHASH_NOTOLD" => "If \$REQUIRE_TALKHASH is on, also make sure that the talkhash provided was issued in the past two hours.  Defaults to off.",
             "DONT_LOG_IMAGES" => "Don't log requests for images.",
             "DO_GZIP" => "Compress text content sent to browsers.  Cuts bandwidth by over 50%.",
             "EVERYONE_VALID" => "Users don't need to validate their email addresses.",
             "IS_DEV_SERVER" => "This is a development installation only, and not used for production.  A lot of debug info and intentional security holes for convenience are introduced when this is enabled.",
             "LOG_GTOP" => "Log per-request CPU and memory usage, using gtop libraries.",
             "NO_PASSWORD_CHECK" => "Don't do strong password checks.  Users can use any old dumb password they'd like.",
             "OPENID_CONSUMER" => "Accept OpenID identies for logging in and commenting.",
             "OPENID_SERVER" => "Be an OpenID server.",
             "OTHER_VHOSTS" => "Let users CNAME their vanity domains to this LiveJournal installation to transparently load their journal.",
             "USE_SSL" => "Links to SSL portions of the site should be visible.",
             "USE_PGP" => "Let users set their PGP/GPG public key, and accept PGP/GPG-signed emails (for authentication)",
             "OPENID_COMPAT" => "Support pre-1.0 OpenID specs as well as final spec.",
             "OPENID_STATELESS" => "Speak stateless OpenID.  Slower, but no local state needs to be kept.",
             "ONLY_USER_VHOSTS" => "Don't allow www.* journals at /users/ and /~ and /community/.  Only allow them on their own user virtual host domains.",
             "USERPIC_MOGILEFS" => "Store userpics on MogileFS.",
             "CONCAT_RES" => "Instruct Perlbal to concatenate static files on non-SSL pages",
             "CONCAT_RES_SSL" => "Instruct Perlbal to concatenate static files on SSL pages",
             );

foreach my $k (keys %bools) {
    my $val = $bools{$k};
    $val = { des => $val } unless ref $val;
    $val->{type} = "bool",
    $val->{des} = "If set to true, " . lcfirst($val->{des});
    add_conf("\$$k", %$val);
}

1;
