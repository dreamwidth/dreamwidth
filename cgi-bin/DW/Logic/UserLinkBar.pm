#!/usr/bin/perl
#
# DW::Logic::UserLinkBar - This module provides logic for rendering the user link bar on various pages.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
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
  $link = $user_link_bar->search;

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
        my $link = $self->can( $key ) ? $self->$key : undef;
        push @ret, $link if $link;
    }
    return @ret;
}

sub fix_link {
    my ( $self, $link ) = @_;
    $link->{image} = "$LJ::IMGPREFIX/silk/profile/$link->{image}"
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

    $link->{width} ||= 20;
    $link->{height} ||= 18;

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
                url      => "circle/$user/edit",
                title_ml => 'userlinkbar.leavecomm.title',
                image    => 'community_leave.png',
                text_ml  => 'userlinkbar.leavecomm2',
                class    => "leave",
            } );

        # if logged out, OR, not a member
        } else {
            my @comm_settings = $u->get_comm_settings;
            my $closed = ( $comm_settings[0] && $comm_settings[0] eq 'closed' ) ? 1 : 0;

            my $link = {
                text_ml => 'userlinkbar.joincomm',
            };

            # if they're not allowed to join at this moment (many reasons)
            if ( $closed || !$remote || !$u->is_visible ) {
                $link->{title_ml} = $closed ?
                                        'userlinkbar.joincomm.title.closed' :
                                        'userlinkbar.joincomm.title.loggedout';
                $link->{image}    = 'community_join_disabled.png';
                $link->{class}    = "join_disabled disabled";

            # allowed to join
            } else {
                $link->{url}      = "circle/$user/edit";
                $link->{title_ml} = 'userlinkbar.joincomm.title.open';
                $link->{image}    = 'community_join.png';
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
            $link->{url} = "manage/circle/add?user=$user&action=access";
            $link->{title_ml} = $remote_trusts ? 'userlinkbar.modifytrust.title.other' : 'userlinkbar.addtrust.title.other';
            $link->{class} = "addtrust";
            if ( $remote_trusts ) {
                $link->{image} = 'access_remove.png';
            } else {
                $link->{image} = 'access_grant.png';
            }
        } else {
            $link->{title_ml} = 'userlinkbar.addtrust.title.loggedout';
            $link->{class} = "addtrust_disabled disabled";
            $link->{image} = 'access_grant_disabled.png';
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
        $link->{url} = "manage/circle/add?user=$user&action=subscribe";

        if ( $remote->equals( $u ) ) {
            $link->{title_ml} = $remote_watches ? 'userlinkbar.modifysub.title.self' : 'userlinkbar.addsub.title.self';
        } else {
            $link->{title_ml} = $remote_watches ? 'userlinkbar.modifysub.title.other' : 'userlinkbar.addsub.title.other';
        }

        if ( $u->is_community ) {
            $link->{class} = "addsub_comm";
            if ( $remote_watches ) {
                $link->{image} = 'subscription_remove.png';
            } else {
                $link->{image} = 'subscription_add.png';
            }
        } elsif ( $u->is_syndicated ) {
            $link->{class} = "addsub_feed";
            if ( $remote_watches ) {
                $link->{image} = 'subscription_remove.png';
            } else {
                $link->{image} = 'subscription_add.png';
            }
        } else {
            $link->{class} = "addsub_person";
            if ( $remote_watches ) {
                $link->{image} = 'subscription_remove.png';
            } else {
                $link->{image} = 'subscription_add.png';
            }
        }
    } else {
        $link->{title_ml} = 'userlinkbar.addsub.title.loggedout';
        if ( $u->is_community ) {
            $link->{class} = "addsub_comm_disabled disabled";
            $link->{image} = 'subscription_add_disabled.png';
        } elsif ( $u->is_syndicated ) {
            $link->{class} = "addsub_feed_disabled disabled";
            $link->{image} = 'subscription_add_disabled.png';
        } else {
            $link->{class} = "addsub_person_disabled disabled";
            $link->{image} = 'subscription_add_disabled.png';
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
            url => "update?usejournal=$user",
            class => "postentry",
            image => 'post.png',
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
            class => "postentry_disabled disabled",
            image => 'post_disabled.png',
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
            $link->{url} = "manage/tracking/user?journal=$user";
            $link->{class} = "trackuser";
            $link->{image} = 'track.png';
        } else {
            $link->{title_ml} = $remote ? 'userlinkbar.trackuser.title.cantuseesn' : 'userlinkbar.trackuser.title.loggedout';
            $link->{class} = "trackuser_disabled disabled";
            $link->{image} = 'track_disabled.png';
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
            $link->{url} = "inbox/compose?user=$user";
            $link->{class} = "sendmessage";
            $link->{image} = 'message.png';
        } else {
            $link->{title_ml} = $remote ? 'userlinkbar.sendmessage.title.cantsendmessage' : 'userlinkbar.sendmessage.title.loggedout';
            $link->{class} = "sendmessage_disabled disabled";
            $link->{image} = 'message_disabled.png';
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

    if ( $remote && ! $u->is_identity && LJ::is_enabled('tellafriend') )
    {
        my $link = {
            url => "tools/tellafriend?user=$user",
            image => "$LJ::IMGPREFIX/silk/profile/tellafriend.png",
            width => 16,
            height => 16,
            text_ml => 'userlinkbar.tellafriend2',
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
        url => "tools/memories?user=$user",
        image => 'memories.png',
        text_ml => 'userlinkbar.memories',
        class => 'memories',
    };

    $link->{title_ml} = $u->equals( $remote ) ? 'userlinkbar.memories.title.self' : 'userlinkbar.memories.title.other';

    return $self->fix_link( $link );
}

=head2 C<< $obj->search >>

Returns a hashref with the appropriate icon/link/text for searching this journal.

=cut

sub search {
    my $self = $_[0];

    my $u = $self->{u};
    my $remote = $self->{remote};

    # don't show if search is disabled
    return undef unless
        @LJ::SPHINX_SEARCHD && $u->allow_search_by( $remote );

    my $link = {
        url => 'search?user=' . $u->user,
        image => 'search.png',
        text_ml => "userlinkbar.search",
        title_ml => "userlinkbar.search.title",
        class => 'search',
    };

    return $self->fix_link( $link );
}

=head2 C<< $obj->buyaccount >>

Returns a hashref with the appropriate icon/link/text for buying this user a paid account.

=cut

sub buyaccount {
    my $self = $_[0];

    my $u = $self->{u};
    my $remote = $self->{remote};
    my $user = $u->user;

    # if payments are enabled:
    # show link on personal journals and communities that aren't seed accounts
    # as long as they have less than a year's worth of paid time
    if (
        ( LJ::is_enabled( 'payments' ) ) &&
        ( $u->is_personal || $u->is_community ) &&
        ( DW::Pay::get_account_type( $u ) ne 'seed' ) &&
        ( ( DW::Pay::get_account_expiration_time( $u ) - time() ) < 86400*30 )
    ) {
        my $remote_is_u = $remote && $remote->equals( $u ) ? 1 : 0;
        my $type = $remote_is_u ? 'self' : 'other';
        $type = 'comm' if $u->is_community;

        my $link = {
            url => $remote_is_u ? "shop/account?for=self" : "shop/account?for=gift&user=$user",
            image => 'buy_account.png',
            text_ml => "userlinkbar.buyaccount.$type",
            title_ml => "userlinkbar.buyaccount.title.$type",
            class => 'buyaccount',
        };

        return $self->fix_link( $link );
    }
}

=head1 BUGS

=head1 AUTHORS

Janine Smith <janine@netrophic.com>
Afuna <coder.dw@afunamatata.com>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
