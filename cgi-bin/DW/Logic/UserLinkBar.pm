#!/usr/bin/perl
#
# DW::Logic::UserLinkBar - This module provides logic for rendering the user link bar on various pages.
#
# Authors:
#      Janine Costanzo <janine@netrophic.com>
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Logic::UserLinkBar;

=head1 NAME

DW::Logic::UserLinkBar - This module provides logic for rendering the user link bar on various pages.

=head1 SYNOPSIS

  use DW::Logic::UserLinkBar;

  # initialize the object
  my $user_link_bar = $u->user_link_bar( $remote, [class_prefix => $context ] );
  
  # get links in bulk
  my @links = $user_link_bar->get_links( "manage_membership", "trust", ... );

  # get links apiece
  my $link;
  $link = $user_link_bar->manage_membership;
  $link = $user_link_bar->trust;
  $link = $user_link_bar->watch;
  $link = $user_link_bar->post;
  $link = $user_link_bar->track;
  $link = $user_link_bar->message;
  $link = $user_link_bar->tellafriend;
  $link = $user_link_bar->memories;

=cut

use strict;
use warnings;

=head1 API

=head2 C<< $u->user_link_bar( $remote, %opts ) >>

Returns a new user link bar object.

=cut

sub user_link_bar {
    my ( $u, $remote, %opts ) = @_;
    $u = LJ::want_user( $u ) or return undef;

    # remote may be undef, OR a valid object
    return undef
        if defined $remote && ! LJ::isu( $remote );

    my $prefix = defined( $opts{class_prefix} ) ? $opts{class_prefix} : "userlinkbar";
    
    # sprinkle holy water
    my $self = { u => $u, remote => $remote, class_prefix => $prefix };
    bless $self, __PACKAGE__;
    return $self;
}
*LJ::User::user_link_bar = \&user_link_bar;
*DW::User::user_link_bar = \&user_link_bar;

=head2 C<< $obj->get_links( "funcname", "funcname2", ... ) >>

Given a list of keys corresponding to the user link bar functions, 
return an array of hashrefs containing link information.

(
    {   url => "http://...",
        title => "Something"
        image => "http://...",
        text => "More Text",
        class => ".css.class",
    },
    { ... },
    ...
)

=cut

sub get_links {
    my ( $self, @link_keyseq ) = @_;
    
    my @ret;
    foreach my $key ( @link_keyseq ) {
        my $link = $self->$key if $self->can( $key );
        push @ret, $link if $link;
    }
    return @ret;
}

sub fix_link {
    my ( $self, $link ) = @_;
    $link->{image} = "$LJ::IMGPREFIX/profile_icons/$link->{image}"
        if $link->{image} && $link->{image} !~ /^$LJ::IMGPREFIX/;
    $link->{url} = "$LJ::SITEROOT/$link->{url}"
        if $link->{url} && $link->{url} !~ /^$LJ::SITEROOT/;

    if ( my $ml = delete $link->{title_ml} ) {
        $link->{title} = LJ::Lang::ml( $ml );
    }
    if ( my $ml = delete $link->{text_ml} ) {
        $link->{text} = LJ::Lang::ml( $ml );
    }
    
    $link->{class} = $self->{class_prefix} . "_" . $link->{class} 
        if $self->{class_prefix} && $link->{class};

    return $link;
}

=head2 C<< $obj->manage_membership >>

Returns a hashref with the appropriate icon/link/text for joining/leaving a community

=cut

sub manage_membership {
    my $self = $_[0];
    
    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    if ( $u->is_community ) {
        # if logged in and a member of the community $u
        if ( $remote && $remote->member_of( $u ) ) {
            return $self->fix_link( {
                url      => "community/leave.bml?comm=$user",
                title_ml => 'userlinkbar.leavecomm.title',
                image    => 'leave-comm.gif',
                text_ml  => 'userlinkbar.leavecomm',
                class    => "leave",
            } );

        # if logged out, OR, not a member
        } else {
            my @comm_settings = LJ::get_comm_settings($u);

            my $link = {
                text_ml => 'userlinkbar.joincomm',
            };

            # if they're not allowed to join at this moment (many reasons)
            if ($comm_settings[0] eq 'closed' || !$remote || $remote->is_identity || !$u->is_visible) {
                $link->{title_ml} = $comm_settings[0] eq 'closed' ?
                                        'userlinkbar.joincomm.title.closed' :
                                        'userlinkbar.joincomm.title.loggedout';
                $link->{title_ml} = 'userlinkbar.joincomm.title.cantjoin'
                    if $remote && $remote->is_identity;
                $link->{image}    = 'join-comm-disabled.gif';
                $link->{class}    = "join_disabled";

            # allowed to join
            } else {
                $link->{url}      = "community/join.bml?comm=$user";
                $link->{title_ml} = 'userlinkbar.joincomm.title.open';
                $link->{image}    = 'join-comm.gif';
                $link->{class}    = "join";
            }

            return $self->fix_link( $link );
        }
    }
}

