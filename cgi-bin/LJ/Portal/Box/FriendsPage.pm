package LJ::Portal::Box::FriendsPage; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = 'Read Your Friends Page';
our $_box_name = "View Friends Page";
our $_box_class = "FriendsPage";
our $_prop_keys = {
    'showgroups' => 2,
    'itemshow'   => 1,
    'imageplaceholders' => 3,
};

our $_config_props = {
    'showgroups' => {
        'type'      => 'checkbox',
        'desc'      => 'Show friend groups?',
        'default'   => '0',
    },
    'itemshow' => {
        'type'      => 'integer',
        'desc'      => 'Display how many recent entries?',
        'default'   => '3',
        'min'       => '1',
        'max'       => '25',
    },
    'imageplaceholders' => {
        'type'      => 'checkbox',
        'desc'      => 'Use placeholders for images?',
        'default'   => '0',
    },
};

sub generate_content {
    my $self = shift;
    my $pboxid = $self->{'pboxid'};
    my $u = $self->{'u'};

    my $content;

    my $showgroups = $self->get_prop('showgroups');
    my $itemshow = $self->get_prop('itemshow');
    my $useplaceholders = $self->get_prop('imageplaceholders');

    my $frpagefaqbtn = LJ::Portal->get_faq_link('friendspage');

    # get latest friends page entries
    # filter by "default view" if it exists
    my $grp = LJ::get_friend_group($u, { 'name'=> 'Default View' });
    my $bit = $grp ? $grp->{'groupnum'} : 0;
    my $filter = $bit ? (1 << $bit) : undef;

    my @entries = LJ::get_friend_items( {
        'remoteid'         => $u->{'userid'},
        'itemshow'         => $itemshow,
        'skip'             => 0,
        'showtypes'        => 'PYC',
        'u'                => $u,
        'userid'           => $u->{'userid'},
        'filter'           => $filter,
    } );

    # correct pluralization (translationableness would be cool at some point)
    my $entrytext = @entries == 1 ? 'entry' : 'entries';

    # link to friends' page
    my $friendspageurl = $u->journal_base . '/friends/';

    $content .= "<div class=\"FriendsPageTitle\"><img src='$LJ::SITEROOT/img/userinfo.gif' /> <a href=\"$friendspageurl\">Latest Friends page $entrytext: $frpagefaqbtn</a></div>";

    my $entriescontent;

    foreach my $entryinfo (@entries) {
        next unless $entryinfo;

        my $entry;

        if ($entryinfo->{'ditemid'}) {
            $entry = LJ::Entry->new($entryinfo->{'journalid'},
                                    ditemid => $entryinfo->{'ditemid'});
        } elsif ($entryinfo->{'itemid'} && $entryinfo->{'anum'}) {
            $entry = LJ::Entry->new($entryinfo->{'journalid'},
                                    jitemid => $entryinfo->{'itemid'},
                                    anum    => $entryinfo->{'anum'});
        }

        next unless $entry;

        my $subject    = $entry->subject_html;
        my $entrylink  = $entry->url;

        my $event      = $useplaceholders ?
            $entry->event_html( { 'extractimages' => 1,
                                  'cuturl' => $entrylink } ) :
            $entry->event_html( { 'cuturl' => $entrylink  } );

        my $posteru    = $entry->poster;

        next if $posteru && $posteru->{statusvis} =~ /[XSD]/;

        my $poster     = $posteru->ljuser_display;
        my $props      = $entry->props;
        my $pickeyword = $props->{'picture_keyword'};
        my $replycount = $props->{'replycount'};
        my $picinfo;

        my $journalid = $entryinfo->{journalid};
        my $posterid = $entry->posterid;

        # is this a post in a comm?
        if ($journalid != $posterid) {
            my $journalu = LJ::load_userid($journalid);
            if ($journalu) {
                $poster = $poster . " posting in ";
                $poster .= $journalu->ljuser_display;
            }
        }

        my $replyurl = LJ::Talk::talkargs($entrylink, "mode=reply");

        # security icon
        my $sec = "";
        if ($entry->security eq "private") {
            $sec = BML::fill_template("securityprivate");
        } elsif ($entry->security eq "usemask") {
            $sec = BML::fill_template("securityprotected");
        }

        # replies link/reply link
        my $readlinktext = 'No replies';
        if ($replycount == 1) {
            $readlinktext = "1 Reply";
        } elsif ($replycount > 1) {
            $readlinktext = "$replycount replies";
        }
        my $replylink = "<a href=\"$replyurl\">Reply</a>";
        my $readlink = "<a href=\"$entrylink\">$readlinktext</a>";

        # load userpic
        my $pichtml;
        if ($pickeyword) {
            $picinfo = LJ::get_pic_from_keyword($posteru, $pickeyword);
        } else {
            my $picid = $posteru->{'defaultpicid'};
            my %pic;
            LJ::load_userpics(\%pic, [ $posteru, $picid ]);
            $picinfo = $pic{$picid};
            $picinfo->{'picid'} = $picid;
        }

        if ($picinfo && $picinfo->{picid}) {
            my $width = $picinfo->{'width'} ? "width=\"" . int($picinfo->{'width'} / 2) . '"' : '';
            my $height = $picinfo->{'height'} ? "height=\"" . int($picinfo->{'height'} / 2) . '"' : '';

            $pichtml .= "<img src='$LJ::USERPIC_ROOT/$picinfo->{'picid'}/$posteru->{'userid'}' $width $height align='absmiddle' />";
        }

        $entriescontent .= qq {
            <div class="PortalFriendsPageMeta">
                <span class="PortalFriendsPageUserpic">$pichtml</span>
                <span class="PortalFriendsPagePoster">$poster</span>
                </div>
                <div class="PortalFriendsPageSubject">
                <span class="PortalFriendsPageSecurityIcon">$sec</span>
                $subject
                </div>
                <div class="PortalFriendsPageEntry">
                $event
                </div>
                <div class="PortalFriendsPageLinks">
                $readlink | $replylink
                </div>
            };
    }

    if (! scalar @entries) {
        $entriescontent .= "There have been no recent posts by your friends.";
    }

    $content .= qq {
        <div class="FriendsPageEntry">
            $entriescontent
        </div>
    };

    if ($showgroups) {
        my $groups = LJ::get_friend_group($u);
        my $foundgroups = 0;

        if ($groups) {
            my $groupcount = scalar (keys %$groups);
            my @sortedgroups = sort
            {$groups->{$a}->{'sortorder'} <=>
                 $groups->{$b}->{'sortorder'}}
            keys %$groups;
            $content .= "<div class=\"FriendsPageTitle\"><img src='$LJ::SITEROOT/img/friendgroup.gif' /> Friend Groups ($groupcount):</div>";
            $content .= '<div class="FriendsPageEntry">';

            foreach my $group (@sortedgroups) {
                my $journalbase = LJ::journal_base($u);
                my $groupname = $groups->{$group}->{'groupname'};
                $content .= qq { <a href="$journalbase/friends/$groupname">$groupname</a>, };
                $foundgroups = 1;
            }
        }

        if ($foundgroups) {
            chop $content;
            chop $content;
        } else {
            $content .= "You have no friend groups defined.";
        }

        $content .= "<br />(<a href=\"$LJ::SITEROOT/friends/editgroups.bml\">Edit Friend Groups</a>)";

        $content .= '</div>';
    }

    return $content;
}


sub can_refresh { 1; }

#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }

1;
