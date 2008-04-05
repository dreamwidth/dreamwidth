package LJ::Widget::CommsOfUser;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub render_body {
    my $class = shift;
    my %opts = @_;
    my $ret;

    return "" unless $opts{user};

    my $u = LJ::isu($opts{user}) ? $opts{user} : LJ::load_user($opts{user});
    return "" unless $u;

    my $remote = LJ::get_remote();
    return "" if $u->id == $remote->id;

    my $max_comms = $opts{max_comms} || 3;
    my @notable_comms = $u->notable_communities($max_comms);
    return "" unless @notable_comms;

    $ret .= "<h2>" . $class->ml('.widget.commsofuser.title', {user => $u->ljuser_display}) . "</h2>";
    $ret .= "<ul class='nostyle'>";
    foreach my $comm (@notable_comms) {
        $ret .= "<li>" . $comm->ljuser_display . " - " . $comm->name_html  . "</li>";
    }
    $ret .= "</ul>";
    $ret .= "<p class='detail' style='text-align: right;'>";
    $ret .= "<a href='" . $u->profile_url . "' class='more-link'>" . $class->ml('.widget.commsofuser.viewprofile', {user => $u->display_username}) . "</a>";
    $ret .= "<a href='" . $u->journal_base . "/friends/' class='more-link' style='top: 22px;'>" . $class->ml('.widget.commsofuser.viewfriendspage', {user => $u->display_username}) . "</a>";
    $ret .= "</p>";

    return $ret;
}

1;
