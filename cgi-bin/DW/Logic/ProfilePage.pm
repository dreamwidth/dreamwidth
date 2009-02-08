#!/usr/bin/perl
#
# DW::Logic::ProfilePage
#
# This module provides logic for rendering the profile page for various types
# of accounts.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Costanzo <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Logic::ProfilePage;

use strict;


# returns a new profile page object
sub profile_page {
    my ( $u, $remote ) = @_;
    $u = LJ::want_user( $u ) or return undef;

    # remote may be undef, OR a valid object
    return undef
        if defined $remote && ! LJ::isu( $remote );

    # sprinkle holy water
    my $self = { u => $u, remote => $remote };
    bless $self, __PACKAGE__;
    return $self;
}
*LJ::User::profile_page = \&profile_page;
*DW::User::profile_page = \&profile_page;


# returns array of hashrefs
#   (
#       { url => "http://...",
#         title => "Something"
#         image => "http://...",
#         text => "More Text",
#         class => ".css.class",
#       },
#       { ... },
#       ...
#   )
sub action_links {
    my $self = $_[0];

    my $u = $self->{u};
    my $user = $u->user;
    my $remote = $self->{remote};
    my @ret;

### JOIN/LEAVE COMMUNITY

    if ( $u->is_community ) {

        # if logged in and a member of the community $u 
        if ( $remote && 0 ) {
            push @ret, {
                url      => "community/leave.bml?comm=$user",
                title_ml => '.optionlinks.leavecomm.title',
                image    => 'leave-comm.gif',
                text_ml  => '.optionlinks.leavecomm',
                class    => 'profile_leave',
            };

        # if logged out, OR, not a member
        } else {
            my @comm_settings = LJ::get_comm_settings($u);

            my $link = {
                url     => "community/join.bml?comm=$user",
                text_ml => '.optionlinks.joincomm',
            };

            # if they're not allowed to join at this moment (many reasons)
            if ($comm_settings[0] eq 'closed' || !$remote || $remote->is_identity || !$u->is_visible) {
                $link->{title_ml} = $comm_settings[0] eq 'closed' ?
                                        '.optionlinks.joincomm.title.closed' :
                                        '.optionlinks.joincomm.title.loggedout';
                $link->{title_ml} = '.optionlinks.joincomm.title.cantjoin'
                    if $remote && $remote->is_identity;
                $link->{image}    = 'join-comm-disabled.gif';
                $link->{class}    = 'profile_join_disabled';

            # allowed to join
            } else {
                $link->{title_ml} = '.optionlinks.joincomm.title.open';
                $link->{image}    = 'join-comm.gif';
                $link->{class}    = 'profile_join';
            }

            push @ret, $link;
        }

    }

    # fix up image links and URLs and language
    foreach my $link ( @ret ) {
        $link->{image} = "$LJ::IMGPREFIX/profile_icons/$link->{image}"
            if $link->{image} !~ /^$LJ::IMGPREFIX/;
        $link->{url} = "$LJ::SITEROOT/$link->{url}"
            if $link->{image} !~ /^$LJ::SITEROOT/;

        if ( my $ml = delete $link->{title_ml} ) {
            $link->{title} = LJ::Lang::ml( $ml );
        }
        if ( my $ml = delete $link->{text_ml} ) {
            $link->{text} = LJ::Lang::ml( $ml );
        }
    }

    return @ret;
}


# returns hashref with userpic display options
#  {
#     userpic      => 'http://...',
#     userpic_url  => 'http://...',    # OPTIONAL
#     caption_text => 'Edit',          # OPTIONAL
#     caption_url  => 'http://...',    # OPTIONAL
#  }
sub userpic {
    my $self = $_[0];

    my $u = $self->{u};
    my $user = $u->user;
    my $remote = $self->{remote};
    my $ret = {};

    # syndicated accounts have a very simple thing
    if ( $u->is_syndicated ) {
        return {
            userpic => "$LJ::IMGPREFIX/profile_icons/feed.gif",
        };
    }

    # determine what picture URL to use
    if ( my $up = $u->userpic ) {
        $ret->{userpic} = $up->url;
    } elsif ( $u->is_person ) {
        $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/user.gif";
    } elsif ( $u->is_community ) {
        $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/comm.gif";
    } elsif ( $u->is_identity ) {
        $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/openid.gif";
    }

    # now determine what caption text to show
    if ( $remote && $remote->can_manage( $u ) ) {
        if ( LJ::userpic_count( $u ) ) {
            $ret->{userpic_url} = "$LJ::SITEROOT/allpics.bml?user=$user";
            $ret->{caption_text} = LJ::Lang::ml( '.section.edit' );
            $ret->{caption_url} = "$LJ::SITEROOT/editpics.bml?authas=$user"
        } else {
            $ret->{userpic_url} = "$LJ::SITEROOT/editpics.bml?authas=$user";
            $ret->{caption_text} = LJ::Lang::ml( '.userpic.upload' );
            $ret->{caption_url} = "$LJ::SITEROOT/editpics.bml?authas=$user"
        }
    } else {
        if ( LJ::userpic_count( $u ) ) {
            $ret->{userpic_url} = "$LJ::SITEROOT/allpics.bml?user=$user";
        }
    }

    return $ret;
}


