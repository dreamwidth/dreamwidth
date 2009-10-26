#!/usr/bin/perl
#
# DW::Logic::ProfilePage
#
# This module provides logic for rendering the profile page for various types
# of accounts.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Logic::ProfilePage;

use strict;
use DW::Logic::UserLinkBar;

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
    my $remote = $self->{remote};
    
    my $user_link_bar = $u->user_link_bar( $remote, class_prefix => "profile" );
    my @ret = $user_link_bar->get_links( "manage_membership", "trust", "watch", "post", "track", "message", "search", "buyaccount" );
}


# returns hashref with userpic display options
#  {
#     userpic      => 'http://...',
#     userpic_url  => 'http://...',    # OPTIONAL
#     caption_text => 'Edit',          # OPTIONAL
#     caption_url  => 'http://...',    # OPTIONAL
#     imgtag       => HTML to display
#  }
sub userpic {

    my $self = $_[0];

    my $u = $self->{u};
    my $user = $u->user;
    my $remote = $self->{remote};
    my $ret = {};

    # syndicated accounts have a very simple thing
    if ( $u->is_syndicated ) {
        $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/feed.png";
    } else {

        # determine what picture URL to use
        if ( my $up = $u->userpic ) {
            $ret->{userpic} = $up->url;
        } elsif ( $u->is_personal ) {
            $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/user.png";
            $ret->{alt_text} = LJ::Lang::ml( '.userpic.user.alt' );
            $ret->{width} = 100;
            $ret->{height} = 100;
        } elsif ( $u->is_community ) {
            $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/comm.png";
            $ret->{alt_text} = LJ::Lang::ml( '.userpic.comm.alt' );
            $ret->{width} = 100;
            $ret->{height} = 100;
        } elsif ( $u->is_identity ) {
            $ret->{userpic} = "$LJ::IMGPREFIX/profile_icons/openid.png";
            $ret->{alt_text} = LJ::Lang::ml( '.userpic.openid.alt' );
            $ret->{width} = 100;
            $ret->{height} = 100;
        }
    
        # now determine what caption text to show
        if ( $remote && $remote->can_manage( $u ) ) {
            if ( LJ::userpic_count( $u ) ) {
                $ret->{userpic_url} = $u->allpics_base;
                $ret->{caption_text} = LJ::Lang::ml( '.section.edit' );
                $ret->{caption_url} = "$LJ::SITEROOT/editpics?authas=$user"
            } else {
                $ret->{userpic_url} = "$LJ::SITEROOT/editpics?authas=$user";
                $ret->{caption_text} = LJ::Lang::ml( '.userpic.upload' );
                $ret->{caption_url} = "$LJ::SITEROOT/editpics?authas=$user"
            }
        } else {
            if ( LJ::userpic_count( $u ) ) {
                $ret->{userpic_url} = $u->allpics_base;
            }
        }
    }

    # build the HTML tag
    my $userpic_obj = LJ::Userpic->get( $u, $u->{defaultpicid} );
    my $imgtag_conditional;
    if ( $userpic_obj ) {
      $imgtag_conditional = $userpic_obj->imgtag;
    } else {
      $imgtag_conditional = '<img src="' . $ret->{userpic} .
                            '" height=' . $ret->{height} .
                            ' width=' . $ret->{width} .
                            ' alt="' . $ret->{alt_text} .
                            '" />';
    }
   

    #  Set the wrapper materials to surrounded the  userpic image
    my ( $apre, $apost );
    if ( $ret->{userpic_url} ) {
        $apre = "<a href='" . LJ::ehtml($ret->{userpic_url}) . "'>";
        $apost = "</a>";
    }

    # Set the HTML to display the userpic
    if ( $ret->{caption_text} ) {
        $apost .= qq(
            <br />
            <span class="user_pic_caption">
                [<a href="$ret->{caption_url}">$ret->{caption_text}</a>]
            </span>
        );
    }

    $ret->{imgtag} =  $apre . $imgtag_conditional . $apost;

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
        aopts => "href='$LJ::SITEROOT/tools/memories?user=" . $u->user . "'",
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
        aopts => "href='" . $u->allpics_base . "'",
    } )
        unless $u->is_syndicated;
    
    return @ret;
}


