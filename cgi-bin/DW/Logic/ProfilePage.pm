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
    my ( $u, $remote, %opts ) = @_;
    $u = LJ::want_user( $u ) or return undef;

    # remote may be undef, OR a valid object
    return undef
        if defined $remote && ! LJ::isu( $remote );

    my $viewall = $opts{viewall} ? $opts{viewall} : 0;

    # sprinkle holy water
    my $self = { u => $u, remote => $remote, viewall => $viewall };
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
        # FIXME: change this when there's a way to check community membership
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
                $link->{url}      = "community/join.bml?comm=$user";
                $link->{title_ml} = '.optionlinks.joincomm.title.open';
                $link->{image}    = 'join-comm.gif';
                $link->{class}    = 'profile_join';
            }

            push @ret, $link;
        }
    }

### ADD TRUST

    # can add/modify trust for the user if they are a person and not the same as the remote user
    if ( ( $u->is_personal || $u->is_identity ) && ( !$remote || ( $remote && !$remote->equals( $u ) ) ) ) {
        my $link = {};

        my $remote_trusts = $remote && $remote->trusts( $u ) ? 1 : 0;
        $link->{text_ml} = $remote_trusts ? '.optionlinks.modifytrust' : '.optionlinks.addtrust';
        if ( $remote && ( $remote_trusts || $u->is_visible ) ) {
            $link->{url} = "manage/circle/add.bml?user=$user";
            $link->{title_ml} = $remote_trusts ? '.optionlinks.modifytrust.title.other' : '.optionlinks.addtrust.title.other';
            $link->{class} = 'profile_addtrust';
            $link->{image} = 'add-friend.gif';
        } else {
            $link->{title_ml} = '.optionlinks.addtrust.title.loggedout';
            $link->{class} = 'profile_addtrust_disabled';
            $link->{image} = 'add-friend-disabled.gif';
        }

        push @ret, $link;
    }

### ADD WATCH

    {
        my $link = {};

        my $remote_watches = $remote && $remote->watches( $u ) ? 1 : 0;
        $link->{text_ml} = $remote_watches ? '.optionlinks.modifysub' : '.optionlinks.addsub';
        if ( $remote && ( $remote_watches || $u->is_visible ) ) {
            $link->{url} = "manage/circle/add.bml?user=$user";

            if ( $remote->equals( $u ) ) {
                $link->{title_ml} = $remote_watches ? '.optionlinks.modifysub.title.self' : '.optionlinks.addsub.title.self';
            } else {
                $link->{title_ml} = $remote_watches ? '.optionlinks.modifysub.title.other' : '.optionlinks.addsub.title.other';
            }

            if ( $u->is_community ) {
                $link->{class} = 'profile_addsub_comm';
                $link->{image} = 'watch-comm.gif';
            } elsif ( $u->is_syndicated ) {
                $link->{class} = 'profile_addsub_feed';
                $link->{image} = 'add-feed.gif';
            } else {
                $link->{class} = 'profile_addsub_person';
                $link->{image} = 'add-friend.gif';
            }
        } else {
            $link->{title_ml} = '.optionlinks.addsub.title.loggedout';
            if ( $u->is_community ) {
                $link->{class} = 'profile_addsub_comm_disabled';
                $link->{image} = 'watch-comm-disabled.gif';
            } elsif ( $u->is_syndicated ) {
                $link->{class} = 'profile_addsub_feed_disabled';
                $link->{image} = 'add-feed-disabled.gif';
            } else {
                $link->{class} = 'profile_addsub_person_disabled';
                $link->{image} = 'add-friend-disabled.gif';
            }
        }

        push @ret, $link;
    }

### POST ENTRY

    if ( $remote && $remote->is_personal && ( $u->is_personal || $u->is_community ) && $remote->can_post_to( $u ) ) {
        my $link = {
            url => "update.bml?usejournal=$user",
            class => 'profile_postentry',
            image => 'post-entry.gif',
        };

        if ( $u->is_community ) {
            $link->{text_ml} = '.optionlinks.post';
            $link->{title_ml} = '.optionlinks.post.title';
        } else {
            $link->{text_ml} = '.optionlinks.postentry';
            $link->{title_ml} = '.optionlinks.postentry.title';
        }

        push @ret, $link;
    } elsif ( $u->is_community ) {
        push @ret, {
            text_ml => '.optionlinks.post',
            title_ml => $remote ? '.optionlinks.post.title.cantpost' : '.optionlinks.post.title.loggedout',
            class => 'profile_postentry_disabled',
            image => 'post-entry-disabled.gif',
        };
    }

