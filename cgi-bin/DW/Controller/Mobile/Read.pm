#!/usr/bin/perl
#
# DW::Controller::Mobile::Read
#
# The mobile reading page (/mobile/read): a minimal standalone (no sitescheme)
# list of the most recent entries on the viewer's reading page, with a content
# filter selector and skip-based pagination.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Mobile::Read;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

use LJ::CleanHTML;

DW::Routing->register_string( "/mobile/read", \&read_handler, app => 1 );

sub read_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};
    my $u = $rv->{remote};

    # Not logged in: render the "log in first" message.
    unless ($u) {
        $rv->{not_logged_in} = 1;
        return DW::Template->render_template( 'mobile/read.tt', $rv, { no_sitescheme => 1 } );
    }

    my $get          = $r->get_args;
    my $itemsperpage = 50;
    my $skip         = int( $get->{skip} || 0 );
    my $view         = $get->{view};

    my $showtypes = '';
    my $reqfilter;
    if ( defined $view && $view =~ /^[CPY]$/ ) {
        $showtypes = $view;
    }
    elsif ( defined $view ) {
        $reqfilter = int $view;
    }

    # Filters to check for: the specified filter ID, then "Mobile", "Mobile
    # View", "Default", "Default View" -- if none exist, no filter. Skip the
    # default-filter lookup when all subscriptions were explicitly requested
    # (view == 0).
    my $cf;
    $cf = $u->content_filters( id => $reqfilter ) if $reqfilter;
    $cf ||=
           $u->content_filters( name => "Mobile" )
        || $u->content_filters( name => "Mobile View" )
        || $u->content_filters( name => "Default" )
        || $u->content_filters( name => "Default View" )
        unless defined $view && $view == 0;

    my @items = $u->watch_items(
        remote         => $u->userid,
        itemshow       => $itemsperpage,
        skip           => $skip,
        showtypes      => $showtypes,
        u              => $u,
        userid         => $u->userid,
        content_filter => $cf,
    );

    my $numentries = scalar @items;

    # Pagination: "previous" walks toward older entries (a higher skip) and is
    # shown whenever this page is full; "next" walks toward newer entries (a
    # lower skip) and is shown whenever we are not already on the first page.
    $rv->{itemsperpage} = $itemsperpage;
    $rv->{show_prev}    = $numentries < $itemsperpage ? 0 : 1;
    $rv->{prev_skip}    = $skip + $itemsperpage;
    $rv->{show_next}    = $skip ? 1 : 0;
    $rv->{next_skip}    = $skip - $itemsperpage;

    # The filter dropdown: the four built-in subscription views, then the user's
    # own content filters.
    my @filters = (
        "0" => LJ::Lang::ml('web.controlstrip.select.friends.all'),
        "P" => LJ::Lang::ml('web.controlstrip.select.friends.journals'),
        "C" => LJ::Lang::ml('web.controlstrip.select.friends.communities'),
        "Y" => LJ::Lang::ml('web.controlstrip.select.friends.feeds'),
    );
    push @filters, $_->id, $_->name foreach $u->content_filters;
    $rv->{filter_items} = \@filters;

    # showtypes overrides the default filter, but an explicit reqfilter wins.
    my $selected = "0";
    $selected = $cf->id    if $cf;
    $selected = $showtypes if $showtypes;
    $selected = $cf->id    if $reqfilter;
    $rv->{filter_selected} = $selected;

    # Build display-ready rows for each entry.
    my @entries;
    foreach my $ei (@items) {
        next unless $ei;

        my $entry;
        if ( $ei->{ditemid} ) {
            $entry = LJ::Entry->new( $ei->{journalid}, ditemid => $ei->{ditemid} );
        }
        elsif ( $ei->{jitemid} && $ei->{anum} ) {
            $entry =
                LJ::Entry->new( $ei->{journalid}, jitemid => $ei->{jitemid}, anum => $ei->{anum} );
        }
        next unless $entry;

        my $pu = $entry->poster;
        my $ju = $entry->journal;

        my $subject = $entry->subject_text;
        unless ($subject) {
            $subject = $entry->event_text;
            my $truncated = 0;
            LJ::CleanHTML::clean_and_trim_subject( \$subject, undef, \$truncated );
            $subject .= "..." if $truncated;
        }
        $subject ||= "(no subject)";

        push @entries,
            {
            url          => $entry->url . "?format=light",
            subject      => $subject,
            poster_url   => $pu->journal_base . "/",
            poster_user  => $pu->user,
            journal_url  => $ju->journal_base . "/",
            journal_user => $ju->user,
            in_community => $pu->userid != $ju->userid ? 1 : 0,
            };
    }
    $rv->{entries}    = \@entries;
    $rv->{numentries} = $numentries;

    return DW::Template->render_template( 'mobile/read.tt', $rv, { no_sitescheme => 1 } );
}

1;
