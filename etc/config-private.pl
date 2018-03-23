#!/usr/bin/perl
# -*-perl-*-

# THIS FILE IS INTENDED FOR EXAMPLE/DOCUMENTATION PURPOSES ONLY.
# An active site should have a customized version of this file located in ext/local/etc.

# Dreamwidth configuration file.  Copy this out of the current
# directory to ext/local/etc/config-private.pl and edit as necessary.
# This will separate your active config file from the canonical
# one under version control, and protect it from getting clobbered
# when you upgrade to the newest Dreamwidth code in the future.

# This is where you define private, site-specific configs (e.g. passwords).

{
    package LJ;

    # database info.  only the master is necessary.
    %DBINFO = (
               'master' => {  # master must be named 'master'
                   'host' => "localhost",
                   'port' => 3306,
                   'user' => 'dw',    # CHANGETHIS if on Dreamhack to dh_username
                   'pass' => 'password',    # CHANGETHIS
                   'dbname' => 'dw',    # CHANGETHIS if on Dreamhack to dreamhack_username
                   'role' => {
                       'cluster1' => 1,
                       'slow' => 1,

                       # optionally, apache write its access logs to a mysql database
                       #logs => 1,
                   },
               },
               # example of a TCP-based DB connection
               #'somehostname' => {
               #    'host' => "somehost",
               #    'port' => 1234,
               #    'user' => 'username',
               #    'pass' => 'password',
               #},
               # example of a UNIX domain-socket DB connection
               #'otherhost' => {
               #    'sock' => "$HOME/var/mysqld.sock",
               #    'user' => 'username',
               #    'pass' => 'password',
               #},
    );

    # Schwartz DB configuration
    @THESCHWARTZ_DBS = (
            {
                dsn => 'dbi:mysql:dw_schwartz;host=localhost', # CHANGETHIS if on Dreamhack to dreamhack_username instead of dw_schwartz
                user => 'dw', # CHANGETHIS if on Dreamhack to dh_username
                pass => 'password',     # CHANGETHIS
            },
        );

    # 32 vs 64 bit arch. By default everything goes to a 64 bit arch.
    # Automatically detected. Uncomment to force 32 bit arch support.
    #
    # WARNING: This must be set prior to setting up your site.  If you change it
    # later on a running site, things may go badly for you.
    #
    #$ARCH32 = "1";

    # allow changelog posting.  this allows unauthenticated posts to the changelog
    # community from the IP and users specified.  this does not work on its own,
    # you have to configure your version control server to do the posting.  see
    # cgi-bin/DW/Hooks/Changelog.pm for more information.
    %CHANGELOG = (
        enabled          => 0,
        community        => 'changelog',
        allowed_posters  => [ qw/ mark denise / ],
        allowed_ips      => [ qw/ 123.123.123.123 / ],
    );

    # example user account for FAQs. By default, [[username]] in an FAQ answer
    # will use the username of the logged-in user; however, if the viewer is
    # not logged in, this username will be used instead. (You should own this
    # account so that nobody can take it.)
    $EXAMPLE_USER_ACCOUNT = "username";

    # list of official journals, as a list of "'username' => 1" pairs
    # used to determine whether to fire off an OfficialPost notification
    # when an entry is posted; hash instead of array for efficiency
    %OFFICIAL_JOURNALS = (
        news => 1,
    );

    # the "news" journal, to be specially displayed on the front page, etc
    $NEWS_JOURNAL = "news";

    # temporary config variables to trigger special import workflow, in the form of
    #    username => 1
    # turned on for the duration of the import
    # %LJ::ALLOW_COMM_IMPORT = (
    #    examplecomm => 1,
    #);

    # %LJ::FIX_COMMENT_IMPORT = (
    #    user_with_blank_imported_comments => 1,
    #);


    # list of alternate domains that point to your site.
    @ALTERNATE_DOMAINS = (
        'ljsite.org',
        'ljsite.net',
        'ljsite.co.uk',
        'ljsite.tld',
    );

    # Set this to the IP address of your main site.  This is used for Tor exit checking.
    #$EXTERNAL_IP = '127.0.0.1';

    # Set this to the port number used for incoming SSL connections
    #$SSL_PORT = 443;

    # configuration/ID for statistics tracker modules which apply to
    # site pages (www, non-journal)
    %SITE_PAGESTAT_CONFIG = (
    #    google_analytics => 'UA-xxxxxx-x',
    );

    # Path (e.g. /bots) at which a informational page about your acceptable bot
    # policies are documented.  This URI is excluded from anti-bot measures, so
    # make sure it's as permissive as possible to allow humans in who may be
    # lazy in their typing.  For example, leave off the trailing slash (/bots
    # instead of /bots/) if your URI is a directory.
    #$BLOCKED_BOT_URI = '/bots';

    # Add any tags here that you wish to create global 'latest posts' feed groups.
    # %LATEST_TAG_FEEDS =
    #     group_names => {
    #         # short name => long name, used for the UI
    #         nnwm09 => 'NaNoWriMo 2009',
    #     },
    #
    #     tag_maps => {
    #         # tag => short name, in this case, all of the tags in the list on the
    #         # right map to the 'nnwm09' group on the left
    #         map { $_ => 'nnwm09' } ( 'nnwm09', 'nano', 'nanowrimo' ),
    #     },
    # );

    # If you want to enable DW::Stats business metrics reporting, uncomment
    # this structure and set it up. This was originally implemented to work
    # with the local dogstatsd daemon from datadog.com, but it should work
    # with any system that follows the same protocol.
    # %STATS = (
    #     host => '127.0.0.1',
    #     port => 8125,
    # );

    # If you are going to be using the external content proxy system, you should
    # define a file here that contains your private salt.
    # $PROXY_URL = "https://proxy.myhost.net";
    # $PROXY_SALT_FILE = "$HOME/etc/proxy-salt";

    # If you want to use Amazon SES (e.g. bin/worker/send-email-ses) then you
    # need to do a lot of setup on the Amazon side and then fill this out. The
    # settings are from the SMTP Settings page in SES.
    # %EMAIL_VIA_SES = (
    #     hostname => '...',
    #     username => '...',
    #     password => '...',
    # );

    # Configuration of BlobStore. This is the new storage abstraction used to
    # store any blobs (images, userpics, media, etc) that need storage. For small
    # sites/single servers, the localdisk mode is useful. For production
    # systems S3 should be used.
    # @BLOBSTORES = (
    #     # Local disk configuration, can be used to store everything on one machine
    #     localdisk => {
    #         path => "$LJ::HOME/var/blobstore",
    #     },
    #
    #     # S3 configuration, requires separate setup and maintenance of an S3
    #     # bucket with appropriate ACLs
    #     s3 => {
    #         # WARNING:
    #         # The preferred/secure method of providing access is by using IAM Roles. If
    #         # you are running Dreamwidth in EC2, please leave access_key/secret_key undef
    #         # and assign your instance a role that has the appropriate permissions.
    #         #
    #         # If you are operating outside of EC2, you can specify access keys here and
    #         # we will use them directly.
    #         access_key => undef,
    #         secret_key => undef,
    #
    #         # The name of your bucket. This is created in the S3 control panel.
    #         bucket_name => 'my-bucket-name',
    #
    #         # The name of the region in AWS nomenclature. If you're in US Standard then
    #         # this is us-east-1.
    #         region => 'us-east-1',
    #
    #         # This is used in case you have multiple DWs using the same bucket,
    #         # i.e. in our Hack setup. In that case we set the prefix to be different
    #         # per environment so each user doesn't collide. This is prefixed to the
    #         # files written. It can be undef which means don't use a prefix.
    #         # If it is defined, it should match regex [a-zA-Z0-9_-]+.
    #         prefix => undef,
    #     },
    # );
}

{
    package DW::PRIVATE;

    $DOMAIN = "ljsite.com";

    #%PAYPAL = (
    #    user => ,
    #    password => ,
    #    signature => ,
    #    email => ,
    #);

    #%YOUTUBE =(
    #    apikey => '',
    #);

    #%DBINFO = (
    #    master => {
    #        pass => ,
    #    },
    #);

    #%THESCHWARTZ_DBS = (
    #    pass => ,
    #);

    #%RECAPTCHA = (
    #    public_key  => ,
    #    private_key => ,
    #);

    #%TEXTCAPTCHA = (
    #   # this works for testing purposes.
    #   # sign up at the textcaptcha website for a key for production use
    #    api_key => "demo",
    #    timeout => 10,
    #);
}

1;
