package LJ::Widget::CreateAccountProgressMeter;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);

sub need_res { qw( stc/widgets/createaccountprogressmeter.css ) }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $u = LJ::get_effective_remote();

    my $given_step = $opts{step} || 1;
    my @steps_to_show = !LJ::is_enabled( 'payments' )
                    || ( $LJ::USE_ACCT_CODES && $given_step == 1 && DW::InviteCodes->paid_status( code => $opts{code} ) )
                    || ( $given_step > 1 && $u && $u->is_paid )
                    ? ( 1, 2, 4 ) : ( 1..4 );

    my $ret;

    $ret .= "<table cellspacing='0' cellpadding='0'><tr>";

    my $count = 1;
    foreach my $step (@steps_to_show) {
        my $css_class = $step == $given_step ? " step-selected" : "";
        $css_class .= $step < $given_step ? " step-previous" : "";
        $css_class .= $step > $given_step ? " step-next" : "";

        my $active = $step == $given_step ? "active" : "inactive";

        $ret .= "<td class='step$css_class'>";
        $ret .= "<div class='step-block-$active'>$count</div>";
        $ret .= "<div class='step-block-text'>" . $class->ml( "widget.createaccountprogressmeter.step$step" ) . "</div>";
        $ret .= "</td>";

        $count++;
    }

    $ret .= "</tr></table>";

    return $ret;
}

1;
