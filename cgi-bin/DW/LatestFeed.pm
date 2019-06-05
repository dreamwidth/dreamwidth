#!/usr/bin/perl
#
# DW::LatestFeed
#
# This module is the "frontend" for the latest feed.  You call this module to
# insert something into the feed or get the feed back in a consumable fashion.
# There is a lot of room for optimization to make this process more efficient
# but for now I haven't really done that.
#
# Also note, if memcache is cleared, the latest things go away and have to be
# repopulated from scratch.  This is not good behavior from the user experience
# aspect, but it's OK for this feature.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::LatestFeed;
use strict;

# time in seconds to hold events for.  until an event is this old, we will not
# show it on any page.
use constant EVENT_HORIZON => 300;

# number of popular tags to track... more tags means more work, more memory, but
# more neat data?  might be worth experimenting with this.  this should always
# be higher than what we show in any UI across the site...
use constant NUM_TOP_TAGS => 200;

# call this with whatever you want to stick onto the latest feed, and note that
# this just fires off TheSchwartz jobs, the work isn't actually done until the
# worker process it
sub new_item {
    my ( $class, $obj ) = @_;
    return unless $obj && ref $obj;

    my $sclient = LJ::theschwartz() or return;

    # entries are [ journalid, jitemid ] which lets us get the LJ::Entry back
    if ( $obj->isa('LJ::Entry') ) {
        return
            unless $obj->journal->is_community
            || $obj->journal->is_individual;

        $sclient->insert_jobs(
            TheSchwartz::Job->new_from_array(
                'DW::Worker::LatestFeed',
                {
                    type      => 'entry',
                    journalid => $obj->journalid,
                    jitemid   => $obj->jitemid,
                }
            )
        );

        # comments are stored as [ journalid, jtalkid ] which allows us to rebuild
        # the object easily
    }
    elsif ( $obj->isa('LJ::Comment') ) {
        $sclient->insert_jobs(
            TheSchwartz::Job->new_from_array(
                'DW::Worker::LatestFeed',
                {
                    type      => 'comment',
                    journalid => $obj->journalid,
                    jtalkid   => $obj->jtalkid,
                }
            )
        );

    }

    return undef;
}

# returns arrayref of item hashrefs that you can handle and display if you want
sub get_items {
    my ( $class, %opts ) = @_;
    return if $opts{feed} && !exists $LJ::LATEST_TAG_FEEDS{group_names}->{ $opts{feed} };
    return if $opts{tagkwid} && $opts{tagkwid} !~ /^\d+$/;

    # make sure we process the queue of items first.  this makes sure that if we
    # don't have much traffic we don't have to wait for new posts to drive the
    # processor.
    $class->_process_queue;

    # and simply get the list and return it ... simplicity
    my $thinger = $opts{feed} || $opts{tagkwid};
    my $mckey   = $thinger ? "latest_items_tag:$thinger" : "latest_items";
    return LJ::MemCache::get($mckey) || [];
}

# returns a hashref of our popular tags.
#    { kwid => { tag => tagname, count => value }, ... }
sub get_popular_tags {
    my ( $class, %opts ) = @_;
    my $ct = $opts{count} + 0;

    # and just for safety, we should warn the site admin if they adjust something
    # or try to do something that we know is going to fail or be weird.
    warn "WARNING: Requested $ct tags in $class->get_popular_tags, but currently we are\n"
        . "         configured to only store data for "
        . NUM_TOP_TAGS
        . " tags.\n"
        if $ct > NUM_TOP_TAGS * 0.8;

    # make sure we process the queue of items first.  this makes sure that if we
    # don't have much traffic we don't have to wait for new posts to drive the
    # processor.
    $class->_process_queue;

    # get the data, then splice the most popular requested
    my $data = LJ::MemCache::get('latest_items_tag_frequency_map') || [];
    @$data = splice @$data, 0, $ct if $ct;

    # return it in a slightly more useful format
    return { map { $_->[1] => { tag => $_->[0], count => $_->[2] } } @$data };
}

# INTERNAL; called by the worker when there's an item for us to handle.  at this
# point we are guaranteed to be the only active task updating the memcache keys
sub _process_item {
    my ( $class, $opts ) = @_;
    return unless $opts && ref $opts eq 'HASH';

    # we need to get the latest queue lock so we can edit it.  note that we will
    # try and try to get the lock because we really really want to succeed
    my $lock;
    while (1) {
        $lock = LJ::locker()->trylock('latest_queue');
        last if $lock;

        # pause for 0.0-0.3 seconds to shuffle things up.  generally good behavior
        # when you're contending for locks.
        select undef, undef, undef, rand() * 0.3;
    }

    # the way this works, since we want a 5 minute delay on items being posted and
    # appearing, is that when we get an item to process we just want to put it onto
    # an array.  when we LOAD the list we will process it, if we need to.
    my $dest = LJ::MemCache::get('latest_queue') || [];
    $opts->{t} = time + EVENT_HORIZON;
    push @$dest, $opts;

    # prune the list if it gets too large
    if ( scalar @$dest > 10_000 ) {
        warn "$class->_process_item: latest_queue too large, dropping items.\n";
        @$dest = splice @$dest, 0, 10_000;
    }

    # now stick it in memcache
    LJ::MemCache::set( latest_queue => $dest );

    # and just in case, try to process the queue since we're here anyway
    $class->_process_queue( have_lock => 1 );
}