=head2 C<< $obj->trust >>

Returns a hashref with the appropriate icon/link/text for adding a journal to your trust list.

=cut

sub trust {
    my $self = $_[0];
    
    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    # can add/modify trust for the user if they are a person and not the same as the remote user, and remote is a personal account
    if ( ( $u->is_personal || $u->is_identity ) && ( !$remote || ( $remote && !$remote->equals( $u ) && $remote->is_personal ) ) ) {
        my $link = {};

        my $remote_trusts = $remote && $remote->trusts( $u ) ? 1 : 0;
        $link->{text_ml} = $remote_trusts ? 'userlinkbar.modifytrust' : 'userlinkbar.addtrust';
        if ( $remote && ( $remote_trusts || $u->is_visible ) ) {
            $link->{url} = "manage/circle/add.bml?user=$user&action=access";
            $link->{title_ml} = $remote_trusts ? 'userlinkbar.modifytrust.title.other' : 'userlinkbar.addtrust.title.other';
            $link->{class} = "addtrust";
            $link->{image} = 'add-friend.gif';
        } else {
            $link->{title_ml} = 'userlinkbar.addtrust.title.loggedout';
            $link->{class} = "addtrust_disabled";
            $link->{image} = 'add-friend-disabled.gif';
        }

        return $self->fix_link( $link );
    }
}

=head2 C<< $obj->watch >>

Returns a hashref with the appropriate icon/link/text for adding a journal to your watch list.

=cut

sub watch {
    my $self = $_[0];
    
    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    my $link = {};

    my $remote_watches = $remote && $remote->watches( $u ) ? 1 : 0;
    $link->{text_ml} = $remote_watches ? 'userlinkbar.modifysub' : 'userlinkbar.addsub';
    if ( $remote && ( $remote_watches || $u->is_visible ) ) {
        $link->{url} = "manage/circle/add.bml?user=$user&action=subscribe";

        if ( $remote->equals( $u ) ) {
            $link->{title_ml} = $remote_watches ? 'userlinkbar.modifysub.title.self' : 'userlinkbar.addsub.title.self';
        } else {
            $link->{title_ml} = $remote_watches ? 'userlinkbar.modifysub.title.other' : 'userlinkbar.addsub.title.other';
        }

        if ( $u->is_community ) {
            $link->{class} = "addsub_comm";
            $link->{image} = 'watch-comm.gif';
        } elsif ( $u->is_syndicated ) {
            $link->{class} = "addsub_feed";
            $link->{image} = 'add-feed.gif';
        } else {
            $link->{class} = "addsub_person";
            $link->{image} = 'add-friend.gif';
        }
    } else {
        $link->{title_ml} = 'userlinkbar.addsub.title.loggedout';
        if ( $u->is_community ) {
            $link->{class} = "addsub_comm_disabled";
            $link->{image} = 'watch-comm-disabled.gif';
        } elsif ( $u->is_syndicated ) {
            $link->{class} = "addsub_feed_disabled";
            $link->{image} = 'add-feed-disabled.gif';
        } else {
            $link->{class} = "addsub_person_disabled";
            $link->{image} = 'add-friend-disabled.gif';
        }
    }

    return $self->fix_link( $link );
}


=head2 C<< $obj->post >>

Returns a hashref with the appropriate icon/link/text for posting an entry to this journal.

=cut

