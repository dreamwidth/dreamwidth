#!/usr/bin/perl
use strict;

package LJ::S1w2;

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

%LJ::S1w2::viewcreator = (
    lastn => \&LJ::S1w2::create_view_lastn,
    friends => \&LJ::S1w2::create_view_friends,
    calendar => \&LJ::S1w2::create_view_calendar,
    day => \&LJ::S1w2::create_view_day,
);

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

sub current_mood_str {
    my ($pic, $moodname) = @_;

    my $ret = "";

    if ($pic) {
        $ret .= qq{<img src="$pic->{url}" align="absmiddle" width="$pic->{width}" height="$pic->{height}" vspace="1" alt="" /> };
    }
    $ret .= $moodname;

    return $ret;
}

sub prepare_event {
    my ($item, $vars, $prefix, $eventnum, $s2p) = @_;

    $s2p ||= {};

    my %date_format = %{LJ::S1w2::date_s2_to_s1($item->{time})};

    my %event = ();
    $event{'eventnum'} = $eventnum;
    $event{'itemid'} = $item->{itemid};
    $event{'datetime'} = LJ::fill_var_props($vars, "${prefix}_DATE_FORMAT", \%date_format);
    if ($item->{subject}) {
        $event{'subject'} = LJ::fill_var_props($vars, "${prefix}_SUBJECT", {
            "subject" => $item->{subject},
        });
    }

    $event{'event'} = $item->{text};
    $event{'user'} = $item->{journal}{username};

    # Special case for friends view: userpic for friend
    if ($vars->{"${prefix}_FRIENDPIC"} && $item->{userpic} && $item->{userpic}{url}) {
        $event{friendpic} = LJ::fill_var_props($vars, "${prefix}_FRIENDPIC", {
            "width" => $item->{userpic}{width},
            "height" => $item->{userpic}{height},
            "src" => $item->{userpic}{url},
        });
    }

    # Special case for friends view: per-friend configured colors
    if ($s2p && $s2p->{friends}) {
        $event{fgcolor} = $s2p->{friends}{$item->{journal}{username}}{fgcolor}{as_string};
        $event{bgcolor} = $s2p->{friends}{$item->{journal}{username}}{bgcolor}{as_string};
    }

    if ($item->{comments}{enabled}) {
        my $itemargs = "journal=".$item->{journal}{username}."&ditemid=".$item->{itemid};

        $event{'talklinks'} = LJ::fill_var_props($vars, "${prefix}_TALK_LINKS", {
            'itemid' => $item->{itemid},
            'itemargs' => $itemargs,
            'urlpost' => $item->{comments}{post_url},
            'urlread' => $item->{comments}{read_url},
            'messagecount' => $item->{comments}{count},
            'readlink' => $item->{comments}{show_readlink} ? LJ::fill_var_props($vars, "${prefix}_TALK_READLINK", {
                'urlread' => $item->{comments}{read_url},
                'messagecount' => $item->{comments}{count} == -1 ? "?" : $item->{comments}{count},
                'mc-plural-s' => $item->{comments}{count} == 1 ? "" : "s",
                'mc-plural-es' => $item->{comments}{count} == 1 ? "" : "es",
                'mc-plural-ies' => $item->{comments}{count} == 1 ? "y" : "ies",
            }) : "",
        });
    }

    LJ::prepare_currents({
        'entry' => $item,
        'vars' => $vars,
        'prefix' => $prefix,
        'event' => \%event,
    });

    if ($item->{poster}{_u}{userid} != $item->{journal}{_u}{userid}) {
        my %altposter = ();

        $altposter{'poster'} = $item->{poster}{username};
        $altposter{'owner'} = $item->{journal}{username};
        $altposter{'fgcolor'} = $event{'fgcolor'}; # Only set for friends view
        $altposter{'bgcolor'} = $event{'bgcolor'}; # Only set for friends view

        if ($item->{userpic} && $item->{userpic}->{url} && $vars->{"${prefix}_ALTPOSTER_PIC"}) {
            $altposter{'pic'} = LJ::fill_var_props($vars, "${prefix}_ALTPOSTER_PIC", {
                "src" => $item->{userpic}{url},
                "width" => $item->{userpic}{width},
                "height" => $item->{userpic}{height},
            });
        }
        $event{'altposter'} = LJ::fill_var_props($vars, "${prefix}_ALTPOSTER", \%altposter);
    }

    my $var = "${prefix}_EVENT";
    if ($item->{security} eq "private" &&
        $vars->{"${prefix}_EVENT_PRIVATE"}) { $var = "${prefix}_EVENT_PRIVATE"; }
    if ($item->{security} eq "protected" &&
        $vars->{"${prefix}_EVENT_PROTECTED"}) { $var = "${prefix}_EVENT_PROTECTED"; }

    return LJ::fill_var_props($vars, $var, \%event);
    
}

