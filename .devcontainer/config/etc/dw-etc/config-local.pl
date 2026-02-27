#!/usr/bin/perl

# Local configuration for the .devcontainer; this should work out of the box.
# You should not need to modify this file.
#
# This is where you define local, site-specific configs (e.g. general configs
# that you might share with someone else developing on your site).
#
# config-private.pl will load first, so you can depend on it.

{
    package LJ;

    # keep this enabled only if this site is a development server and
    # operating inside a development container (which disables all of the
    # domain management/redirect logic)
    $IS_DEV_SERVER = 1;
    $IS_DEV_CONTAINER = 1;

    # human readable name of this site as well as shortened versions
    $SITENAME = "DW Devcontainer";
    $SITENAMESHORT = "DWDev";
    $SITENAMEABBREV = "DW";
    $SITECOMPANY = "DWDev Company";
    $SITEADDRESS = "123 Main St.<br />Somewhere, XX 12345";
    $SITEADDRESSLINE = "123 Main St. Somewhere, XX 12345";

    # supported languages (defaults to qw(en) if none given)
    # First element is default language for user interface, untranslated text
    @LANGS = qw( en_DW );

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
        'layout' => 'ciel/layout',
        'theme' => 'ciel/indil',
    };
}


# Enable shop point transfers
%LJ::SHOP = ( points => [] );
1;