sub post {
    my $self = $_[0];
    
    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    if ( $remote && $remote->is_personal && ( $u->is_personal || $u->is_community ) && $remote->can_post_to( $u ) ) {
        my $link = {
            url => "update.bml?usejournal=$user",
            class => "postentry",
            image => 'post-entry.gif',
        };

        if ( $u->is_community ) {
            $link->{text_ml} = 'userlinkbar.post';
            $link->{title_ml} = 'userlinkbar.post.title';
        } else {
            $link->{text_ml} = 'userlinkbar.postentry';
            $link->{title_ml} = 'userlinkbar.postentry.title';
        }

        return $self->fix_link( $link );
    } elsif ( $u->is_community ) {
        return $self->fix_link ( {
            text_ml => 'userlinkbar.post',
            title_ml => $remote ? 'userlinkbar.post.title.cantpost' : 'userlinkbar.post.title.loggedout',
            class => "postentry_disabled",
            image => 'post-entry-disabled.gif',
        } );
    }
}

=head2 C<< $obj->track >>

Returns a hashref with the appropriate icon/link/text for tracking this journal

=cut

sub track {
    my $self = $_[0];
    
    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    if ( LJ::is_enabled( 'esn' ) ) {
        my $link = {
            text_ml => 'userlinkbar.trackuser',
            title_ml => 'userlinkbar.trackuser.title',
        };

        if ( $remote && $remote->equals( $u ) ) {
            # you can't track yourself
            return undef;
        } elsif ( $u->is_community ) {
            $link->{text_ml} = 'userlinkbar.track';
            $link->{title_ml} = 'userlinkbar.track.title';
        } elsif ( $u->is_syndicated ) {
            $link->{text_ml} = 'userlinkbar.tracksyn';
            $link->{title_ml} = 'userlinkbar.tracksyn.title';
        }

        if ( $remote && $remote->can_use_esn ) {
            $link->{url} = "manage/subscriptions/user.bml?journal=$user";
            $link->{class} = "trackuser";
            $link->{image} = 'track.gif';
        } else {
            $link->{title_ml} = $remote ? 'userlinkbar.trackuser.title.cantuseesn' : 'userlinkbar.trackuser.title.loggedout';
            $link->{class} = "trackuser_disabled";
            $link->{image} = 'track-disabled.gif';
        }

        return $self->fix_link( $link );
    }
}

=head2 C<< $obj->message >>

Returns a hashref with the appropriate icon/link/text for sending a PM to this user.

=cut

sub message {
    my $self = $_[0];
    
    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    if ( $u->is_personal || $u->is_identity ) {
        my $link = {
            text_ml => 'userlinkbar.sendmessage',
            title_ml => 'userlinkbar.sendmessage.title',
        };

        $link->{title_ml} = 'userlinkbar.sendmessage.title.self' if $u->equals( $remote );

        if ( $remote && $u->can_receive_message( $remote ) ) {
            $link->{url} = "inbox/compose.bml?user=$user";
            $link->{class} = "sendmessage";
            $link->{image} = 'send-message.gif';
        } else {
            $link->{title_ml} = $remote ? 'userlinkbar.sendmessage.title.cantsendmessage' : 'userlinkbar.sendmessage.title.loggedout';
            $link->{class} = "sendmessage_disabled";
            $link->{image} = 'send-message-disabled.gif';
        }

        return $self->fix_link( $link );
    }
}

=head2 C<< $obj->tellafriend >>

Returns a hashref with the appropriate icon/link/text for telling a friend about this journal.

=cut

sub tellafriend {
    my $self = $_[0];
    
    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    if ( $remote && $u->{journaltype} ne 'I' && ! $LJ::DISABLED{tellafriend} )
    {
        my $link = {
            url => "tools/tellafriend.bml?user=$user",
            image => "$LJ::IMGPREFIX/btn_tellfriend.gif", # this button doesn't fit in
            text_ml => 'userlinkbar.tellafriend',
            class => 'tellafriend',
        };

        $link->{title_ml} = $u->equals( $remote ) ? 'userlinkbar.tellafriend.title.self' : 'userlinkbar.tellafriend.title.other';
        return $self->fix_link( $link );
    }
}

=head2 C<< $obj->memories >>

Returns a hashref with the appropriate icon/link/text for viewing this user's memories.

=cut

sub memories {
    my $self = $_[0];

    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    my $link = {
        url => "tools/memories.bml?user=$user",
        image => 'memories.gif',
        text_ml => 'userlinkbar.memories',
        class => 'memories',
    };

    $link->{title_ml} = $u->equals( $remote ) ? 'userlinkbar.memories.title.self' : 'userlinkbar.memories.title.other';

    return $self->fix_link( $link );
}

=head1 BUGS

=head1 AUTHORS

Janine Costanzo <janine@netrophic.com>
Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
