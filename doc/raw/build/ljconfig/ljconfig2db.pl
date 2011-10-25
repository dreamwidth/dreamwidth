#!/usr/bin/perl
#

use strict;

$LJ::HOME = $ENV{'LJHOME'};

unless (-d $LJ::HOME) {
    die "\$LJHOME not set.\n";
}

my $LJHOME = $LJ::HOME;
require "$LJHOME/doc/raw/build/docbooklib.pl";

my %ljconfig =
(
    'user' => {
        'name' => 'User-Configurable',
        'desc' => "New installations will probably want to set these variables. Some are ".
                  "automatically set by LJ/Global/Defaults.pm based on your other settings, but it ".
                  "wouldn't hurt to specify them all explicitly.",

        'abuse' => {
            'name' => "Abuse Prevention",
            'blocked_bot_message' => {
                    'desc' => "Message (&html;) shown to people suspected to be bots, informing them they've been banned, and where/what the rules are.",
                    'default' => "You don't have permission to view this page.",
            },
            'blocked_bot_info' => {
                    'desc' => "Include unique cookie information and <acronym>IP</acronym> address with the [ljconfig[blocked_bot_message]] notice.",
            },
            'blocked_bot_subject' => {
                    'desc' => "Subject/title (text-only) shown to people suspected to be bots.",
                    'default' => "403 Denied",
            },
            'blocked_bot_uri' => {
                    'desc' => "Path (e.g. /bots) at which an informational page about your acceptable bot policies is documented.  This &uri; is excluded from anti-bot measures, so make sure it&apos;s as permissive as possible to allow humans in who may be lazy in their typing.  For example, leave off the trailing slash (/bots instead of /bots/) if your &uri; is a directory.",
            },
            'blocked_password_email' => {
                    'desc' => "If enabled, when a user attempts to change &email; addresses the new address is checked for validity; changing to [ljconfig[user_email]] addresses is also disallowed.",
            },
            'deny_request_from_email' => {
                    'desc' => "Setup support &email; address to not accept new &email;s.  Basically if an address is specified below, any user who &email;s it out of the blue will be sent back a copy of the specified file along with their &email;.  Users will still be allowed to respond to &email;s from the support system, but they are not able to open a request by &email;ing the address. The value part of the hash is the name of an include file.  It will be loaded out of <filename class='directory'><parameter>\$<envar>LJHOME</envar></parameter>/htdocs/inc</filename>.  See [ljconfig[fileedit_via_db]] for how to make it read from &memcached;/&db;.",
                    'example' => "(
    'abuse\@\$DOMAIN' => 'bounce-abuse',
    );",
                    'type' => "hash",
            },
            'email_change_requires_password' => {
                    'desc' => "If enabled, users will not be able to edit their &email; address at <uri>manage/profile</uri>. Instead, a link
                    to <filename>changeemail.bml</filename> will be displayed, and (non-&openid;) users will be prompted for their password at that page.",
            },
            'log_changeemail_ip' => {
                    'desc' => "If enabled, when a user attempts to change their &email; address at <filename>changeemail.bml</filename>,
                    their <acronym>IP</acronym> address is included with the record noting the change in the [dbtable[statushistory]] table.",
            },
            'rate_comment_anon' => {
                    'desc' => "Arrayref of rate rules to apply incoming comments from anonymous <quote>users</quote>.  It is switched off by default.  Each rate rule is an arrayref of two items:  number of comments, and period of time.  If user tries to make more comments in the specified time period, the comment is denied, at least without a &captcha;. In the example, anonymous comments will <emphasis>always</emphasis> require a &captcha;. For efficient anti-spammer rate-limiting we recommend you also run &memcached;, and set the appropriate <filename>ljconfig.pl</filename> variables ([ljconfig[memcache_compress_threshold]] and [ljconfig[memcache_servers]]).",
                    'default' => "[ [ 300, 3600 ], [ 200, 1800 ], [ 150, 900 ], [ 15, 60 ] ];",
                    'example' => "[[0, 65535]];",
            },
            'rate_comment_auth' => {
                    'desc' => "Arrayref of rate rules to apply incoming comments from authenticated users .  It is switched off by default. Each rate rule is an arrayref of two items:  number of comments, and period of time.  If user makes more comments in period of time, comment is denied, at least without a &captcha;.",
                    'default' => "[ [ 200, 3600 ], [ 20, 60 ] ];",
            },
            'rbl_list' => {
                    'desc' => "Real-time Block List support for comments. In the array specify providers you wish to use, like <systemitem class='domainname'>dsbl.org</systemitem>&apos;s or <systemitem class='domainname'>openproxies.com</systemitem>&apos;s data, to help combat comment spam.",
                    'type' => "array",
            },
            'require_talkhash' => {
                    'desc' => "Require submitted comments to include a signed hidden value provided by the server.  Slows down comment-spammers, at least, in that they have to fetch pages first, instead of just blasting away POSTs.  Defaults to off.",
            },
            'require_talkhash_notold' => {
                    'desc' => "If [ljconfig[require_talkhash]] is on, also make sure that the talkhash provided was issued in the past two hours.  Defaults to off.",
            },
            'talk_abort_regexp' => {
                    'desc' => "Regular expression which, when matched on incoming comment bodies, kills the comment.",
                    # How is this different from @talkspam?
            },
            'talkspam' => {
                    'desc' => "Filter comments for spam using this list of regular expressions.",
                    'type' => "array",
                    'example' => "(
        'morphese',
        );",
            },
        },

        'caps' => {
            'name' => "Capabilities/User Options",
            'allow_pics_over_quota' => {
                    'desc' => "By default, when a user has more userpics than their account type allows, perhaps due to expiration of paid time, their least often used userpics (based on their journal posts) will be marked inactive. This happens whenever their account type is changed or they visit <filename>editicons.bml</filename>. They will no longer be available for use, and only the account owner may see them on <filename>editicons.bml</filename>. Turning this boolean setting true will circumvent this behavior. In other words, enabling this option lets users just keep whatever userpics they had when their account type changed.",
            },
            'cap' => {
                    'desc' => "A hash that defines the capability class limits. The keys are bit numbers, from 0 &ndash; 15, and the values ".
                    "are hashrefs with limit names and values. Consult [special[caps]] for more information.",
                    'type' => "hash",
            },
            'cap_def' => {
                    'desc' => "The default capability limits, used only when no other class-specific limit below matches.",
                    'type' => "hash",
            },
            'email_post_domain' => {
                    'desc' => "If set, and your <acronym>MTA</acronym> is configured, users can post to their account via username\@\$EMAIL_POST_DOMAIN.",
                    'example' => 'post.$DOMAIN',
            },
            'everyone_valid' => {
                    'desc' => "If set to true, users don&apos;t need to validate their &email; addresses.",
            },
            'newuser_caps' => {
                    'desc' => "The default capability class mask for new users. Bitmask of capability classes that new users begin their accounts with.  By default users are not in any capability classes and get only the default site-wide capabilities.  See also [ljconfig[cap]].",
            },
            'user_email' => {
                    'desc' => "Do certain users get a forwarding &email; address, such as user\@\$DOMAIN?. This requires additional mail system configuration. Users will also need the <quote>useremail</quote> cap.",
            },
            'use_pgp' => {
                    'desc' => "Let users set their <acronym>PGP</acronym>/<acronym>GPG</acronym> public key, and accept <acronym>PGP</acronym>/<acronym>GPG</acronym>-signed &email; for &email; posting. Requires <package>GnuPG::Interface</package> and <package>Mail::GnuPG</package> modules to be installed. Note: users need to use <acronym>GPG</acronym> version 1.2.4, or higher.",
            },
            'userprop_def' => {
                    'desc' => "This option defines the user-properties that users should have by default.",
                    'type' => "hash",
                    'example' => '%USERPROP_DEF = (
    "s1_lastn_style" => 29,
    "s1_friends_style" => 20,
    "s1_calendar_style" => 2,
    "s1_day_style" => 11,
    );',
            },
        },

        'contact_email_addresses' => {
            'name' => "Contact &email; addresses",
            'alias_to_supportcat' => {
                    'desc' => "This provides a way to declare more than one &email; address which is routed to a support category.  The primary incoming &email; address for a support category is in the [dbtable[supportcat]] table.  If you need more than one, this hash maps from the &email; address you want to accept mail, to the primary &email; address of that support category.  For instance:  \%ALIAS_TO_SUPPORTCAT = ('dmca\@example.com' => 'webmaster\@example.com') would mean that dmca\@ would go to the same support category that webmaster\@ would otherwise go to.",
                    'type' => "hash",
            },
            'support_email' => {
                    'desc' => "Used as a contact method for people to report problems with the &lj; installation.",
                    'default' => "support\@\$DOMAIN",
            },
        },

        'database_related' => {
            'name' => "Database Related",
            'clusters' => {
                    'desc' => "This is an array listing the names of the clusters that your configuration uses. Each one needs a &apos;cluster\$i&apos; role in [ljconfig[dbinfo]]. Consult <xref linkend='lj\.install\.supplemental_sw\.multiple_db' /> for more details.",
                    'default' => '( 1 )',
                    'example' => '( 1, 2, 3 )',
                    'type' => "array",
            },
        'cluster_pair_active' => {
                'desc' => "A hash that defines master-master &db; cluster pairs.",
                'type' => "hash",
            },
            'db_log_host' => {
                    'desc' => "An optional host:port to send <acronym>UDP</acronym> packets to with blocking reports.  The reports log the total amount of time used in a slow operation to a remote host via <acronym>UDP</acronym>.",
                    'example' => "foo.example.com:8030",
            },
            'dbinfo' => {
                    'desc' => "This is a hash that contains the necessary information to connect to your database, as well as ".
                    "the configuration for multiple database clusters, if your installation supports them. ".
                    "Consult [special[dbinfo]] for more details.",
                    'type' => "hash",
            },
            'default_cluster' => {
                    'desc' => "The default cluster to choose when creating new accounts. If you have an arrayref of multiple cluster names, for scalability, one of the listed clusters is chosen at random. You can weight new users by repeating cluster numbers, e.g. [ 1, 1, 1, 2 ] puts 75&percnt; of people on cluster 1, 25&percnt; of people on cluster 2.  Clusters are checked for validity before being used.",
                    'default' => "[ 1 ]",
            },
            'directory_separate' => {
                    'desc' => "If true, only use the 'directory' &db; role for the directory, and don&apos;t also try the 'slave' and 'master' roles. Consult [special[dbinfo]] for details on setting roles.",
            },
            'disable_master' => {
                    'desc' => "If set to true, access to the 'master' &db; role is prevented, by breaking the <xref linkend='ljp\.api\.lj\.get_dbh' /> function.  Useful during master database migrations.",
            },
            'disconnect_dbs' => {
                    'desc' => "If set to true, all database connection handles (except those for logging) are disconnected at the end of each request.  Recommended for high-performance sites with lots of database clusters.",
            },
            'disconnect_memcache' => {
                    'desc' => "If set to true, &memcached; connection handles are disconnected at the end of each request.  Not recommended if your &memcached; instances are &linux; 2.6.",
            },
            'fileedit_via_db' => {
                    'desc' => "Boolean value that controls /admin/fileedit setup. If you are using and frequently editing the files
                    in <filename class='directory'>htdocs/inc</filename>, you may wish to put all of these files into the database. It uses the &bml; hook
                    called <quote>include_getter</quote>. If it <emphasis role='strong'>is</emphasis> defined, then it is called and checked every
                    time &bml; includes something. It behaves like other &bml; hooks. The hook uses the <literal>LJ::load_include</literal> &api;. Using
                    these <filename>ljconfig.pl</filename> options, you can configure it to make none/some/all <literal>include</literal> files be loaded
                    from &memcached; / &db;. You can instruct &bml; to treat <emphasis>all</emphasis> &lt;?_include?&gt; statements as being pulled
                    from &memcached; (failover to the database) by uncommenting this.
                    Alternatively, you can specify that only particular files should be kept in &memcached; and the database, using a hash: (\%LJ::FILEEDIT_VIA_DB).
                    An example value for the hash, is: ( 'support_links' => 1, );",
                    # Because DocBook XML-XSL relies on unique names to create links, separate entries
                    # in this file for 'fileedit_via_db' as a hash, and as a boolean, would make it choke while building the docs. So, hash example is here.
            },
            'gearman_servers' => {
                    'desc' => "&gearman; information, if you have <systemitem class='daemon'>gearmand</systemitem> servers running, so you can run workers. Uses form: hostname:port.",
                    'type' => "array",
                    'example' => "('foo.example.com:7003')",
            },
            'memcache_compress_threshold' => {
                    'desc' => "This is used to set the minimum size of an object before trying to compress it. A value of &apos;0&apos; turns off compress; a value of <replaceable>x</replaceable> sets that size as required. You specify the array value in bytes.",
                    'type' => "array",
                    'example' => "1_000;",
            },
            'memcache_pref_ip' => {
                    'desc' => "If you have multiple internal networks and would like the &memcached; libraries to pick one network over the other, you can set the preferred <acronym>IP</acronym> list. In the example below, the variable is set to say <quote>if we try to connect to 10.0.0.1, instead try 10.10.0.1 first and then fall back to 10.0.0.1</quote>.",
                    'type' => "hash",
                    'example' => "(
    10.0.0.1 => 10.10.0.1,
    );",
            },
            'memcache_servers' => {
                    'desc' => "Memcache information, if you have &memcached; servers running. Uses form: hostname:port.",
                    'type' => "array",
                    'example' => "('foo.example.com:11211')",
            },
            'stats_force_slow' => {
                    'desc' => "Make the stats system use the <quote>slow</quote> database role, never using <quote>slave</quote> or <quote>master</quote>, and dying loudly if it is unable to do so.",
            },
            'support_slow_roles' => {
                    'desc' => "Array of database roles to be used for slow support queries, in order of precedence.",
                    'type' => "array",
                    'default' => "('slow')",
            },
            'theschwartz_dbs' => {
                    'desc' => "&thesch; information, so it can connect to your database, if you have &thesch; server and workers running.",
                    'type' => "array",
                    'example' => "my \$mast = \$LJ::DBINFO{master};
    my \$dbname = \$mast->{dbname} || 'livejournal';
    \@LJ::THESCHWARTZ_DBS =({
    dsn  => 'dbi:mysql:\$dbname;host=\$mast->{host}',
    user => \$mast->{user},
    pass => \$mast->{pass},
    prefix => 'sch_',
    });"
            },
            'use_innodb' => {
                    'desc' => "Create new tables as InnoDB by default.",
            },
        },

        'debug' => {
            'name' => "Development/Debugging Options",
            'allow_cluster_select' => {
                    'desc' => "When set true, the journal creation page will display a drop-down list of clusters (from [ljconfig[clusters]]) along ".
                    "with the old 'cluster 0' which used the old &db; schema and the user creating an account can choose where they go. ".
                    "In reality, there's no use for this, it is only useful when working on the code. <emphasis>Deprecated</emphasis>. Instead, use: \$LJ::DEBUG{allow_cluster_select} = 1;.",
            },
            'anti_squatter' => {
                    'desc' => "Set true if your installation is a publicly available development server and if you would like ".
                    "beta testers to ensure that they understand as such. If left alone your installation might become susceptible to ".
                    "hordes of squatter accounts. <emphasis>Deprecated</emphasis>. Instead, use: \$LJ::DEBUG{anti_squatter} = 1;",
            },
            'is_dev_server' => {
                    'desc' => "Enable this option to signify that the server running the &lj; software is being used as a development server and not used for production.  A lot of debug info and intentional security holes for convenience are introduced when this is enabled. When enabled, the  tool will check your <filename>ljconfig.pl</filename> variables (using the <literal>LJ::ConfCheck::*</literal> module). Additionally, changed library files are automatically reloaded without stopping/starting &apache;.",
            },
            'dev_has_real_ssl' => {
                    'desc' => "Enable this if you are running a development installation and have set up &ssl;.",
            },
            'langs_in_progress' => {
                    'desc' => "Array of additional (<acronym>ISO</acronym> 639/639_3166) language codes to allow users to select e.g. using an argument on a &url;, if they know about them. These ones are actively being translated, but are not yet ready to be publicly available.",
                    'type' => "array",
            },
            'post_without_auth' => {
                    'desc' => "Support explicit <acronym>IP</acronym> + community + user posting without passwords, for
                    internal purposes. You might want to use this if you want to make commits to your local &svn; repository but without parsing your local &svn; configuration,
                    for example. An alternative to this hash is the generic <literal>post_noauth</literal> hook, which allows dynamically generating posters based on how you program the hook to be used.",
                    'type' => "hash",
                    'example' => "(
    '127.0.0.1' => {
    'changelog' => [qw(stan eric wendy kyle etc)],
    'another_community' => [qw(bob mary jane sue)],
    },
    );"
            },
            'testaccts' => {
                    'desc' => "A list of usernames used for testing purposes. The password to these accounts cannot be changed through the user interface.",
                    'type' => "array",
                    'example' => "qw(test test2);",
            },
        },

        'domain' => {
            'name' => 'Domain Related',
            'adserver' => {
                    'desc' => "Subdomain &url; to use for ad-serving.",
            },
            'cookie_domain' => {
                    'desc' => "The <quote>domain</quote> value set on cookies sent to users. Note the leading period, which is a wildcard for everything at or under \$DOMAIN.
                    Cookie domains should simply be set to .\$domain.tld, based on the Netscape Cookie <abbrev>Spec.</abbrev>, ".
                    "but some older browsers do not adhere to the specs very well. [ljconfig[cookie_domain]] can ".
                    "be a single string value, or it can be a perl array ref.",
                    'example' => '["", ".$DOMAIN"]',
                    'default' => ".\$DOMAIN;",
            },
            'domain' => {
                    'desc' => "The minimal domain name of the site, excluding the 'www.' prefix if applicable.",
                    'default' => 'example.com',
            },
            'domain_web' => {
                    'desc' => "The preferred domain name for your installation&apos;s web root.  For instance, if your \$DOMAIN is 'foo.com', your \$DOMAIN_WEB might be 'www.foo.com', so any user who goes to foo.com will be redirected to www.foo.com. If defined and different from [ljconfig[domain]], any GET requests to [ljconfig[domain]] will be redirected to [ljconfig[domain_web]].",
                    'default' =>  "www.\$DOMAIN;",
            },
            'embed_module_domain' => {
                    'desc' => "Prefix for embedded media content. Media is embedded into an entry or comment using an iframe. We recommend using a separate domain, for security.",
                    'example' => "embed.\$DOMAIN",
            },
            'frontpage_journal' => {
                    'desc' => "If set, the main page of the site loads the specified journal, not the default index page. ".
                    "Use this if you're running a news site where there's only one journal, or one journal is dominant.",
            },
            'imgprefix' => {
                    'desc' => "The &url; prefix of the (static) image directory or subdomain. Does not take a trailing slash. By default it is \$SITEROOT/img, but your load balancing may dictate another hostname or port for efficiency. See also [ljconfig[jsprefix]].",
                    'default' => '$SITEROOT/img',
            },
            'jsprefix' => {
                    'desc' => "Prefix on (static) &js; directory or subdomain, for &url;s. Does not take a trailing slash. By default it is \$SITEROOT/js, but your load balancing may dictate another hostname or port for efficiency. See also [ljconfig[imgprefix]].",
                    'default' => '$SITEROOT/js',
            },
            'only_user_vhosts' => {
                    'desc' => "If you <emphasis role='strong'>only</emphasis> want [ljconfig[user_vhosts]] to work, and want to disable the typical /users/USERNAME, /~USERNAME, and /community/USERNAME &url;s, set this boolean option.",
            },
            'other_vhosts' => {
                    'desc' => "Let users <systemitem class='protocol'>CNAME</systemitem> their vanity domains to this &lj; installation, to transparently load their
                    journal. Users will also need the <quote>domainmap</quote> cap.",
            },
            'palimgroot' => {
                    'desc' => "The &url; prefix to the palimgs directory or subdomain. Does not take a trailing slash. Prefix on <acronym>GIF</acronym>/<acronym>PNG</acronym>s with dynamically generated palettes.  By default, it's '\$SITEROOT/palimg\', and there is little reason to change it. Useful if you want to move images, used for styling, to another host. You can use it in a similar way to \$LJ::SITEROOT (e.g. \$LJ::PALIMGROOT/myimage.png). Somewhat related: note that &perlbal; has a plugin to handle these before it gets to &modperl;, if you would like to relieve some load on your backend &modperl;s.  But you do not necessarily need this option for using &perlbal; to do it.  It depends on your configuration.",
                    'default' => '$SITEROOT/palimg',
            },
                 'server_name' => {
                    'desc' => "System&apos;s hostname. If using db-based web logging, this field is stored in the database in the server
                    column, so you can see later how well each server performed. In a massive &lj; webfarm, each node would have its own value of this.
                    The default is to query the local machine&apos;s hostname at runtime, so you don&apos;t need to set this.  It is not used for anything too important anyway ".
                    "To share the same ljconfig.pl on each host (say, over <acronym>NFS</acronym>), you can put something like the example in
                    your <filename>ljconfig.pl</filename>: It is kind&apos;ve ugly, but it works. ",
                    'example' => 'chomp($SERVER_NAME = `hostname`);',
                    'default' => "Sys::Hostname::hostname();",
            },
            'sitename' => {
                    'desc' => "The name of the site. This is set to the default, unless you override it in <filename>ljconfig.pl</filename>, or you define [ljconfig[sitenameshort]] which is stripped of its trailing .tld suffix (.net, .com, etc.) and used for \$SITENAME.",
                    'default' => "YourSite.com;",
            },
            'sitenameabbrev' => {
                    'desc' => "The abbreviated (shortened) possible slang name of your site.",
                    'default' => "YS",
            },
            'sitenameshort' => {
                    'desc' => "The shortened name of the site, for brevity purposes.",
                    'default' => "YourSite",
            },
            'siteroot' => {
                    'desc' => "The &url; prefix, including 'http://', to construct canonical pages. Does not take a trailing slash. This can include the port number, if 80 is not in use. This is what gets prepended to all &url;s. This can&apos;t be auto-detected because of reverse-proxies, etc. See also [ljconfig[sslroot]].",
                    'default' => "http://\$DOMAIN_WEB",
                    'example' => "http://www.\$DOMAIN:8011",
            },
            'sslimgprefix' => {
                    'desc' => "Parallels [ljconfig[imgprefix]]. The &url; prefix of the (static) image directory or subdomain, for the &ssl;-portion of the site. Does not take a trailing slash.",
                    'default' => '$SSLROOT/img',
            },
            'ssljsprefix' => {
                    'desc' => "Parallels [ljconfig[jsprefix]]. Prefix on (static) &js; directory or subdomain, for the &ssl;-portion of the site. Does not take a trailing slash.",
                    'default' => '$SSLROOT/js',
            },
            'sslroot' => {
                    'desc' => "The &url; prefix, including 'https://', for the base of the &ssl;-portion of the site. Does not take a trailing slash. This can&apos;t be auto-detected because of reverse-proxies, etc. See also [ljconfig[siteroot]].",
                    'default' => "https://www.\$DOMAIN:8011/",
            },
            'sslstatprefix' => {
                    'desc' => "Parallels [ljconfig[statprefix]]. The &url; prefix to the static content directory or subdomain, for the &ssl;-portion of the site. Does not take a trailing slash.",
                    'default' => '$SSLROOT/stc',
            },
            'sslwstatprefix' => {
                    'desc' => "Parallels [ljconfig[jsprefix]]. Prefix on (static) &js; directory or subdomain, for the &ssl;-portion of the site. Does not take a trailing slash.",
                    'default' => '$SSLROOT/stc',
            },
            'statprefix' => {
                    'desc' => "The &url; prefix to the static content directory or subdomain. Does not take a trailing slash.",
                    'default' => '$SITEROOT/stc',
            },
           'subdomain_function' => {
                    'desc' => "This lets site administrators mark a subdomain as the normal path (foo.\$DOMAIN), ignoring the user component of the subdomain. It is
                    useful if you want to serve palimg files elsewhere (like an image caching service, as part of a content delivery network). Some load balancer configuration
                    is also required (see [ljconfig[palimgroot]]). The value part of the hash is the subdomain type, such as &apos;userpics&apos;,
                    or &apos;files&apos; (for serving hook-supplied files).",
            },
            'user_domain' => {
                    'desc' => "If [ljconfig[user_vhosts]] is enabled, this is the part of the &url; that follows &apos;username&apos;.",
                    'example' => '$DOMAIN',
            },
            'user_vhosts' => {
                    'desc' => "If enabled, the &lj; installation will support username &url;s of the form <uri>http://username.yoursite.com/</uri>. Users will also need the <quote>userdomain</quote> cap.",
            },
            'userpic_root' => {
                    'desc' => "The &url; prefix to the userpic directory or subdomain. Defaults to \$SITEROOT/userpic. Does not take a trailing slash.
                    See [ljconfig[subdomain_function]] to use something else.",
                    'default' => '$LJ::SITEROOT/userpic',
            },
            'wstatprefix' => {
                    'desc' => "Your static prefix on the same domain as \$LJ::DOMAIN_WEB. Does not take a trailing slash. This is needed for &js; security, since a script on
                    <uri>stat.example.com</uri> can&apos;t access content on <uri>www.example.com</uri>.",
                    'default' => '$SITEROOT/stc',
            },
        },

        'external_pluggable_auth' => {
            'name' => "External and Pluggable Authorization Support",
            'openid_compat' => {
                    'desc' => "Support pre-1.0 &openid; specs as well as final spec.",
            },
            'openid_consumer' => {
                    'desc' => "Enable &openid; consumer support, to accept &openid; identities for logging in and commenting. Off by default.",
            },
            'openid_server' => {
                    'desc' => "Enable &openid; server support.",
            },
            'openid_stateless' => {
                    'desc' => "Speak stateless &openid;. Slower, but no local state needs to be kept.",
            },
        },

        'filesystem_related' => {
            'name' => "Filesystem Related",
            'disable_media_uploads' => {
                'desc' => "Boolean to disable all media uploads/modifications that would go to &mogfs;. This puts code that interacts with &mogfs; into read-only mode: editicons.bml - users can&apos;t delete/upload userpics while in this mode, and &captcha;s - can&apos;t generate new ones or delete old ones while flag on. You might set this if you needed to turn off your &mogfs; install, for example.",
            },
            'mogilefs_config' => {
                    'desc' => "If you are using &mogfs; on your site for userpics (the userpic factory requires &mogfs; in order to work) or other purposes, you will need to define this hash and complete the information in it. Please see also [ljconfig[userpic_mogilefs]]. The <literal>your_class</literal> element allows you to define any special &mogfs; classes you need. If you want &captcha;s to come from a &mogfs; backend, enable [ljconfig[captcha_mogilefs]]; you also need a class called &apos;captcha&apos; in your domain, as in the example.",
                    'type' => "hash",
                    'example' => "(
    domain => 'example.com::lj',  # arbitrary namespace, not DNS domain
    hosts => [ '10.0.0.1:6001' ],
    root => '/var/mogdata',
    # timeout => 3,               # optional timeout on MogileFS clients.
    classes => {
    userpics => 3,
    captcha => 2,
    # your_class => 3,
    },
);",
            },
            'mogilefs_pref_ip' => {
                    'desc' => "If you have multiple internal networks and would like the &mogfs; libraries to pick one network over the other, you can set the preferred <acronym>IP</acronym> list. In the example below, the variable is set to say <quote>if we try to connect to 10.0.0.1, instead try 10.10.0.1 first and then fall back to 10.0.0.1</quote>.",
                    'type' => "hash",
                    'example' => "(
    10.0.0.1 => 10.10.0.1,
    );",
            },
            'userpic_blobserver' => {
                    'desc' => "If set to true, userpics are store as a file on the server rather than in the database. This depends on a <quote>Blob Server</quote> being set up in the [ljconfig[blobinfo]] section. <emphasis role='strong'>This is old. &mogfs; is the future</emphasis>. You might want to use this option, though, for development, as blobserver in local-filesystem-mode is easy to set up. See also [ljconfig[perlbal_root]].",
            },
            'userpic_mogilefs' => {
                    'desc' => "Uncomment this to put new userpics in &mogfs;.",
            },
        },

        'human_checks' => {
            'name' => "Human Checks",
            'captcha_audio_make' => {
                    'desc' => "The max number of audio &captcha;s to make per-process.  Should be less than [ljconfig[captcha_audio_pregen]].  Useful for farming out generation of \$LJ::CAPTCHA_AUDIO_PREGEN to lots of machines. (This value is not ideal, since after each generation, processes should just double-check the number available so this configuration variable can be removed, from the codebase).",
                    'default' => "100;",
            },
            'captcha_audio_pregen' => {
                    'desc' => "The max number of audio &captcha;s to pre-generate ahead of time.",
                    'default' => "100;",
            },
            'captcha_image_pregen' => {
                    'desc' => "The max number of image &captcha;s to pre-generate ahead of time.",
                    'default' => "500;",
            },
            'captcha_image_raw' => {
                    'desc' => "What image files to use to generate image &captcha;s.",
                    'default' => "\$LJ::HOME/htdocs/img/captcha",
            },
            'captcha_mogilefs' => {
                    'desc' => "In addition to filling out the [ljconfig[mogilefs_config]] hash, you need to enable some options if you want to use &mogfs;. Turn this on to put &captcha;s in &mogfs;.",
            },
            'human_check' => {
                    'desc' => "This option enables human checks at various places throughout the site. Enabling this requires a <quote>Blob Server</quote> setup (for details of setting one up, refer to the [ljconfig[blobinfo]] section of the document.).",
                    'type' => "hash",
                    'example' => "(
        create => 1,
        anonpost => 1,
);",
            },
            'anti_talkspam' => {
                    'desc' => "You should also turn this on to enable anonymous comment &captcha;s.",
            },
        },

        'maintenance' => {
            'name' => "Maintenance Messages",
            'msg_db_unavailable' => {
                    'desc' => "Customizable &db; unavailable message.",
                    'example' => "Sorry, database temporarily unavailable.
Please see &lt;a href='http://status.example.com/'&gt;&hellip;&lt;/a&gt; for status updates.",
            },
            'msg_error' => {
                    'desc' => "Customizable generic unavailable message.",
                    'default' => "Sorry, there was a problem.",
            },
            'nodb_msg' => {
                    'desc' => "Message to send to users when the database is unavailable",
                    'default' => "Database temporarily unavailable. Try again shortly.",
            },
            'server_down' => {
                    'desc' => "Set true when performing maintenance that requires user activity to be minimum, such as database defragmentation and cluster movements. The site is globally marked as 'down' and users get an error message, as defined by \$SERVER_DOWN_MESSAGE and \$SERVER_DOWN_SUBJECT.  See also [ljconfig[server_totally_down]].",
                    'default' => "0",
            },
            'server_down_message' => {
                    'desc' => "While [ljconfig[server_down]] is set true, this message will be displayed for anyone trying to access the &lj; installation.",
                    'example' => '$SITENAME is down right now while we upgrade. It should be up in a few minutes.',
            },
            'server_down_subject' => {
                    'desc' => "While [ljconfig[server_down]] is set true, this subject/title is displayed on the error message for anyone trying to access the &lj; installation.",
                    'example' => "Maintenance",
            },
            'server_totally_down' => {
                    'desc' => "The site is globally marked as 'down' and users get an error message, as defined by \$SERVER_DOWN_MESSAGE and \$SERVER_DOWN_SUBJECT.  But compared to \$SERVER_DOWN, this error message is done incredibly early before any dispatch to different modules. See also [ljconfig[server_down]].",
            },
        },

        'misc' => {
            'name' => "Miscellaneous settings",
            'bml_deny_config' => {
                    'desc' => "Comma-separated list of directories under <filename class='directory'>htdocs</filename> which should be served without parsing their _config.bml files.  For example, directories that might be under a lesser-trusted person's control.",
            },
            'dont_log_images' => {
                    'desc' => "If &apache; access logging to a database is enabled, in the [ljconfig[dbinfo]] hash, this boolean lets you choose whether to log images or just page requests.",
            },
            'example_user_account' => {
                    'desc' => "The username of the example user account, for use in Support and user-documentation.  Must be an actual account on the site.",
            },

            'helpurls' => {
                'desc' => "A hash of &url;s. If defined, little help bubbles appear next to common widgets to the &url; you define. ".
                          "Consult [special[helpurls]] for more information.",
                    'type' => "hash",
                    'example' => '%HELPURLS = (
            "accounttype" => "http://www.example.com/doc/faq/",
            "security" => "\$SITEROOT/support/faqbrowse.bml?faqid=1",
            "linklist_support" => "\$SITEROOT/customize/options.bml?group=linkslist",
            );',
            },
            'initial_friends' => {
                    'desc' => "This is a list of usernames that will be added automatically to the Friends list of all newly created accounts on this installation.",
                    'type' => "array",
                    'example' => "qw(news)",
            },
            'initial_optional_friends' => {
                    'desc' => "Initial <emphasis>optional</emphasis> friends, listed on create.bml.",
                    'type' => "array",
                    'example' => "qw(news);",
            },
            'initial_optout_friends' => {
                    'desc' => "Makes initial friends (checkboxes) on create.bml be selected by default.",
                    'type' => "array",
                    'example' => "qw(news);",
            },
            'langs' => {
                    'desc' => "Array of <acronym>ISO</acronym> (639/639_3166) language codes to make available for users to select from.  You can edit the array in <filename>ljconfig.pl</filename>, as in the example, for any extra languages you plan to configure, translate and make available on your site. Also, if the user has not selected a language, it is auto-detected from their browser. See also [ljconfig[default_lang]].",
                    'type' => "array",
                    'default' => "en",
                    'example' => "qw(en_YS en_GB de da es it ru ja pt eo nl hu fi sv pl zh lv tr ms);",
            },
            'max_bans' => {
                    'desc' => "If you want to change the limit on how many bans a user can make, use this variable. The default is 5000, but it is site-configurable.",
            },
            'mogile_path_cache_timeout' => {
                    'desc' => "If using &mogfs; for userpics, and are not using \$LJ::REPROXY_DISABLE{userpics}, the server headers will advise they be cached for this value. Value is in seconds. Defaults to 3600 (one hour).",
                    'default' => "3600",
            },
         'perlbal_root' => {
                'desc' => "If you are reproxying userpics (on by default, but add this for it to work), and store userpics on a blobserver, set its location here so reproxy headers can be generated to the blobserver. Please see also [ljconfig[userpic_blobserver]] and [ljconfig[reproxy_disable]].",
                'type' => "hash",
                'example' => "(
                    'userpics' => '/mnt/xy_blob',
    );",
            },
            'protected_usernames' => {
                    'desc' => "This is a list of regular expressions matching usernames that users on this &lj; installation can&apos;t create on their own.",
                    'type' => "array",
                    'example' => '("^ex_", "^lj_")',
            },
            'qbufferd_isolate' => {
                    'desc' => "On a larger installation, it is useful to have multiple <systemitem class='process'>qbufferd.pl</systemitem> processes, one for each command type. This is not necessary on a small installation.",
                    'type' => "array",
                    'example' => "('weblogscom', 'eg_comnewpost')",
            },
            'qbufferd_pidfile' => {
                    'desc' => "Sets the file to which the qbufferd.pl parent process records the process id of the daemon. The presence of the file ensures qbufferd.pl knows if it already has a process started. The value must be a valid path, as the parent has to kill the child process if the parent couldn&apos;t create or write to its pid.",
                    'default' => '$LJ::HOME/var/qbufferd.pid',
            },
            'random_user_period' => {
                    'desc' => "If you want to change the amount of time a user stays in the [dbtable[random_user_set]] table, change this. The random user search feature uses this. The value is in days (default is one week).",
                    'default' => "7",
            },
            'reproxy_disable' => {
                    'desc' => "If you are using &perlbal; to balance your web site, it can use reproxying to distribute the files itself. You can use this option to disable that reproxying on an item-by-item basis. This can be useful for extremely busy sites without persistent connections between &perlbal; and <systemitem>mogstored</systemitem>, etc.  The hash is a set of file classes that should not be internally redirected to <systemitem>mogstored</systemitem> nodes / a blobserver.  Values are true, keys are one of 'userpics', 'captchas', or site-local file types like 'phoneposts' for <literal>ljcom</literal>. The default is to allow all reproxying.",
                    'type' => "hash",
                    'example' => "(
        userpics => 1,
        captchas => 1,
        );",
            },
            'support_diagnostics' => {
                    'desc' => "Support diagnostics can be helpful if you are trying to track down a bug that has been occurring.  The user-agent information will be appended to requests that users open through the web interface.",
                    'type' => "hash",
                    'example' => "( 'track_useragent' => 1, );",
            },
            'track_url_active' => {
                    'desc' => "Record in &memcached; what &url; a given host/pid is working on.",
            },
            'trust_x_headers' => {
                    'desc' => "If you know that your installation is behind a proxy or other fence that inserts <literal>X-Forwarded-For</literal> headers that you can trust, enable this. Otherwise, don&apos;t! Default is off (for direct connection to the &apos;net).  If behind your own reverse proxies, you should enable this.",
            },
            'use_qbufferd_delay' => {
                    'desc' => "Used in conjunction with [ljconfig[qbufferd_isolate]], to specify a time to sleep between runs of <systemitem>qbuffered</systemitem> tasks. The default is 15 seconds.",
                    'example' => "10",
            },
            'usersearch_metafile_path' => {
                    'desc' => "File name and path the search-updater worker should use for the usersearch data file.",
                    'default' => "\$LJ::HOME/var/usersearch.data",
            },
            'use_ssl' => {
                    'desc' => "Links to &ssl; portions of the site should be visible. This makes pages default to their SSL versions. If somebody can&apos;t do SSL due to proxies/etc, they can use insecure versions by appending ?ssl=no to the &url;.",
            },
        },

        'optimizations' => {
            'name' => "Optimization",
            'compress_text' => {
                    'desc' => "Boolean setting that compresses entry (stored in [dbtable[logtext2]]) and comment text (stored in [dbtable[talktext2]]) in the database, to
                    save disk space.",
            },
            'concat_res' => {
                    'desc' => "Instruct &perlbal; to concatenate static files on <emphasis>non</emphasis>-&ssl; pages.",
            },
            'concat_res_ssl' => {
                    'desc' => "Instruct &perlbal; to concatenate static files on &ssl; pages.",
            },
            'css_fetch_timeout' => {
                    'desc' => "Sets length of time in minutes to try fetching external &css; before timing out.",
                    'default' => "2;",
            },
            'disabled' => {
                    'desc' => "Boolean hash, signifying that separate parts of this &lj; installation are working and are available to use. A value of 1 on individual items within
                    the hash indicates &apos;on&apos; i.e. <quote>please switch on disabling of this feature</quote>.".
                    "Consult [special[disabled]] for more information.",
                    'type' => "hash",
            },
            'do_gzip' => {
                    'desc' => "Boolean setting that when enabled, signals to the installation to use <command>gzip</command> encoding, to compress text content
                    sent to browsers, wherever possible. In most cases this is known to cut bandwidth usage in half.
                    Requires the <package>Compress::Zlib</package> perl module. <package>mod_gzip</package> is somewhat buggy in &apache; 1.3x;
                    just use <package>Compress::Zlib</package>. See also [ljconfig[gzip_okay]]",
            },
            'force_empty_friends' => {
                    'desc' => "A hash of userids whose Friends views should be disabled for performance reasons. This is useful if new accounts are auto-added to ".
                    "another account upon creation (described in [ljconfig[initial_friends]]), as in most situations building a Friends view for <emphasis>those</emphasis> ".
                    "accounts would be superfluous and taxing on your installation. In the example, 234 and 232252 are userids of popular system communities.",
                    'type' => "hash",
                    'example' => "(
        234 => 1,
        232252 => 1,
);",
            },
            'loadfriends_using_gearman' => {
                    'desc' => "Enable this to use &gearman; when a set of <quote>Friends</quote> need loading. You will also need to run the corresponding worker.",
            },
            'loadsysban_using_gearman' => {
                    'desc' => "Enable this to use &gearman; to load sysbanned users, instead of &apache;. You will also need to run the corresponding worker.",
            },
            'loadtags_using_gearman' => {
                    'desc' => "Enable this to use &gearman; for loading user tags. This needs to be enabled so the corresponding worker operates, otherwise it falls back to loading in-process among the web processes.",
            },
            'max_s2compiled_cache_size' => {
                    'desc' => "Threshold (in bytes) under which compiled S2 layers are cached in &memcached;. If you have a lot of free &memcached; memory and a loaded database server with lots of queries to the [dbtable[s2compiled]] table, turn this up.",
                    'default' => "7500;",
            },
            'qbufferd_clusters' => {
                    'desc' => "If defined, list of clusters that qbufferd should use when retrieving and processing outstanding jobs.  Defaults to value of [ljconfig[clusters]]. You might set this if you removed a cluster you wanted to retire from \@LJ::CLUSTERS so it receives no new qbufferd jobs, but still needed to get qbufferd to process remaining jobs.",
                    'type' => "array",
            },
            'recent_tag_limit' => {
                    'desc' => "The [dbtable[logtagsrecent]] table holds mapping on a set quantity of the most recent tags applied to an entry. This variable sets that quantity.",
                    'example' => "100",
                    'default' => "500",
            },
            'suicide' => {
                    'desc' => "Large processes should voluntarily kill themselves at the end of requests.",
            },
           'suicide_over' => {
                    'desc' => "This is used by [ljconfig[suicide]], with Apache::DebateSuicide, the underlying cleanup handler, to decide whether a large process should voluntarily kill itself at the end of the request. It lets the site administrator set a global and/or per-server maximum memory cap on the sum of all of &modperl; children. If a processes memory is over the configured size (in <abbrev>KB</abbrev>), then the process will exit.",
                    'type' => "hash",
                    'default' => '1_000_000;',
            },
           'suicide_under' => {
                    'desc' => "See also [ljconfig[suicide_over]]. If a processes memory is under the configured size (in <abbrev>KB</abbrev>), then the process will exit.",
                    'type' => "hash",
                    'default' => '150_000;',
            },
           'synsuck_max_size' => {
                    'desc' => "Maximum external feed size a syndicated account may pull in (in <abbrev>KB</abbrev>). Defaults to 300. Can be overridden for individual syndicated accounts by giving them the siteadmin:largefeedsize priv.",
                    'default' => '300;',
            },

            'synd_cluster' => {
                    'desc' => "Syndicated accounts tend to have more database traffic than normal accounts, so it is a good idea to set up a separate cluster for them. ".
                    "If set to a cluster (defined by [ljconfig[clusters]]), all newly created accounts will reside on that cluster. If undefined, syndicated accounts are assigned
                    to user clusters (partitions) in the normal way.",
            },
            'tools_recent_comments_max' => {
                    'desc' => "Maximum number of comments to display on Recent Comments page <uri>/tools/recent_comments.bml</uri>.",
                    'default' => "50;",
            },
        },

        'policy_options' => {
            'name' => "Policy Options",
            'no_password_check' => {
                    'desc' => "Set this option true if you are running an installation using <literal>ljcom</literal> code and if you haven't installed the <package>Crypt::Cracklib</package> perl module. When enabled, the installation will not do strong password checks. Users can use any old dumb password they like.",
            },
            'required_tos' => {
                    'desc' => "Require users to agree to the <acronym>TOS</acronym>. The array items, respectively, allow you to: Set required version to enable tos version requirement mechanism, and change the messages displayed to users. The configurable title/html/text group values displayed are defaults, and are used if no 'domain'-specific values are defined in the rest of the array. The remaining items refer to: text/&html; to use when message displayed for a login action, an update action, posting a comment (this will just use the defaults above), protocol actions, and last, support requests.  The revision must be found in the first line of your <filename><parameter>\$<envar>LJHOME</envar></parameter>/htdocs/inc/legal-tos</filename> include file. <programlisting><![CDATA[<!-- \$Revision\$ -->]]></programlisting>",
                    'type' => "hash",
                    'example' => "(
            rev   => '1.0',

            title => 'Configurable Title for TOS agreement requirement notice',
            html  => 'Configurable HTML for TOS requirement',
            text  => 'Configurable text error message for TOS requirement',

            login => {
            html => 'Before logging in, you must update your TOS agreement',
            },

            update => {
            html => 'HTML to use in update.bml',
            },

            comment => {
            },

            protocol => {
            text => 'Please visit \$LJ::SITEROOT/legal/tos.bml to update your TOS agreement',
            },

            support => {
            html => 'Text to use when viewing a support request',
            },

);",
            },
            'tos_check' => {
                    'desc' => "If set, the account creation dialog shows a checkbox, asking users if they agree to the site Terms of Service, ".
                          "and will not allow them to create an account if they refuse. This depends on a few files being located in the proper directories, ".
                          "namely <filename>tos.bml</filename> and <filename>tos-mini.bml</filename> under <filename class='directory'><parameter>\$<envar>LJHOME</envar></parameter>/htdocs/legal</filename>. ".
                          "The account creation dialog can also check for new instances of the Terms of Service if the Terms of Service text is located in an ".
                          "&svn; managed include file (<filename><parameter>\$<envar>LJHOME</envar></parameter>/htdocs/inc/legal-tos</filename>), ".
                          "and if the include file includes the following line at the top: <programlisting><![CDATA[<!-- \$Revision\$ -->]]></programlisting>",
            },
            'use_acct_codes' => {
                    'desc' => "A boolean setting that makes joining the site require an <quote>invite code</quote> before being able to create a new account.  Not all features are implemented in the <literal>livejournal</literal>-only tree. &ljcom; used this for a period until late 2003. Note that this code might&apos;ve bitrotted, so perhaps it should be kept off.",
            },
        },

        'styling' => {
            'name' => "Styling Related",
            'default_style' => {
                    'desc' => "A hash that defines the default S2 layers to use for accounts. Keys are layer types, values are the S2 redist_uniqs.",
                    'default' => "{
            'core' => 'core1',
            'layout' => 'generator/layout',
            'i18n' => 'generator/en',
        };",
                    'example' => "{
            'core' => 'core1',
            'i18nc' => 'i18nc/en1',
            'layout' => 'generator/layout',
            'theme' => 'generator/nautical',
            'i18n' => 'generator/en',
            };",
            },
            'dont_touch_styles' => {
                    'desc' => "During the upgrade populator, do not touch styles.  That is, consider the local styles the definitive ones, and any differences between the database and the distribution files should mean that the distribution is old, not the database.",
            },
            'max_friends_view_age' => {
                    'desc' => "Sets how far back somebody can go on a user&apos;s <literal>Friends</literal> page, including their own. The default value is two weeks. That is, entries posted more than two weeks ago will not appear on anybody&apos;s <literal>Friends</literal> page, even if they are the most recent entries in that user&apos;s journal. See also \$LJ::MAX_SCROLLBACK_FRIENDS.",
                    'default' => "3600*24*14;",
            },
            'max_scrollback_friends' => {
                    'desc' => "Sets how far back somebody can go on a user&apos;s <literal>Friends</literal> page. That is, how far you can skip back with the ?skip= &url; argument.  A higher value can significantly affect the speed of the installation.",
                    'default' => "1000",
            },
            'max_scrollback_lastn' => {
                    'desc' => "The recent items (lastn view)'s max scrollback depth.  That is, how far you can skip back with the ?skip= &url; argument.  Defaults to 100.  After that, the 'previous' links go to day views, which are stable &url;s. ?skip= &url;s aren't stable, and there are inefficiencies making this value too large, so you&apos;re advised to not go too far above the default of 100.",
                    'default' => "100",
            },
            'minimal_useragent' => {
                    'desc' => "Some people on portable devices may have troubles viewing the nice site scheme you've setup, so you can specify that some user-agent prefixes should instead use fallback presentation information. In the example below, the fallback enables if the user-agent field starts with <quote>Foo</quote>. Note you can only put text here; no numbers, spaces, or symbols. The <quote>w</quote> in the defaults refers to <application>w3m</application>.",
                    'type' => "hash",
                    'default' => "(
    'Links' => 1,
    'Lynx' => 1,
    'w' => 1,
    'BlackBerry' => 1,
    'WebTV' => 1,
    );",
                    'example' => "(
    'Foo' => 1,
    );",
            },
            'minimal_bml_scheme' => {
                    'desc' => "Used with [ljconfig[minimal_useragent]].",
                    'example' => "'lynx';",
            },
            'minimal_style' => {
                    'desc' => "In the example, the default S2 bare style (usually it is 'core', but it is site-configurable) is used. You can add more layers and styles, which must be public styles. Used with [ljconfig[minimal_useragent]].",
                    'type' => "hash",
                    'example' => "(
    'core' => 'core1',
    );",
            },
            'syn_lastn_s1' => {
                    'desc' => "When set to an appropriate <literal>LASTN</literal> style, all syndicated accounts on this installation will use this style.",
            },
            's2_trusted' => {
                    'desc' => "Allows a specific user&apos;s S2 layers to run &js;. This is normally considered a potential security risk and disabled for all accounts. The hash structure is a series of userid => username pairs. The system account is trusted by default, so it is not necessary to add it to this hash.",
                    'type' => "hash",
                    'example' => "( '2' => 'exampleusername', '3' => 'test', );",
            },
            'use_control_strip' => {
                    'desc' => "Enable the navigation strip onsite. This gives users quick access to common site features from a toolbar at the top of journal Recent Entries and Friends pages, when the journal style supports it.",
            },
        },

        'system_tools' => {
            'name' => "System Tools",
            'bin_festival' => {
                    'desc' => "Path to <application>festival</application> (available in the &debian; package <quote><package>festival</package></quote>). Needed for audio &captcha;s.",
            },
            'bin_sox' => {
                    'desc' => "Path to <application>sox</application> (available in the &debian; package <quote><package>sox</package></quote>). Needed for audio &captcha;s.",
            },
            'dmtp_server' => {
                    'desc' => "Host/<acronym>IP</acronym> with port number to outgoing <systemitem class='protocol'>DMTP</systemitem> server.  Takes precedence over [ljconfig[smtp_server]]. Note: the <systemitem class='protocol'>DMTP</systemitem> (Danga Mail Transfer Protocol)
                    protocol and server is a dumb hack.  If you have a good outgoing &smtp; server, use that instead.",
                    'type' => "array",
                    'example' => "127.0.0.1:8030",
            },
        'ljmaint_verbose' => {
                    'desc' => "Use verbose output during maintenance tasks, like parsing for syndicated feed accounts. Values are one of 0=quiet, 1=normal, 2=verbose. If you only run maintenance tasks using <systemitem class='daemon'>cron</systemitem>, modify your crontabs accordingly if you enable this. For example,
                    if you re-direct standard output to <filename>/dev/null</filename> (using &gt;<filename>/dev/null</filename>), change that part of the cron job line to direct the verbose output to a file, or remove the redirect so <systemitem>cron</systemitem> falls back to the default, where cron jobs generate an &email; to the user executing the command.",
                    'default' => "1",
            },
            'lockdir' => {
                    'desc' => "A directory to use for lock files if you're not using <literal>ddlockd</literal> for locking. Using <literal>ddlockd</literal>, the default lockdir is <filename class='directory'><parameter>\$<envar>LJHOME</envar></parameter>/locks</filename>.",
                    'example' => "/var/lock/livejournal",
            },
            'log_gtop' => {
                    'desc' => "Turn on statistics generation that shows memory/cpu usage deltas of the &apache; child for each request, for database logs.  It requires that the <package>GTop</package> module be installed.",
            },
            'smtp_server' => {
                    'desc' => "Host/<acronym>IP</acronym> to outgoing &smtp; server.  Takes precedence over [ljconfig[sendmail]]. This the recommended system to use for sending &email;.",
                    'example' => "127.0.0.1",
            },
            'speller' => {
                    'desc' => "The system path to a spell checking binary, along with any necessary parameters.",
                    'example' => '"/usr/bin/aspell pipe --sug-mode=fast --ignore-case"',
            },
        },

    },

    'auto' => {
        'name' => 'Auto-Configured',
                    'desc' => "These <varname>\$LJ::</varname> settings are automatically set in ".
                    "<filename>cgi-bin/LJ/Global/Defaults.pm</filename>. You do not need to use all of them. ".
                    "Some are only documented here for people interested in extending &lj;, or for other special cases.".
                    "You can define them in <filename>etc/config.pl</filename> ahead of time so you can use them in ".
                    "definitions of future variables. ",

        'configuration_directories' => {
            'name' => "Configuration Directories",
            'bin' => {
                    'desc' => "Points to the <filename class='directory'>bin</filename> directory under [ljconfig[home]].",
                    'default' => "\$HOME/bin",
            },
            'cvsdir' => {
                    'desc' => "Points to the <filename class='directory'>cvs</filename> directory under [ljconfig[home]]. This is used by <filename>multicvs.conf</filename>, which specifies how the files from the multiple &svn; repositories map onto the live file space ([ljconfig[livedir]] / [ljconfig[home]]).",
                    'default' => "\$HOME/cvs",
            },
            'home' => {
                    'desc' => "Set to the same value as [special[ljhome]].",
                    'default' => "\$LJ::HOME",
            },
            'htdocs' => {
                    'desc' => "Points to the <filename class='directory'>htdocs</filename> directory under [ljconfig[home]].",
                    'default' => "\$HOME/htdocs",
            },
            'livedir' => {
                    'desc' => "Points to [ljconfig[home]]. This is used by <filename>multicvs.conf</filename>, which specifies how the files from the multiple &svn; repositories map onto the live file space from [ljconfig[cvsdir]].",
                    'default' => "\$LJ::HOME",
            },
            'ssldocs' => {
                    'desc' => "Points to the <filename class='directory'>ssldocs</filename> directory under [ljconfig[home]].",
                    'default' => "\$HOME/ssldocs",
            },
            'temp' => {
                    'desc' => "Points to the <filename class='directory'>temp</filename> directory under [ljconfig[home]].",
                    'default' => "\$HOME/temp",
            },
            'var' => {
                    'desc' => "Points to the <filename class='directory'>var</filename> directory under [ljconfig[home]].",
                    'default' => "\$HOME/var",
            },
        },

        'database_setup' => {
            'name' => "Database Setup",
            'max_repl_lag' => {
                    'desc' => "The max number of bytes that a &mysql; database slave can be behind in replication and still be considered usable.  Note that slave databases are never used for any &apos;important&apos; read operations (and especially never writes, because writes only go to the master), so in general &mysql;'s async replication won&apos;t bite you.  This mostly controls how fresh of data a visitor would see, not a content owner.  But in reality, the default of 100k is pretty much real-time, so you can safely ignore this setting.",
            },
            'db_timeout' => {
                    'desc' => "Integer number of seconds to wait for database handles before timing out.  By default, zero, which means no timeout.",
                    'default' => "0;",
            },
        },

        'email_related' => {
            'name' => "E-mail Related",
            'admin_email' => {
                    'desc' => "Given as the administrative address for functions like changing passwords or information.",
                    'default' => "webmaster\@\$DOMAIN",
            },
            'bogus_email' => {
                    'desc' => "Used for automated notices like comment replies and general support request messages. It should be encouraged <emphasis>not</emphasis> to reply to this address.",
                    'default' => "ys_dontreply\@\$DOMAIN",
            },
            'community_email' => {
                    'desc' => "Sets the from address for community invitation &email;s. When this option is not set, it defaults to the [ljconfig[admin_email]] address. This makes them appear to be official communications from the site because the same address is used for password reminders and validation &email;s. The invitations are actually communications from individual users through a site feature - they are more comparable to comment &email;s.",
                    'default' => "webmaster\@\$DOMAIN",
                    'example' => "community_invitation\@\$DOMAIN",
            },
        },

        'misc_auto' => {
            'name' => "Miscellaneous Auto-Configured",
            'autosave_draft_interval' => {
                    'desc' => "Sets how often the editor at <filename>update.bml</filename> will automatically save a draft of the entry. The default saves at intervals of three minutes.",
                    'default' => "3;",
            },
            'default_editor' => {
                    'desc' => "Editor for new entries if the user hasn\'t overridden it.  Should be \'rich\' or \'plain\'.",
                    'default' => 'rich',
                 },
            'gzip_okay' => {
                    'desc' => "If [ljconfig[do_gzip]] is enabled, the list of content types considered valid for <command>gzip</command> compression is defined in this hash.",
                    'type' => "hash",
                    'default' => "
    'text/html' =&gt; 1,                # regular web pages; XHTML 1.0 'may' be this
    'text/xml' =&gt; 1,                 # regular XML files
    'application/xml' =&gt; 1,          # XHTML 1.1 'may' be this
    'application/xhtml+xml' =&gt; 1,    # XHTML 1.1 'should' be this
    'application/rdf+xml' =&gt; 1,      # FOAF should be this",
            },
            'max_atom_upload' => {
                    'desc' => "Max number of bytes that users are allowed to upload via Atom &api;.  Note that this upload path is not ideal, so the entire upload must fit in memory.  Default is 25MB until path is optimized. It is set like this because the &http; content-length header is in bytes (a 25600 value would be 25KB).",
                    'default' => '26214400',
            },
            'max_foaf_friends' => {
                    'desc' => "The maximum number of friends that users' <acronym>FOAF</acronym> files will show (so the server does not get overloaded).  If they have more than the configured amount, some friends will be omitted.",
                    'default' => '1000',
            },
            'max_friendof_load' => {
                    'desc' => "The maximum number of friend-ofs ('fans'/'followers') to load for a given user.  Defaults to 5000.  Beyond that, a user is just too popular and saying 5,000 is usually sufficient because people aren&apos;t actually reading the list.",
                    'default' => '5000',
            },
            'max_userpic_keywords' => {
                    'desc' => "Boolean hash to set usercap for the maximum amount of keywords a userpic can have. The keywords themselves have a 40 character limit; userpic comments can be up to 255 bytes or 120 chars.",
                    'default' => "10;",
            },
            'profile_bml_file' => {
                    'desc' => "The file (relative to htdocs) to use for the profile &url;.  Defaults to <filename>profile.bml</filename>",
            },
            'stats_block_size' => {
                    'desc' => "Block size used in stats generation code that gets <replaceable>n</replaceable> rows from the database at a time.",
                    'default' => "10_000;",
            },
        },

        'others_do_not_use_us' => {
            'name' => "Others",
            'cookie_domain_reset' => {
                    'desc' => "Array of cookie domain values to send when deleting cookies from users.  Only useful when changing domains, and even then kind&apos;ve useless. Notes: ancient hack for one old specific use.",
                    'type' => "array",
                    'default' => '("", "$DOMAIN", ".$DOMAIN")',
            },
            'cookie_path' => {
                    'desc' => "According to the <acronym>RFC</acronym>s concerning cookies, the cookie path must be explicitly set as well. If &lj; is installed ".
                    "underneath a directory other than the top-level domain directory, this needs to be set accordingly. Note: Setting or changing this variable has no practical use, since &lj; must be rooted at <systemitem>/</systemitem>.",
                    'default' => "/",
            },
            'dys_left_top' => {
                    'desc' => "&html; to show at the top left corner of the Dystopia skin. This was never actually used. Second, the Dystopia &apos;skin&apos; (scheme) is <literal>ljcom</literal>, not <acronym>GPL</acronym>-licensed <literal>livejournal</literal> code.",
            },
            'fix_usercounter_enabled' => {
                    'desc' => "<emphasis role='strong'>Old historic baggage: Do not use.</emphasis> This boolean enables the <filename>fix_usercounter.bml</filename> tool at \$SITEROOT/admin. The tool reset user counters to resolve <quote>duplicate key error</quote> issues with journals. A better way to address the problem was found, making this tool redundant.",
            },
        },

        'site_maintenance' => {
            'name' => "Site Maintenance",
            'msg_no_comment' => {
                    'desc' => "Message to show users when they're not allowed to comment due to either their 'get_comments' or 'leave_comments' capability being disabled, probably by the admin to lower activity after a hardware rotation.",
                    'example' => "Due to hardware maintenance, you cannot leave comments at this time.  Watch the news " .
                    "page for updates.",
            },
            'msg_no_post' => {
                    'desc' => "Message to show users when they are not allowed to post due to their 'can_post' capability being disabled, probably by the admin to lower activity after a hardware rotation.",
                    'example' => "Due to hardware maintenance, you cannot post at this time.  Watch the news page for updates.",
            },
            'msg_readonly_user' => {
                    'desc' => "Message to show users when their journal (or a journal they are visiting) is in read-only mode due to maintenance.",
                    'example' => "This journal is in read-only mode right now while database maintenance
is being performed. Try again in a few minutes.",
                    'default' => "Database temporarily in read-only mode during maintenance.",
            },
        },

        'system_related' => {
            'name' => "System Related",
            'mail_transports' => {
                    'desc' => "Mail transports setup. Array values are: protocol, mailserver hostname, and preferential weight. ".
                    "<systemitem class='protocol'>qmtp</systemitem> (requires the <package>Net::QMTP</package> perl module to work properly), ".
                    "&smtp;, <systemitem class='protocol'>dmtp</systemitem>, and ".
                    "<systemitem class='protocol'>sendmail</systemitem> are the currently supported protocols.",
                    'type' => "array",
                    'default' => "( [ 'sendmail', \$SENDMAIL, 1 ] )",
            },
            'sendmail' => {
                    'desc' => "The system path to the sendmail program, along with any necessary parameters. This option is ignored if you have defined the higher-precedence option: [ljconfig[mail_transports]]. See also [ljconfig[smtp_server]]",
                    'example' => '"/usr/sbin/sendmail -t -oi"',
            },
        },

        'visuals' => {
            'name' => "Visuals",
            'cssproxy' => {
                    'desc' => "If set, external &css; should be proxied through this &url; (&url; is given a ?u= argument with the escaped &url; of &css; to clean. If unset, remote &css; is blocked.  See also [ljconfig[css_fetch_timeout]].",
            },
            's2_compiled_migration_done' => {
                    'desc' => "Do not try to load compiled S2 layers from the global cluster. Any new installation can enable this safely as a minor optimization. If you have an existing site, make sure to only turn this flag on if you have actually migrated everything. The option only really makes sense for large, old sites",
                    'default' => "0;",
            },
            'schemes' => {
                    'desc' => "An array of hashes with keys (&apos;scheme&apos;) being a &bml; scheme name and the values (&apos;title&apos;) being the scheme description. When set, users can change their default site scheme to the scheme of their choice. Schemes will be displayed according to their order in the array, but the first array item is the site default scheme.",
                    'type' => "array",
                    'default' => "(
        { scheme => 'lynx', title => 'Lynx', },
        );",
                    'example' => "(
        { scheme => 'lynx', title => 'Lynx',
        thumb => [ 'schemethumb/lynx.png', 200, 166 ]  },
        );",
            },
            's1_shortcomings' => {
                    'desc' => "Use the S2 style named 's1shortcomings' to handle page types that S1 can't handle.  Otherwise, &bml; is used.  This is off by default, but will eventually become on by default, and no longer an option.",
            },
        },

        'i18n' => {
            'name' => "Internationalization",
            'default_lang' => {
                    'desc' => "Default <acronym>ISO</acronym> (639/639_3166) language code to show site in, for users that have not set their language. Defaults to the first item in \@LANGS, which is usually \"en\", for English. Optional.",
                    'type' => "array",
                    'default' => 'en',
            },
            'unicode' => {
                    'desc' => "Boolean setting that allows <acronym>UTF</acronym>-8 support (for posts in multiple languages). The default has been 'on' for ages, and turning it off is nowadays not recommended or even known to be working/reliable.  Keep it enabled.",
            },
        },

    },
);

