package LJ::Widget::RecentlyExpunged;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

use Class::Autouse qw(LJ::ExpungedUsers);

sub need_res {
    return qw( stc/widgets/recentlyexpunged.css );
}

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $within = delete $opts{within} || 3600;
    my $limit  = delete $opts{limit}  || 20;

    # [ u, expunge_time ]
    my @rows = LJ::ExpungedUsers->load_recent
        ( within => $within, limit  => $limit );

    # if no rows, just don't render
    return "" unless @rows;

    my $ret = "<div id='appwidget-recentlyexpunged-list-wrapper'>";
    $ret .= "<h3>In the last 24 hours...</h3>";
    if (@rows) {
        my $ct = 0;
        $ret .= "<ul id='appwidget-recentlyexpunged-list'>";
        foreach my $row (sort { $b->[1] <=> $a->[1] } @rows) {
            my ($u, $exp_time) = @$row;
        
            $ret .= "<li>" . $u->display_username . "</li>";
            $ct++;

            last if $ct >= 30;
        }
        $ret .= "</ul>";
    } else {
        $ret .= "<b>Sorry, there are no recently expunged users</b>";
    }
    $ret .= "</div>\n";

    return $ret;
}

1;
