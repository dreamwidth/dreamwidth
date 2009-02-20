#!/usr/bin/perl
#
# DW::Logic::LogItems
#
# Contains logic used to calculate what items should be showed on the reading page
# and other related functions.  Functions related to loading large numbers of entries
# in a complicated fashion should be in here.  General purpose entry functionality
# should be in LJ::Entry, etc.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Logic::LogItems;
use strict;

use Carp qw/ confess /;

# name: $u->watch_items
# des: Return watch list items for a given user, filter, and period.
# args: hash of items, key/values:
#           - remote
#           - itemshow
#           - skip
#           - filter  (opt) defaults to all
#           - friends (opt) friends rows loaded via [func[LJ::get_friends]]
#           - friends_u (opt) u objects of all friends loaded
#           - idsbycluster (opt) hashref to set clusterid key to [ [ journalid, itemid ]+ ]
#           - dateformat:  either "S2" for S2 code, or anything else for S1
#           - common_filter:  set true if this is the default view
#           - friendsoffriends: load friends of friends, not just friends
#           - showtypes: /[PICNYF]/
#           - events_date: date to load events for ($u must have friendspage_per_day)
# returns: Array of item hashrefs containing the same elements
sub watch_items
{
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';

    my $userid = $u->id;
    return () if $LJ::FORCE_EMPTY_FRIENDS{$userid};

    my $dbr = LJ::get_db_reader()
        or return ();

    my $remote = LJ::want_user( delete $args{remote} );
    my $remoteid = $remote ? $remote->id : 0;

    # if ONLY_USER_VHOSTS is on (where each user gets his/her own domain),
    # then assume we're also using domain-session cookies, and assume
    # domain session cookies should be as most useless as possible,
    # so don't let friends pages on other domains have protected content
    # because really, nobody reads other people's friends pages anyway
    if ($LJ::ONLY_USER_VHOSTS && $remote && $remoteid != $userid) {
        $remote = undef;
        $remoteid = 0;
    }

    my @items = ();
    my $itemshow = $args{itemshow}+0;
    my $skip = $args{skip}+0;
    my $getitems = $itemshow + $skip;

    # friendspage per day is allowed only for journals with
    # special cap 'friendspage_per_day'
    my $events_date = ( ( $remoteid == $userid ) && $u->get_cap('friendspage_per_day') )
                        ? $args{events_date}
                        : '';

    my $filter  = int $args{filter};
    my $max_age = $LJ::MAX_FRIENDS_VIEW_AGE || 3600*24*14;  # 2 week default.
    my $lastmax = $LJ::EndOfTime - ($events_date || (time() - $max_age));
    my $lastmax_cutoff = 0; # if nonzero, never search for entries with rlogtime higher than this (set when cache in use)

    # sanity check:
    $skip = 0 if $skip < 0;

    # given a hash of friends rows, strip out rows with invalid journaltype
    my $filter_journaltypes = sub {
        my ( $friends, $friends_u, $memcache_only, $valid_types ) = @_;
        return unless $friends && $friends_u;
        $valid_types ||= uc $args{showtypes};

        # make (F)eeds an alias for s(Y)ndicated
        $valid_types =~ s/F/Y/g;

        # load u objects for all the given
        LJ::load_userids_multiple([ map { $_, \$friends_u->{$_} } keys %$friends ], [$remote],
                                  $memcache_only);

        # delete u objects based on 'showtypes'
        foreach my $fid ( keys %$friends_u ) {
            my $fu = $friends_u->{$fid};
            if ($fu->{statusvis} ne 'V' ||
                $valid_types && index(uc($valid_types), $fu->{journaltype}) == -1)
            {
                delete $friends_u->{$fid};
                delete $friends->{$fid};
            }
        }

        # all args passed by reference
        return;
    };

    my @friends_buffer = ();
    my $fr_loaded = 0;  # flag:  have we loaded friends?

    # normal friends mode
    my $get_next_friend = sub {

        # return one if we already have some loaded.
        return $friends_buffer[0] if @friends_buffer;
        return undef if $fr_loaded;

        # get all friends for this user and groupmask
        my $friends = $u->watch_list;
        my %friends_u;

        # strip out rows with invalid journal types
        $filter_journaltypes->($friends, \%friends_u);

        # get update times for all the friendids
        my $tu_opts = {};
        my $fcount = scalar keys %$friends;
        if ($LJ::SLOPPY_FRIENDS_THRESHOLD && $fcount > $LJ::SLOPPY_FRIENDS_THRESHOLD) {
            $tu_opts->{memcache_only} = 1;
        }

        my $times = $events_date
                        ? LJ::get_times_multi($tu_opts, keys %$friends)
                        : {updated => LJ::get_timeupdate_multi($tu_opts, keys %$friends)};
        my $timeupdate = $times->{updated};

        # now push a properly formatted @friends_buffer row
        foreach my $fid (keys %$timeupdate) {
            my $fu = $friends_u{$fid};
            my $rupdate = $LJ::EndOfTime - $timeupdate->{$fid};
            my $clusterid = $fu->{'clusterid'};
            push @friends_buffer, [ $fid, $rupdate, $clusterid, $friends->{$fid}, $fu ];
        }

        @friends_buffer =
            sort { $a->[1] <=> $b->[1] }
            grep {
                $timeupdate->{$_->[0]} >= $lastmax and # reverse index
                ($events_date
                    ? $times->{created}->{$_->[0]} < $events_date
                    : 1
                )
            }
            @friends_buffer;

        # note that we've already loaded the friends
        $fr_loaded = 1;

        # return one if we just found some, else we're all
        # out and there's nobody else to load.
        return @friends_buffer ? $friends_buffer[0] : undef;
    };

    # memcached friends of friends mode
    $get_next_friend = sub {

        # return one if we already have some loaded.
        return $friends_buffer[0] if @friends_buffer;
        return undef if $fr_loaded;

        # get journal's friends
        my $friends = LJ::get_friends($userid) || {};
        return undef unless %$friends;

        my %friends_u;

        # fill %allfriends with all friendids and cut $friends
        # down to only include those that match $filter
        my %allfriends = ();
        foreach my $fid (keys %$friends) {
            $allfriends{$fid}++;

            # delete from friends if it doesn't match the filter
            next unless $filter && ! ($friends->{$fid}->{'groupmask'}+0 & $filter+0);
            delete $friends->{$fid};
        }

        # strip out invalid friend journaltypes
        $filter_journaltypes->($friends, \%friends_u, "memcache_only", "P");

        # get update times for all the friendids
        my $f_tu = LJ::get_timeupdate_multi({'memcache_only' => 1}, keys %$friends);

        # get friends of friends
        my $ffct = 0;
        my %ffriends = ();
        foreach my $fid (sort { $f_tu->{$b} <=> $f_tu->{$a} } keys %$friends) {
            last if $ffct > 50;
            my $ff = LJ::get_friends($fid, undef, "memcache_only") || {};
            my $ct = 0;
            while (my $ffid = each %$ff) {
                last if $ct > 100;
                next if $allfriends{$ffid} || $ffid == $userid;
                $ffriends{$ffid} = $ff->{$ffid};
                $ct++;
            }
            $ffct++;
        }

        # strip out invalid friendsfriends journaltypes
        my %ffriends_u;
        $filter_journaltypes->(\%ffriends, \%ffriends_u, "memcache_only");

        # get update times for all the friendids
        my $ff_tu = LJ::get_timeupdate_multi({'memcache_only' => 1}, keys %ffriends);

        # build friends buffer
        foreach my $ffid (sort { $ff_tu->{$b} <=> $ff_tu->{$a} } keys %$ff_tu) {
            my $rupdate = $LJ::EndOfTime - $ff_tu->{$ffid};
            my $clusterid = $ffriends_u{$ffid}->{'clusterid'};

            # since this is ff mode, we'll force colors to ffffff on 000000
            $ffriends{$ffid}->{'fgcolor'} = "#000000";
            $ffriends{$ffid}->{'bgcolor'} = "#ffffff";

            push @friends_buffer, [ $ffid, $rupdate, $clusterid, $ffriends{$ffid}, $ffriends_u{$ffid} ];
        }

        @friends_buffer = sort { $a->[1] <=> $b->[1] } @friends_buffer;

        # note that we've already loaded the friends
        $fr_loaded = 1;

        # return one if we just found some fine, else we're all
        # out and there's nobody else to load.
        return @friends_buffer ? $friends_buffer[0] : undef;

    } if $args{friendsoffriends} && @LJ::MEMCACHE_SERVERS;

    # friends of friends disabled w/o memcache
    confess 'friends of friends mode requires memcache'
        if $args{friendsoffriends} && ! @LJ::MEMCACHE_SERVERS;

    my $loop = 1;
    my $itemsleft = $getitems;  # even though we got a bunch, potentially, they could be old
    my $fr;

    while ($loop && ($fr = $get_next_friend->()))
    {
        shift @friends_buffer;

        # load the next recent updating friend's recent items
        my $friendid = $fr->[0];

        $args{friends}->{$friendid} = $fr->[3];  # friends row
        $args{friends_u}->{$friendid} = $fr->[4]; # friend u object

        my @newitems = LJ::get_log2_recent_user({
            'clusterid'   => $fr->[2],
            'userid'      => $friendid,
            'remote'      => $remote,
            'itemshow'    => $itemsleft,
            'notafter'    => $lastmax,
            'dateformat'  => $args{dateformat},
            'update'      => $LJ::EndOfTime - $fr->[1], # reverse back to normal
            'events_date' => $events_date,
        });

        # stamp each with clusterid if from cluster, so ljviews and other
        # callers will know which items are old (no/0 clusterid) and which
        # are new
        if ($fr->[2]) {
            foreach (@newitems) { $_->{'clusterid'} = $fr->[2]; }
        }

        my $nextfr;

        if (@newitems)
        {
            push @items, @newitems;

            # For the next user, we need one event less for each event in
            # @newitems that we're sure to keep, that is, with a logtime that
            # makes it more recent than the "last updated" timestamp for the
            # next user. This is usually at least 1, but if the most recent
            # entry for the user retrieved in the previous round is invisible
            # to $remote (or it's not $remote's friends page), it should be 0.
            # Otherwise, excessive pruning may occur. See
            # http://www.dreamwidth.org/show_bug.cgi?id=86.
            #
            # Note that this can in some cases prune more aggressively than was
            # previously the case, if logtimes indicate that more than one
            # entry in @newitems is guaranteed to be kept. Also note that this
            # is a separate optimization than the one further down involving
            # $lastmax, which checks for entries guaranteed *not* to be kept.

            $nextfr ||= $get_next_friend->();
            if ($nextfr) {
                foreach my $it (@newitems) {
                    last if $it->{'rlogtime'} < $nextfr->[1];
                    $itemsleft--;
                }
            }

            # sort all the total items by rlogtime (recent at beginning).
            # if there's an in-second tie, the "newer" post is determined by
            # the higher jitemid, which means nothing if the posts aren't in
            # the same journal, but means everything if they are (which happens
            # almost never for a human, but all the time for RSS feeds, once we
            # remove the synsucker's 1-second delay between postevents)
            @items = sort { $a->{'rlogtime'} <=> $b->{'rlogtime'} ||
                            $b->{'jitemid'}  <=> $a->{'jitemid'}     } @items;

            # cut the list down to what we need.
            @items = splice(@items, 0, $getitems) if (@items > $getitems);
        }

        if (@items == $getitems)
        {
            $lastmax = $items[-1]->{'rlogtime'};
            $lastmax = $lastmax_cutoff if $lastmax_cutoff && $lastmax > $lastmax_cutoff;

            # stop looping if we know the next friend's newest entry
            # is greater (older) than the oldest one we've already
            # loaded.
            $nextfr ||= $get_next_friend->();
            $loop = 0 if ($nextfr && $nextfr->[1] > $lastmax);
        }
    }

    # remove skipped ones
    splice(@items, 0, $skip) if $skip;

    # get items
    foreach (@items) {
        $args{owners}->{$_->{'ownerid'}} = 1;
    }

    # return the itemids grouped by clusters, if callers wants it.
    if (ref $args{idsbycluster} eq "HASH") {
        foreach (@items) {
            push @{$args{idsbycluster}->{$_->{'clusterid'}}},
            [ $_->{'ownerid'}, $_->{'itemid'} ];
        }
    }

    return @items;
}
*LJ::User::watch_items = \&watch_items;
*DW::User::watch_items = \&watch_items;


