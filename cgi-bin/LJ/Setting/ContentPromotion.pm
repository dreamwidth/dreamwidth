package LJ::Setting::ContentPromotion;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && LJ::is_enabled("verticals", $u) && $u->is_personal ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "explorelj_full";
}

sub label {
    my ($class, $u) = @_;

    return $class->ml('setting.contentpromotion.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $contentpromotion = $class->get_arg($args, "contentpromotion") || $u->opt_exclude_from_verticals eq "none";

    my $ret = LJ::html_check({
        name => "${key}contentpromotion",
        id => "${key}contentpromotion",
        value => 1,
        selected => $contentpromotion ? 1 : 0,
    });
    $ret .= " <label for='${key}contentpromotion'>" . $class->ml('setting.contentpromotion.option', { sitenameabbrev => $LJ::SITENAMEABBREV }) . "</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    # flip the bit since we're asking the user about inclusion, but setting exclusion
    my $val = $class->get_arg($args, "contentpromotion") ? 0 : 1;
    $u->set_opt_exclude_from_verticals($val);

    return 1;
}

1;
