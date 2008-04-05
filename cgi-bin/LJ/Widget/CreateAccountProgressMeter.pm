package LJ::Widget::CreateAccountProgressMeter;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/createaccountprogressmeter.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $given_step = $opts{step} || 1;
    my @steps_to_show = LJ::ab_testing_value() == 0 ? (1, 2, 4) : (1..4);

    my $ret;

    $ret .= "<table cellspacing='0' cellpadding='0'><tr>";

    my $count = 1;
    foreach my $step (@steps_to_show) {
        my $css_class = $step == $given_step ? " step-selected" : "";
        $css_class .= $step < $given_step ? " step-previous" : "";
        $css_class .= $step > $given_step ? " step-next" : "";

        my $active = $step == $given_step ? "active" : "inactive";

        $ret .= "<td class='step$css_class'>";
        $ret .= "<img src='$LJ::IMGPREFIX/create/numbers-$active/$count.gif' alt='$count' align='absmiddle' /> ";
        $ret .= $class->ml("widget.createaccountprogressmeter.step$step");
        $ret .= "</td>";

        $count++;
    }

    $ret .= "</tr></table>";

    return $ret;
}

1;