# returns an array of journal warnings
#   (
#       { class => 'someclass',
#         text => 'Some Warning',
#        },
#       ...
#   )
sub warnings {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    if ($u->is_locked) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml( 'statusvis_message.locked' ) };
    } elsif ($u->is_memorial) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml( 'statusvis_message.memorial' ) };
    } elsif ($u->is_readonly) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml( 'statusvis_message.readonly' ) };
    }

    unless ($u->is_identity) {
        if ($u->adult_content_calculated eq 'explicit') {
            push @ret, { class => 'journal_adult_warning', text => LJ::Lang::ml( '.details.warning.explicit' ) };
        } elsif ($u->adult_content_calculated eq 'concepts') {
            push @ret, { class => 'journal_adult_warning', text => LJ::Lang::ml( '.details.warning.concepts' ) };
        }
    }

    return @ret;
}


# returns an array of comment statistic strings
sub comment_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $num_comments_received = $u->num_comments_received;
    my $num_comments_posted = $u->num_comments_posted;

    push @ret, LJ::Lang::ml( '.details.comments.received2', { num_raw => $num_comments_received, num_comma => LJ::commafy( $num_comments_received ) } )
        unless $u->is_identity;
    push @ret, LJ::Lang::ml( '.details.comments.posted2', { num_raw => $num_comments_posted, num_comma => LJ::commafy( $num_comments_posted ) } )
        if LJ::is_enabled( 'show-talkleft' ) && ( $u->is_personal || $u->is_identity );

    return @ret;
}


# returns an array of support statistic strings
sub support_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $supportpoints = $u->support_points_count;
    push @ret, LJ::Lang::ml( '.details.supportpoints2', { aopts => qq{href="$LJ::SITEROOT/support/"}, num => LJ::commafy( $supportpoints ) } )
        if $supportpoints;

    return @ret;
}


# return array of statistic strings
sub entry_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $ct = $u->number_of_posts;
    push @ret, LJ::Lang::ml( '.details.entries3', {
        num_raw => $ct,
        num_comma => LJ::commafy( $ct ),
        aopts => 'href="' . $u->journal_base . '"',
    } )
        unless $u->is_identity;
    
    return @ret;
}


# return array of statistic strings
sub tag_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $ct = scalar keys %{ $u->tags || {} };
    push @ret, LJ::Lang::ml( '.details.tags2', {
        num_raw => $ct,
        num_comma => LJ::commafy( $ct ),
        aopts => 'href="' . $u->journal_base . '/tag/"',
    } )
        unless $u->is_identity || $u->is_syndicated;
    
    return @ret;
}


# return array of statistic strings
sub memory_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $ct = LJ::Memories::count( $u->id ) || 0;
    push @ret, LJ::Lang::ml( '.details.memories2', {
        num_raw => $ct,
        num_comma => LJ::commafy( $ct ),
        aopts => "href='$LJ::SITEROOT/tools/memories.bml?user=" . $u->user . "'",
    } )
        unless $u->is_syndicated;
    
    return @ret;
}


# return array of statistic strings
sub userpic_stats {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    my $ct = LJ::userpic_count( $u );
    push @ret, LJ::Lang::ml( '.details.userpics', {
        num_raw => $ct,
        num_comma => LJ::commafy( $ct ),
        aopts => "href='$LJ::SITEROOT/allpics.bml?user=" . $u->user . "'",
    } )
        unless $u->is_syndicated;
    
    return @ret;
}


# returns array of hashrefs
sub basic_info_rows {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret = $self->_basic_info_display_name;

# FIXME: remove this line :)
    return @ret;

    if ( $u->is_community ) {
        push @ret, $self->_basic_info_location;
        push @ret, $self->_basic_info_website;
        push @ret, $self->_basic_info_comm_settings;
        push @ret, $self->_basic_info_comm_theme;

    } elsif ( $u->is_syndicated ) {
        push @ret, $self->_basic_info_syn_status;
        push @ret, $self->_basic_info_syn_readers;

    } else {
        push @ret, $self->_basic_info_birthday;
        push @ret, $self->_basic_info_location;
        push @ret, $self->_basic_info_website;
    }

    return @ret;
}


sub _basic_info_display_name {
    my $self = $_[0];

    my $u = $self->{u};
    return [ "test", "display name" ];
}


sub _basic_info_website {
    return [ "stuff", { url => "blah", text => "some text" } ];
}


sub contact_rows {
    return ( { email => 'foo@bar.com' }, "thingy2" );
}


1;
