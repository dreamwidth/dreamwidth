package LJ::Setting::StyleAlwaysMine;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return LJ::is_enabled("stylealwaysmine") && $u && $u->is_personal ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.stylealwaysmine.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $stylealwaysmine = $class->get_arg($args, "stylealwaysmine") || $u->opt_stylealwaysmine;
    my $can_use_stylealwaysmine = $u->can_use_stylealwaysmine ? 1 : 0;
    my $upgrade_link = $can_use_stylealwaysmine ? "" : (LJ::run_hook("upgrade_link", $u, "paid") || "");

    my $ret = LJ::html_check({
        name => "${key}stylealwaysmine",
        id => "${key}stylealwaysmine",
        value => 1,
        selected => $stylealwaysmine && $can_use_stylealwaysmine ? 1 : 0,
        disabled => $can_use_stylealwaysmine ? 0 : 1,
    });
    $ret .= " <label for='${key}stylealwaysmine'>" . $class->ml('setting.stylealwaysmine.option') . " $upgrade_link</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "stylealwaysmine") ? "Y" : "N";
    $u->set_prop( opt_stylealwaysmine => $val );

    return 1;
}

1;
