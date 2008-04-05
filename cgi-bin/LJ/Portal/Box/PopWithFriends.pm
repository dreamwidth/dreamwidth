package LJ::Portal::Box::PopWithFriends; # <--- Change this
use base 'LJ::Portal::Box';
use strict;

######################## override this stuff ######################

our $_box_class = "PopWithFriends";
our $_box_description = 'See who\'s popular';
our $_box_name = "Popular With Your Friends";
our $_prop_keys = {
    'showpeople' => 0,
    'showcoms' => 1,
    'showsyn' => 2,
    'showown' => 3,
    'limit' => 4,
};

our $_config_props = {
    'limit' => {
        'type'      => 'integer',
        'desc'      => 'Maximum number of users to display',
        'min'       => 1,
        'max'       => 50,
        'default'   => 10,
    },
    'showcoms'  => {
        'type'    => 'checkbox',
        'desc'    => 'Show communities',
        'default' => 1,
    },
    'showpeople'=> {
        'type'    => 'checkbox',
        'desc'    => 'Show users',
        'default' => 1,
    },
    'showsyn'   => {
        'type'    => 'checkbox',
        'desc'    => 'Show syndicated accounts',
        'default' => 1,
    },
    'showown'   => {
        'type'    => 'checkbox',
        'desc'    => 'Show my own friends',
        'default' => 0,
    },
};

sub generate_content {
    my $self = shift;
    my $content = '';
    my $u = $self->{'u'};
    my $maxitems = $self->get_prop('limit');
    my $showsyn = $self->get_prop('showsyn');
    my $showpeople = $self->get_prop('showpeople');
    my $showown = $self->get_prop('showown');
    my $showcoms = $self->get_prop('showcoms');

    my $LIMIT=300;

    if ($LJ::DISABLED{'friendspopwithfriends'}) {
        return 'Sorry, this feature is disabled.';
    }

    unless (LJ::get_cap($u, "friendspopwithfriends")) {
        return BML::ml("portal.popwithfriends.accttype");
    }

    # load user's friends
    my $fr = LJ::get_friends($u);
    return 'No friends found.' unless $fr;

    my @ids = keys %$fr;
    splice(@ids, 0, $LIMIT) if @ids > $LIMIT;

    my $fus = LJ::load_userids(@ids);

    # show friends of users only
    @ids = grep { $fus->{$_}{journaltype} eq "P" } @ids;

    my %count;

    my $MAX_DELAY = 4;

    # count friends of friends
    my $start = time();
    while (@ids && time() < $start + $MAX_DELAY) {
        my $fid = shift @ids;

        my $fr = LJ::get_friends($fid);
        next unless $fr;
        $count{$_}++  foreach (keys %$fr);
    }

    my @pop = (sort { $count{$b} <=> $count{$a} } keys %count);

    my $rows;
    my $shown;

    my $fofus = LJ::load_userids(@pop);

    my $displayed = 0;
    foreach my $popid (@pop) {
        # don't show self
        next if ($popid eq $u->{'userid'});

        # don't show own friends if option set
        next if ($fr->{$popid} && !$showown);

        my $fofu = $fofus->{$popid};

        my $journaltype = $fofu->{journaltype};
        next if ($journaltype eq 'P' || $journaltype eq 'I') && !$showpeople;
        next if $journaltype eq 'C' && !$showcoms;
        next if $journaltype eq 'Y' && !$showsyn;

        my $friendcount = $count{$popid};
        next if $friendcount == 0;

        last if $displayed++ >= $maxitems;

        $rows .= "<tr><td>" . LJ::ljuser($fofu) . " - " . LJ::ehtml($fofu->{name}) .
            "</td><td align='right'>$friendcount</td>";
        $rows .= "<td><a href=\"$LJ::SITEROOT/friends/add.bml?user=$fofu->{user}\"><img src=\"$LJ::IMGPREFIX/btn_addfriend.gif\" alt=\"Add this user as a friend\" /></a></td>" if !$fr->{$fofu->{userid}};
        $rows .= "</tr>\n";
    }

    if ($rows) {
        $content .= "<div class=\"PopWithFriendsHeader\">The following friends are " .
            "listed often by your friends, but not by you.</div>";
        $content .= "<table cellpadding='3' style='width:100%;'>\n";
        $content .= "<tr><td><b>User</b></td><td><b>Count</b></td><td><b>Add</b></td></tr>\n";
        $content .= $rows;
        $content .= "</table>\n";

    } else {
        return 'You have no friends of friends.';
    }

    return $content;
}


#######################################


sub box_description { $_box_description; }
sub box_name { $_box_name; };
sub box_class { $_box_class; }
sub config_props { $_config_props; }
sub prop_keys { $_prop_keys; }

# caching options
sub cache_global { 0; } # cache per-user
sub cache_time { 60 * 60; } # cache for an hour

1;
