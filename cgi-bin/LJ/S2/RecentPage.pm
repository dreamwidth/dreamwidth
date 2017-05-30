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

sub RecentPage
{
    my ($u, $remote, $opts) = @_;

    # specify this so that the Page call will add in openid information.
    # this allows us to put the tags early in the <head>, before we start
    # adding other head_content here.
    $opts->{'addopenid'} = 1;

    # and ditto for RSS feeds, otherwise we show RSS feeds for the journal
    # on other views ... kinda confusing
    $opts->{'addfeeds'} = 1;

    my $p = Page($u, $opts);
    $p->{_type} = "RecentPage";
    $p->{view} = "recent";
    $p->{entries} = [];
    $p->{filter_active} = 0;
    $p->{filter_name} = "";
    $p->{filter_tags} = 0;

    # Link to the friends page as a "group", for use with OpenID "Group Membership Protocol"
    {
        my $is_comm = $u->is_community;
        my $friendstitle = $LJ::SITENAMESHORT." ".($is_comm ? "members" : "friends");
        my $rel = "group ".($is_comm ? "members" : "friends made");
        my $friendsurl = $u->journal_base."/read"; # We want the canonical form here, not the vhost form
        $p->{head_content} .= '<link rel="'.$rel.'" title="'.LJ::ehtml($friendstitle).'" href="'.LJ::ehtml($friendsurl)."\" />\n";
    }

    my $user = $u->user;
    my $journalbase = $u->journal_base( vhost => $opts->{'vhost'} );

    my $datalink = sub {
        my ($what, $caption) = @_;
        return Link($p->{'base_url'} . "/data/$what" . ($opts->{tags} ? "?tag=".join(",", map({ LJ::eurl($_) } @{$opts->{tags}})) : ""),
                    $caption, Image_std( $what ) );
    };

    $p->{'data_link'} = {
        'rss' => $datalink->('rss', 'RSS'),
        'atom' => $datalink->('atom', 'Atom'),
    };
    $p->{'data_links_order'} = [ qw(rss atom) ];

    $remote->preload_props( "opt_nctalklinks", "opt_cut_disable_journal") if $remote;

    if ( $opts->{tags} ) {
        $p->{filter_active} = 1;
        $p->{filter_name} = join(", ", @{$opts->{tags}});
        $p->{filter_tags} = 1;
    }

    if ( $opts->{securityfilter} ) {
        my $filter = $u->trust_groups( id => $opts->{securityfilter} );
        $p->{filter_active} = 1;
        if ( defined $filter ) {
            $p->{filter_name} = $filter->{groupname};
        } else {
            # something went wrong; just use the group number
            $p->{filter_name} = $opts->{securityfilter};
        }
    } 

    my $get = $opts->{'getargs'};

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }

    if ($u->should_block_robots || $get->{'skip'}) {
        $p->{'head_content'} .= LJ::robot_meta_tags();
    }

    if (my $icbm = $u->prop("icbm")) {
        $p->{'head_content'} .= qq{<meta name="ICBM" content="$icbm" />\n};
    }

    LJ::need_res( LJ::S2::tracking_popup_js() );

    # include JS for quick reply, icon browser, and ajax cut tag
    my $handle_with_siteviews = $opts->{handle_with_siteviews_ref} &&
                              ${$opts->{handle_with_siteviews_ref}};
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

    my $itemshow = S2::get_property_value($opts->{'ctx'}, "num_items_recent")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }

    my $skip = $get->{skip} ? $get->{skip} + 0 : 0;
    my $maxskip = $LJ::MAX_SCROLLBACK_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # honor ?style=mine
    my $mine = $get->{style} || '';
    $mine = '' unless $mine eq 'mine';

    # do they want to view all entries, regardless of security?
    my $viewall = 0;
    my $viewsome = 0;
    if ( $remote ) {
        ( $viewall, $viewsome ) =
            $remote->view_priv_check( $u, $get->{viewall}, 'lastn' );
    }

    my $posteru_filter;
    if ( defined( $get->{poster} ) ) {
        $posteru_filter = LJ::load_user_or_identity( $get->{poster} );
    }

    ## load the itemids
    my @itemids;
    my $err;
    my @items = $u->recent_items(
        clusterid     => $u->{clusterid},
        clustersource => 'slave',
        viewall       => $viewall,
        remote        => $remote,
        itemshow      => $itemshow + 1,
        skip          => $skip,
        tagids        => $opts->{tagids},
        tagmode       => $opts->{tagmode},
        security      => $opts->{securityfilter},
        itemids       => \@itemids,
        dateformat    => 'S2',
        order         => $u->is_community ? 'logtime' : '',
        err           => \$err,
        posterid      => $posteru_filter ? $posteru_filter->id : undef,
    );

    my $is_prev_exist = scalar @items - $itemshow > 0 ? 1 : 0;
    pop @items if $is_prev_exist;

    die $err if $err;

    # Prepare sticky entries for S2.
    # Only show sticky entry on first page of Recent Entries.
    # Do not show stickies unless they have the relevant permissions.
    # Do not sticky posts on tagged view but display in place.
    # Do not sticky posts on poster view but display in place.
    # On skip pages show sticky entries in place.
    my $show_sticky_entries = $skip == 0 && ! $opts->{securityfilter} && ! $opts->{tagids} && ! $posteru_filter;
    if ( $show_sticky_entries ) {
        foreach my $sticky_entry ( $u->sticky_entries ) {
            # only show if visible to user
            if ( $sticky_entry && $sticky_entry->visible_to( $remote, $get->{viewall} ) ) {
                # create S2 entry object and show first on page
                my $entry = Entry_from_entryobj( $u, $sticky_entry, $opts );
                # sticky entry specific things
                my $sticky_icon = Image_std( 'sticky-entry' );
                $entry->{_type} = 'StickyEntry';
                $entry->{sticky_entry_icon} = $sticky_icon;
                # show on top of page
                push @{$p->{entries}}, $entry;
            }
        }
    }

    my $lastdate = "";
    my $itemnum = 0;
    my $lastentry = undef;

    $opts->{cut_disable} = ( $remote && $remote->prop( 'opt_cut_disable_journal' ) );

    my $sticky_entries = $u->sticky_entries_lookup;

  ENTRY:
    foreach my $item (@items)
    {
        my ($posterid, $itemid, $anum) =
            map { $item->{$_} } qw(posterid itemid anum);

        # need to increment before possibly doing a next, so that the skiplinks will work
        $itemnum++;

        my $ditemid = $itemid * 256 + $anum;
        next if $itemnum > 0 && $show_sticky_entries && $sticky_entries->{$ditemid};

        my $entry_obj = LJ::Entry->new( $u, ditemid => $ditemid );

        # don't show posts from suspended users or suspended posts unless the user doing the viewing says to (and is allowed)
        next ENTRY if $entry_obj && $entry_obj->poster->is_suspended && ! $viewsome;
        next ENTRY if $entry_obj && $entry_obj->is_suspended_for($remote);

        # create S2 entry, journal posted to is $u
        my $entry = $lastentry = Entry_from_entryobj( $u, $entry_obj, $opts );

        # end_day and new_day need to be set
        my $alldatepart = LJ::alldatepart_s2( $entry_obj->{eventtime} );
        my $date = substr($alldatepart, 0, 10);
        my $new_day = 0;
        if ( $date ne $lastdate ) {
            $new_day = 1;
            $lastdate = $date;
            $lastentry->{end_day} = 1 if $lastentry;
        }
        $entry->{new_day} = $new_day,

        push @{$p->{entries}}, $entry;

        LJ::Hooks::run_hook('notify_event_displayed', $entry_obj);
    }

    # mark last entry as closing.
    $p->{'entries'}->[-1]->{'end_day'} = 1 if @{$p->{'entries'} || []};

    #### make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
        'count' => $itemnum,
    };

    my %valid_modes = ( all => 'all', and => 'all' );
    my $tagmode = $valid_modes{$get->{mode} || ''};

    # these are the same for both previous and next links
    my %linkattrs = ( style    => $mine                        || "",
                      mode     => $tagmode                     || "",
                      s2id     => LJ::eurl( $get->{s2id} )     || "",
                      tag      => LJ::eurl( $get->{tag} )      || "",
                      security => LJ::eurl( $get->{security} ) || "",
                      poster   => $posteru_filter ?
                                  $posteru_filter->user         : "",
                    );

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my $newskip = $skip - $itemshow;
        $newskip = 0 if $newskip <= 0;
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_url'} = LJ::S2::make_link( "$p->{'base_url'}/",
                                { skip => $newskip || "", %linkattrs } );
        $nav->{'forward_count'} = $itemshow;
        $p->{head_content} .= qq{<link rel="next" href="$nav->{forward_url}" />\n}
    }

    # unless we didn't even load as many as we were expecting on this
    # page, then there are more (unless there are exactly the number shown
    # on the page, but who cares about that)
    unless ($itemnum != $itemshow) {
        $nav->{'backward_count'} = $itemshow;
        if ($skip == $maxskip) {
            my $date_slashes = $lastdate;  # "yyyy mm dd";
            $date_slashes =~ s! !/!g;
            $nav->{'backward_url'} = "$p->{'base_url'}/$date_slashes";
        } elsif ($is_prev_exist) {
            my $newskip = $skip + $itemshow;
            $nav->{'backward_url'} = LJ::S2::make_link( "$p->{'base_url'}/",
                                { skip => $newskip || "", %linkattrs } );
            $nav->{'backward_skip'} = $newskip;
        }
        $p->{head_content} .= qq{<link rel="prev" href="$nav->{backward_url}" />\n};
    }

    $p->{'nav'} = $nav;
    return $p;
}

1;
