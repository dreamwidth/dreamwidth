package LJ::Widget::CreateAccountNextSteps;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/createaccountnextsteps.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $ret;
    $ret .= "<h2>" . $class->ml('widget.createaccountnextsteps.title') . "</h2>";
    $ret .= "<p class='intro'>" . $class->ml('widget.createaccountnextsteps.steps', { sitename => $LJ::SITENAMESHORT }) . "</p>";

    $ret .= "<table cellspacing='0' cellpadding='0'>";
    $ret .= "<tr valign='top'><td><ul>";
    $ret .= "<li><a href='$LJ::SITEROOT/update'>" . $class->ml('widget.createaccountnextsteps.steps.post') . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/editpics'>" . $class->ml('widget.createaccountnextsteps.steps.userpics') . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/interests'>" . $class->ml('widget.createaccountnextsteps.steps.find') . "</a></li>";
    $ret .= "</ul></td><td><ul>";
    $ret .= "<li><a href='$LJ::SITEROOT/customize/'>" . $class->ml('widget.createaccountnextsteps.steps.customize') . "</a></li>";
    $ret .= "<li><a href='$LJ::SITEROOT/manage/profile/'>" . $class->ml('widget.createaccountnextsteps.steps.profile') . "</a></li>";
    $ret .= "</ul></td></tr>";
    $ret .= "</table>";

    return $ret;
}

1;
