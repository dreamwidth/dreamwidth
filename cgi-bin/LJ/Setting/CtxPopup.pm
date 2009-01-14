package LJ::Setting::CtxPopup;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return !$LJ::CTX_POPUP || !$u || $u->is_community ? 0 : 1;
}

sub label {
    my ($class, $u) = @_;

    return $class->ml('setting.ctxpopup.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $ctxpopup = $class->get_arg($args, "ctxpopup") || $u->prop('opt_ctxpopup');

    my $ret = LJ::html_check({
        name => "${key}ctxpopup",
        id => "${key}ctxpopup",
        value => 1,
        selected => $ctxpopup ? 1 : 0,
    });
    $ret .= " <label for='${key}ctxpopup'>" . $class->ml('setting.ctxpopup.option') . "</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "ctxpopup") ? "Y" : "N";
    $u->set_prop( opt_ctxpopup => $val );

    return 1;
}

1;
