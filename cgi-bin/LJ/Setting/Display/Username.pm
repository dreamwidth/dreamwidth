package LJ::Setting::Display::Username;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return !$u->is_identity ? "renaming" : "";
}

sub actionlink {
    my ($class, $u) = @_;

    return !$u->is_identity ? "<a href='$LJ::SITEROOT/rename/'>" . $class->ml('setting.display.username.actionlink') . "</a>" : "";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.username.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    if ($u->is_identity) {
        return $u->display_username . " " . $class->ml('setting.display.username.option.openidusername', { user => $u->user });
    } else {
        return $u->user . " <a href='$LJ::SITEROOT/misc/expunged_list.bml' class='smaller'>" . $class->ml('setting.display.username.option.list') . "</a>";
    }
}

1;
