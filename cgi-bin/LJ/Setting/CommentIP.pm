package LJ::Setting::CommentIP;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "iplogging";
}

sub label {
    my $class = shift;

    return $class->ml('setting.commentip.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $commentip = $class->get_arg($args, "commentip") || $u->prop("opt_logcommentips");

    my @options = (
        N => $class->ml('setting.commentip.option.select.none'),
        S => $class->ml('setting.commentip.option.select.anon'),
        A => $class->ml('setting.commentip.option.select.all'),
    );

    my $ret = "<label for='${key}commentip'>" . $class->ml('setting.commentip.option') . "</label> ";
    $ret .= LJ::html_select({
        name => "${key}commentip",
        id => "${key}commentip",
        selected => $commentip,
    }, @options);

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "commentip");
    $val = "N" unless $val =~ /^[NSA]$/;

    $u->set_prop( opt_logcommentips => $val );

    return 1;
}

1;
