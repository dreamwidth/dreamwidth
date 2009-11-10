package LJ::Widget::FriendInterests;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( js/widgets/friendinterests.js );
}

sub handle_post {
    my $class = shift;
    my $fields = shift;

    return unless $fields->{user};
    return unless $fields->{from};

    my $u = LJ::isu($fields->{user}) ? $fields->{user} : LJ::load_user($fields->{user});
    return unless $u;
    my $fromu = LJ::isu($fields->{from}) ? $fields->{from} : LJ::load_user($fields->{from});
    return unless $fromu;

    my $uints = $u->interests;
    my $fromints = $fromu->interests;
    return unless keys %$fromints;

    my @fromintids = values %$fromints;
    my $uitable = $u->is_comm ? 'comminterests' : 'userinterests';

    my @todel;
    my @toadd;
    foreach my $fromint (@fromintids) {
        next unless $fromint > 0;    # prevent adding zero or negative intid
        push @todel, $fromint if  $uints->{$fromint} && !$fields->{'int_'.$fromint};
        push @toadd, $fromint if !$uints->{$fromint} &&  $fields->{'int_'.$fromint};
    }

    my $intcount = scalar %$uints;
    my $deleted = 0;
    if (@todel) {
        my $intid_in = join(",", @todel);
        my $dbh = LJ::get_db_writer();
        $dbh->do("DELETE FROM $uitable WHERE userid=? AND intid IN ($intid_in)",
                 undef, $u->id);
        $dbh->do("UPDATE interests SET intcount=intcount-1 WHERE intid IN ($intid_in)");
        $deleted = 1;
    }
    if (@toadd) {
        my $maxinterests = $u->count_max_interests;

        if ($intcount + scalar @toadd > $maxinterests) {
            if ($deleted) {
                die BML::ml('/interests.bml.results.del_and_toomany', {'intcount' => $maxinterests});
            } else {
                die BML::ml('/interests.bml.results.toomany', {'intcount' => $maxinterests});
            }
        } else {
            my $dbh = LJ::get_db_writer();
            my $sqlp = "(?,?)" . (",(?,?)" x (scalar(@toadd) - 1));
            my @bindvars = map { ($u->id, $_) } @toadd;
            $dbh->do("REPLACE INTO $uitable (userid, intid) VALUES $sqlp", undef, @bindvars);

            my $intid_in = join(",", @toadd);
            $dbh->do("UPDATE interests SET intcount=intcount+1 WHERE intid IN ($intid_in)");
        }
    }

    # if a community, remove any old rows from userinterests
    if ($u->is_comm) {
        my $dbh = LJ::get_db_writer();
        $dbh->do("DELETE FROM userinterests WHERE userid=?", undef, $u->id);
    }

    LJ::memcache_kill($u, "intids");

    return;
}

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    return "" unless $opts{user};
    return "" unless $opts{from};

    my $u = LJ::isu($opts{user}) ? $opts{user} : LJ::load_user($opts{user});
    return "" unless $u;
    my $fromu = LJ::isu($opts{from}) ? $opts{from} : LJ::load_user($opts{from});
    return "" unless $fromu;

    my $uints = $u->interests;
    my $fromints = $fromu->interests;

    return "" unless keys %$fromints;
    return "" if $u->id == $fromu->id;

    $ret .= "<div id='friend_interests' class='pkg' style='display: none;'>";
    $ret .= $class->ml('widget.friendinterests.intro', {user => $fromu->ljuser_display});

    $ret .= "<table>";
    my @fromintsorted = sort keys %$fromints;
    my $cols = 4;
    my $rows = int((scalar(@fromintsorted) + $cols - 1) / $cols);
    for (my $i = 0; $i < $rows; $i++) {
        $ret .= "<tr valign='middle'>";
        for (my $j = 0; $j < $cols; $j++) {
            my $index = $rows * $j + $i;
            if ($index < scalar @fromintsorted) {
                my $friend_interest = $fromintsorted[$index];
                my $checked = $uints->{$friend_interest} ? 1 : undef;
                my $friend_interest_id = $fromints->{$friend_interest};
                $ret .= "<td align='left' nowrap='nowrap'>";
                $ret .= $class->html_check(
                    name     => "int_$friend_interest_id",
                    class    => "check",
                    id       => "int_$friend_interest_id",
                    selected => $checked,
                    value    => 1,
                );
                $ret .= "<label class='right' for='int_$friend_interest_id'>$friend_interest</label></td>";
            } else {
                $ret .= "<td></td>";
            }
        }
        $ret .= "</tr>";
    }
    $ret .= "</table>";
    $ret .= $class->html_hidden( user => $u->user );
    $ret .= $class->html_hidden({ name => "from", id => "from_user", value => $fromu->user });
    $ret .= "</div>";

    return $ret;
}

1;
