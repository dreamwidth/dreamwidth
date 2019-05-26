# t/feed-canonicalizer.t
#
# Feed Canonicalizer
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::FeedCanonicalizer;

# FIXME: We should probably test things LOTS BETTER
my @pairs = map {
    $_->[0] =~ m!^//\.(.+)$!
        ? (
        [ "http://$1",      $_->[1] ],
        [ "https://$1",     $_->[1] ],
        [ "http://www.$1",  $_->[1] ],
        [ "https://www.$1", $_->[1] ],
        )
        : $_->[0] =~ m!^(https?)://\.(.+)$! ? ( [ "$1://$2", $_->[1] ], [ "$1://www.$2", $_->[1] ] )
        : $_->[0] =~ m!^//! ? ( [ "http:$_->[0]", $_->[1] ], [ "https:$_->[0]", $_->[1] ] )
        : $_
} (
    [ "//username.fakejournal.com/data/rss",          "ljish://fakejournal.com/username" ],
    [ "http://username.fakejournal.com/data/rss.xml", "ljish://fakejournal.com/username" ],

    [ "http://username.fakejournal.com/data/atom",     "ljish://fakejournal.com/username" ],
    [ "http://username.fakejournal.com/data/atom.xml", "ljish://fakejournal.com/username" ],

    [
        "http://username.fakejournal.com/data/rss_friends",
        "ljish://fakejournal.com/username/friends"
    ],
    [
        "http://username.fakejournal.com/data/atom_friends",
        "ljish://fakejournal.com/username/friends"
    ],

    [
        "http://username.fakejournal.com/data/rss?tag=cupcakes",
        "ljish://fakejournal.com/username?tag=cupcakes"
    ],
    [
        "http://username.fakejournal.com/data/atom?tag=cupcakes",
        "ljish://fakejournal.com/username?tag=cupcakes"
    ],

    [
        "http://username.fakejournal.com/data/rss?tag=cupcakes",
        "ljish://fakejournal.com/username?tag=cupcakes"
    ],
    [
        "http://username.fakejournal.com/data/atom?tag=cupcakes",
        "ljish://fakejournal.com/username?tag=cupcakes"
    ],

    # These only work on lj-ish sites
    [ "http://username.livejournal.com/rss",         "ljish://livejournal.com/username" ],
    [ "http://username.livejournal.com/rss/friends", "ljish://livejournal.com/username/friends" ],
    [ "http://.livejournal.com/~username/rss",       "ljish://livejournal.com/username" ],

    [ "http://username.fakejournal.com/rss/friends", undef ],
    [ "http://username.fakejournal.com/rss",         undef ],
    [ "http://.fakejournal.com/~username/rss",       undef ],

    # LJish, legacy users/community/syndicated
    (
        map {
            [ "//$_.fakejournal.com/username/data/rss", "ljish://fakejournal.com/username" ],

                [ "//.fakejournal.com/$_/username/data/rss", "ljish://fakejournal.com/username" ],
        } qw( users community syndicated )
    ),

    [ "//username.fakejournal.com/data/rss",   "ljish://fakejournal.com/username" ],
    [ "//.fakejournal.com/~username/data/rss", "ljish://fakejournal.com/username" ],

    [ "//.fakejournal.com/~username/data/rss", "ljish://fakejournal.com/username" ],

    [ "//.fakejournal.com/~username/data/rss", "ljish://fakejournal.com/username" ],

    [ "//asylums.insanejournal.com/username/data/rss", "ljish://insanejournal.com/username" ],

    [ "//username.tumblr.com/rss",     "tumblr://username" ],
    [ "//username.tumblr.com/rss/",    "tumblr://username" ],
    [ "//username.tumblr.com/rss.xml", "tumblr://username" ],

    [ "//username.tumblr.com/tagged/cupcakes/rss", "tumblr://username/tagged/cupcakes" ],

    [ "//.blogger.com/feeds/0123456789/posts/default", "blogger://0123456789/posts" ],
    [ "//.blogger.com/feeds/0123456789/posts/full",    "blogger://0123456789/posts/full" ],
    [ "//.blogger.com/feeds/0123456789/comments/full", "blogger://0123456789/comments/full" ],
    [
        "//.blogger.com/feeds/0123456789/1234/comments/full",
        "blogger://0123456789/1234/comments/full"
    ],

    [ "//feeds1.feedburner.com/burnme", "feedburner://burnme" ],

    [ "//username.wordpress.com",           undef ],
    [ "//username.wordpress.com?feed=rss",  "wordpress://username" ],
    [ "//username.wordpress.com?feed=atom", "wordpress://username" ],

    # FIXME: Skipping simple wordpress feeds

    # Twitter is legacy:
    [ "//.twitter.com/statuses/user_timeline/username.rss", "twitter://username" ],
    [ "//.twitter.com/statuses/user_timeline/username.rss", "twitter://username" ],

    [ "//api.twitter.com/1/statuses/user_timeline.rss",                               undef ],
    [ "//api.twitter.com/1/statuses/user_timeline.rss?screen_name=username,cupcakes", undef ],
    [ "//api.twitter.com/1/statuses/user_timeline.rss?screen_name=username", "twitter://username" ],

    [ "//.twfeed.com/rss/username",  "twitter://username" ],
    [ "//.twfeed.com/atom/username", "twitter://username" ],

    # FIXME: Myspace requires special case

    [ "//.archiveofourown.org/tags/1234567/feed.atom", "ao3://tag/1234567" ],
    [ "//.archiveofourown.org/tags/1234567/feed.rss",  "ao3://tag/1234567" ],

    # FIXME: Skipping pinboard, need sample to figure out WTF that is doing

    # FIXME: gdata youtube and typepad
);

plan tests => scalar @pairs;

foreach my $pair (@pairs) {
    is( DW::FeedCanonicalizer::canonicalize( $pair->[0] ), $pair->[1], $pair->[0] );
}
