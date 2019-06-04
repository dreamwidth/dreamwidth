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
#      RSH <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2009-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::LatestFeed;
use strict;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

DW::Routing->register_string( "/latest", \&index_handler, app => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r   = $rv->{r};
    my $GET = $r->get_args;
    my ( $type, $max, $fmt, $feed, $tag ) =
        ( $GET->{type}, ( $GET->{max} + 0 ) || 100, $GET->{fmt}, $GET->{feed}, $GET->{tag} );
    my $tagname = $tag;
    my $now     = time();

    $type = { entries => 'entry', comments => 'comment' }->{$type} || 'entry';
    $max = 100 if $max < 0 || 1000 < $max;
    $fmt = { rss => 'rss', atom => 'atom', html => 'html' }->{$fmt} || 'html';
    $feed = '' unless $feed && exists $LJ::LATEST_TAG_FEEDS{group_names}->{$feed};
    $tag  = '' unless $tag = LJ::get_sitekeyword_id( $tag, 0 );

    # if they want a format we don't support ... FIXME: implement all formats
    return "Sorry, that format is not supported yet."
        if $fmt ne 'html';

    # see if somebody has asked for this particular feed in the last minute or so, in
    # which case it is going to be in memcache
    my $mckey = "latest_src:$type:$max:$fmt" . ( $feed ? ":$feed" : '' ) . ( $tag ? ":$tag" : '' );

    my $cache_opts = { expire => 60, };

    LJ::need_res("stc/latest.css");
    return DW::Template->render_cached_template( $mckey, 'latest/index.tt', \&generate_vars,
        $cache_opts );
}

sub make_short_entry {
    my $entry = $_[0];
    my $url   = $entry->url;
    my $truncated;
    my $evt =
        $entry->event_html_summary( 2000,
        { cuturl => $url, preformatted => $entry->prop('opt_preformatted') },
        \$truncated );

    # put a "(Read more)" link at the end of the text if the entry had to be shortened
    $evt .= ' <a href="' . $url . '">(Read more)</a>' if $truncated;
    return $evt;
}

sub generate_vars {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r   = $rv->{r};
    my $GET = $r->get_args;
    my ( $type, $max, $fmt, $feed, $tag ) =
        ( $GET->{type}, ( $GET->{max} + 0 ) || 100, $GET->{fmt}, $GET->{feed}, $GET->{tag} );
    my $tagname = $tag;
    my $now     = time();

    $type = { entries => 'entry', comments => 'comment' }->{$type} || 'entry';
    $max = 100 if $max < 0 || 1000 < $max;
    $fmt = { rss => 'rss', atom => 'atom', html => 'html' }->{$fmt} || 'html';
    $feed = '' unless $feed && exists $LJ::LATEST_TAG_FEEDS{group_names}->{$feed};
    $tag  = '' unless $tag = LJ::get_sitekeyword_id( $tag, 0 );

    # if they want a format we don't support ... FIXME: implement all formats
    return "Sorry, that format is not supported yet."
        if $fmt ne 'html';

    # ask for the items from the latest feed
    my $items = DW::LatestFeed->get_items( feed => $feed, tagkwid => $tag );
    return "Failed to get latest items."
        unless $items && ref $items eq 'ARRAY';

    # now, iterate and extract only the things we want
    my @objs;
    foreach my $item (@$items) {
        next unless $item->{type} eq $type;
        push @objs, [ $item->{journalid}, $item->{jitemid}, $item->{jtalkid} ];
    }

    # splice off the top number we want
    @objs = splice @objs, 0, $max;

    # now get the journalids to load
    my $us = LJ::load_userids( map { $_->[0] } @objs );

    # and now construct real objects
    for ( my $i = 0 ; $i <= $#objs ; $i++ ) {
        if ( $type eq 'entry' ) {
            $objs[$i] = LJ::Entry->new( $us->{ $objs[$i]->[0] }, jitemid => $objs[$i]->[1] );
        }
        elsif ( $type eq 'comment' ) {
            $objs[$i] = LJ::Comment->new( $us->{ $objs[$i]->[0] }, jtalkid => $objs[$i]->[2] );
        }
    }

    # if we're in comment mode, let's construct the entries.  we only
    # have to reference this so that it gets turned into a singleton
    # so later when we call something on an entry it preloads all of them.
    if ( $type eq 'comment' ) {
        $_->entry foreach @objs;
    }

    my $tagfeeds = '';
    unless ( $tag || $feed ) {
        $tagfeeds = join ' ', map {
                  $feed eq $_
                ? $LJ::LATEST_TAG_FEEDS{group_names}->{$_}
                : qq(<a href="$LJ::SITEROOT/latest?feed=$_">$LJ::LATEST_TAG_FEEDS{group_names}->{$_}</a>)
            }
            sort { $a cmp $b } keys %{ $LJ::LATEST_TAG_FEEDS{group_names} };
        if ($feed) {
            $tagfeeds = qq{[<a href="$LJ::SITEROOT/latest">show all</a>] } . $tagfeeds;
        }
    }

    # but if we are filtering to a tag, let them unfilter
    if ($feed) {
        $tagfeeds .=
qq|Currently viewing posts about <strong>$LJ::LATEST_TAG_FEEDS{group_names}->{$feed}</strong>.  <a href="$LJ::SITEROOT/latest">Show all.</a>|;
    }
    if ($tag) {
        $tagfeeds .=
              qq{Currently viewing posts tagged <strong>}
            . LJ::ehtml($tagname)
            . qq{</strong>.  <a href="$LJ::SITEROOT/latest">Show all.</a>};
    }

    # and now, tag cloud!
    my $tfmap = DW::LatestFeed->get_popular_tags( count => 100 ) || {};
    if ( !$tag && !$feed && scalar keys %$tfmap ) {
        my $taghr = {
            map {
                $tfmap->{$_}->{tag} => {
                    url   => "$LJ::SITEROOT/latest?tag=" . LJ::eurl( $tfmap->{$_}->{tag} ),
                    value => $tfmap->{$_}->{count}
                }
            } keys %$tfmap
        };
        $tagfeeds .= "<br /><br />" . LJ::tag_cloud($taghr) . "\n";
    }
    my $vars = {
        items            => \@objs,
        tagfeeds         => $tagfeeds,
        time_diff        => \&LJ::diff_ago_text,
        now              => $now,
        make_short_entry => \&make_short_entry,
    };

    return $vars;
}

1;