# returns the account's PubSubHubbub information
# available only for syndication account types
sub hubbub_info_rows {
    my $self = $_[0];

    my $u = $self->{u};
    return () unless $u->is_syndicated && LJ::is_enabled( 'hubbub' );

    # FIXME: should probably have a PubSubHubbub module that gets this sort
    # of thing so we don't have to scatter SQL in the profile logic...
    my $dbr = LJ::get_db_reader();

    # for each subscription we have active, return a hash of the information
    my $subs = $dbr->selectall_hashref(
        q{SELECT id, userid, huburl, topicurl, UNIX_TIMESTAMP() - lastseenat AS 'lastseen',
                 leasegoodto, timespinged
          FROM syndicated_hubbub2
          WHERE userid = ?},
        'id', undef, $u->id
    );
    return () if $dbr->err;

    # return this as an array sorted by id (just keeps it stable)
    return sort { $a->{id} <=> $b->{id} } values %{ $subs || {} };
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
        $ret->[0] = LJ::Lang::ml( '.label.name' );
        $ret->[1] = $name;
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
            my ($year, $mon, $day) = split /-/, $bdate;
            my $moname = LJ::Lang::month_short_ml( $mon );
            $day += 0;
            if ( $u->bday_string =~ /\d+-\d+-\d+/ ) {
                $ret->[1] = "$moname $day, $year";
            } elsif ( $u->bday_string =~ /\d+-\d+/ ) {
                $ret->[1] = "$moname $day";
            } else {
                $ret->[1] = $u->bday_string;
            }
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
                { url => "$LJ::SITEROOT/directory?opt_sort=ut&amp;s_loc=1&amp;loc_cn=$ecountry", text => $countries{ $country } } :
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
                { url => "$LJ::SITEROOT/directory?opt_sort=ut&amp;s_loc=1&amp;loc_cn=$ecountry&amp;loc_st=$estate", text => LJ::ehtml( $state ) } :
                LJ::ehtml( $state );
        }

        if ( $city ) {
            $city = LJ::ehtml( $city );
            $city_ret = $country && LJ::is_enabled( 'directory' ) ?
                { url => "$LJ::SITEROOT/directory?opt_sort=ut&amp;s_loc=1&amp;loc_cn=$ecountry&amp;loc_st=$estate&amp;loc_ci=$ecity", text => $city } :
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
    return () unless $u->is_syndicated;

    my $ret = [];
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
    return () unless $u->is_syndicated;

    my $ret = [];
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
    if ( ( $u->is_personal || $u->is_identity ) && $remote && $u->can_receive_message( $remote ) ) {
        push @ret, { url => "$LJ::SITEROOT/inbox/compose?user=" . $u->user, text => LJ::Lang::ml( '.contact.pm' ) };
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
        push @ret, { url => "$LJ::SITEROOT/tools/textmessage?user=" . $u->user, text => LJ::Lang::ml( '.contact.txtmsg' ) };
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

    my $ints = $u->get_interests(); # arrayref of: [ intid, intname, intcount ]
    if ( @$ints ) {
        foreach my $int ( @$ints ) {
            my $intid = $int->[0];
            my $intname = $int->[1];
            my $intcount = $int->[2];

            LJ::text_out( \$intname );
            my $eint = LJ::eurl( $intname );
            if ( $intcount > 1 ) {
                # bold shared interests on all profiles except your own
                if ( $remote && !$remote->equals( $u ) ) {
                    my %remote_intids = map { $_ => 1 } @{ $remote->get_interests( { justids => 1 } ) };
                    $intname = "<strong>$intname</strong>" if $remote_intids{$intid};
                }
                push @ret, { url => "$LJ::SITEROOT/interests?int=$eint", text => $intname };
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
            status_image => "http://big.oscar.aol.com/$eaol?on_url=http://cdn.aim.com/remote/gr/MNB_online.gif&amp;off_url=http://cdn.aim.com/remote/gr/MNB_offline.gif",
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
            status_image => "http://opi.yahoo.com/online?u=$yahoo&amp;m=g&amp;t=0",
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
        my $lastfm_url = 'http://www.last.fm/user/%username%';
        $lastfm_url =~ s/%username%/$elastfm/g;
        push @ret, {
            type => 'lastfm',
            text => LJ::ehtml( $lastfm ),
            url => $lastfm_url,
            image => 'lastfm.gif',
            title_ml => '.im.lastfm',
        };
    }

    if ( my $twitter = $u->prop( 'twitter' ) ) {
        my $twitter = LJ::eurl( $twitter );
        push @ret, {
            type => 'twitter',
            text => LJ::ehtml( $twitter ),
            url => "http://www.twitter.com/$twitter",
            image => 'twitter.png',
            title_ml => '.service.twitter',
        };
    }

    if ( my $delicious = $u->prop( 'delicious' ) ) {
        my $delicious = LJ::eurl( $delicious );
        push @ret, {
            type => 'delicious',
            text => LJ::ehtml( $delicious ),
            url => "http://www.delicious.com/$delicious",
            image => 'delicious.png',
            title_ml => '.service.delicious',
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
                year_end => $schools->{$sid}->{year_start} != $schools->{$sid}->{year_end} ? $schools->{$sid}->{year_end} || LJ::Lang::ml('.schools.presentyear') : undef,
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
