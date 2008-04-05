package LJ::Widget::SubmitRequest::Support;

use strict;
use base qw(LJ::Widget::SubmitRequest LJ::Widget);
use Carp qw(croak);

sub text_done {
    my ($class, %opts) = @_;

    my $ret;

    $ret .= "<div class='right-sidebar'>";
    $ret .= "<?h2 " . $class->ml('/support/submit.bml.help.header') . " h2?>";
    $ret .= "<?p " . $class->ml('/support/submit.bml.help.text', { aopts => "href='$LJ::SITEROOT/support/help.bml'" }) . " p?>";
    $ret .= "</div>";

    $ret .= $class->SUPER::text_done(%opts);

    return $ret;
}

1;