# <LJFUNC>
# class: s1
# name: LJ::S1w2::prepare_currents
# des: do all the current music/mood/weather/whatever stuff.  only used by ljviews.pl.
# args: dbarg, args
# des-args: hashref with keys: 'entry' (an S2 Entry object), 'vars' hashref with
#           keys being S1 variables and 'prefix' string which is LASTN, DAY, etc.
# </LJFUNC>
sub prepare_currents
{
    my $args = shift;

    my $datakey = $args->{'datakey'} || $args->{'itemid'}; # new || old

    my $entry = $args->{entry};

    my %currents = ();

    if (my $val = $entry->{metadata}{music}) {
        $currents{'Music'} = $val;
    }

    $currents{'Mood'} = LJ::current_mood_str($entry->{mood_icon}, $entry->{metadata}{mood});
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

# <LJFUNC>
# class: s1
# name: LJ::S1w2::date_s2_to_s1
# des: Convert an S2 Date or DateTime object into an S1 date hash.
# args: s2date
# des-s2date: the S2 date object to convert.
# </LJFUNC>
sub date_s2_to_s1
{
    my ($s2d) = @_;
    my $dayofweek = S2::Builtin::LJ::Date__day_of_week([], $s2d);
    my $am = $s2d->{hour} < 12 ? 'am' : 'pm';
    my $h12h = $s2d->{hour} > 12 ? $s2d->{hour} - 12 : $s2d->{hour};
    $h12h ||= 12; # Fix up hour 0
    return {
        'dayshort' => LJ::Lang::day_short($dayofweek),
        'daylong' => LJ::Lang::day_long($dayofweek),
        'monshort' => LJ::Lang::month_short($s2d->{month}),
        'monlong' => LJ::Lang::month_long($s2d->{month}),
        'yy' => substr($s2d->{year}, -2),
        'yyyy' => $s2d->{year},
        'm' => $s2d->{month},
        'mm' => sprintf("%02i", $s2d->{month}),
        'd' => $s2d->{day},
        'dd' => sprintf("%02i", $s2d->{day}),
        'dth' => $s2d->{day}.LJ::Lang::day_ord($s2d->{day}),
        'ap' => substr($am,1),
        'AP' => substr(uc($am),1),
        'ampm' => $am,
        'AMPM' => uc($am),
        'min' => sprintf("%02i", $s2d->{min}),
	'12h' => $h12h,
        '12hh' => sprintf("%02i", $h12h),
        '24h' => $s2d->{hour},
        '24hh' => sprintf("%02i", $s2d->{hour}),
    };
}

sub prepare_adverts_and_control_strip {
    my ($vars, $prefix, $page, $u) = @_;

    my $show_ad = LJ::run_hook('should_show_ad', {
        ctx  => "journal",
        user => $u->{user},
    });
    my $show_control_strip = LJ::run_hook('show_control_strip', {
        user => $u->{user},
    });

    # FIXME: Do I need to add the ad and control stuff to <head> here,
    # or has the S2 backend done it for me already?

    # Note: unlike the rest of this, we're not using the S2 API to do the ads or control strip,
    #  but instead just hitting the respective APIs directly.
    if ($LJ::USE_ADS && $show_ad) {
        $page->{'skyscraper_ad'} = LJ::fill_var_props($vars, "${prefix}_SKYSCRAPER_AD",
                                                            { "ad" => LJ::ads( type => "journal",
                                                                               orient => 'Journal-Badge',
                                                                               pubtext => $LJ::REQ_GLOBAL{'text_of_first_public_post'},
                                                                               user => $u->{user}) .
                                                                      LJ::ads( type => "journal",
                                                                               orient => 'Journal-Skyscraper',
                                                                               pubtext => $LJ::REQ_GLOBAL{'text_of_first_public_post'},
                                                                               user => $u->{user}), });
        $page->{'open_skyscraper_ad'}  = $vars->{"${prefix}_OPEN_SKYSCRAPER_AD"};
        $page->{'close_skyscraper_ad'} = $vars->{"${prefix}_CLOSE_SKYSCRAPER_AD"};
    }
    if ($LJ::USE_CONTROL_STRIP && $show_control_strip) {
        my $control_strip = LJ::control_strip(user => $u->{user});
        $page->{'control_strip'} = $control_strip;
    }

    return 1;
}

package LJ::S1w2;
use strict;
use lib "$LJ::HOME/cgi-bin";
use LJ::Config;
LJ::Config->load;

require "ljlang.pl";
require "cleanhtml.pl";

# the creator for the 'lastn' view:
sub create_view_lastn
{
    my ($ret, $u, $vars, $remote, $opts) = @_;

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => ($vars->{'LASTN_OPT_ITEMS'}+0) || 20,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::RecentPage($u, $remote, $opts);

    my %lastn_page = ();
    $lastn_page{'name'} = $s2p->{journal}{name};
    $lastn_page{'name-\'s'} = ($lastn_page{'name'} =~ /s$/i) ? "'" : "'s";
    $lastn_page{'username'} = $s2p->{journal}{username};
    $lastn_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                     $lastn_page{'name'} . $lastn_page{'name-\'s'} . " Journal");
    $lastn_page{'numitems'} = ($vars->{'LASTN_OPT_ITEMS'}) || 20;

    $lastn_page{'urlfriends'} = $s2p->{view_url}{friends};
    $lastn_page{'urlcalendar'} = $s2p->{view_url}{archive};

    if ($s2p->{journal}{website_url}) {
        $lastn_page{'website'} =
            LJ::fill_var_props($vars, 'LASTN_WEBSITE', {
                "url" => $s2p->{journal}{website_url},
                "name" => $s2p->{journal}{website_name} || "My Website",
            });
    }

    $lastn_page{'events'} = "";
    $lastn_page{'head'} = $s2p->{head_content};
    $lastn_page{'head'} .= LJ::res_includes();
    $lastn_page{'head'} .= $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'LASTN_HEAD'};

    my $events = \$lastn_page{'events'};

    if ($s2p->{journal}{default_pic}{url}) {
        my $pic = $s2p->{journal}{default_pic};
        $lastn_page{'userpic'} =
            LJ::fill_var_props($vars, 'LASTN_USERPIC', {
                "src" => $pic->{url},
                "width" => $pic->{width},
                "height" => $pic->{height},
            });
    }

    my $eventnum = 0;
    my $firstday = 1;
    foreach my $item (@{$s2p->{entries}}) {
        if ($item->{new_day}) {
            my %date_format = %{LJ::S1w2::date_s2_to_s1($item->{time})};
            my %new_day = ();
            foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth)) {
                $new_day{$_} = $date_format{$_};
            }
            unless ($firstday) {
                $$events .= LJ::fill_var_props($vars, "LASTN_END_DAY", {});
            }
            $$events .= LJ::fill_var_props($vars, "LASTN_NEW_DAY", \%new_day);

            $firstday = 0;
        }

        $$events .= LJ::S1w2::prepare_event($item, $vars, 'LASTN', $eventnum++);
    }

    $$events .= LJ::fill_var_props($vars, 'LASTN_END_DAY', {});

    if ($s2p->{nav}{skip}) {
        $lastn_page{'range'} =
            LJ::fill_var_props($vars, 'LASTN_RANGE_HISTORY', {
                "numitems" => $s2p->{nav}{count},
                "skip" => $s2p->{nav}{skip},
            });
    } else {
        $lastn_page{'range'} =
            LJ::fill_var_props($vars, 'LASTN_RANGE_MOSTRECENT', {
                "numitems" => $s2p->{nav}{count},
            });
    }

    #### make the skip links
    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    if ($s2p->{nav}{forward_url}) {
        $skip_f = 1;

        $skiplinks{'skipforward'} =
            LJ::fill_var_props($vars, 'LASTN_SKIP_FORWARD', {
                "numitems" => $s2p->{nav}{forward_count},
                "url" => $s2p->{nav}{forward_url},
            });
    }

    my $maxskip = $LJ::MAX_SCROLLBACK_LASTN - $vars->{'LASTN_OPT_ITEMS'};

    if ($s2p->{nav}{backward_url}) {
        $skip_b = 1;

        $skiplinks{'skipbackward'} =
            LJ::fill_var_props($vars, 'LASTN_SKIP_BACKWARD', {
                "numitems" => $s2p->{nav}{backward_count},
                "url" => $s2p->{nav}{backward_url},
            });
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

    LJ::S1w2::prepare_adverts_and_control_strip($vars, "LASTN", \%lastn_page, $u);

    $$ret = LJ::fill_var_props($vars, 'LASTN_PAGE', \%lastn_page);

    return 1;
}

