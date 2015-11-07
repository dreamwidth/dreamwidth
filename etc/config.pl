#!/usr/bin/perl
# -*-perl-*-

# LiveJournal configuration file.

# THIS FILE IS INTENDED FOR EXAMPLE/DOCUMENTATION PURPOSES ONLY.

# Ideally, any configuration changes for your site should go in
# config-local.pl or config-private.pl.  If you feel like you need
# a site-specific config.pl, make sure you copy it to ext/local/etc
# and customize it there.  This will protect it from getting clobbered
# when you upgrade to the newest Dreamwidth code in the future, but
# you will not automatically inherit additions or updates to this file.

{
    package LJ;

    ###
    ### Site Information
    ###

    $HTDOCS = "$HOME/htdocs";
    $BIN = "$HOME/bin";
    $TEMP = "$HOME/temp";
    $VAR = "$HOME/var";

    $DOMAIN_WEB = "www.$DOMAIN"; # necessary

    # this is what gets prepended to all URLs
    $SITEROOT = "http://$DOMAIN_WEB";
    $SSLROOT = "https://$DOMAIN_WEB";
    $RELATIVE_SITEROOT = "//$DOMAIN_WEB";

    # prefix for images
    $IMGPREFIX = "$SITEROOT/img";

    # set this if you're running an FTP server that mirrors your htdocs/files
    #$FTPPREFIX = "ftp://ftp.$DOMAIN";

    # where we set the cookies (note the period before the domain)
    # can be one value or an array ref (to accomodate certain old
    # broken browsers)
    $COOKIE_DOMAIN = ".$DOMAIN";

    # email addresses
    $ADMIN_EMAIL = "webmaster\@$DOMAIN";
    $ABUSE_EMAIL = "abuse\@$DOMAIN";
    $ANTISPAM_EMAIL = "antispam\@$DOMAIN";
    $SUPPORT_EMAIL = "support\@$DOMAIN";
    $COMMUNITY_EMAIL = "community_invitation\@$DOMAIN";
    $BOGUS_EMAIL = "dw_null\@$DOMAIN";
    $COPPA_EMAIL = "coppa\@$DOMAIN";
    $PRIVACY_EMAIL = "privacy\@$DOMAIN";
    $ACCOUNTS_EMAIL = "accounts\@$DOMAIN";

    # news site support. if set, that journal loads on the main page.
    #$FRONTPAGE_JOURNAL = "news";

    # css proxy
    $CSSPROXY = "//cssproxy.$DOMAIN/";

    # setup subdomains that work
    %SUBDOMAIN_FUNCTION = (
            community => 'journal',
            users => 'journal',
            syndicated => 'journal',
            cssproxy => 'cssproxy',
            shop => 'shop',
            mobile => 'mobile',
            m => 'mobile',
            support => 'support',
            u => 'userpics',
            v => 'userpics',
        );



    ###
    ### Policy Options
    ###

    # filter comments for spam using this list of regular expressions:
    #@TALKSPAM = (
    #             "morphese",
    #             );

    # require new free acounts to be referred by an existing user?
    $USE_ACCT_CODES = 1;

    #$EVERYONE_VALID = 1; # are all users validated by default?

    ###
    ### System Information
    ###

    # path to sendmail and any necessary options
    $SENDMAIL = "/usr/sbin/sendmail -t";

    # command-line to spell checker, or undefined if you don't want spell checking
    #$SPELLER = "/usr/local/bin/ispell -a";
    #$SPELLER = "/usr/bin/aspell pipe --mode=html --sug-mode=fast --ignore-case";

    # use a gearman worker for spellcheck
    #$RUN_SPELLCHECK_USING_GEARMAN = 1;

    # to save bandwidth, should we compress pages before they go out?
    # require Compress::Zlib to be installed
    #$DO_GZIP = 1;

    # Support signed PGP email for email posting?
    # Requires GnuPG::Interface and Mail::GnuPG to be installed.
    #$USE_PGP = 1;

    # HINTS:
    #   how far you can scroll back on lastn and friends pages.
    #   big performance implications if you make these too high.
    #   also, once you lower them, increasing them won't change anything
    #   until there are new posts numbering the difference you increased
    #   it by.
    $MAX_HINTS_LASTN = 800;
    $MAX_SCROLLBACK_LASTN = 750;

    # do paid users get email addresses?  username@$USER_DOMAIN ?
    # (requires additional mail system configuration)
    $USER_EMAIL  = 1;

    # Support URLs of the form http://username.yoursite.com/ ?
    # If so, what's the part after "username." ?
    $USER_VHOSTS = 1;
    $USER_DOMAIN = $DOMAIN;

    # If you ONLY want USER_VHOSTS to work and not the typical /users/USER and /community/USER
    # then set this option:
    $ONLY_USER_VHOSTS = 1;

    # Support updating of journals via email?
    # Users can post to user@$EMAIL_POST_DOMAIN.
    $EMAIL_POST_DOMAIN = "post.$DOMAIN";

    # Support replying to comments via email?
    # We set the reply-to for the user in the form of user.$auth@EMAIL_REPLY_DOMAIN
    $EMAIL_REPLY_DOMAIN = "replies.$DOMAIN";

    # This should be a path to a Maildir, matching the delivery
    # location of your MTA.
    # If you are using sendmail, you should deliver with procmail
    # (versions 3.14 and above) for Maildir support.
    #$MAILSPOOL = '/home/livejournal/mail';

    # turns these from 0 to 1 to disable parts of the site that are
    # CPU & database intensive or that you simply don't want to use
    %DISABLED = (
                 adult_content => 0,
                 loggedout_support_requests => 1,
                 'community-logins' => 0,
                 captcha => 0,
                 directory => 0,
                 esn_archive => 1,
                 eventlogrecord => 1,
                 googlecheckout => 1,
                 icon_renames => 0,
                 importing => 0,
                 'interests-findsim' => 0,
                 memories => 0,
                 opt_findbyemail => 1,
                 payments => 0,
                 'show-talkleft' => 0,
                 'stats-recentupdates' => 0,
                 'stats-newjournals' => 0,
                 'support_request_language' => 1,
                 tellafriend => 0,
                 );

    # allow extacct_info for all sites except LiveJournal
    #$DISABLED{extacct_info} = sub {
    #    ref $_[0] && defined $_[0]->{sitename} &&
    #        $_[0]->{sitename} eq 'LiveJournal' ? 1 : 0 };

    # disable the recaptcha module, but keep textcaptcha enabled
    # you'd probably want to edit $LJ::DEFAULT_CAPTCHA_TYPE in this case
    #$DISABLED{captcha} = sub {
    #   my $module = $_[0];
    #   return 1 if $module eq "recaptcha";
    #   return 0 if $module eq "textcaptcha";
    #   return 0;
    #};
    #$DEFAULT_CAPTCHA_TYPE = "T";


    # turn $SERVER_DOWN on while you do any maintenance
    $SERVER_TOTALLY_DOWN = 0;
    $SERVER_DOWN = 0;
    $SERVER_DOWN_SUBJECT = "Maintenance";
    $SERVER_DOWN_MESSAGE = "$SITENAME is down right now while we upgrade.  It should be up in a few minutes.";
    $MSG_READONLY_USER   = "This journal is in read-only mode right now while database maintenance is performed " .
                           "on the server where the journal is located.  Try again in several minutes.";
    $MSG_NO_POST    = "Due to hardware maintenance, you cannot post at this time.  Watch the news page for updates.";
    $MSG_NO_COMMENT = "Due to hardware maintenance, you cannot leave comments at this time.  Watch the news " .
                      "page for updates.";
    #$MSG_DB_UNAVAILABLE = "Sorry, database temporarily unavailable.  Please see <a href='...'>...</a> for status updates.";

    # can also disable media uploads/modifications, if for some reason you need to
    # turn off your MogileFS install, for example.
    $DISABLE_MEDIA_UPLOADS = 0;

    ###
    ### Language / Scheme support
    ###

    # schemes available to users.
    # schemes will be displayed according to their order in the array,
    # but the first item in the array is the default scheme
    # 'title' is the printed name, while 'scheme' is the scheme name.
    @SCHEMES = (
                { scheme => 'blueshift', title => 'Blueshift' },
               );

    # supported languages (defaults to qw(en) if none given)
    # First element is default language for user interface, untranslated text
    unless (@LANGS) {
      @LANGS = qw( en_DW ) if -d "$HOME/ext/dw-nonfree";
    }


    ###
    ### Database Configuration
    ###

    # if database logging is enabled above, should we log images or just page requests?
    #$DONT_LOG_IMAGES = 1;

    # Turn on memory/cpu usage statistics generation for database logs (requires the
    # GTop module to be installed)
    #$LOG_GTOP = 1;

    # directory optimizations
    $DIR_DB_HOST = "master";  # DB role to use when connecting to directory DB
    $DIR_DB = "";             # by default, hit the main database (bad for big sites!)

    # list of all clusters - each one needs a 'cluster$i' role in %DBINFO
    @CLUSTERS = (1);    # eg: (1, 2, 3) (for scalability)

    # can users choose which cluster they're assigned to?  leave this off.
    $ALLOW_CLUSTER_SELECT = 0;

    # which cluster(s) get new users?
    # if it's an arrayref, choose one of the listed clusters at random.  you can weight
    # new users by repeating cluster numbers, e.g. [ 1, 1, 1, 2 ] puts 75% of people on
    # cluster 1, 25% of people on cluster 2.  clusters are checked for validity before
    # being used.
    $DEFAULT_CLUSTER = [ 1 ];

    # which cluster should syndication accounts live on?
    $SYND_CLUSTER = 1;

    ###
    ### Account Information
    ###

    # initial friends for new accounts.
    # leave undefined if you don't want to use it.
    @INITIAL_SUBSCRIPTIONS = qw(news);

    # initial optional friends
    #@LJ::INITIAL_OPTIONAL_SUBSCRIPTIONS = qw(news);

    # initial friends checked by default on create.bml
    #@LJ::INITIAL_OPTOUT_SUBSCRIPTIONS = qw(news);

    # some system accounts have so many friends it is harmful to display
    # them.  list these accounts here.
    #%FORCE_EMPTY_SUBSCRIPTIONS = (
     #                             '81752' => 'paidmembers'
    #                             );


    # test accounts are special
    @TESTACCTS = qw(test);

    # props users should have by default
    %USERPROP_DEF = ();

    ### User Capabilities Classes:

    # default capability limits, used only when no other
    # class-specific limit below matches.
    %CAP_DEF = (
            'activeentries' => 0,
            'bonus_icons' => 0,
            'can_post' => 1,
            'checkfriends' => 0,
            'checkfriends_interval' => 300,
            'directorysearch' => 0,
            'emailpost' => 0,
            'findsim' => 0,
            'friendspage_per_day' => 0,
            'friendsviewupdate' => 30,
            'full_rss' => 1,
            'get_comments' => 1,
            'getselfemail' => 0,
            'google_analytics' => 0,
            'hide_email_after' => 60,
            'import_comm' => 0,
            'interests' => 150,
            'leave_comments' => 1,
            'makepoll' => 0,
            'maxcomments' => 10000,
            'maxfriends' => 500,
            'media_file_quota' => 500, # megabytes
            'mod_queue' => 50,
            'mod_queue_per_poster' => 5,
            'moodthemecreate' => 0,
            'rateallowed-commcreate' => 3,
            'rateallowed-failed_login' => 3,
            'rateallowed-lostinfo' => 3,
            'rateperiod-commcreate' => 86400*7, # 7 days / 1 week
            'rateperiod-failed_login' => 60*5, # 5 minutes
            'rateperiod-lostinfo' => 60*60*24, # 24 hours
            's2layersmax' => 0,
            's2styles' => 0,
            's2stylesmax' => 0,
            's2viewentry' => 1,
            's2viewreply' => 1,
            'staff_headicon' => 0,
            'styles' => 0,
            'thread_expand_all' => 0,
            'thread_expander' => 0,
            'track_all_comments' => 0,
            'userdomain' => 1,
            'useremail' => 1,
            'userlinks' => 10,
            'userpics' => 5,
            'xpost_accounts' => 0,
            );

    # for convenience and consistency, let's put common caps for all paid account types here:
    my %CAP_PAID = (
            'paid' => 1,
            'activeentries' => 1,
            'bonus_icons' => 1,
            'checkfriends' => 1,
            'checkfriends_interval' => 600,
            'directory' => 1,
            'edit_comments' => 1,
            'emailpost' => 1,
            'fastserver' => 1,
            'findsim' => 1,
            'friendsfriendsview' => 1,
            'friendspage_per_day' => 1,
            'friendsviewupdate' => 1,
            'full_rss' => 1,
            'getselfemail' => 1,
            'google_analytics' => 1,
            'import_comm' => 1,
            'makepoll' => 1,
            'mass_privacy' => 1,
            'mod_queue' => 100,
            'mod_queue_per_poster' => 5,
            'moodthemecreate' => 1,
            'popsubscriptions' => 1,
            's2props' => 1,
            's2styles' => 1,
            'security_filter' => 1,
            'stickies' => 5,
            'synd_create' => 1,
            'thread_expand_all' => 1,
            'thread_expander' => 1,
            'track_defriended' => 1,
            'track_pollvotes' => 1,
            'track_thread' => 1,
            'track_user_newuserpic' => 1,
            'useremail' => 1,
            'userlinks' => 50,
            'usermessage_length' => 10000,
            'userpicselect' => 1,
            'viewmailqueue' => 1,
    );

    # for convenience and consistency, let's put common caps for all premium account types here:
    my %CAP_PREMIUM = (
            'bookmark_max' => 1000,
            'inbox_max' => 6000,
            'interests' => 250,
            'maxfriends' => 2000,
            's2layersmax' => 300,
            's2stylesmax' => 100,
            'subscriptions' => 1000,
            'tags_max' => 2000,
            'tools_recent_comments_display' => 150,
            'track_all_comments' => 1,
            'userlinks' => 100,
            'userpics' => 150,
            'xpost_accounts' => 5,
    );

    # capability class limits.
    # keys are bit numbers, from 0 .. 15.  values are hashrefs
    # with limit names and values (see doc/capabilities.txt)
    # NOTE: you don't even need to have different capability classes!
    #       all users can be the same if you want, just delete all
    #       this.  the important part then is %CAP_DEF, above.
    %CAP = (
        '0' => {  # 0x01
            '_name' => 'UNUSED',
            '_key' => 'UNUSED',
        },
        '1' => {  # 0x02
            '_name' => 'Free',
            '_visible_name' => 'Free Account',
            '_key' => 'free_user',
            '_account_type' => 'free',
            '_account_default' => 1,    # default account for payment system
            'activeentries' => 0,
            'bookmark_max' => 25,
            'checkfriends' => 0,
            'checkfriends_interval' => 0,
            'directory' => 1,
            'edit_comments' => 0,
            'emailpost' => 1,
            'findsim' => 0,
            'friendsfriendsview' => 0,
            'friendspage_per_day' => 0,
            'friendsviewupdate' => 0,
            'full_rss' => 1,
            'getselfemail' => 0,
            'google_analytics' => 0,
            'import_comm' => 1,
            'inbox_max' => 2000,
            'interests' => 150,
            'makepoll' => 0,
            'mass_privacy' => 0,
            'maxfriends' => 1000,
            'mod_queue' => 50,
            'mod_queue_per_poster' => 3,
            'moodthemecreate' => 0,
            'popsubscriptions' => 0,
            's2layersmax' => 0,
            's2props' => 0,
            's2styles' => 0,
            's2stylesmax' => 0,
            'security_filter' => 0,
            'stickies' => 2,
            'subscriptions' => 25,
            'synd_create' => 1,
            'tags_max' => 1000,
            'thread_expand_all' => 0,
            'thread_expander' => 0,
            'tools_recent_comments_display' => 10,
            'track_all_comments' => 0,
            'track_defriended' => 0,
            'track_pollvotes' => 0,
            'track_thread' => 0,
            'track_user_newuserpic' => 0,
            'useremail' => 0,
            'userlinks' => 10,
            'usermessage_length' => 5000,
            'userpics' => 6,
            'userpicselect' => 0,
            'viewmailqueue' => 0,
            'xpost_accounts' => 1,
        },
        '2' => {  # 0x04
            '_name' => 'UNUSED2',
            '_key' => 'UNUSED2',
        },
        '3' => {  # 0x08
            '_name' => 'Paid',
            '_key' => 'paid_user', # Some things expect that key name
            '_visible_name' => 'Paid Account',
            '_account_type' => 'paid',
            '_refund_points' => 30,
            %CAP_PAID,
            'bookmark_max' => 500,
            'inbox_max' => 4000,
            'interests' => 200,
            'maxfriends' => 1500,
            's2layersmax' => 150,
            's2stylesmax' => 50,
            'subscriptions' => 500,
            'tags_max' => 1500,
            'tools_recent_comments_display' => 100,
            'track_all_comments' => 0,
            'userpics' => 75,
            'xpost_accounts' => 3,
        },
        '4' => {  # 0x10
            '_name' => 'Premium Paid',
            '_key' => 'premium_user',
            '_visible_name' => 'Premium Paid Account',
            '_account_type' => 'premium',
            '_refund_points' => 41,
            %CAP_PAID,
            %CAP_PREMIUM,
        },
        # a capability class with a name of "_moveinprogress" is required
        # if you want to be able to move users between clusters with the
        # provided tool.  further, this class must define 'readonly' => 1
        '5' => {  # 0x20
            '_name' => '_moveinprogress',
            'readonly' => 1,
        },
        '6' => {  # 0x40
            '_name' => 'Permanent',
            '_key' => 'permanent_user',
            '_visible_name' => 'Seed Account',
            '_account_type' => 'seed',
            %CAP_PAID,
            %CAP_PREMIUM,
        },
        '7' => {  # 0x80
            '_name' => 'Staff',
            '_key' => 'staff',
            '_visible_name' => 'Staff Account',
            'staff_headicon' => 1,
            %CAP_PAID,
            %CAP_PREMIUM,
        },
        8 => { _name => 'beta', _key => 'betafeatures' }, # 0x100
    );

    # default capability class mask for new users:
    # (16 bit unsigned int ... each bit is capability class flag)
    $NEWUSER_CAPS = 2;

    # by default, give users a style
    $DEFAULT_STYLE = {
        'core' => 'core2',
        'layout' => 'negatives/layout',
        'theme' => 'negatives/black',
    };

    ### /admin/fileedit setup
    # If you are using the files in htdocs/inc and are frequently editing
    # those, you may wish to put all of these files into the database.
    # You can instruct BML to treat all <?_include?> statements as being
    # pulled from memcached (failover to the database) by uncommenting:
    # $FILEEDIT_VIA_DB = 1;
    # Alternately, you can specify that only particular files should be
    # kept in memcache and the database by doing:
    # %FILEEDIT_VIA_DB = ( 'support_links' => 1, );


    # Setup support email address to not accept new emails.  Basically if an
    # address is specified below, any user who emails it out of the blue will
    # be sent back a copy of the specified file along with their email.  Users
    # will still be allowed to respond to emails from the support system, but
    # they can't open a request by emailing the address.  The value part of
    # the hash is the name of an include file.  It will be loaded out of
    # LJHOME/htdocs/inc.  See %FILEEDIT_VIA_DB for how to make it read
    # from memcache/DB.
    #%DENY_REQUEST_FROM_EMAIL = (
    #    "abuse\@$DOMAIN" => "bounce-abuse",
    #);

    # Support diagnostics can be helpful if you are trying to track down a
    # bug that has been occurring.  You can turn on and off various tracking
    # features here.  Just uncomment any/all of the following lines.  The
    # gathered information will be appended to requests that the user opens
    # through the web interface.
    %SUPPORT_DIAGNOSTICS = (
    #    'track_useragent' => 1,
    );

    # If you want to change the limit on how many bans a user can make, uncomment
    # the following line.  Default is 5000.
    #$MAX_BANS = 5000;

    # If you are using MogileFS on your site for userpics or other purposes, you
    # will need to define the following hash and complete the information in it.
    #%MOGILEFS_CONFIG = (
    #    hosts => [ '10.0.0.1:6001' ],
    #    root => '/mnt/mogdata',
    #    classes => {
    #        'your_class' => 3,  # define any special MogileFS classes you need
    #    },
    #);

    # Some people on portable devices may have troubles viewing the nice site
    # scheme you've setup, so you can specify that some user-agent prefixes
    # should instead use fallback presentation information.
    %MINIMAL_USERAGENT = (
        #'Foo' => 1, # if the user-agent field starts with "Foo" ...
                     # note you can only put text here; no numbers, spaces, or symbols.
    );
    $MINIMAL_BML_SCHEME = 'lynx';
    %MINIMAL_STYLE = (
        'core' => 'core1', # default, but you can add more layers and styles... note
                           # that they must be public styles
    );

    # if you know that your installation is behind a proxy or other fence that inserts
    # X-Forwarded-For headers that you can trust (eg Perlbal), enable this.  otherwise, don't!
    # $TRUST_X_HEADERS = 1;

    # By default, when using TRUST_X_HEADERS, all proxies using X-Forwarded-For
    # are trusted and the real client IP is found first in the list. To trust
    # only specific proxy IPs, write a sub that returns true when its input
    # is a trusted proxy IP. In that case, trusted proxies will be removed from
    # the end of X-Forwarded-For (or if supplied as the remote IP), and the
    # real client IP will be found last in the resulting list.
    # $IS_TRUSTED_PROXY = sub { $_[0] eq '192.168.1.1'; };

    # the following values allow you to control enabling your OpenID server and consumer
    # support.
    $OPENID_SERVER = 1;
    $OPENID_CONSUMER = 1;

    # how many days to store random users for; after this many days they fall out of the table.
    # high traffic sites probably want a reasonably low number, whereas lower traffic sites might
    # want to set this higher to give a larger sample of users to select from.
    $RANDOM_USER_PERIOD = 7;

    # turn on control/nav strip
    $USE_CONTROL_STRIP = 1;

    # initial settings for new users
    %USER_INIT = (
        opt_whocanreply => 'reg',
        opt_mangleemail => 'Y',
        moodthemeid => 7,
    );

    # initial userprop settings for new users
    %USERPROP_INIT = (
        opt_showmutualfriends => 1,
    );

    # remote's safe_search prop value must be greater than or equal to the defined
    # safe_search_level value in order for users with that level's content flag to be
    # filtered out of remote's search results
    #
    # e.g. remote must have a safe_search prop value of 11 or more in order to not
    # see any search results that contain adult concepts
    #
    # a safe_search value of 0 means that it shouldn't ever be filtered
    %CONTENT_FLAGS = (
        explicit => {
            safe_search_level => 1,
        },
        concepts => {
            safe_search_level => 11,
        },
    );

    # default is plain (change to 'rich' if you want RTE by default)
    $DEFAULT_EDITOR = 'plain';

    # page that 'noanon_ip' sysbanned users can access to get more information
    # on why they're banned
    # $BLOCKED_ANON_URI = '';

    # pages where we want to see captcha
    %CAPTCHA_FOR = (
        create   => 0,               # account creation
        lostinfo => 1,               # forgotten password/username
        validate_openid => 1,        # confirming email address of openid acc
        support_submit_anon => 0,    # support request without logged-in user
        anonpost => 1,               # rate-limiting on anon posts
        authpost => 0,               # rate-limiting on non-anon posts
        comment_html_anon => 1,      # HTML comments from anon commenters?
        comment_html_auth => 0,      # HTML comments from non-anon commenters?
    );
}

1;