### TRACK

    if ( LJ::is_enabled( 'esn' ) ) {
        my $link = {
            text_ml => '.optionlinks.trackuser',
            title_ml => '.optionlinks.trackuser.title',
        };

        if ( $remote && $remote->equals( $u ) ) {
            $link->{text_ml} = '.optionlinks.tracking';
            $link->{title_ml} = '.optionlinks.tracking.title';
        } elsif ( $u->is_community ) {
            $link->{text_ml} = '.optionlinks.track';
            $link->{title_ml} = '.optionlinks.track.title';
        } elsif ( $u->is_syndicated ) {
            $link->{text_ml} = '.optionlinks.tracksyn';
            $link->{title_ml} = '.optionlinks.tracksyn.title';
        }

        if ( $remote && $remote->can_use_esn ) {
            $link->{url} = "manage/subscriptions/user.bml?journal=$user";
            $link->{class} = 'profile_trackuser';
            $link->{image} = 'track.gif';
        } else {
            $link->{title_ml} = $remote ? '.optionlinks.trackuser.title.cantuseesn' : '.optionlinks.trackuser.title.loggedout';
            $link->{class} = 'profile_trackuser_disabled';
            $link->{image} = 'track-disabled.gif';
        }

        push @ret, $link;
    }

### PRIVATE MESSAGE

    if ( ( $u->is_personal || $u->is_identity ) && !$u->equals( $remote ) ) {
        my $link = {
            text_ml => '.optionlinks.sendmessage',
            title_ml => '.optionlinks.sendmessage.title',
        };

        if ( $remote && $u->can_receive_message( $remote ) ) {
            $link->{url} = "inbox/compose.bml?user=$user";
            $link->{class} = 'profile_sendmessage';
            $link->{image} = 'send-message.gif';
        } else {
            $link->{title_ml} = $remote ? '.optionlinks.sendmessage.title.cantsendmessage' : '.optionlinks.sendmessage.title.loggedout';
            $link->{class} = 'profile_sendmessage_disabled';
            $link->{image} = 'send-message-disabled.gif';
        }

        push @ret, $link;
    }