# the creator for the 'friends' view:
sub create_view_friends
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $sth;

    $$ret = "";

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => ($vars->{'FRIENDS_OPT_ITEMS'}+0) || 20,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::FriendsPage($u, $remote, $opts);
    return $s2p if ref $s2p ne 'HASH';

    my %friends_page = ();
    $friends_page{'name'} = $s2p->{journal}{name};
    $friends_page{'name-\'s'} = ($friends_page{'name'} =~ /s$/i) ? "'" : "'s";
    $friends_page{'username'} = $s2p->{journal}{username};
    $friends_page{'title'} = LJ::ehtml($u->{'friendspagetitle'} ||
                                       $friends_page{'name'} . $friends_page{'name-\'s'} . " Friends");
    $friends_page{'numitems'} = ($vars->{'FRIENDS_OPT_ITEMS'}+0) || 20;

    $friends_page{'urllastn'} = $s2p->{view_url}{recent};
    $friends_page{'urlcalendar'} = $s2p->{view_url}{archive};

    if ($s2p->{journal}{website_url}) {
        $friends_page{'website'} =
            LJ::fill_var_props($vars, 'FRIENDS_WEBSITE', {
                "url" => $s2p->{journal}{website_url},
                "name" => $s2p->{journal}{website_name} || "My Website",
            });
    }

    $friends_page{'events'} = "";
    $friends_page{'head'} = $s2p->{head_content};
    $friends_page{'head'} .= LJ::res_includes();
    $friends_page{'head'} .= $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'LASTN_HEAD'};

    if ($s2p->{nav}{skip}) {
        $friends_page{'range'} =
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_HISTORY', {
                "numitems" => $s2p->{nav}{count},
                "skip" => $s2p->{nav}{skip},
            });
    } else {
        $friends_page{'range'} =
            LJ::fill_var_props($vars, 'FRIENDS_RANGE_MOSTRECENT', {
                "numitems" => $s2p->{nav}{count},
            });
    }

    #### make the skip links
    my ($skip_f, $skip_b) = (0, 0);
    my %skiplinks;

    if ($s2p->{nav}{forward_url}) {
        $skip_f = 1;

        $skiplinks{'skipforward'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_FORWARD', {
                "numitems" => $s2p->{nav}{forward_count},
                "url" => $s2p->{nav}{forward_url},
            });
    }

    if ($s2p->{nav}{backward_url}) {
        $skip_b = 1;

        $skiplinks{'skipbackward'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_BACKWARD', {
                "numitems" => $s2p->{nav}{backward_count},
                "url" => $s2p->{nav}{backward_url},
            });
    }

    ### if they're both on, show a spacer
    if ($skip_b && $skip_f) {
        $skiplinks{'skipspacer'} = $vars->{'FRIENDS_SKIP_SPACER'};
    }

    ### if either are on, put skiplinks into lastn_page
    if ($skip_b || $skip_f) {
        $friends_page{'skiplinks'} =
            LJ::fill_var_props($vars, 'FRIENDS_SKIP_LINKS', \%skiplinks);
    }

    unless (%{$s2p->{friends}}) {
        $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_NOFRIENDS', {
          "name" => $friends_page{'name'},
          "name-\'s" => $friends_page{'name-\'s'},
          "username" => $friends_page{'username'},
        });

        $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);
        return 1;
    }

    my %friends_events = ();
    my $events = \$friends_events{'events'};

    my $firstday = 1;
    my $eventnum = 0;

    foreach my $item (@{$s2p->{entries}}) {
        if ($item->{new_day}) {
            my %date_format = %{LJ::S1w2::date_s2_to_s1($item->{time})};
            my %new_day = ();
            foreach (qw(dayshort daylong monshort monlong m mm yy yyyy d dd dth)) {
                $new_day{$_} = $date_format{$_};
            }
            unless ($firstday) {
                $$events .= LJ::fill_var_props($vars, "FRIENDS_END_DAY", {});
            }
            $$events .= LJ::fill_var_props($vars, "FRIENDS_NEW_DAY", \%new_day);

            $firstday = 0;
        }

        $$events .= LJ::S1w2::prepare_event($item, $vars, 'FRIENDS', $eventnum++, $s2p);
    }

    $$events .= LJ::fill_var_props($vars, 'FRIENDS_END_DAY', {});
    $friends_page{'events'} = LJ::fill_var_props($vars, 'FRIENDS_EVENTS', \%friends_events);

    LJ::S1w2::prepare_adverts_and_control_strip($vars, "FRIENDS", \%friends_page, $u);

    $$ret .= LJ::fill_var_props($vars, 'FRIENDS_PAGE', \%friends_page);

    return 1;
}