# name: $u->recent_items
# des: Returns journal entries for a given account.
# takes hash of options as arguments
#           -- err: scalar ref to return error code/msg in
#           -- remote: remote user's $u
#           -- clusterid: clusterid of userid
#           -- tagids: arrayref of tagids to return entries with
#           -- security: (public|friends|private) or a group number
#           -- clustersource: if value 'slave', uses replicated databases
#           -- order: if 'logtime', sorts by logtime, not eventtime
#           -- friendsview: if true, sorts by logtime, not eventtime
#           -- notafter: upper bound inclusive for rlogtime/revttime (depending on sort mode),
#           defaults to no limit
#           -- skip: items to skip
#           -- itemshow: items to show
#           -- viewall: if set, no security is used.
#           -- dateformat: if "S2", uses S2's 'alldatepart' format.
#           -- itemids: optional arrayref onto which itemids should be pushed
# returns: array of hashrefs containing keys:
#          -- itemid (the jitemid)
#          -- posterid
#          -- security
#          -- alldatepart (in S1 or S2 fmt, depending on 'dateformat' req key)
#          -- system_alldatepart (same as above, but for the system time)
#          -- ownerid (if in 'friendsview' mode)
#          -- rlogtime (if in 'friendsview' mode)
sub recent_items
{
    my ( $u, %args ) = @_;
    $u = LJ::want_user( $u ) or confess 'invalid user object';

    my $userid = $u->id;

    my @items = ();             # what we'll return
    my $err = $args{err};

    my $remote = LJ::want_user( delete $args{remote} );
    my $remoteid = $remote ? $remote->id : 0;

    my $max_hints = $LJ::MAX_SCROLLBACK_LASTN;  # temporary
    my $sort_key = "revttime";

    my $clusterid = $args{'clusterid'}+0;
    my @sources = ("cluster$clusterid");
    if (my $ab = $LJ::CLUSTER_PAIR_ACTIVE{$clusterid}) {
        @sources = ("cluster${clusterid}${ab}");
    }
    unshift @sources, ("cluster${clusterid}lite", "cluster${clusterid}slave")
        if $args{'clustersource'} eq "slave";
    my $logdb = LJ::get_dbh(@sources);

    # community/friend views need to post by log time, not event time
    $sort_key = "rlogtime" if ($args{'order'} eq "logtime" ||
                               $args{'friendsview'});

    # 'notafter':
    #   the friends view doesn't want to load things that it knows it
    #   won't be able to use.  if this argument is zero or undefined,
    #   then we'll load everything less than or equal to 1 second from
    #   the end of time.  we don't include the last end of time second
    #   because that's what backdated entries are set to.  (so for one
    #   second at the end of time we'll have a flashback of all those
    #   backdated entries... but then the world explodes and everybody
    #   with 32 bit time_t structs dies)
    my $notafter = $args{'notafter'} + 0 || $LJ::EndOfTime - 1;

    my $skip = $args{'skip'}+0;
    my $itemshow = $args{'itemshow'}+0;
    if ($itemshow > $max_hints) { $itemshow = $max_hints; }
    my $maxskip = $max_hints - $itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }
    my $itemload = $itemshow + $skip;

    my $mask = 0;
    if ($remote && ($remote->{'journaltype'} eq "P" || $remote->{'journaltype'} eq "I") && $remoteid != $userid) {
        $mask = $u->trustmask( $remote );
    }

    # decide what level of security the remote user can see
    my $secwhere = "";
    if ($userid == $remoteid || $args{'viewall'}) {
        # no extra where restrictions... user can see all their own stuff
        # alternatively, if 'viewall' opt flag is set, security is off.
    } elsif ($mask) {
        # can see public or things with them in the mask
        $secwhere = "AND (security='public' OR (security='usemask' AND allowmask & $mask != 0))";
    } else {
        # not a friend?  only see public.
        $secwhere = "AND security='public' ";
    }

    # because LJ::get_friend_items needs rlogtime for sorting.
    my $extra_sql;
    if ($args{'friendsview'}) {
        $extra_sql .= "journalid AS 'ownerid', rlogtime, ";
    }

    # if we need to get by tag, get an itemid list now
    my $jitemidwhere;
    if (ref $args{tagids} eq 'ARRAY' && @{$args{tagids}}) {
        # select jitemids uniquely
        my $in = join(',', map { $_+0 } @{$args{tagids}});
        my $jitemids = $logdb->selectcol_arrayref(qq{
                SELECT DISTINCT jitemid FROM logtagsrecent WHERE journalid = ? AND kwid IN ($in)
            }, undef, $userid);
        die $logdb->errstr if $logdb->err;

        # set $jitemidwhere iff we have jitemids
        if (@$jitemids) {
            $jitemidwhere = " AND jitemid IN (" .
                            join(',', map { $_+0 } @$jitemids) .
                            ")";
        } else {
            # no items, so show no entries
            return ();
        }
    }

    # if we need to filter by security, build up the where clause for that too
    my $securitywhere;
    if ($args{'security'}) {
        my $security = $args{'security'};
        if (($security eq "public") || ($security eq "private")) {
            $securitywhere = " AND security = \"$security\"";
        }
        elsif ($security eq "friends") {
            $securitywhere = " AND security = \"usemask\" AND allowmask = 1";
        }
        elsif ($security=~/^\d+$/) {
            $securitywhere = " AND security = \"usemask\" AND (allowmask & " . (1 << $security) . ")";
        }
    }

    my $sql;

    my $dateformat = "%a %W %b %M %y %Y %c %m %e %d %D %p %i %l %h %k %H";
    if ($args{'dateformat'} eq "S2") {
        $dateformat = "%Y %m %d %H %i %s %w"; # yyyy mm dd hh mm ss day_of_week
    }

    my ($sql_limit, $sql_select) = ('', '');
    if ($args{'ymd'}) {
        my ($year, $month, $day);
        if ($args{'ymd'} =~ m!^(\d\d\d\d)/(\d\d)/(\d\d)\b!) {
            ($year, $month, $day) = ($1, $2, $3);
            # check
            if ($year !~ /^\d+$/) { $$err = "Corrupt or non-existant year."; return (); }
            if ($month !~ /^\d+$/) { $$err = "Corrupt or non-existant month." ; return (); }
            if ($day !~ /^\d+$/) { $$err = "Corrupt or non-existant day." ; return (); }
            if ($month < 1 || $month > 12 || int($month) != $month) { $$err = "Invalid month." ; return (); }
            if ($year < 1970 || $year > 2038 || int($year) != $year) { $$err = "Invalid year: $year"; return (); }
            if ($day < 1 || $day > 31 || int($day) != $day) { $$err = "Invalid day."; return (); }
            if ($day > LJ::days_in_month($month, $year)) { $$err = "That month doesn't have that many days."; return (); }
        } else {
            $$err = "wrong date: " . $args{'ymd'};
            return ();
        }
        $sql_limit  = "LIMIT 200";
        $sql_select = "AND year=$year AND month=$month AND day=$day";
        $extra_sql .= "allowmask, ";
    } else {
        $sql_limit  = "LIMIT $skip,$itemshow";
        $sql_select = "AND $sort_key <= $notafter";
    }

    $sql = qq{
        SELECT jitemid AS 'itemid', posterid, security, $extra_sql
               DATE_FORMAT(eventtime, "$dateformat") AS 'alldatepart', anum,
               DATE_FORMAT(logtime, "$dateformat") AS 'system_alldatepart',
               allowmask, eventtime, logtime
        FROM log2 USE INDEX ($sort_key)
        WHERE journalid=$userid $sql_select $secwhere $jitemidwhere $securitywhere
        ORDER BY journalid, $sort_key
        $sql_limit
    };

    unless ($logdb) {
        $$err = "nodb" if ref $err eq "SCALAR";
        return ();
    }

    my $sth = $logdb->prepare($sql);
    $sth->execute;
    if ($logdb->err) { die $logdb->errstr; }

    # keep track of the last alldatepart, and a per-minute buffer
    my $last_time;
    my @buf;
    my $flush = sub {
        return unless @buf;
        push @items, sort { $b->{itemid} <=> $a->{itemid} } @buf;
        @buf = ();
    };

    while (my $li = $sth->fetchrow_hashref) {
        push @{$args{'itemids'}}, $li->{'itemid'};

        $flush->() if $li->{alldatepart} ne $last_time;
        push @buf, $li;
        $last_time = $li->{alldatepart};

        # construct an LJ::Entry singleton
        my $entry = LJ::Entry->new($userid, jitemid => $li->{itemid});
        $entry->absorb_row(%$li);
    }
    $flush->();

    return @items;
}
*LJ::User::recent_items = \&recent_items;
*DW::User::recent_items = \&recent_items;


1;
