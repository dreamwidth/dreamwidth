package LJ::Setting::GettingStarted;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return !$u || $u->is_community || LJ::Widget::GettingStarted->tasks_completed($u) ? 0 : 1;
}

sub label {
    my ($class, $u) = @_;

    return $class->ml('setting.gettingstarted.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $gettingstarted = $u->has_enabled_getting_started;

    my $ret = LJ::html_check({
        name => "${key}gettingstarted",
        id => "${key}gettingstarted",
        value => 1,
        selected => $gettingstarted ? 1 : 0,
    });
    $ret .= " <label for='${key}gettingstarted'>" . $class->ml('setting.gettingstarted.option') . "</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "gettingstarted") ? "Y" : "N";
    $u->set_prop( opt_getting_started => $val );

    return 1;
}

1;