# the creator for the 'calendar' view:
sub create_view_calendar
{
    my ($ret, $u, $vars, $remote, $opts) = @_;

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => $vars->{'LASTN_OPT_ITEMS'}+0,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::YearPage($u, $remote, $opts);

    my $user = $u->{'user'};

    my %calendar_page = ();
    $calendar_page{'name'} = $s2p->{journal}{name};
    $calendar_page{'name-\'s'} = ($calendar_page{'name'} =~ /s$/i) ? "'" : "'s";
    $calendar_page{'username'} = $user;
    $calendar_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                     $calendar_page{'name'} . $calendar_page{'name-\'s'} . " Journal");

    $calendar_page{'urlfriends'} = $s2p->{view_url}{friends};
    $calendar_page{'urllastn'} = $s2p->{view_url}{recent};

    $calendar_page{'head'} = $s2p->{head_content};
    $calendar_page{'head'} .= LJ::res_includes();
    $calendar_page{'head'} .= $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'CALENDAR_HEAD'};

    if ($s2p->{journal}{website_url}) {
        $calendar_page{'website'} = LJ::fill_var_props($vars, 'CALENDAR_WEBSITE', {
            "url" => $s2p->{journal}{website_url},
            "name" => $s2p->{journal}{website_name} || "My Website",
        });
    }

    $calendar_page{'months'} = "";
    my $months = \$calendar_page{'months'};

    if (scalar(@{$s2p->{years}}) > 1) {
        my $yearlinks = "";
        foreach my $year ($vars->{CALENDAR_SORT_MODE} eq 'reverse' ? reverse @{$s2p->{years}} : @{$s2p->{years}}) {
            my $yy = sprintf("%02d", $year->{year} % 100);
            my $url = $year->{url};
            unless ($year->{displayed}) {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINK', {
                    "url" => $url, "yyyy" => $year->{year}, "yy" => $yy });
            } else {
                $yearlinks .= LJ::fill_var_props($vars, 'CALENDAR_YEAR_DISPLAYED', {
                    "yyyy" => $year->{year}, "yy" => $yy });
            }
        }
        $calendar_page{'yearlinks'} = LJ::fill_var_props($vars, 'CALENDAR_YEAR_LINKS', { "years" => $yearlinks });
    }

    $$months .= LJ::fill_var_props($vars, 'CALENDAR_NEW_YEAR', {
        'yyyy' => $s2p->{year},
        'yy' => substr($s2p->{year}, 2, 2),
    });

    foreach my $month ($vars->{CALENDAR_SORT_MODE} eq 'reverse' ? reverse @{$s2p->{months}} : @{$s2p->{months}}) {
	next unless $month->{has_entries};

        my %calendar_month = ();
        $calendar_month{'monlong'} = LJ::Lang::month_long($month->{month});
        $calendar_month{'monshort'} = LJ::Lang::month_short($month->{month});
        $calendar_month{'yyyy'} = $month->{year};
        $calendar_month{'yy'} = substr($calendar_month{'yyyy'}, 2, 2);
        $calendar_month{'weeks'} = "";
        $calendar_month{'urlmonthview'} = $month->{url};
        my $weeks = \$calendar_month{'weeks'};

	foreach my $week (@{$month->{weeks}}) {
            my %calendar_week = ();

            $calendar_week{emptydays_beg} = LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', { "numempty" => $week->{pre_empty} }) if $week->{pre_empty};
            $calendar_week{emptydays_end} = LJ::fill_var_props($vars, 'CALENDAR_EMPTY_DAYS', { "numempty" => $week->{post_empty} }) if $week->{post_empty};
            $calendar_week{days} = "";
            my $days = \$calendar_week{days};

            foreach my $day (@{$week->{days}}) {
                my %calendar_day = ();

                $calendar_day{d} = $day->{date}{day};
                $calendar_day{eventcount} = $day->{num_entries};
                $calendar_day{dayevent} = LJ::fill_var_props($vars, 'CALENDAR_DAY_EVENT', {
                    eventcount => $day->{num_entries},
                    dayurl => $day->{url},
                }) if $day->{num_entries};
                $calendar_day{daynoevent} = LJ::fill_var_props($vars, 'CALENDAR_DAY_NOEVENT', {}) unless $day->{num_entries};

                $$days .= LJ::fill_var_props($vars, 'CALENDAR_DAY', \%calendar_day);
            }

            $$weeks .= LJ::fill_var_props($vars, 'CALENDAR_WEEK', \%calendar_week);
        }
        $$months .= LJ::fill_var_props($vars, 'CALENDAR_MONTH', \%calendar_month);
    }

    LJ::S1w2::prepare_adverts_and_control_strip($vars, "CALENDAR", \%calendar_page, $u);

    $$ret .= LJ::fill_var_props($vars, 'CALENDAR_PAGE', \%calendar_page);

    return 1;
}

