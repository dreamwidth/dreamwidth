package LJ::Portal::Box::Manage; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "Manage";
our $_box_description = "Useful links";
our $_box_name = "Quick Links";

# list of links to choose from
our $_prop_keys = {
    'EditFriends' => 1,
    'EditProfile' => 2,
    'EditPics' => 3,
    'ManageCom' => 4,
    'ManageMood' => 5,
    'ChangePassword' => 6,

    'LinkList' => 7,
    'EmailGateway' => 8,
    'VoicePost' => 9,
    'InviteFriend' => 10,
    'TextMessage' => 11,
    'Memories' => 12,
    'Todo' => 13,
    'EditFriendGroups' => 14,
    'FriendsFilter' => 15,
    'CommSearch' => 16,
    'CommInvite' => 17,
    'EditStyles' => 18,
    'BuyFriends' => 19,
    'Syndication' => 20,
    'Tags' => 21,
    'SearchRegion' => 22,
    'AdvancedSearch' => 23,
    'InterestSearch' => 24,
    'EditEntries' => 25,
};

# Prop => [URL, Text, Default] mapping
our $linkinfo = {
    'EditFriends'    => [ '/friends/edit.bml', 'Edit Friends', 1 ],
    'EditProfile'       => [ "/manage/profile/", 'Edit Profile', 1 ],
    'EditPics'       => [ '/editpics.bml', 'Upload and Manage Your Userpics', 1 ],
    'ManageCom'      => [ '/community/manage.bml', 'Manage Communities', 1 ],
    'ManageMood'     => [ '/customize/style.bml', 'Set Your Mood Theme', 1 ],
    'ChangePassword' => [ '/changepassword.bml', 'Change Account Password', 1 ],

    'LinkList'       => [ '/manage/links.bml', 'Create Link List', 0 ],
    'EmailGateway'   => [ '/manage/emailpost.bml', 'Mobile Post Settings', 0 ],
    'VoicePost'      => [ '/manage/voicepost.bml', 'Voice Post Settings', 0 ],
    'InviteFriend'   => [ '/friends/invite.bml', 'Invite a Friend', 0 ],
    'TextMessage'    => [ '/tools/textmessage.bml', 'Text Message Tool', 0 ],
    'Memories'       => [ '/tools/memories.bml', 'Memorable Posts', 0 ],
    'Todo'           => [ '/todo', 'To-Do List', 0 ],
    'EditFriendGroups' => [ '/friends/editgroups.bml', 'Edit Your Friends Groups', 0 ],
    'FriendsFilter'  => [ '/friends/filter.bml', 'Friends Filter', 0 ],
    'CommSearch'     => [ '/community/search.bml', 'Community Search', 0 ],
    'CommInvite'  => [ '/manage/invites.bml', 'Community Invitations', 0 ],
    'EditStyles'  => [ '/styles/edit.bml', 'Edit Styles', 0 ],
    'BuyFriends'  => [ '/paidaccounts/friends.bml', 'Buy for Friends', 0 ],
    'Syndication' => [ '/syn', 'Syndication', 0 ],
    'Tags'        => [ '/manage/tags.bml', 'Manage Your Journal Tags', 0 ],
    'SearchRegion'   => [ '/directory.bml', 'Search by Region', 0 ],
    'AdvancedSearch' => [ '/directorysearch.bml', 'Advanced Search', 0 ],
    'InterestSearch' => [ '/interests.bml', 'Search by Interests', 0 ],
    'EditEntries'    => [ '/editjournal.bml', 'Edit Your Journal Entries', 0 ],
};

our $_config_props;

foreach my $info (keys %$linkinfo) {
    $_config_props->{$info} = { 'type'    => 'checkbox',
                                'desc'    => $linkinfo->{$info}->[1],
                                'default' => $linkinfo->{$info}->[2] || 0,
                            };
}

sub generate_content {
    my $self = shift;
    my $content = '';
    my $pboxid = $self->pboxid;
    my $u = $self->{'u'};

    my $props = $self->get_props;

    $content .= qq {
        <table style="width: 100%;">
        };

    # print links
    my $col = 0;
    foreach my $link (keys %$linkinfo) {
        next unless $props->{$link};

        my $linkurl = $linkinfo->{$link}->[0];
        my $linktext = $linkinfo->{$link}->[1];

        if ($col++ % 2 == 0) {
            $content .= qq { <tr><td><a href="$LJ::SITEROOT$linkurl">$linktext</a></td> };
        } else {
            $content .= qq { <td><a href="$LJ::SITEROOT$linkurl">$linktext</a></td></tr> };
        }
    }

    $content .= qq {
        </table>
    };

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }

1;
