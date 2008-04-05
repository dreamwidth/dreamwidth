package LJ::Widget::FriendBirthdays;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res {
    return qw( stc/widgets/friendbirthdays.css );
}

# args
#   user: optional $u whose friend birthdays we should get (remote is default)
#   limit: optional max number of birthdays to show; default is 5
sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = $opts{user} && LJ::isu($opts{user}) ? $opts{user} : LJ::get_remote();
    return "" unless $u;

    my $limit = defined $opts{limit} ? $opts{limit} : 5;

    my @bdays = $u->get_friends_birthdays( months_ahead => 1 );
    @bdays = @bdays[0..$limit-1]
        if @bdays > $limit;

    return "" unless @bdays;

    my $ret;
    $ret .= "<h2><span>" . $class->ml('widget.friendbirthdays.title') . "</span></h2>";
    $ret .= "<a href='$LJ::SITEROOT/birthdays.bml' class='more-link'>" . $class->ml('widget.friendbirthdays.viewall') . "</a></p>";
    $ret .= "<div class='indent_sm'><table>";

    foreach my $bday (@bdays) {
        my $u = LJ::load_user($bday->[2]);
        my $month = $bday->[0];
        my $day = $bday->[1];
        next unless $u && $month && $day;

        # remove leading zero on day
        $day =~ s/^0//;

        $ret .= "<tr>";
        $ret .= "<td>" . $u->ljuser_display . "</td>";
        $ret .= "<td>" . $class->ml('widget.friendbirthdays.userbirthday', {'month' => LJ::Lang::month_short($month), 'day' => $day}) . "</td>";
        $ret .= "<td><a href='$LJ::SITEROOT/shop/view.bml?item=paidaccount&gift=1&for=" . $u->user . "' class='gift-link'>";
        $ret .= $class->ml('widget.friendbirthdays.gift') . "</a></td>";
        $ret .= "</tr>";
    }

    $ret .= "</table></div>";

    $ret .= "<p class='indent_sm'>&raquo; <a href='$LJ::SITEROOT/birthdays.bml'>" .
            $class->ml('widget.friendbirthdays.friends_link') .
            "</a></p>" if $opts{friends_link};
    $ret .= "<p class='indent_sm'>&raquo; <a href='$LJ::SITEROOT/paidaccounts/friends.bml'>" .
            $class->ml('widget.friendbirthdays.paidtime_link') .
            "</a></p>" if $opts{paidtime_link};

    return $ret;
}

1;
