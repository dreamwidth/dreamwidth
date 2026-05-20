#!/usr/bin/perl
#
# DW::TaskQueue::Dedup
#
# Memcache-based deduplication for task queue jobs. Uses LJ::MemCache::add()
# (atomic, fails if key exists) to prevent duplicate tasks from being enqueued.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::TaskQueue::Dedup;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::MemCache;

# claim_unique($class, $queue_name, $uniqkey, $ttl)
#
# Attempts to claim a unique slot for a task. Returns 1 if the claim was
# successful (no duplicate exists), 0 if a duplicate is already pending.
# Uses LJ::MemCache::add() which is atomic -- it only succeeds if the key
# does not already exist.
sub claim_unique {
    my ( $class, $queue_name, $uniqkey, $ttl ) = @_;

    return 0 unless defined $queue_name && defined $uniqkey;
    $ttl ||= 3600;

    my $key = "taskdedup:$queue_name:$uniqkey";
    my $rv  = LJ::MemCache::add( $key, 1, $ttl );

    if ($rv) {
        $log->debug("Claimed unique slot: $key (ttl=$ttl)");
    }
    else {
        $log->debug("Duplicate task, skipping: $key");
    }

    return $rv ? 1 : 0;
}

# release_unique($class, $queue_name, $uniqkey)
#
# Releases a unique slot after task completion, allowing the same task
# to be enqueued again.
sub release_unique {
    my ( $class, $queue_name, $uniqkey ) = @_;

    return unless defined $queue_name && defined $uniqkey;

    my $key = "taskdedup:$queue_name:$uniqkey";
    LJ::MemCache::delete($key);
    $log->debug("Released unique slot: $key");
}

# is_pending($class, $queue_name, $uniqkey)
#
# Checks whether a task with the given unique key is currently pending.
# Returns 1 if pending, 0 if not.
sub is_pending {
    my ( $class, $queue_name, $uniqkey ) = @_;

    return 0 unless defined $queue_name && defined $uniqkey;

    my $key = "taskdedup:$queue_name:$uniqkey";
    return LJ::MemCache::get($key) ? 1 : 0;
}

1;
