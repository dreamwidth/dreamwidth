package LJ::Widget::BetaFeature;

use strict;
use base qw(LJ::Widget);
use Carp qw(croak);
use Class::Autouse qw( LJ::BetaFeatures );

sub need_res { }

sub render_body {
    my $class = shift;
    my %opts = @_;

    my $feature = $opts{feature};
    return "" unless $feature;

    my $u = $opts{u};
    return "" unless LJ::isu($u);

    my $handler = LJ::BetaFeatures->get_handler($feature);
    my $ret;

    $ret .= "<h2>" . $class->ml("widget.betafeature.$feature.title") . "</h2>"
        if $handler->is_active;

    if ($handler->is_active && $handler->user_can_add($u)) {
        $ret .= $class->start_form;
        if ($u->is_in_beta($feature)) {
            $ret .= "<?p " . $class->ml("widget.betafeature.$feature.on") . " p?>";
            $ret .= $class->html_submit("off", $class->ml('widget.betafeature.btn.off'));
        } else {
            $ret .= "<?p " . $class->ml("widget.betafeature.$feature.off") . " p?>";
            $ret .= $class->html_submit("on", $class->ml('widget.betafeature.btn.on'));
        }
        $ret .= $class->html_hidden( feature => $feature, user => $u->user );
        $ret .= $class->end_form;
    } elsif (!$handler->user_can_add($u)) {
        $ret .= "<?p " . $class->ml("widget.betafeature.$feature.cantadd") . " p?>";
    }

    return $ret;
}

sub handle_post {
    my $class = shift;
    my $post = shift;
    my %opts = @_;

    my $feature = $post->{feature};
    die "No feature defined." unless $feature;

    my $u = LJ::load_user($post->{user});
    die "Invalid user." unless $u;

    if ($post->{on}) {
        LJ::BetaFeatures->add_to_beta( $u => $feature );
    } else {
        LJ::BetaFeatures->remove_from_beta( $u => $feature );
    }

    return;
}

1;