for my $type ( keys %ljconfig )
{
    print "  <section id='lj.install.ljconfig.vars.$type'>\n";
    print "    <title>" . %ljconfig->{$type}->{'name'} . "</title>\n";
    print "    <para>" . %ljconfig->{$type}->{'desc'} . "</para>\n";
    for my $list ( sort keys %{%ljconfig->{$type}} ) {
        next if ($list eq "name" || $list eq "desc");
        print "    <variablelist>\n";
        print "      <title>" . %ljconfig->{$type}->{$list}->{'name'} . "</title>\n";
        foreach my $var ( sort keys %{%ljconfig->{$type}->{$list}} ) {
            next if $var eq "name";
            my $vartype = '$';
            if (%ljconfig->{$type}->{$list}->{$var}->{'type'} eq "hash") { $vartype = '%'; }
            if (%ljconfig->{$type}->{$list}->{$var}->{'type'} eq "array") { $vartype = '@'; }
            print "      <varlistentry id='ljconfig.$var'>\n";
            print "        <term><varname role='ljconfig.variable'>" . $vartype . "LJ::" . uc($var) . "</varname></term>\n";
            my $des = %ljconfig->{$type}->{$list}->{$var}->{'desc'};
            $des =~ s/&(?!(?:[a-zA-Z0-9]+|#\d+);)/&amp;/g;
            xlinkify(\$des);
            print "        <listitem><para>$des</para>\n";
            if (%ljconfig->{$type}->{$list}->{$var}->{'example'})
            {
                print "          <para><emphasis>Example:</emphasis> ";
                print "<informalexample><programlisting>";
                print %ljconfig->{$type}->{$list}->{$var}->{'example'};
                print "</programlisting></informalexample></para>\n";
            }
            if (%ljconfig->{$type}->{$list}->{$var}->{'default'})
            {
                print "          <para><emphasis>Default:</emphasis> ";
                print "<informalexample><programlisting>";
                print %ljconfig->{$type}->{$list}->{$var}->{'default'};
                print "</programlisting></informalexample></para>\n";
            }
            print "        </listitem>\n";
            print "      </varlistentry>\n";
        }
        print "    </variablelist>\n";
    }
    print "  </section>\n";
}

#hooks();