# INTERNAL; called and attempts to do something with the latest items queue
sub _process_queue {
    my ( $class, %opts ) = @_;

    # we only process the queue every 60 seconds, no matter how often users might
    # ask for a page.  check the timer and bail if it's too soon.
    my $now = time;
    return unless ( LJ::MemCache::get('latest_queue_next') || 0 ) <= $now;

    # if we can't get the lock that means somebody else is processing the queue right
    # now so we should do nothing.  this returns immediately if the lock can't be gotten.
    my $lock;
    unless ( $opts{have_lock} ) {
        $lock = LJ::locker()->trylock('latest_queue')
            or return;
    }

    # update timer, now that we know we're the ones to do the work
    LJ::MemCache::set( latest_queue_next => $now + 60 );

    # get queue to process
    my $lq = LJ::MemCache::get('latest_queue');
    return unless $lq && ref $lq eq 'ARRAY' && @$lq;

    # BLOCK OF COMMENT TEXT
    #
    # okay, so this entire process is rather contorted but it's the only way to get the
    # efficient behavior we want.  potentially the latest queue can have a zillion items
    # in it, so we want to make sure to load things in the most efficient patterns possible.
    # apologies for the convolutedness.
    #

    # step 1) determine which items we can flat out ignore, dump those on the @rq and the
    # rest onto the @pq

    my ( @pq, @rq );
    foreach my $item (@$lq) {

        # result queue it if it has not passed our event horizon time yet
        if ( $now < $item->{t} ) {
            push @rq, $item;
            next;
        }

        push @pq, $item;
    }

    # step 1.5) we are done with the latest queue so we can toss that back into memcache and
    # set the timer for the next update.

    LJ::MemCache::set( latest_queue => \@rq );

    # step 2) load the user objects in one swoop.  we have to do this first because the
    # objects we instantiant in step 3 need the user objects.  if you give them a userid
    # they will load the user one by one, which is inefficient.  this is better.

    my $us = LJ::load_userids( map { $_->{journalid} } @pq );

    # step 3) create the objects we need.  we create them all first and DO NOT TOUCH THEM
    # so that we can take advantage of the singleton loading.

    foreach my $item (@pq) {

        # now, we want to create an object for the item
        if ( $item->{type} eq 'entry' ) {
            $item->{obj} =
                LJ::Entry->new( $us->{ $item->{journalid} }, jitemid => $item->{jitemid} );
        }
        elsif ( $item->{type} eq 'comment' ) {
            $item->{obj} =
                LJ::Comment->new( $us->{ $item->{journalid} }, jtalkid => $item->{jtalkid} );
        }
    }

    # step 4) now we have to process the comments to dig up the entry they go to.  this
    # causes the comments to preload.

    foreach my $item (@pq) {
        if ( $item->{type} eq 'comment' ) {
            $item->{obj_entry} = $item->{obj}->entry;
        }
    }

   # step 5) get all of the poster ids for the entries and comments so that we can load those in one
   # massive swoop

    # get userids for comments, entries, and then filter based on what we already have
    my @uids = map { $_->{obj}->posterid } grep { $_->{type} eq 'entry' } @pq;
    push @uids,
        map { $_->{obj}->posterid, $_->{obj_entry}->posterid } grep { $_->{type} eq 'comment' } @pq;
    @uids = grep { !exists $us->{$_} } @uids;

    # load the new users, backport to $us
    my $us2 = LJ::load_userids(@uids);
    $us->{$_} = $us2->{$_} foreach keys %$us2;

    # step 6) now we can iterate over everything and see what should be shown or not.  the items
    # that make the cut are stuck on @gq.

    my $show_entry = sub {
        my $entry = $_[0];

        return 0 unless $entry->security eq 'public';
        return 0
            unless $entry->poster->include_in_latest_feed
            && $entry->journal->include_in_latest_feed;
        return 0 if $entry->is_backdated;

        return 1;
    };

    my @gq;
    foreach my $item (@pq) {

        if ( $item->{type} eq 'entry' ) {

            # push the entry if it passes muster
            push @gq, $item if $show_entry->( $item->{obj} );

        }
        elsif ( $item->{type} eq 'comment' ) {

            # the comment has to be visible and the poster allows latest feed
            next
                unless $item->{obj}->is_active
                && $item->{obj}->poster->include_in_latest_feed;

            # now push it, but only if the entry is OK
            push @gq, $item if $show_entry->( $item->{obj_entry} );
        }
    }

    # step 6.5) we're going to need the latest things global tag frequency map (...hah)
    #   [ [ tagname, kwid, ct, time ], [ tagname, kwid, ct, time ], ... ]
    my $tfmap = LJ::MemCache::get('latest_items_tag_frequency_map') || [];

    #   ( kwid => tagname, kwid => tagname, ... )
    my %tfsr = map { $_->[1] => $_->[0] } @$tfmap;

    # step 7) now that we have the good items, we want to sort them and put them on the
    # list of latest items
    my %tagids;
    my %lists = ( latest_items => LJ::MemCache::get('latest_items') || [] );
    foreach my $item (@gq) {

        # $ent is always the entry, since comments always have obj_entry, and if that doesn't
        # exist then obj will be the entry
        my $ent = $item->{obj_entry} || $item->{obj};
        delete $item->{obj};
        delete $item->{obj_entry};

        # make sure we only add once, if the entry has multiple tags that map to the same feed
        my %feed_added;

        # step 7.5) if the entry contains any tags that we are currently showing
        # globally, then put that onto the list
        foreach my $tag ( $ent->tags ) {

            # some lists we guarantee are always shown, these are the special feeds that actually
            # allow combining tags and things...
            my $feed;
            if ( ( $feed = $LJ::LATEST_TAG_FEEDS{tag_maps}->{$tag} ) and ( !$feed_added{$feed} ) ) {
                my $nom = "latest_items_tag:$feed";
                $lists{$nom} ||= LJ::MemCache::get($nom) || [];
                unshift @{ $lists{$nom} }, $item;

                $feed_added{$feed}++;
            }

          # and now we try to determine if a tag is popular (top-N) and if so, then we also want
          # to store that information.  (actually we want to store information on the top N+10% tags
          # so that as things move up and down the popularity list they have data)
            if ( my $kwid = $tagids{$tag} ||= LJ::get_sitekeyword_id($tag) ) {

                # this has the side effect of allowing a tag to get promoted later if it gets enough
                # hits to get it onto the popular category... note: inefficient, heh.
                foreach my $row (@$tfmap) {
                    next unless $row->[1] == $kwid;

                    # found the row, so increment the count and bail. also, we update the last used
                    # time so that we know when we can purge the items if they go stale.
                    $row->[2]++;
                    $row->[3] = time();
                    last;
                }

                # ensure it's in memcache, then increment itd
                LJ::MemCache::add( "latest_items_tag_ct:$kwid", 0 );
                LJ::MemCache::incr("latest_items_tag_ct:$kwid");

                # if the tag is not already in the list, see if we should add it
                if ( !exists $tfsr{$kwid} ) {
                    my $ct = LJ::MemCache::get("latest_items_tag_ct:$kwid") || 0;
                    next
                        unless scalar @$tfmap <
                        NUM_TOP_TAGS                   # or we don't have enough tags in the list
                        || $ct > $tfmap->[-1]->[2];    # exceeds minimum value in list already

                    # okay, we're going to put this one in the list, prepare a space
                    push @$tfmap, [ $tag, $kwid, $ct, time() ];
                    @$tfmap = sort { $b->[2] <=> $a->[2] } @$tfmap;
                    @$tfmap = splice @$tfmap, 0, NUM_TOP_TAGS;
                }

                # and now we insert it onto a list for this keyword id (tag)
                my $nom = "latest_items_tag:$kwid";
                $lists{$nom} ||= LJ::MemCache::get($nom) || [];
                unshift @{ $lists{$nom} }, $item;
            }

        }

        # step 7.8) if the entry has a mood, add the moodid to the list of moods.
        my $moodid = $ent->prop('current_moodid');
        if ( $item->{type} eq 'entry' and $moodid ) {
            my $nom = "latest_moods";
            $lists{$nom} ||= LJ::MemCache::get($nom) || [];
            unshift @{ $lists{$nom} }, $moodid;
        }

        # we always put the item onto the latest everything list
        unshift @{ $lists{latest_items} }, $item;
    }

    # re-sort and update our tag frequency map, then store it
    my $cutoff = time() - 86400;    # ignore tags staler than this
    @$tfmap = sort { $b->[2] <=> $a->[2] }
        grep { $_->[3] > $cutoff } @$tfmap;
    @$tfmap = splice @$tfmap, 0, NUM_TOP_TAGS;
    LJ::MemCache::set( latest_items_tag_frequency_map => $tfmap );

    # prune and set all lists
    foreach my $key ( keys %lists ) {
        @{ $lists{$key} } = splice @{ $lists{$key} }, 0, 1000;
        LJ::MemCache::set( $key => $lists{$key} );
    }

    # we're done now
}

1;