# the creator for the 'day' view:
sub create_view_day
{
    my ($ret, $u, $vars, $remote, $opts) = @_;
    my $sth;

    # Fake S2 context. Bit of a hack.
    my $s2ctx = [];
    $s2ctx->[S2::PROPS] = {
        "page_recent_items" => $vars->{'LASTN_OPT_ITEMS'}+0,
    };
    $opts->{ctx} = $s2ctx;

    my $s2p = LJ::S2::DayPage($u, $remote, $opts);

    my $user = $u->{'user'};

    my %day_page = ();
    $day_page{'name'} = $s2p->{journal}{name};
    $day_page{'name-\'s'} = ($day_page{'name'} =~ /s$/i) ? "'" : "'s";
    $day_page{'username'} = $user;
    $day_page{'title'} = LJ::ehtml($u->{'journaltitle'} ||
                                   $day_page{'name'} . $day_page{'name-\'s'} . " Journal");

    $day_page{'urlfriends'} = $s2p->{view_url}{friends};
    $day_page{'urllastn'} = $s2p->{view_url}{recent};
    $day_page{'urlcalendar'} = $s2p->{view_url}{archive};

    $day_page{'head'} = $s2p->{head_content};
    $day_page{'head'} .= LJ::res_includes();
    $day_page{'head'} .= $vars->{'GLOBAL_HEAD'} . "\n" . $vars->{'DAY_HEAD'};

    if ($s2p->{journal}{website_url}) {
        $day_page{'website'} = LJ::fill_var_props($vars, 'DAY_WEBSITE', {
            "url" => $s2p->{journal}{website_url},
            "name" => $s2p->{journal}{website_name} || "My Website",
        });
    }

    my $date = LJ::S1w2::date_s2_to_s1($s2p->{date});
    map { $day_page{$_} = $date->{$_} } qw(dayshort daylong monshort monlong yy yyyy m mm d dd dth);

    $day_page{'prevday_url'} = $s2p->{prev_url};
    $day_page{'nextday_url'} = $s2p->{next_url};

    $day_page{'events'} = "";
    my $events = \$day_page{'events'};

    my $entries = $s2p->{entries};
    if (@$entries) {
        my $inevents = "";
        foreach my $item ($vars->{DAY_SORT_MODE} eq 'reverse' ? reverse @$entries : @$entries) {
            $inevents .= LJ::S1w2::prepare_event($item, $vars, 'DAY');
        }
        $$events = LJ::fill_var_props($vars, 'DAY_EVENTS', { events => $inevents });
    }
    else {
        $$events = LJ::fill_var_props($vars, 'DAY_NOEVENTS', {});
    }

    LJ::S1w2::prepare_adverts_and_control_strip($vars, "DAY", \%day_page, $u);

    $$ret .= LJ::fill_var_props($vars, 'DAY_PAGE', \%day_page);
    return 1;
}

# Temporary utility function called by LJ::make_journal in LJ/User.pm
# to make a diff between pure S1 output and S1w2 output.
sub _make_diff {
    my ($pure, $mine) = @_;
    
    # This is really ghetto, hits the filesystem and
    # won't work for two concurrent requests, but
    # it works well enough for a single-user dev server.
    my $tn1 = "/tmp/s1plain";
    my $tn2 = "/tmp/s1w2";
    open(S1PLAIN, '>', $tn1);
    open(S1w2, '>', $tn2);
    print S1PLAIN $pure;
    print S1w2 $mine;
    close(S1w2);
    close(S1PLAIN);
    my $diff = `diff -u $tn1 $tn2`;
    unlink($tn1);
    unlink($tn2);
    return $diff;    
}

1;

