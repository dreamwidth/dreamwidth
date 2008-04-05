package LJ::Widget::CreateAccountNextSteps;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/createaccountnextsteps.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret;
    $ret .= "<div class='rounded-box'><div class='rounded-box-tr'><div class='rounded-box-bl'><div class='rounded-box-br'>";
    $ret .= "<div class='rounded-box'><div class='rounded-box-tr'><div class='rounded-box-bl'><div class='rounded-box-br'>";

    $ret .= "<div class='rounded-box-content'>";
    $ret .= "<h2>" . $class->ml('widget.createaccountnextsteps.title') . "</h2>";
    $ret .= "<p class='intro'>" . $class->ml('widget.createaccountnextsteps.steps', { sitename => $LJ::SITENAMESHORT }) . "</p>";

    $ret .= "<table cellspacing='0' cellpadding='0'>";
    $ret .= "<tr valign='top'><td><ul>";
    $ret .= "<li><a href='$LJ::SITEROOT/update.bml'>" . $class->ml('widget.createaccountnextsteps.steps.post') . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/editpics.bml'>" . $class->ml('widget.createaccountnextsteps.steps.userpics') . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/interests.bml'>" . $class->ml('widget.createaccountnextsteps.steps.find') . "</a></li>";
    $ret .= "</ul></td><td><ul>";
    $ret .= "<li><a href='$LJ::SITEROOT/explore/'>" . $class->ml('widget.createaccountnextsteps.steps.explore', { sitenameabbrev => $LJ::SITENAMEABBREV }) . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/customize/'>" . $class->ml('widget.createaccountnextsteps.steps.customize') . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/manage/profile/'>" . $class->ml('widget.createaccountnextsteps.steps.profile') . "</a></li>";
    $ret .= "</ul></td></tr>";
    $ret .= "</table>";
    $ret .= "</div>";

    $ret .= "</div></div></div></div>";
    $ret .= "</div></div></div></div>";

    return $ret;
}

1;
