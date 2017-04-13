#!/usr/bin/perl
# -*-perl-*-

# THIS FILE IS INTENDED FOR EXAMPLE/DOCUMENTATION PURPOSES ONLY.
# An active site should have a customized version of this file located in ext/local/etc.

# Dreamwidth configuration file.  Copy this out of the current
# directory to ext/local/etc/config-local.pl and edit as necessary.
# This will separate your active config file from the canonical
# one under version control, and protect it from getting clobbered
# when you upgrade to the newest Dreamwidth code in the future.

# This, and config-private.pl should be the only files you need to
# change to get the Dreamwidth code to run on your site. Variables
# which are set by $DW::PRIVATE::... should be configured in
# config-private.pl instead.

# Use the checkconfig.pl utility to find any other config variables
# that might not be documented here. You should be able to set config
# values here and have the DW code run; if you have to modify the
# code itself, it's a bug and you should report it.

{
    package LJ;

    # keep this enabled only if this site is a development server
    $IS_DEV_SERVER = 1;

    # change this to "1" to enable certain site content to respond securely
    $USE_SSL = 0;

    # change this to "1" to redirect all incoming connections to use HTTPS
    $USE_HTTPS_EVERYWHERE = 0;

    # home directory
    $HOME = $ENV{'LJHOME'};

    # the base domain of your site.
    $DOMAIN = $DW::PRIVATE::DOMAIN;

    # human readable name of this site as well as shortened versions
    # CHANGE THIS
    $SITENAME = "A New Dreamwidth Installation";
    $SITENAMESHORT = "YourSite";
    $SITENAMEABBREV = "YS";
    $SITECOMPANY = "YourSite's Company";
    $SITEADDRESS = "123 Main St.<br />Somewhere, XX 12345";
    $SITEADDRESSLINE = "123 Main St. Somewhere, XX 12345";

    # supported languages (defaults to qw(en) if none given)
    # First element is default language for user interface, untranslated text
    #@LANGS = qw( en_DW );

    # MemCache information, if you have MemCache servers running
    #@MEMCACHE_SERVERS = ('hostname:port');
    #$MEMCACHE_COMPRESS_THRESHOLD = 1_000; # bytes

    # optional SMTP server if it is to be used instead of sendmail
    #$SMTP_SERVER = "127.0.0.1";
    #$MAIL_TO_THESCHWARTZ = 1;

    # setup recaptcha
    %RECAPTCHA = (
            public_key  => $DW::PRIVATE::RECAPTCHA{public_key},
            private_key => $DW::PRIVATE::RECAPTCHA{private_key},
        );

    # setup textcaptcha
    %TEXTCAPTCHA = (
            api_key => $DW::PRIVATE::TEXTCAPTCHA{api_key},
    );

    # PayPal configuration.  If you want to use PayPal, uncomment this
    # section and make sure to fill in the fields at the bottom of config-private.pl.
    #%PAYPAL_CONFIG = (
    #        # express checkout URL, the token gets appended to this
    #        url       => 'https://www.sandbox.paypal.com/cgi-bin/webscr?cmd=_express-checkout&token=',
    #        api_url   => 'https://api-3t.sandbox.paypal.com/nvp',

    #        # credentials for the API
    #        user      => $DW::PRIVATE::PAYPAL{user},
    #        password  => $DW::PRIVATE::PAYPAL{password},
    #        signature => $DW::PRIVATE::PAYPAL{signature},

    #        # set this to someone who is responsible for getting emails about
    #        # various PayPal related events
    #        email     => $DW::PRIVATE::PAYPAL{email},
    #    );


    # YouTube configuration.
    # To get access  to YouTube APIs, you will need to create a Google API key.
    # Uncomment this section and make sure to fill in the fields at the bottom of config-private.pl.
    #%YOUTUBE_CONFIG = (
    #        # api URL, the token gets appended to this
    #        api_url   =>        'https://www.googleapis.com/youtube/v3/videos?id=',
    #
    #        # credentials for the API
    #        apikey      => $DW::PRIVATE::YOUTUBE{apikey},
    #);

    # if you define these, little help bubbles appear next to common
    # widgets to the URL you define:
    %HELPURL = (
        paidaccountinfo => "#",
    );

    # additional domain from which to serve the iframes for embedded content
    # for security reasons, we strongly recommend that this not be on your $DOMAIN
    $EMBED_MODULE_DOMAIN = "embed.my-other-domain.net";

    # merchandise link
    # $MERCH_URL = "https://www.zazzle.com/dreamwidth*";

    # shop/pricing configuration
    # %SHOP = (
    #    key => [ $USD, months, account type, cost in points ],
    #    prem6  => [  20,  6, 'premium', 200 ],
    #    prem12 => [  40, 12, 'premium', 400 ],
    #    paid1  => [   3,  1, 'paid', 30    ],
    #    paid2  => [   5,  2, 'paid', 50    ],
    #    paid6  => [  13,  6, 'paid', 130   ],
    #    paid12 => [  25, 12, 'paid', 250   ],
    #    seed   => [ 200, 99, 'seed', 2000   ],
    #    points => [],     # if present, sell points
    #    vgifts => [],     # if present, sell virtual gifts
    #    rename => [ 15, undef, undef, 150 ],
    #);

    # number of days to display virtual gifts on the profile - default to two weeks
    # $VGIFT_EXPIRE_DAYS = 14;

    # You can turn on/off community importing here.
    $ALLOW_COMM_IMPORTS = 0;

    # If this is defined and a number, if someone tries to import more than this many
    # comments in a single import, the error specified will be raised and the job will fail.
    $COMMENT_IMPORT_MAX = undef;
    $COMMENT_IMPORT_ERROR = "Importing more than 10,000 comments is currently disabled.";

    # privileges for various email aliases in /admin/sendmail
    # make sure these map to existing support categories on your site
    %SENDMAIL_ACCOUNTS = (
        support  => 'supportread:support',
        abuse    => 'supportread:abuse',
        accounts => 'supportread:accounts',
        antispam => 'siteadmin:spamreports',
        );

    # Set the URI for iOS to find the icon it uses for home-screen
    # bookmarks on user subdomains (or anything else rendered through
    # S2). This file is not part of the dw-free installation, and is
    # therefore disabled by default.
    #$APPLE_TOUCH_ICON = "$LJ::RELATIVE_SITEROOT/apple-touch-icon.png";
    # Similarly for the icon used by Facebook for previews on links
    #$FACEBOOK_PREVIEW_ICON = "$LJ::RELATIVE_SITEROOT/img/Swirly-d-square.png";

    # sphinx search daemon
    #@SPHINX_SEARCHD = ( '127.0.0.1', 3312 );


    # example betafeature config
#    %BETA_FEATURES = (
#        "updatepage" => {
#            start_time => 0,
#            end_time => "Inf",
#        },
#        "s2comments" => {
#            start_time => 0,
#            end_time => "Inf",
#            sitewide => 1,
#        },
#    );

    # Domains that are known to support HTTPS. This is an optimization to
    # reduce traffic to our proxy and improve the user experience.
    %KNOWN_HTTPS_SITES = map { $_ => 1 }
                         qw/ imgur.com yandex.ru xkcd.com abload.de tumblr.com
                             flickr.com staticflickr.com blogspot.com feedburner.com
                             imageshack.us levkonoe.com wikimedia.org plurk.com
                           /;

}

1;
