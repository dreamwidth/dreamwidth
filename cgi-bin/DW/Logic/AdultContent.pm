#!/usr/bin/perl
#
# DW::Logic::AdultContent
#
# This module provides logic for various adult content related functions.
#
# Authors:
#      Janine Costanzo <janine@netrophic.com>
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
    return '' unless $entry && $type;

    my $url = $entry->url;
    my $msg;

    my $markedby = $entry->adult_content_marker;

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

    my $path = "$LJ::HOME/htdocs/misc/adult_${type}.bml";
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
            $ret .= LJ::Lang::ml( '/misc/adult_content.bml.message.concepts.' . $what . 'reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        } else {
            $ret .= LJ::Lang::ml( '/misc/adult_content.bml.message.explicit.' . $what . 'reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        }

        $reason_exists = 1;
    }

    if ( defined $entry && $entry->adult_content && $entry->adult_content ne 'none' && $entry->adult_content_reason ) {
        $ret .= "<br />" if $reason_exists;
        my $reason = LJ::ehtml( $entry->adult_content_reason );

        if ( $entry->adult_content eq 'concepts' ) {
            $ret .= LJ::Lang::ml( '/misc/adult_content.bml.message.concepts.byposter.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        } else {
            $ret .= LJ::Lang::ml( '/misc/adult_content.bml.message.explicit.byposter.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        }
        $reason_exists = 1;
    }

    if ( defined $entry && $entry->adult_content_maintainer && $entry->adult_content_maintainer ne 'none' && $entry->adult_content_maintainer_reason ) {
        $ret .= "<br />" if $reason_exists;
        my $reason = LJ::ehtml( $entry->adult_content_maintainer_reason );

        if ( $entry->adult_content_maintainer eq 'concepts' ) {
            $ret .= LJ::Lang::ml( '/misc/adult_content.bml.message.concepts.byjournal.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        } else {
            $ret .= LJ::Lang::ml( '/misc/adult_content.bml.message.explicit.byjournal.reason', { journal => $journal->ljuser_display, poster => $poster->ljuser_display, reason => $reason } );
        }
        $reason_exists = 1;
    }

    if ( $reason_exists ) {
        $ret = "<tr><td colspan=\"2\">\n$ret\n</td></tr>\n";
    }

    return $ret;
}

sub check_adult_cookie {
    my ( $class, $returl, $postref, $type ) = @_;

    my $cookiename = __PACKAGE__->cookie_name( $type );
    return undef unless $cookiename;

    my $has_seen = $BML::COOKIE{$cookiename};
    my $adult_check = $postref->{adult_check};

    BML::set_cookie( $cookiename => '1', 0 ) if $adult_check;
    return $has_seen || $adult_check ? $returl : undef;
}

sub cookie_name {
    my ( $class, $type ) = @_;

    return "" unless $type eq "concepts" || $type eq "explicit";
    return "adult_$type";
}

1;
