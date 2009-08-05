package LJ::Setting::Display::Password;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "secure_password";
}

sub actionlink {
    my ($class, $u) = @_;

    return "<a href='$LJ::SITEROOT/changepassword'>" . $class->ml('setting.display.password.actionlink') . "</a>";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.password.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    return "******";
}

1;
