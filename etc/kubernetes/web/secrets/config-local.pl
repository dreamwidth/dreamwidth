#!/usr/bin/perl
{
    package LJ;

    # keep this enabled only if this site is a development server
    $IS_DEV_SERVER = 1;

    # home directory
    $HOME = $ENV{'LJHOME'};

    # the base domain of your site.
    $DOMAIN = 'dw.local';

    # human readable name of this site as well as shortened versions
    # CHANGE THIS
    $SITENAME = "Dreamwidth Studios";
    $SITENAMESHORT = "Dreamwidth";
    $SITENAMEABBREV = "DW";
    $SITECOMPANY = "Dreamwidth Studios, LLC";

    # supported languages (defaults to qw(en) if none given)
    # First element is default language for user interface, untranslated text
    @LANGS = qw( en_DW );

    # MemCache information, if you have MemCache servers running
    #@MEMCACHE_SERVERS = ('memcached:11211');

    # optional SMTP server if it is to be used instead of sendmail
    $SMTP_SERVER = "localhost";
    $MAIL_TO_THESCHWARTZ = 1;

    # if you define these, little help bubbles appear next to common
    # widgets to the URL you define:
    %HELPURL = (
        paidaccountinfo => "https://www.dreamwidth.org/support/faqbrowse.bml?faqid=4",
    );

    # Configuration for suggestions community & adminbot
    $SUGGESTIONS_COMM = "dw_suggestions";
    $SUGGESTIONS_USER = "suggestions_bot";

    # 404 page
    # Uncomment if you don't want the (dw-free) default, 404-error.bml
    # (Note: you need to provide your own 404-error-local.bml)
    $PAGE_404 = "404-error-local.bml";

    # merchandise link
    $MERCH_URL = "https://www.zazzle.com/dreamwidth*";

    # shop/pricing configuration
    %SHOP = (
        # key => [ $USD, months, account type, cost in points ],
        prem6  => [  20,  6, 'premium', 200 ],
        prem12 => [  40, 12, 'premium', 400 ],
        paid1  => [   3,  1, 'paid', 30    ],
        paid2  => [   5,  2, 'paid', 50    ],
        paid6  => [  13,  6, 'paid', 130   ],
        paid12 => [  25, 12, 'paid', 250   ],
        seed   => [ 200, 99, 'seed', 2000   ],
        points => [],
        rename => [ 15, undef, undef, 150 ],
    #    vgifts => [],     # if present, sell virtual gifts
    );

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
    $APPLE_TOUCH_ICON = "$LJ::RELATIVE_SITEROOT/apple-touch-icon.png";
    # Similarly for the icon used by Facebook for previews on links
    $FACEBOOK_PREVIEW_ICON = "$LJ::RELATIVE_SITEROOT/img/Swirly-d-square.png";

    # Needed for concatenation of static resources (see bin/build-static.sh)
    $STATDOCS = "$HOME/build/static";
}

1;
