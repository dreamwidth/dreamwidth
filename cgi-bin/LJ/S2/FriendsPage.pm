#!/usr/bin/perl
#
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


use strict;
package LJ::S2;
use DW::Logic::AdultContent;

sub FriendsPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts);
    $p->{'_type'} = "FriendsPage";
    $p->{view} = $opts->{view} eq "network" ? "network" : "read";
    $p->{'entries'} = [];
    $p->{'friends'} = {};
    $p->{'friends_title'} = LJ::ehtml($u->{'friendspagetitle'});
    $p->{'friends_subtitle'} = LJ::ehtml($u->{'friendspagesubtitle'});

    # Add a friends-specific XRDS reference
    $p->{'head_content'} .= qq{<meta http-equiv="X-XRDS-Location" content="}.LJ::ehtml($u->journal_base).qq{/data/yadis/friends" />\n};

    LJ::need_res( LJ::S2::tracking_popup_js() );

    # include JS for quick reply, icon browser, and ajax cut tag
    my $handle_with_siteviews = 0;  # not an option for FriendsPage?
    LJ::Talk::init_s2journal_js( iconbrowser => $remote && $remote->can_use_userpic_select,
                                 siteskin => $handle_with_siteviews, lastn => 1 );

    my $collapsed = BML::ml( 'widget.cuttag.collapsed' );
    my $expanded = BML::ml( 'widget.cuttag.expanded' );
    my $collapseAll = BML::ml( 'widget.cuttag.collapseAll' );
    my $expandAll = BML::ml( 'widget.cuttag.expandAll' );
    $p->{'head_content'} .= qq[
  <script type='text/javascript'>
  expanded = '$expanded';
  collapsed = '$collapsed';
  collapseAll = '$collapseAll';
  expandAll = '$expandAll';
  </script>
    ];

    # init shortcut js if selected
    LJ::Talk::init_s2journal_shortcut_js( $remote, $p );

    my $sth;
    my $user = $u->{'user'};

    # see how often the remote user can reload this page.
    # "friendsviewupdate" time determines what granularity time
    # increments by for checking for new updates
    my $nowtime = time();

    # update delay specified by "friendsviewupdate"
    my $newinterval = LJ::Capabilities::get_cap_min( $remote, "friendsviewupdate" ) || 1;

    # when are we going to say page was last modified?  back up to the
    # most recent time in the past where $time % $interval == 0
    my $lastmod = $nowtime;
    $lastmod -= $lastmod % $newinterval;

    # see if they have a previously cached copy of this page they
    # might be able to still use.
    if ($opts->{'header'}->{'If-Modified-Since'}) {
        my $theirtime = LJ::http_to_time($opts->{'header'}->{'If-Modified-Since'});

        # send back a 304 Not Modified if they say they've reloaded this
        # document in the last $newinterval seconds:
        my $uniq = BML::get_request()->notes->{uniq};
        if ($theirtime > $lastmod && !($uniq && LJ::MemCache::get("loginout:$uniq"))) {
            $opts->{'handler_return'} = 304;
            return 1;
        }
    }
    $opts->{'headers'}->{'Last-Modified'} = LJ::time_to_http($lastmod);

    my $get = $opts->{'getargs'};

    my $ret;

    $remote->preload_props( "opt_nctalklinks", "opt_stylemine", "opt_imagelinks", "opt_imageundef", "opt_cut_disable_reading" ) if $remote;

    # load options for image links
    my ($maximgwidth, $maximgheight) = (undef, undef);
    ($maximgwidth, $maximgheight) = ($1, $2)
        if ( $remote && $remote->equals( $u ) && $remote->{opt_imagelinks} &&
             $remote->{opt_imagelinks} =~ m/^(\d+)\|(\d+)$/ );

    ## never have spiders index friends pages (change too much, and some
    ## people might not want to be indexed)
    $p->{'head_content'} .= LJ::robot_meta_tags();

    my $itemshow = S2::get_property_value($opts->{'ctx'}, "num_items_reading")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{skip} ? $get->{skip} + 0 : 0;
    my $maxskip = ($LJ::MAX_SCROLLBACK_FRIENDS || 1000) - $itemshow;
    if ($skip > $maxskip) { $skip = $maxskip; }
    if ($skip < 0) { $skip = 0; }
    my $itemload = $itemshow+$skip;
    my $get_date = $get->{date} || '';

    my $events_date   = ( $get_date =~ m!^(\d{4})-(\d\d)-(\d\d)$! )
                        ? LJ::mysqldate_to_time("$1-$2-$3")
                        : 0;

    # allow toggling network mode
    $p->{friends_mode} = 'network'
        if $opts->{view} eq 'network';

    # try to get a group name if they specified one
    my $group_name = '';
    if ( $group_name = $opts->{pathextra} ) {
        $group_name =~ s!^/!!;
        $group_name =~ s!/$!!;
        $group_name = LJ::durl( $group_name );
    }

    # try to get a content filter, try a specified group name first, fall back to Default,
    # and failing that try Default View (for the old school diehards)
    my $cf = $u->content_filters( name => $group_name || "Default" ) ||
             $u->content_filters( name => "Default View" );

    my $filter;
    if ( $opts->{securityfilter} ) {
        my $filter = $u->trust_groups( id => $opts->{securityfilter} );
        $p->{filter_active} = 1;
        if ( defined $filter ) {
            $p->{filter_name} = $filter->{groupname};
        } else {
            # something went wrong; just use the group number
            $p->{filter_name} = $opts->{securityfilter};
        }
    } else {
    # but we can't just use a filter, we have to make sure the person is allowed to
        if ( ( ! defined $get->{filter} || $get->{filter} ne "0" )
                && $cf && ( $u->equals( $remote ) || $cf->public ) ) {
            $filter = $cf;

        # if we couldn't use the group, then we can throw an error, but ONLY IF they specified
        # a group name manually.  if we tried to load the default on our own, don't toss an
        # error as that would let a user disable their friends page.
        } elsif ( $group_name ) {
            $opts->{badfriendgroup} = 1;  # nobiscuit
            return 1;
        }
    }

    if ( $filter && !$filter->is_default ) {
        $p->{filter_active} = 1;
        $p->{filter_name} = $filter->name;
    }

    ## load the itemids
    my ( %friends, %friends_row, %idsbycluster );
    my @items = $u->watch_items(
        itemshow          => $itemshow + 1,
        skip              => $skip,
        content_filter    => $filter,
        friends_u         => \%friends,
        friends           => \%friends_row,
        idsbycluster      => \%idsbycluster,
        showtypes         => $get->{show},
        friendsoffriends  => $opts->{view} eq 'network',
        security          => $opts->{securityfilter},
        dateformat        => 'S2',
        events_date       => $events_date,
    );

    my $is_prev_exist = scalar @items - $itemshow > 0 ? 1 : 0;
    pop @items if $is_prev_exist;

    while ($_ = each %friends) {
        # we expect fgcolor/bgcolor to be in here later
        $friends{$_}->{'fgcolor'} = $friends_row{$_}->{'fgcolor'} || '#ffffff';
        $friends{$_}->{'bgcolor'} = $friends_row{$_}->{'bgcolor'} || '#000000';
    }

    return $p unless %friends;

    my %posters;
    {
        my @posterids;
        foreach my $item (@items) {
            next if $friends{$item->{'posterid'}};
            push @posterids, $item->{'posterid'};
        }
        LJ::load_userids_multiple([ map { $_ => \$posters{$_} } @posterids ])
            if @posterids;
    }

    my $eventnum = 0;
    my $hiddenentries = 0;
    $opts->{cut_disable} = ( $remote && $remote->prop( 'opt_cut_disable_reading' ) );

  ENTRY:
    foreach my $item (@items)
    {
        my ($friendid, $posterid, $itemid, $anum) =
            map { $item->{$_} } qw(ownerid posterid itemid anum);

        # $fr = journal posted in, can be community
        my $fr = $friends{$friendid};
        $p->{friends}->{$fr->{user}} ||= Friend($fr);

        my $ditemid = $itemid * 256 + $anum;
        my $entry_obj = LJ::Entry->new( $fr, ditemid => $ditemid );

        # get the poster user
        my $po = $posters{$posterid} || $friends{$posterid};

        # don't allow posts from suspended users or suspended posts
        if ($po->is_suspended || ($entry_obj && $entry_obj->is_suspended_for($remote))) {
            $hiddenentries++; # Remember how many we've skipped for later
            next ENTRY;
        }

        # reading page might need placeholder images
        $opts->{cleanhtml_extra} = {
            maximgheight => $maximgheight,
            maximgwidth =>  $maximgwidth,
            imageplaceundef => $remote ? $remote->{'opt_imageundef'} : undef
        };

        # make S2 entry
        my $entry = Entry_from_entryobj( $u, $entry_obj, $opts );

        $entry->{_ymd} = join('-', map { $entry->{'time'}->{$_} } qw(year month day));

        push @{$p->{'entries'}}, $entry;
        $eventnum++;

        LJ::Hooks::run_hook('notify_event_displayed', $entry_obj);
    } # end while

    # set the new_day and end_day members.
    if ($eventnum) {
        for (my $i = 0; $i < $eventnum; $i++) {
            my $entry = $p->{'entries'}->[$i];
            $entry->{'new_day'} = 1;
            my $last = $i;
            for (my $j = $i+1; $j < $eventnum; $j++) {
                my $ej = $p->{'entries'}->[$j];
                if ($ej->{'_ymd'} eq $entry->{'_ymd'}) {
                    $last = $j;
                }
            }
            $p->{'entries'}->[$last]->{'end_day'} = 1;
            $i = $last;
        }
    }

    # make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
        'count' => $eventnum,
    };

    my $base = "$u->{_journalbase}/$opts->{view}";
    $base .= "/" . LJ::eurl( $group_name )
        if $group_name;

    # these are the same for both previous and next links
    my %linkvars;
    $linkvars{show} = $get->{show} if defined $get->{show} && $get->{show} =~ /^\w+$/;
    $linkvars{date} = $get->{date} if $get->{date} && $u->can_use_daily_readpage;
    $linkvars{filter} = $get->{filter} + 0 if defined $get->{filter};

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my $newskip = $skip - $itemshow;
        if ($newskip > 0) { $linkvars{'skip'} = $newskip; }
        else { $newskip = 0; }
        $nav->{'forward_url'} = LJ::S2::make_link( $base, \%linkvars );
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_count'} = $itemshow;
        $p->{head_content} .= qq#<link rel="next" href="$nav->{forward_url}" />\n#;
    } elsif ( $linkvars{date} ) {
        # next day when viewing by date
        my %nextvars = %linkvars;
        my $nexttime = LJ::mysqldate_to_time( $linkvars{date} ) + 86400;
        unless ( $nexttime > time ) {
            $nextvars{date} = LJ::mysql_date( $nexttime );
            $nav->{'forward_url'} = LJ::S2::make_link( $base, \%nextvars );
            $p->{head_content} .= qq#<link rel="next" href="$nav->{forward_url}" />\n#;
        }
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown
    ## on the page, but who cares about that ... well, we do now...)
    # Must remember to count $hiddenentries or we'll have no skiplinks when > 1
    unless (($eventnum + $hiddenentries) != $itemshow || $skip == $maxskip || !$is_prev_exist) {
        my $newskip = $skip + $itemshow;
        $linkvars{'skip'} = $newskip;
        $nav->{'backward_url'} = LJ::S2::make_link( $base, \%linkvars );
        $nav->{'backward_skip'} = $newskip;
        $nav->{'backward_count'} = $itemshow;
        $p->{head_content} .= qq#<link rel="prev" href="$nav->{backward_url}" />\n#;
    } elsif ( $linkvars{date} ) {
        # prev day when viewing by date
        my %prevvars = %linkvars;
        my $prevtime = LJ::mysqldate_to_time( $linkvars{date} ) - 86400;
        $prevvars{date} = LJ::mysql_date( $prevtime );
        delete $prevvars{skip};  # from forward case; not used here
        $nav->{'backward_url'} = LJ::S2::make_link( $base, \%prevvars );
        $p->{head_content} .= qq#<link rel="prev" href="$nav->{backward_url}" />\n#;
    }

    $p->{nav} = $nav;

    return $p;
}

1;
