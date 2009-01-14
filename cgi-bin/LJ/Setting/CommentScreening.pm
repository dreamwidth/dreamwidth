package LJ::Setting::CommentScreening;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_identity ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "screening";
}

sub label {
    my $class = shift;

    return $class->ml('setting.commentscreening.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $commentscreening = $class->get_arg($args, "commentscreening") || $u->prop("opt_whoscreened");

    my @options = (
        N => $class->ml('setting.commentscreening.option.select.none'),
        R => $class->ml('setting.commentscreening.option.select.anon'),
        F => $u->is_community ? $class->ml('setting.commentscreening.option.select.nonmembers') : $class->ml('setting.commentscreening.option.select.nonfriends'),
        A => $class->ml('setting.commentscreening.option.select.all'),
    );

    my $select = LJ::html_select({
        name => "${key}commentscreening",
        id => "${key}commentscreening",
        selected => $commentscreening,
    }, @options);

    return "<label for='${key}commentscreening'>" . $class->ml('setting.commentscreening.option', { options => $select }) . "</label>";
}

sub save {
    my ($class, $u, $args) = @_;

    my $val = $class->get_arg($args, "commentscreening");
    $val = "N" unless $val =~ /^[NRFA]$/;

    $u->set_prop( opt_whoscreened => $val );

    return 1;
}

1;