### EXTRA

    # fix up image links and URLs and language
    foreach my $link ( @ret ) {
        $link->{image} = "$LJ::IMGPREFIX/profile_icons/$link->{image}"
            if $link->{image} !~ /^$LJ::IMGPREFIX/;
        $link->{url} = "$LJ::SITEROOT/$link->{url}"
            if $link->{url} !~ /^$LJ::SITEROOT/;

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
    } elsif ( $u->is_personal ) {
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

    if ( $u->is_locked ) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml( 'statusvis_message.locked' ) };
    } elsif ( $u->is_memorial ) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml( 'statusvis_message.memorial' ) };
    } elsif ( $u->is_readonly ) {
        push @ret, { class => 'statusvis_msg', text => LJ::Lang::ml( 'statusvis_message.readonly' ) };
    }

    unless ( $u->is_identity ) {
        if ( $u->adult_content_calculated eq 'explicit' ) {
            push @ret, { class => 'journal_adult_warning', text => LJ::Lang::ml( '.details.warning.explicit' ) };
        } elsif ( $u->adult_content_calculated eq 'concepts' ) {
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

    if ( $u->is_community ) {
        push @ret, $self->_basic_info_location;
        push @ret, $self->_basic_info_website;
        push @ret, $self->_basic_info_comm_membership;
        push @ret, $self->_basic_info_comm_postlevel;
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


# returns the account's displayed name
# available for all account types
sub _basic_info_display_name {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    my $name = $u->name_html;
    if ( $u->is_syndicated ) {
        $ret->[0] = LJ::Lang::ml( '.label.syndicatedfrom' );
        $ret->[1] = ' ';

        if ( my $url = $u->url ) {
            $ret->[2] = { url => LJ::ehtml( $url ), text => $name };
        } else {
            $ret->[2] = { text => $name };
        }

        my $synd = $u->get_syndicated;
        $ret->[3] = {
            url => LJ::ehtml( $synd->{synurl} ),
            text => "<img src='$LJ::IMGPREFIX/xml.gif' width='36' height='14' align='absmiddle' border='0' alt=\"" . LJ::Lang::ml( '.syn.xml' ) . "\" /></a>",
        };
    } else {
        unless ( $u->underage || $name eq $u->prop( 'journaltitle' ) ) {
            $ret->[0] = LJ::Lang::ml( '.label.name' );
            $ret->[1] = $name;
        }
    }

    return $ret;
}


# returns the account's birthday
# available only for personal and identity account types
sub _basic_info_birthday {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret unless $u->is_personal || $u->is_identity;

    if ( $u->bday_string && ( $u->can_share_bday || $self->{viewall} ) ) {
        my $bdate = $u->prop( 'bdate' );
        if ( $bdate && $bdate ne "0000-00-00" ) {
            $ret->[0] = LJ::Lang::ml( '.label.birthdate' );
            $ret->[1] = $u->bday_string;
        }
    }

    return $ret;
}


# returns the account's location
# available only for personal, identity, and community account types
sub _basic_info_location {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret if $u->is_syndicated;

    my ( $city, $state, $country ) = ( $u->prop( 'city' ), $u->prop( 'state' ), $u->prop( 'country' ) );
    my ( $city_ret, $state_ret, $country_ret );
    if ( ( $u->can_show_location || $self->{viewall} ) && ( $city || $state || $country ) ) {
        my $ecity = LJ::eurl( $city );
        my $ecountry = LJ::eurl( $country );
        my $estate = "";

        if ( $country ) {
            my %countries = ();
            LJ::load_codes( { country => \%countries } );

            $country_ret = LJ::is_enabled( 'directory' ) ?
                { url => "$LJ::SITEROOT/directory.bml?opt_sort=ut&amp;s_loc=1&amp;loc_cn=$ecountry", text => $countries{ $country } } :
                $countries{ $country };
        }

        if ( $state ) {
            my %states;
            my $states_type = $LJ::COUNTRIES_WITH_REGIONS{ $country }->{type};
            LJ::load_codes( { $states_type => \%states } ) if defined $states_type;

            $state = LJ::ehtml( $state );
            $state = $states{$state} if $states_type && $states{$state};
            $estate = LJ::eurl( $state );
            $state_ret = $country && LJ::is_enabled( 'directory' ) ?
                { url => "$LJ::SITEROOT/directory.bml?opt_sort=ut&amp;s_loc=1&amp;loc_cn=$ecountry&amp;loc_st=$estate", text => LJ::ehtml( $state ) } :
                LJ::ehtml( $state );
        }

        if ( $city ) {
            $city = LJ::ehtml( $city );
            $city_ret = $country && LJ::is_enabled( 'directory' ) ?
                { url => "$LJ::SITEROOT/directory.bml?opt_sort=ut&amp;s_loc=1&amp;loc_cn=$ecountry&amp;loc_st=$estate&amp;loc_ci=$ecity", text => $city } :
                $city;
        }

        push @$ret, $city_ret, $state_ret, $country_ret;
        unshift @$ret, ( LJ::Lang::ml( '.label.location' ), ', ' );
    }

    return $ret;
}


# returns the account's website
# available only for personal, identity, and community account types
sub _basic_info_website {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret if $u->is_syndicated;

    my ( $url, $urlname ) = ( $u->url, $u->prop( 'urlname' ) );
    if ( $url ) {
        $url = LJ::ehtml( $url );
        unless ($url =~ /^https?:\/\//) {
            $url =~ s/^http\W*//;
            $url = "http://$url";
        }
        $urlname = LJ::ehtml( $urlname || $url );
        if ( $url ) {
            $ret->[0] = LJ::Lang::ml( '.label.website' );
            $ret->[1] = { url => $url, text => $urlname };
        }
    }

    return $ret;
}


# returns the account's community membership
# available only for community account types
sub _basic_info_comm_membership {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret unless $u->is_community;

    my ( $membership, $postlevel ) = LJ::get_comm_settings( $u );

    my $membership_string = LJ::Lang::ml( '.commsettings.membership.open' );
    if ( $membership eq "moderated" ) {
        $membership_string = LJ::Lang::ml( '.commsettings.membership.moderated' );
    } elsif ( $membership eq "closed" ) {
        $membership_string = LJ::Lang::ml( '.commsettings.membership.closed' );
    }

    $ret->[0] = LJ::Lang::ml( '.commsettings.membership.header' );
    $ret->[1] = $membership_string;

    return $ret;
}


# returns the account's community posting level
# available only for community account types
sub _basic_info_comm_postlevel {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret unless $u->is_community;

    my ( $membership, $postlevel ) = LJ::get_comm_settings( $u );

    my $postlevel_string = LJ::Lang::ml( '.commsettings.postlevel.members' );
    if ( $postlevel eq "select" ) {
        $postlevel_string = LJ::Lang::ml( '.commsettings.postlevel.select' );
    } elsif ( $u->prop( 'nonmember_posting' ) ) {
        $postlevel_string = LJ::Lang::ml( '.commsettings.postlevel.anybody' );
    }

    $postlevel_string .= LJ::Lang::ml( '.commsettings.postlevel.moderated' ) if $u->prop( 'moderated' );

    $ret->[0] = LJ::Lang::ml( '.commsettings.postlevel.header' );
    $ret->[1] = $postlevel_string;

    return $ret;
}


# returns the account's community theme
# available only for community account types
sub _basic_info_comm_theme {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret unless $u->is_community;

    if ( $u->prop( 'comm_theme' ) ) {
        $ret->[0] = LJ::Lang::ml( '.commdesc.header' );
        $ret->[1] = LJ::ehtml( $u->prop( 'comm_theme' ) );
    }

    return $ret;
}


# returns the account's feed status
# available only for syndication account types
sub _basic_info_syn_status {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret unless $u->is_syndicated;

    my $synd = $u->get_syndicated;
    my $syn_status;

    $syn_status .= LJ::Lang::ml( '.syn.lastcheck' ) . " ";
    $syn_status .= $synd->{lastcheck} || LJ::Lang::ml( '.syn.last.never' );
    my $status = {
        parseerror => "Parse error",
        notmodified => "Not modified",
        toobig => "Too big",
        posterror => "Posting error",
        ok => "",     # no status line necessary
        nonew => "",  # no status line necessary
    }->{ $synd->{laststatus} };
    $syn_status .= " ($status)" if $status;

    if ($synd->{laststatus} eq 'parseerror') {
       $syn_status .= "<br />" . LJ::Lang::ml( '.syn.parseerror' ) . " " . LJ::ehtml( $u->prop( 'rssparseerror' ) );
    }

    $syn_status .= "<br />" . LJ::Lang::ml( '.syn.nextcheck' ) . " $synd->{checknext}";

    $ret->[0] = LJ::Lang::ml( '.label.syndicatedstatus' );
    $ret->[1] = $syn_status;

    return $ret;
}


# returns the account's feed readers
# available only for syndication account types
sub _basic_info_syn_readers {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret = [];

    return $ret unless $u->is_syndicated;

    $ret->[0] = LJ::Lang::ml( '.label.syndreadcount' );
    $ret->[1] = scalar $u->watched_by_userids;

    return $ret;
}


# returns various methods of contacting the user
sub contact_rows {
    my $self = $_[0];

    my $u = $self->{u};
    my $remote = $self->{remote};
    my @ret = ();

    # private message
    if ( ( $u->is_personal || $u->is_identity ) && $remote && !$remote->equals( $u ) && $u->can_receive_message( $remote ) ) {
        push @ret, { url => "$LJ::SITEROOT/inbox/compose.bml?user=" . $u->user, text => LJ::Lang::ml( '.contact.pm' ) };
    }

    # email
    if ( ( !$u->is_syndicated && $u->share_contactinfo( $remote ) ) || $self->{viewall} ) {
        my @emails = $u->emails_visible( $remote );
        foreach my $email (@emails) {
            push @ret, { email => $email };
        }
    }

    # text message
    if ( !$u->is_syndicated && $u->can_be_text_messaged_by( $remote ) ) {
        push @ret, { url => "$LJ::SITEROOT/tools/textmessage.bml?user=" . $u->user, text => LJ::Lang::ml( '.contact.txtmsg' ) };
    }

    return @ret;
}


# returns the bio
sub bio {
    my $self = $_[0];

    my $u = $self->{u};
    my $ret;

    if ( $ret = $u->bio ) {
        if ( $u->is_identity && $LJ::ONLY_USER_VHOSTS ) {
            $ret = LJ::ehtml( $ret ); # XXXXX FIXME: TEMP FIX
            $ret =~ s!\n!<br />!g;
        } else {
            LJ::CleanHTML::clean_userbio( \$ret );
        }

        LJ::EmbedModule->expand_entry( $u, \$ret );
    }

    return $ret;
}


# returns an array of interests
sub interests {
    my $self = $_[0];

    my $u = $self->{u};
    my $remote = $self->{remote};
    my @ret;

    my $ints = LJ::get_interests( $u ); # arrayref of: [ intid, intname, intcount ]
    if ( @$ints ) {
        foreach my $int ( @$ints ) {
            my $intid = $int->[0];
            my $intname = $int->[1];
            my $intcount = $int->[2];

            LJ::text_out( \$intname );
            my $eint = LJ::eurl( $intname );
            if ( $intcount > 1 ) {
                if ( $remote ) {
                    my %remote_intids = map { $_ => 1 } LJ::get_interests( $remote, { justids => 1 } );
                    $intname = "<strong>$intname</strong>" if $remote_intids{$intid};
                }
                push @ret, { url => "$LJ::SITEROOT/interests.bml?int=$eint", text => $intname };
            } else {
                push @ret, $intname;
            }
        }
    }

    return @ret;
}


# return an array of external services (mostly IM services)
sub external_services {
    my $self = $_[0];

    my $u = $self->{u};
    my $remote = $self->{remote};
    my @ret;

    return () unless $u->is_personal && ( $u->share_contactinfo( $remote ) || $self->{viewall} );

    if ( my $aol = $u->prop( 'aolim') ) {
        my $eaol = LJ::eurl( $aol );
        $eaol =~ s/ //g;
        push @ret, {
            type => 'aim',
            text => LJ::ehtml( $aol ),
            image => 'aim.gif',
            title_ml => '.im.aol',
            status_image => "http://big.oscar.aol.com/$eaol?on_url=http://www.aol.com/aim/gr/online.gif&amp;off_url=http://www.aol.com/aim/gr/offline.gif",
            status_title_ml => '.im.aol.status',
            status_width => 11,
            status_height => 13,
        };
    }

    if ( my $icq = $u->prop( 'icq' ) ) {
        my $eicq = LJ::eurl( $icq );
        push @ret, {
            type => 'icq',
            text => LJ::ehtml( $icq ),
            url => "http://wwp.icq.com/$eicq",
            image => 'icq.gif',
            title_ml => '.im.icq',
            status_image => "http://web.icq.com/whitepages/online?icq=$icq&amp;img=5",
            status_title_ml => '.im.icq.status',
            status_width => 18,
            status_height => 18,
        };
    }

    if ( my $yahoo = $u->prop( 'yahoo' ) ) {
        my $eyahoo = LJ::eurl( $yahoo );
        push @ret, {
            type => 'yahoo',
            text => LJ::ehtml( $yahoo ),
            url => "http://profiles.yahoo.com/$eyahoo",
            image => 'yahoo.gif',
            title_ml => '.im.yim',
            status_image => 'http://opi.yahoo.com/online?u=$yim&amp;m=g&amp;t=0',
            status_title_ml => '.im.yim.status',
            status_width => 12,
            status_height => 12,
        };
    }

    if ( my $msn = $u->prop( 'msn' ) ) {
        push @ret, {
            type => 'msn',
            email => LJ::ehtml( $msn ),
            image => 'msn.gif',
            title_ml => '.im.msn',
        };
    }

    if ( my $jabber = $u->prop( 'jabber' ) ) {
        push @ret, {
            type => 'jabber',
            email => LJ::ehtml( $jabber ),
            image => 'jabber.gif',
            title_ml => '.im.jabber',
        };
    }

    if ( my $google = $u->prop( 'google_talk' ) ) {
        push @ret, {
            type => 'google',
            email => LJ::ehtml( $google ),
            image => 'gtalk.gif',
            title_ml => '.im.gtalk',
        };
    }

    if ( my $skype = $u->prop( 'skype' ) ) {
        my $service = {
            type => 'skype',
            email => LJ::ehtml( $skype ),
            image => 'skype.gif',
            title_ml => '.im.skype',
        };
        if ( $skype =~ /^[\w\.\-]+$/ ) {
            my $eskype = LJ::eurl( $skype );
            $service->{status_image} = "http://mystatus.skype.com/smallicon/$eskype";
            $service->{status_title_ml} = '.im.skype.status';
            $service->{status_width} = 16;
            $service->{status_height} = 16;
        }
        push @ret, $service;
    }

    if ( my $gizmo = $u->gizmo_account ) {
        push @ret, {
            type => 'gizmo',
            email => LJ::ehtml( $gizmo ),
            image => 'gizmo.gif',
            title_ml => '.im.gizmo',
        };
    }

    if ( my $lastfm = $u->prop( 'last_fm_user' ) ) {
        my $elastfm = LJ::eurl( $lastfm );
        my $lastfm_url = $LJ::LAST_FM_USER_URL;
        $lastfm_url =~ s/%username%/$elastfm/g;
        push @ret, {
            type => 'lastfm',
            text => LJ::ehtml( $lastfm ),
            url => $lastfm_url,
            image => 'lastfm.gif',
            title_ml => '.im.lastfm',
        };
    }

    return @ret;
}


# returns an array of schools
sub schools {
    my $self = $_[0];

    my $u = $self->{u};
    my $remote = $self->{remote};
    my @ret;

    return () unless LJ::is_enabled( 'schools' ) && !$u->is_syndicated && ( $u->should_show_schools_to( $remote ) || $self->{viewall} );

    my $schools_list;
    my $schools = LJ::Schools::get_attended( $u );

    if ( $schools && %$schools ) {
        my %countries;
        LJ::load_codes( { country => \%countries } );
        foreach my $sid ( sort { $schools->{$a}->{year_start} <=> $schools->{$b}->{year_start} ||
                                $schools->{$a}->{year_end} <=> $schools->{$b}->{year_end} ||
                                $schools->{$a}->{name} cmp $schools->{$b}->{name} } keys %$schools ) {
            push @ret, {
                url => "$LJ::SITEROOT/schools/" .
                    "?ctc=" . LJ::eurl( $schools->{$sid}->{country} ) .
                    "&sc=" . LJ::eurl( $schools->{$sid}->{state} ) .
                    "&cc=" . LJ::eurl( $schools->{$sid}->{city} ) .
                    "&sid=$sid",
                text => LJ::ehtml( $schools->{$sid}->{name} ),
                city => $schools->{$sid}->{city},
                state => $schools->{$sid}->{state},
                country => $schools->{$sid}->{country} ne 'US' ? $countries{ $schools->{$sid}->{country} } : undef,
                year_start => $schools->{$sid}->{year_start},
                year_end => $schools->{$sid}->{year_start} != $schools->{$sid}->{year_end} ? $schools->{$sid}->{year_end} || LJ::Lang::ml{'.schools.presentyear'} : undef,
            };
        }
    }

    return @ret;
}


# returns whether a given list should be hidden or not
sub hide_list {
    my ( $self, $list ) = @_;

    my $u = $self->{u};
    my $remote = $self->{remote};

    return 1 if $list =~ /^posting_access/;
    return 1 if $u->prop( 'opt_hidefriendofs' );
    return 0;
}


# returns all userids that are trusted but that don't trust in return
sub not_mutually_trusted_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return () unless $u->is_personal;

    my @trusted_userids = $u->trusted_userids;
    my %is_trusted_by = map { $_ => 1 } $u->trusted_by_userids;

    foreach my $uid ( @trusted_userids ) {
        push @ret, $uid if !$is_trusted_by{$uid};
    }

    return @ret;
}


# returns all userids that trust but that aren't trusted in return
sub not_mutually_trusted_by_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return () unless $u->is_personal;

    my @trusted_by_userids = $u->trusted_by_userids;
    my %is_trusted = map { $_ => 1 } $u->trusted_userids;

    foreach my $uid ( @trusted_by_userids ) {
        push @ret, $uid if !$is_trusted{$uid};
    }

    return @ret;
}


# returns all userids that are watched but that don't watch in return
sub not_mutually_watched_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return () unless $u->is_personal || $u->is_identity;

    my @watched_userids = $u->watched_userids;
    my %is_watched_by = map { $_ => 1 } $u->watched_by_userids;

    foreach my $uid ( @watched_userids ) {
        push @ret, $uid if !$is_watched_by{$uid};
    }

    return @ret;
}


# returns all userids that watch but that aren't watched in return
sub not_mutually_watched_by_userids {
    my $self = $_[0];

    my $u = $self->{u};
    my @ret;

    return () unless $u->is_personal || $u->is_identity;

    my @watched_by_userids = $u->watched_by_userids;
    my %is_watched = map { $_ => 1 } $u->watched_userids;

    foreach my $uid ( @watched_by_userids ) {
        push @ret, $uid if !$is_watched{$uid};
    }

    return @ret;
}


1;
