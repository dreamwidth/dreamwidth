#!/usr/bin/perl
#
# DW::Logic::AdultContent
#
# This module provides logic for various adult content related functions.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Logic::AdultContent;

use strict;

# changes an adult post into a fake LJ-cut if this journal/entry is marked as adult content
# and the viewer doesn't want to see such entries
sub transform_post {
    my ( $class, %opts ) = @_;

    my $post = delete $opts{post} or return '';
    return $post unless LJ::is_enabled( 'adult_content' );

    my $entry = $opts{entry} or return $post;
    my $journal = $opts{journal} or return $post;
    my $remote = delete $opts{remote} || LJ::get_remote();

    # we should show the entry expanded if:
    # the remote user owns the journal that the entry is posted in OR
    # the remote user posted the entry
    my $poster = $entry->poster;
    return $post if LJ::isu( $remote ) && ( $remote->can_manage( $journal ) || $remote->equals( $poster ) );

    my $adult_content = $entry->adult_content_calculated || $journal->adult_content_calculated;
    return $post if $adult_content eq 'none';

    my $view_adult = LJ::isu( $remote ) ? $remote->hide_adult_content : 'concepts';
    if ( !$view_adult || $view_adult eq 'none' || ( $view_adult eq 'explicit' && $adult_content eq 'concepts' ) ) {
        return $post;
    }

    # return a fake LJ-cut going to an adult content warning interstitial page
    my $adult_interstitial = sub {
        return $class->adult_interstitial_link( type => shift(), %opts ) || $post;
    };

    if ( $adult_content eq 'concepts' ) {
        return $adult_interstitial->( 'concepts' );
    } elsif ( $adult_content eq 'explicit' ) {
        return $adult_interstitial->( 'explicit' );
    }

    return $post;
}

# returns an link to an adult content warning page
sub adult_interstitial_link {
    my ( $class, %opts ) = @_;

    my $entry = $opts{entry};
    my $type = $opts{type};
    my $journal = $opts{journal};
    return '' unless $entry && $type;

    my $url = $entry->url;
    my $msg;

    my $markedby = $entry->adult_content_marker;
    if ( $journal->is_community ) {
        $markedby .= '.community';
    } else {
        $markedby .= '.personal';
    }

    if ( $type eq 'explicit' ) {
        $msg = LJ::Lang::ml( 'contentflag.viewingexplicit.by' . $markedby );
    } else {
        $msg = LJ::Lang::ml( 'contentflag.viewingconcepts.by' . $markedby );
    }

    return '' unless $msg;

    my $fake_cut = qq{<b>( <a href="$url">$msg</a> )</b>};
    return $fake_cut;
}

# returns path for adult content warning page
sub adult_interstitial_path {
    my ( $class, %opts ) = @_;

    my $type = $opts{type};
    return '' unless $type;

    my $path = "/journal/adult_${type}";
    return $path;
}

sub interstitial_reason {
    my ( $class, $journal, $entry ) = @_;
    my $poster = defined $entry ? $entry->poster : $journal;
    my $ret = "";
    my $reason_exists = 0;

    if ( $journal->adult_content ne 'none' && $journal->adult_content_reason ) {
        my $what = $journal->is_community ? 'community' : 'journal';
        my $reason = LJ::ehtml( $journal->adult_content_reason );

        if ( $journal->adult_content_calculated eq 'concepts' ) {
            $ret .= LJ::Lang::ml( '/journal/adult_content.tt.message.concepts.' . $what . 'reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        } else {
            $ret .= LJ::Lang::ml( '/journal/adult_content.tt.message.explicit.' . $what . 'reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        }

        $reason_exists = 1;
    }

    if ( defined $entry && $entry->adult_content && $entry->adult_content ne 'none' && $entry->adult_content_reason ) {
        $ret .= "<br />" if $reason_exists;
        my $reason = LJ::ehtml( $entry->adult_content_reason );

        if ( $entry->adult_content eq 'concepts' ) {
            $ret .= LJ::Lang::ml( '/journal/adult_content.tt.message.concepts.byposter.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        } else {
            $ret .= LJ::Lang::ml( '/journal/adult_content.tt.message.explicit.byposter.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        }
        $reason_exists = 1;
    }

    if ( defined $entry && $entry->adult_content_maintainer && $entry->adult_content_maintainer ne 'none' && $entry->adult_content_maintainer_reason ) {
        $ret .= "<br />" if $reason_exists;
        my $reason = LJ::ehtml( $entry->adult_content_maintainer_reason );

        if ( $entry->adult_content_maintainer eq 'concepts' ) {
            $ret .= LJ::Lang::ml( '/journal/adult_content.tt.message.concepts.byjournal.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        } else {
            $ret .= LJ::Lang::ml( '/journal/adult_content.tt.message.explicit.byjournal.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        }
        $reason_exists = 1;
    }

    if ( $reason_exists ) {
        $ret = "<p>$ret</p>";
    }

    return $ret;
}


################################################################################
# These methods are for holding/retrieving data in memcache that states whether
# a particular user has confirmed seeing an adult journal or entry.  The
# structure of the hash in memcache is as follows:
#
# {
#     explicit => {
#       journalid => [ entryid, entryid, ... ],
#       journalid => [ entryid, entryid, ... ],
#     },
#     concepts => {
#       journalid => [ entryid, entryid, ... ],
#       journalid => [ entryid, entryid, ... ],
#     },
# }
#
# Note that an entryid of 0 means that the journal itself has been confirmed.
################################################################################

sub _memcache_key {
    my ( $class, $u ) = @_;

    my $key = "confirmedadult:";

    return [ $u->id, $key . $u->id ]
        if LJ::isu( $u );

    return $key . LJ::UniqCookie->current_uniq;
}

sub confirmed_pages {
    my ( $class, $u ) = @_;

    my $memkey = $class->_memcache_key( $u );
    return LJ::MemCache::get( $memkey ) || {};
}

sub set_confirmed_pages {
    my ( $class, %opts ) = @_;

    my $u = $opts{user};
    my $journalid = $opts{journalid}+0;
    my $entryid = $opts{entryid}+0;
    my $adult_content = $opts{adult_content};

    my $confirmed_pages = $class->confirmed_pages( $u );
    if ( $entryid && $journalid ) {
        push @{$confirmed_pages->{$adult_content}->{$journalid}}, $entryid;
    } elsif ( $journalid ) {
        push @{$confirmed_pages->{$adult_content}->{$journalid}}, 0;
    }

    my $memkey = $class->_memcache_key( $u );
    return LJ::MemCache::set( $memkey, $confirmed_pages, 60*30 );
}

sub user_confirmed_page {
    my ( $class, %opts ) = @_;

    my $u = $opts{user};
    my $journal = $opts{journal};
    my $entry = $opts{entry};
    my $adult_content = $opts{adult_content};

    my $confirmed_pages = DW::Logic::AdultContent->confirmed_pages( $u );
    my $page_confirmed = 0;

    if ( $confirmed_pages && $confirmed_pages->{$adult_content} && $confirmed_pages->{$adult_content}->{$journal->id} ) {
        if ( defined $entry && defined $journal ) {
            $page_confirmed = 1
                if grep { $_ == $entry->ditemid } @{$confirmed_pages->{$adult_content}->{$journal->id}};
        } elsif ( defined $journal ) {
            $page_confirmed = 1
                if grep { $_ == 0 } @{$confirmed_pages->{$adult_content}->{$journal->id}};
        }
    }

    return $page_confirmed;
}

1;
