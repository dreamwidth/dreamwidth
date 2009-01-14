package LJ::Setting::GraphicPreviews;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    my $graphicpreviews_obj = LJ::graphicpreviews_obj();
    return $u && $graphicpreviews_obj->is_enabled($u) ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "graphic_previews";
}

sub label {
    my $class = shift;

    return $class->ml('setting.graphicpreviews.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;
    my $key = $class->pkgkey;

    my $graphicpreviews_obj = LJ::graphicpreviews_obj();

    my $ret = LJ::html_check({
        name => "${key}graphicpreviews",
        id => "${key}graphicpreviews",
        value => 1,
        selected => $class->get_arg($args, "graphicpreviews") || $graphicpreviews_obj->should_render($u) ? 1 : 0,
    });
    $ret .= " <label for='${key}graphicpreviews'>";
    $ret .= $u->is_community ? $class->ml('setting.graphicpreviews.option.comm') : $class->ml('setting.graphicpreviews.option.self');
    $ret .= "</label>";

    return $ret;
}

sub save {
    my ($class, $u, $args) = @_;

    my $post_val = $class->get_arg($args, "graphicpreviews") ? "on" : "off";
    my $prop_val = $u->show_graphic_previews;
    if ($post_val ne $prop_val) {
        my $new_val = "explicit_$post_val";
        $u->set_prop('show_graphic_previews', $new_val);
    }

    return 1;
}

1;
