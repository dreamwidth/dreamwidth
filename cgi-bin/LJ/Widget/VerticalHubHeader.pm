package LJ::Widget::VerticalHubHeader;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::Vertical );

sub need_res { qw( stc/widgets/verticalhubheader.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $vertical = $opts{vertical};
    die "Invalid vertical object passed to widget." unless $vertical;

    my $remote = LJ::get_remote();

    my $ret;

    # multiple parents can be defined, but just use the first one for the nav
    my @parents = $vertical->parents;
    my $parent = $parents[0];

    my $ad = LJ::ads( type => 'app', orient => "BML-App-Vertical-Leaderboard", vertical => $vertical->ad_name, page => $opts{page}, force => 1 );
    my $show_leaderboard = $ad && LJ::run_hook("should_show_vertical_leaderboard", $remote) ? 1 : 0;

    if ($show_leaderboard) {
        $ret .= "<table class='title-box'><tr><td class='header-cell'>";
    }
    $ret .= "<h1>";
    if ($parent) {
        $ret .= "<a href='" . $parent->url . "'><strong>" . $parent->display_name . "</strong></a> &gt; ";
    }
    $ret .= $vertical->display_name . " <img src='$LJ::IMGPREFIX/beta.gif' align='absmiddle' alt='Beta' /></h1>";
    if ($show_leaderboard) {
        $ret .= "</td><td class='ad-cell'>";
        $ret .= $ad;
        $ret .= "</td></tr></table>";
    }

    my (@children, @siblings);
    foreach my $child ($vertical->children) {
        next if $child->is_hidden;

        push @children, "<a href='" . $child->url . "'>" . $child->display_name . "</a>";
    }
    foreach my $sibling ($vertical->siblings( include_self => 1 )) {
        next if $sibling->is_hidden;

        my $el;
        if ($sibling->equals($vertical)) {
            $el .= "<strong>";
        } else {
            $el .= "<a href='" . $sibling->url . "'>";
        }
        $el .= $sibling->display_name;
        if ($sibling->equals($vertical)) {
            $el .= "</strong>";
        } else {
            $el .= "</a>";
        }

        push @siblings, $el;
    }
    $ret .= "<p class='children'>" . join(" | ", @children) . "</p>" if @children;
    $ret .= "<p class='siblings'>" . join(" | ", @siblings) . "</p>" if @siblings;

    return $ret;
}

1;
