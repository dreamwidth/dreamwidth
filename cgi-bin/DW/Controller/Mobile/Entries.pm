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
DW::Routing->register_regex( qr!^/mobile/entry/([a-z0-9_]+)/([0-9]+)$!, \&entry_handler, app => 1 );

# TODO: a better option for this
my $ITEMS_PER_PAGE = 5;

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
        display_icons   => 1,
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
        'display_icons' => 1,
    };

    return DW::Template->render_template( 'mobile/entry.tt', $vars, {'no_sitescheme' => 1} );
}

1;
