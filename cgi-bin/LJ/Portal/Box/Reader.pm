package LJ::Portal::Box::Reader; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_description = 'Watch a journal, community or syndicated feed';
our $_box_name = "Reader";
our $_box_class = "Reader";
our $_prop_keys = {
    'username'   => 2,
    'itemshow'   => 1,
};

our $_config_props = {
    'username' => {
        'type'      => 'string',
        'desc'      => 'User, community, or syndicated feed name',
        'default'   => '',
        'size'      => 16,
        'maxlength' => 16,
    },
    'itemshow' => {
        'type'      => 'integer',
        'desc'      => 'Display how many recent entries',
        'default'   => '3',
        'min'       => '1',
        'max'       => '25',
    },
};

sub generate_content {
    my $self = shift;
    my $pboxid = $self->{'pboxid'};
    my $u = $self->{'u'};

    my $content;

    my $username = $self->get_prop('username');
    my $itemshow = $self->get_prop('itemshow');

    return 'You must define a user, community or syndicated feed to watch.' if (!$username || $username eq '');

    my $wu = LJ::load_user($username);

    return "The user, community or syndicated account <b>$username</b> does not exist." unless $wu;

    # get latest entries
    my $err;
    my @entries = LJ::get_recent_items( {
        'remote'           => $u,
        'itemshow'         => $itemshow,
        'skip'             => 0,
        'showtypes'        => 'PYC',
        'u'                => $wu,
        'err'              => \$err,
        'userid'           => $wu->{userid},
        'clusterid'        => $wu->{clusterid},
    } );

    return "Error fetching latest entries: $err" if $err;

    # correct pluralization (translationableness would be cool at some point)
    my $entrytext = @entries == 1 ? 'entry' : 'entries';

    # link to journal
    my $wuuser = LJ::ljuser($wu);

    $content .= "<div class=\"ReaderPageTitle\">$wuuser</div>";

    my $entriescontent;

    foreach my $entryinfo (@entries) {
        next unless $entryinfo;

        my $entry = LJ::Entry->new($wu->{userid},
                                   jitemid => $entryinfo->{'itemid'},
                                   anum    => $entryinfo->{'anum'});

        next unless $entry;

        my $subject    = $entry->subject_html;
        my $entrylink  = $entry->url;

        my $event = $entry->event_html( { 'cuturl' => $entrylink  } );

        my $posteru    = $entry->poster;
        my $poster     = $posteru->ljuser_display;
        my $props      = $entry->props;
        my $pickeyword = $props->{'picture_keyword'};
        my $replycount = $props->{'replycount'};
        my $picinfo;

        my $journalid = $wu->{userid};
        my $posterid = $entry->posterid;

        # is this a post in a comm?
        if ($journalid != $posterid) {
            $poster = $poster . " posting in ";
            $poster .= $wu->ljuser_display;
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

        if ($picinfo) {
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
        $entriescontent .= "There have been no recent posts by $wuuser";
    }

    $content .= qq {
        <div class="ReaderEntry">
            $entriescontent
        </div>
    };

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
