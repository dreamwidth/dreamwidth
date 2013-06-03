#!/usr/bin/perl
#
# DW::Controller::Mobile::Entries
#
# This area manages controllers for advanced management of styles, such as:
#   * layerbrowse viewing
#   * the index for the advanced customization area
#
# Authors:
#      foxfirefey <foxfirefey@gmail.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Mobile::Entries;

use strict;
use warnings;

use DW::Controller;
use DW::Routing;
use DW::Template;

use JSON;

use LJ::Global::Img;

DW::Routing->register_regex( qr!^/mobile/(reading|network)$!, \&readingnetwork_handler, app => 1 );
DW::Routing->register_regex( qr!^/mobile/user/([a-z0-9_]+)/entry/([0-9]+)$!, \&entry_handler, app => 1 );
DW::Routing->register_regex( qr!^/mobile/user/([a-z0-9_]+)/(recent)$!, \&recenttag_handler, app => 1 );

# TODO: a better option for this
my $ITEMS_PER_PAGE = 5;
my $DISPLAY_ICONS = 1;

# this helps decorate an Entry object for mobile display
sub decorate_entry {
    my ( $e, $remote ) = @_;

    $e->{has_userpic} = defined $e->userpic ? 1 : 0;
    $e->{userpic_url} = defined $e->userpic ? $e->userpic->url : $LJ::IMGPREFIX . "/nouserpic.png";

    $e->{processed} = 1;
    if ($e->{security} eq "usemask") {
        if ($e->{allowmask} == 0) { # custom security with no group -- essentially private
            $e->{security} = "private";
            #$e->{'security_icon'} = Image_std("security-private");
        } elsif ( $e->{allowmask} > 1 && $e->{poster} && $e->{poster}->equals( $remote ) ) { # custom group -- only show to journal owner
            $e->{security} = "custom";
            #$e->{security_icon'} = Image_std("security-groups");
        } else { # friends only or custom group showing to non journal owner
            $e->{security} = "protected";
            #$e->{'security_icon'} = Image_std("security-protected");
        }
    }

    $e->{security_icon} = $LJ::Img::img{ "security-" . $e->{security} }
        unless $e->{security} eq "public";
    $e->{adult_content_icon} = $LJ::Img::img{'adult-18'}
      if defined $e->{props}->{adult_content} and $e->{props}->{adult_content} eq "explicit";
    $e->{adult_content_icon} = $LJ::Img::img{'adult-nsfw'}
     if defined $e->{props}->{adult_content} and $e->{props}->{adult_content} eq "concepts";
#                Image( "$LJ::IMGPREFIX$i->{src}",
#                       $i->{width}, $i->{height},

}

sub process_entry_ids {

    my $u;
    my @processed_entries;

    foreach my $ei ( @_ ) {
        next unless $ei;
        my $entry;
        if ( $ei->{ditemid} ) {
            $entry = LJ::Entry->new( $ei->{journalid},
                                    ditemid => $ei->{ditemid} );
        } elsif ($ei->{jitemid} && $ei->{anum}) {
            $entry = LJ::Entry->new($ei->{journalid},
                                    jitemid => $ei->{jitemid},
                                    anum    => $ei->{anum});
        }
        next unless $entry;

        my $subject = $entry->subject_text;
        unless ( $subject ) {
            $subject = $entry->event_text;

            my $truncated = 0;
            LJ::CleanHTML::clean_and_trim_subject( \$subject, undef, \$truncated );
            $subject .= "..." if $truncated;
        }

        # say the entry was all HTML, and we thus have nothing, one more fallback
        $subject ||= "(no subject)";

        $entry->{truncated_subject} = $subject;
        decorate_entry( $entry, $u );

        push @processed_entries, $entry;
    }

    return @processed_entries;
}

sub readingnetwork_handler {
    my ( $opts, $view ) = @_;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r = DW::Request->get;
    # todo: error handling
    my $u = $rv->{remote};

    my $skip = defined $r->get_args->{skip} ? $r->get_args->{skip} + 0 : 0;

    my @entries = $u->watch_items(
        remote             => $u->{userid},
        itemshow           => $ITEMS_PER_PAGE + 1, # get one more to check if we need to go back
        skip               => $skip,
        showtypes          => 'PYC',
        u                  => $u,
        friendsoffriends   => $view eq 'network', # note: requires memcache to work
        userid             => $u->{userid},
#       filter             => $filter,
    );

    my $numentries = @entries;

    my $previous_entries = $numentries > $ITEMS_PER_PAGE ? defined pop @entries : undef;
    my $backcount = $skip + $ITEMS_PER_PAGE if $previous_entries;
    my $forwardcount = $skip ? $skip - $ITEMS_PER_PAGE : -1;

    my @processed_entries = process_entry_ids( $u, @entries );

    my $vars = {
        display_icons   => $DISPLAY_ICONS,
        entries         => \@processed_entries,
        u               => $u,
        skip            => $skip,
        itemsperpage    => $ITEMS_PER_PAGE,
        backcount       => $backcount,
        forwardcount    => $forwardcount,
        view            => $view,
        skipurl         => "mobile/$view",
    };

    return DW::Template->render_template( 'mobile/reading.tt', $vars, {'no_sitescheme' => 1} );
}

