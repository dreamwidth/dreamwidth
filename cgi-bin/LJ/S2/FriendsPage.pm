#!/usr/bin/perl
#

use strict;
package LJ::S2;
use Class::Autouse qw/LJ::ContentFlag/;

sub FriendsPage
{
    my ($u, $remote, $opts) = @_;

    # Check if we should redirect due to a bad password
    $opts->{'redir'} = LJ::bad_password_redirect({ 'returl' => 1 });
    return 1 if $opts->{'redir'};

    my $p = Page($u, $opts);
    $p->{'_type'} = "FriendsPage";
    $p->{'view'} = "friends";
    $p->{'entries'} = [];
    $p->{'friends'} = {};
    $p->{'friends_title'} = LJ::ehtml($u->{'friendspagetitle'});
    $p->{'filter_active'} = 0;
    $p->{'filter_name'} = "";

    # Add a friends-specific XRDS reference
    $p->{'head_content'} .= qq{<meta http-equiv="X-XRDS-Location" content="}.LJ::ehtml($u->journal_base).qq{/data/yadis/friends" />\n};

    my $sth;
    my $user = $u->{'user'};

    # see how often the remote user can reload this page.
    # "friendsviewupdate" time determines what granularity time
    # increments by for checking for new updates
    my $nowtime = time();

    # update delay specified by "friendsviewupdate"
    my $newinterval = LJ::get_cap_min($remote, "friendsviewupdate") || 1;

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

    LJ::load_user_props( $remote, "opt_nctalklinks", "opt_stylemine", "opt_imagelinks", "opt_imageundef", "opt_ljcut_disable_friends" );

    # load options for image links
    my ($maximgwidth, $maximgheight) = (undef, undef);
    ($maximgwidth, $maximgheight) = ($1, $2)
        if ($remote && $remote->{'userid'} == $u->{'userid'} &&
            $remote->{'opt_imagelinks'} =~ m/^(\d+)\|(\d+)$/);

    ## never have spiders index friends pages (change too much, and some
    ## people might not want to be indexed)
    $p->{'head_content'} .= LJ::robot_meta_tags();

    my $itemshow = S2::get_property_value($opts->{'ctx'}, "num_items_reading")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{'skip'}+0;
    my $maxskip = ($LJ::MAX_SCROLLBACK_FRIENDS || 1000) - $itemshow;
    if ($skip > $maxskip) { $skip = $maxskip; }
    if ($skip < 0) { $skip = 0; }
    my $itemload = $itemshow+$skip;

    my $filter;
    my $group_name    = '';
    my $common_filter = 1;
    my $events_date   = ($get->{date} =~ m!^(\d{4})-(\d\d)-(\d\d)$!)
                        ? LJ::mysqldate_to_time("$1-$2-$3")
                        : 0;

    if (defined $get->{'filter'} && $remote && $remote->{'user'} eq $user) {
        $filter = $get->{'filter'};
        $common_filter = 0;
        $p->{'filter_active'} = 1;
        $p->{'filter_name'} = "";
    } else {

        # Show group or day log
        if ($opts->{'pathextra'}) {
            $group_name = $opts->{'pathextra'};
            $group_name =~ s!^/!!;
            $group_name =~ s!/$!!;

            if ($group_name) {
                $group_name    = LJ::durl($group_name);
                $common_filter = 0;

                $p->{'filter_active'} = 1;
                $p->{'filter_name'}   = LJ::ehtml($group_name);
            }
        }

# TODO(mark): WTF broke this, as we no longer use friend groups for watching
#             and therefore have to implement watch groups.  bug #166
        my $grp = {};#LJ::get_friend_group($u, { 'name' => $group_name || "Default View" });
        my $bit = $grp->{'groupnum'};
        my $public = $grp->{'is_public'};
        if ($bit && ($public || ($remote && $remote->{'user'} eq $user))) {
            $filter = (1 << $bit);
        } elsif ($group_name){
            $opts->{'badfriendgroup'} = 1;
            return 1;
        }
    }

    if ($opts->{'view'} eq "network") {
        $p->{'friends_mode'} = "network";
    }

    ## load the itemids
    my %friends;
    my %friends_row;
    my %idsbycluster;
    my @items = $u->watch_items(
        remote            => $remote,
        itemshow          => $itemshow,
        skip              => $skip,
#        filter            => $filter,
        common_filter     => $common_filter,
        friends_u         => \%friends,
        friends           => \%friends_row,
        idsbycluster      => \%idsbycluster,
        showtypes         => $get->{show},
        friendsoffriends  => $opts->{view} eq 'network',
        dateformat        => 'S2',
        events_date       => $events_date,
    );

    while ($_ = each %friends) {
        # we expect fgcolor/bgcolor to be in here later
        $friends{$_}->{'fgcolor'} = $friends_row{$_}->{'fgcolor'} || '#ffffff';
        $friends{$_}->{'bgcolor'} = $friends_row{$_}->{'bgcolor'} || '#000000';
    }

    return $p unless %friends;

    ### load the log properties
    my %logprops = ();  # key is "$owneridOrZero $[j]itemid"
    LJ::load_log_props2multi(\%idsbycluster, \%logprops);

    # load the text of the entries
    my $logtext = LJ::get_logtext2multi(\%idsbycluster);

    # load tags on these entries
    my $logtags = LJ::Tags::get_logtagsmulti(\%idsbycluster);

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

    my %objs_of_picid;
    my @userpic_load;

    my %lite;   # posterid -> s2_UserLite
    my $get_lite = sub {
        my $id = shift;
        return $lite{$id} if $lite{$id};
        return $lite{$id} = UserLite($posters{$id} || $friends{$id});
    };

    my $eventnum = 0;
    my $hiddenentries = 0;
  ENTRY:
    foreach my $item (@items)
    {
        my ($friendid, $posterid, $itemid, $security, $allowmask, $alldatepart) =
            map { $item->{$_} } qw(ownerid posterid itemid security allowmask alldatepart);

        my $fr = $friends{$friendid};
        $p->{'friends'}->{$fr->{'user'}} ||= Friend($fr);

        my $clusterid = $item->{'clusterid'}+0;
        my $datakey = "$friendid $itemid";

        my $replycount = $logprops{$datakey}->{'replycount'};
        my $subject = $logtext->{$datakey}->[0];
        my $text = $logtext->{$datakey}->[1];
        if ($get->{'nohtml'}) {
            # quote all non-LJ tags
            $subject =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
            $text    =~ s{<(?!/?lj)(.*?)>} {&lt;$1&gt;}gi;
        }

        if ($LJ::UNICODE && $logprops{$datakey}->{'unknown8bit'}) {
            LJ::item_toutf8($friends{$friendid}, \$subject, \$text, $logprops{$datakey});
        }

        my ($friend, $poster);
        $friend = $poster = $friends{$friendid}->{'user'};

        LJ::CleanHTML::clean_subject(\$subject) if $subject;

        my $ditemid = $itemid * 256 + $item->{'anum'};
        my $entry_obj = LJ::Entry->new($friends{$friendid}, ditemid => $ditemid);

        my $stylemine = "";
        $stylemine .= "style=mine" if $remote && $remote->{'opt_stylemine'} &&
                                      $remote->{'userid'} != $friendid;

        my $suspend_msg = $entry_obj && $entry_obj->should_show_suspend_msg_to($remote) ? 1 : 0;
        LJ::CleanHTML::clean_event(\$text, { 'preformatted' => $logprops{$datakey}->{'opt_preformatted'},
                                             'cuturl' => LJ::item_link($friends{$friendid}, $itemid, $item->{'anum'}, $stylemine),
                                             'maximgwidth' => $maximgwidth,
                                             'maximgheight' => $maximgheight,
                                             'imageplaceundef' => $remote->{'opt_imageundef'},
                                             'ljcut_disable' => $remote->{'opt_ljcut_disable_friends'},
                                             'suspend_msg' => $suspend_msg,
                                             'unsuspend_supportid' => $suspend_msg ? $entry_obj->prop("unsuspend_supportid") : 0, });
        LJ::expand_embedded($friends{$friendid}, $ditemid, $remote, \$text);

        $text = LJ::ContentFlag->transform_post(post => $text, journal => $friends{$friendid},
                                                remote => $remote, entry => $entry_obj);

        my $userlite_poster = $get_lite->($posterid);
        my $userlite_journal = $get_lite->($friendid);

        # get the poster user
        my $po = $posters{$posterid} || $friends{$posterid};

        # don't allow posts from suspended users or suspended posts
        if ($po->{'statusvis'} eq 'S' || ($entry_obj && $entry_obj->is_suspended_for($remote))) {
            $hiddenentries++; # Remember how many we've skipped for later
            next ENTRY;
        }

        my $eobj = LJ::Entry->new($friends{$friendid}, ditemid => $ditemid);

        # do the picture
        my $picid = 0;
        my $picu = undef;
        if ($friendid != $posterid && S2::get_property_value($opts->{ctx}, 'use_shared_pic')) {
            # using the community, the user wants to see shared pictures
            $picu = $friends{$friendid};

            # use shared pic for community
            $picid = $friends{$friendid}->{defaultpicid};
        } else {
            # we're using the poster for this picture
            $picu = $po;

            # check if they specified one
            $picid = $eobj->userpic ? $eobj->userpic->picid : 0;
        }

        my $nc = "";
        $nc .= "nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};

        my $journalbase = LJ::journal_base($friends{$friendid});
        my $permalink = $eobj->url;
        my $readurl = LJ::Talk::talkargs($permalink, $nc, $stylemine);
        my $posturl = LJ::Talk::talkargs($permalink, "mode=reply", $stylemine);

        my $comments = CommentInfo({
            'read_url' => $readurl,
            'post_url' => $posturl,
            'count' => $replycount,
            'maxcomments' => ($replycount >= LJ::get_cap($u, 'maxcomments')) ? 1 : 0,
            'enabled' => ($friends{$friendid}->{'opt_showtalklinks'} eq "Y" &&
                          ! $logprops{$datakey}->{'opt_nocomments'}) ? 1 : 0,
            'screened' => ($logprops{$datakey}->{'hasscreened'} && $remote &&
                           ($remote->{'user'} eq $fr->{'user'} || LJ::can_manage($remote, $fr))) ? 1 : 0,
        });
        $comments->{show_postlink} = $comments->{enabled};
        $comments->{show_readlink} = $comments->{enabled} && ($replycount || $comments->{screened});

        my $moodthemeid = $u->{'opt_forcemoodtheme'} eq 'Y' ?
            $u->{'moodthemeid'} : $friends{$friendid}->{'moodthemeid'};

        my @taglist;
        while (my ($kwid, $kw) = each %{$logtags->{$datakey} || {}}) {
            push @taglist, Tag($friends{$friendid}, $kwid => $kw);
        }
        LJ::run_hooks('augment_s2_tag_list', u => $u, jitemid => $itemid, tag_list => \@taglist);
        @taglist = sort { $a->{name} cmp $b->{name} } @taglist;

        if ($opts->{enable_tags_compatibility} && @taglist) {
            $text .= LJ::S2::get_tags_text($opts->{ctx}, \@taglist);
        }

        if ($security eq "public" && !$LJ::REQ_GLOBAL{'text_of_first_public_post'}) {
            $LJ::REQ_GLOBAL{'text_of_first_public_post'} = $text;

            if (@taglist) {
                $LJ::REQ_GLOBAL{'tags_of_first_public_post'} = [map { $_->{name} } @taglist];
            }
        }

        my $entry = Entry($u, {
            'subject' => $subject,
            'text' => $text,
            'dateparts' => $alldatepart,
            'system_dateparts' => $item->{'system_alldatepart'},
            'security' => $security,
            'age_restriction' => $eobj->adult_content_calculated,
            'allowmask' => $allowmask,
            'props' => $logprops{$datakey},
            'itemid' => $ditemid,
            'journal' => $userlite_journal,
            'poster' => $userlite_poster,
            'comments' => $comments,
            'new_day' => 0,  # setup below
            'end_day' => 0,  # setup below
            'userpic' => undef,
            'tags' => \@taglist,
            'permalink_url' => $permalink,
            'moodthemeid' => $moodthemeid,
        });
        $entry->{'_ymd'} = join('-', map { $entry->{'time'}->{$_} } qw(year month day));

        if ($picid && $picu) {
            push @userpic_load, [ $picu, $picid ];
            push @{$objs_of_picid{$picid}}, \$entry->{'userpic'};
        }

        push @{$p->{'entries'}}, $entry;
        $eventnum++;
        LJ::run_hook('notify_event_displayed', $eobj);
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

    # load the pictures that were referenced, then retroactively populate
    # the userpic fields of the Entries above
    my %userpics;
    LJ::load_userpics(\%userpics, \@userpic_load);

    foreach my $picid (keys %userpics) {
        my $up = Image("$LJ::USERPIC_ROOT/$picid/$userpics{$picid}->{'userid'}",
                       $userpics{$picid}->{'width'},
                       $userpics{$picid}->{'height'});
        foreach (@{$objs_of_picid{$picid}}) { $$_ = $up; }
    }

    # make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
        'count' => $eventnum,
    };

    my $base = "$u->{'_journalbase'}/$opts->{'view'}";
    if ($group_name) {
        $base .= "/" . LJ::eurl($group_name);
    }

    # $linkfilter is distinct from $filter: if user has a default view,
    # $filter is now set according to it but we don't want it to show in the links.
    # $incfilter may be true even if $filter is 0: user may use filter=0 to turn
    # off the default group
    my $linkfilter = $get->{'filter'} + 0;
    my $incfilter = defined $get->{'filter'};

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my %linkvars;
        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;
        my $newskip = $skip - $itemshow;
        if ($newskip > 0) { $linkvars{'skip'} = $newskip; }
        else { $newskip = 0; }
        $linkvars{'date'} = $get->{date} if $get->{date};
        $nav->{'forward_url'} = LJ::make_link($base, \%linkvars);
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_count'} = $itemshow;
        $p->{head_content} .= qq{<link rel="next" href="$nav->{forward_url}" />\n}
    }

    ## unless we didn't even load as many as we were expecting on this
    ## page, then there are more (unless there are exactly the number shown
    ## on the page, but who cares about that)
    # Must remember to count $hiddenentries or we'll have no skiplinks when > 1
    unless (($eventnum + $hiddenentries) != $itemshow || $skip == $maxskip) {
        my %linkvars;
        $linkvars{'filter'} = $linkfilter if $incfilter;
        $linkvars{'show'} = $get->{'show'} if $get->{'show'} =~ /^\w+$/;
        $linkvars{'date'} = $get->{'date'} if $get->{'date'};
        my $newskip = $skip + $itemshow;
        $linkvars{'skip'} = $newskip;
        $nav->{'backward_url'} = LJ::make_link($base, \%linkvars);
        $nav->{'backward_skip'} = $newskip;
        $nav->{'backward_count'} = $itemshow;
        $p->{head_content} .= qq{<link rel="prev" href="$nav->{backward_url}" />\n};
    }

    $p->{'nav'} = $nav;

    if ($get->{'mode'} eq "framed") {
        $p->{'head_content'} .= "<base target='_top' />";
    }
    return $p;
}

1;
