package LJ::Setting::NotifyWeblogs;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return LJ::is_enabled("weblogs_com") && $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "weblogs";
}

sub label {
    my ($class, $u) = @_;

    return $class->ml('setting.notifyweblogs.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $notifyweblogs = $class->get_arg($args, "notifyweblogs") || $u->prop("opt_weblogscom");
    my $can_use_notifyweblogs = $u->get_cap("weblogscom") ? 1 : 0;
    my $upgrade_link = $can_use_notifyweblogs ? "" : (LJ::run_hook("upgrade_link", $u, "paid") || "");

    my $ret = LJ::html_check({
        name => "${key}notifyweblogs",
        id => "${key}notifyweblogs",
        value => 1,
        selected => $notifyweblogs && $can_use_notifyweblogs ? 1 : 0,
        disabled => $can_use_notifyweblogs ? 0 : 1,
    });
    $ret .= " <label for='${key}notifyweblogs'>";
    $ret .= $u->is_community ? $class->ml('setting.notifyweblogs.option.comm') : $class->ml('setting.notifyweblogs.option.self');
    $ret .= " $upgrade_link</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "notifyweblogs") ? 1 : 0;
    $u->set_prop( opt_weblogscom => $val );

    return 1;
}

1;