sub recenttag_handler {
    my ( $opts, $username, $view ) = @_;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $u = LJ::load_user_or_identity( $username );
    my $remote = LJ::get_remote();

    my $r = DW::Request->get;
    # todo: error handling

    my $skip = defined $r->get_args->{skip} ? $r->get_args->{skip} + 0 : 0;
    my @entryids;
    my $err;
    my @entries = $u->recent_items(
        clusterid     => $u->{clusterid},
        clustersource => 'slave',
       # viewall       => $viewall,
        remote        => $remote,
        itemshow      => $ITEMS_PER_PAGE + 1,
        skip          => $skip,
        #tagids        => $opts->{tagids}, #TODO
        #tagmode       => $opts->{tagmode}, #TODO
        #security      => $opts->{securityfilter}, #TODO
        itemids       => \@entryids,
        dateformat    => 'S2',
        order         => $u->is_community ? 'logtime' : '',
        err           => \$err,
        #posterid      => $posteru_filter ? $posteru_filter->id : undef,
    );

    die $err if $err;

  # ADD SKIPS OVER SUSPENDED USERS

  # ADD STICKY ENTRIES
  #  # prepare sticky entry for S2 - only show sticky entry on first page of Recent Entries, not on skip= pages
  #  # or tag and security subfilters
  #  my $stickyentry;
  #  $stickyentry = $u->get_sticky_entry
  #      if $skip == 0 && ! $opts->{securityfilter} && ! $opts->{tagids};
  #  # only show if visible to user
  #  if ( $stickyentry && $stickyentry->visible_to( $remote, $get->{viewall} ) ) {
  #      # create S2 entry object and show first on page
  #      my $entry = Entry_from_entryobj( $u, $stickyentry, $opts );
  #      # sticky entry specific things
  #      my $sticky_icon = Image_std( 'sticky-entry' );
  #      $entry->{_type} = 'StickyEntry';
  #      $entry->{sticky_entry_icon} = $sticky_icon;
  #      # show on top of page
  #      push @{$p->{entries}}, $entry;
  #  }

    my $numentries = @entries;

    my $previous_entries = $numentries > $ITEMS_PER_PAGE ? defined pop @entries : undef;
    my $backcount = $skip + $ITEMS_PER_PAGE if $previous_entries;
    my $forwardcount = $skip ? $skip - $ITEMS_PER_PAGE : -1;

    my @processed_entries = process_entry_ids( $u,
    	map { { ditemid => $_->{itemid} * 256 + $_->{anum}, journalid => $_->{posterid} } } @entries );

    my $vars = {
        display_icons   => $DISPLAY_ICONS,
        entries         => \@processed_entries,
        u               => $u,
        remote          => $remote,
        skip            => $skip,
        itemsperpage    => $ITEMS_PER_PAGE,
        backcount       => $backcount,
        forwardcount    => $forwardcount,
        view            => $view,
        skipurl         => "mobile/user/" . $u->username . "/$view",
    };

    return DW::Template->render_template( 'mobile/recent.tt', $vars, {'no_sitescheme' => 1} );
}

sub entry_handler {
    my ( $opts, $username, $entryid ) = @_;
    my $r = DW::Request->get;

    my $u = LJ::load_user_or_identity( $username );

    # TODO: error out if this user does not exist

    my $remote = LJ::get_remote();

    my $entry = LJ::Entry->new( $u->userid, ditemid => int( $entryid ) );

    # TODO: check to make sure viewer can view entry
    decorate_entry( $entry, $remote );

    my $vars = {
        'remote' => LJ::User->remote,
        'u' => $u,
        'entry' => $entry,
        'display_icons' => $DISPLAY_ICONS,
    };

    return DW::Template->render_template( 'mobile/entry.tt', $vars, {'no_sitescheme' => 1} );
}

1;
