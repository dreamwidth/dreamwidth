package LJ::Setting::CommentCaptcha;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.commentcaptcha.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $commentcaptcha = $class->get_arg($args, "commentcaptcha") || $u->prop("opt_show_captcha_to");

    my @options = (
        N => $class->ml('setting.commentcaptcha.option.select.none'),
        R => $class->ml('setting.commentcaptcha.option.select.anon'),
        F => $u->is_community ? $class->ml('setting.commentcaptcha.option.select.nonmembers') : $class->ml('setting.commentcaptcha.option.select.nonfriends'),
        A => $class->ml('setting.commentcaptcha.option.select.all'),
    );

    my $ret = "<label for='${key}commentcaptcha'>" . $class->ml('setting.commentcaptcha.option') . "</label> ";
    $ret .= LJ::html_select({
        name => "${key}commentcaptcha",
        id => "${key}commentcaptcha",
        selected => $commentcaptcha,
    }, @options);

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "commentcaptcha");
    $val = "N" unless $val =~ /^[NRFA]$/;

    $u->set_prop( opt_show_captcha_to => $val );

    return 1;
}

1;
