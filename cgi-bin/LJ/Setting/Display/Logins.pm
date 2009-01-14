package LJ::Setting::Display::Logins;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_community ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.logins.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    return "<a href='$LJ::SITEROOT/manage/logins.bml'>" . $class->ml('setting.display.logins.option') . "</a>";
}

1;
