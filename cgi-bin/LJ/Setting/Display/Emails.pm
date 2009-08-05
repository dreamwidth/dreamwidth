package LJ::Setting::Display::Emails;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && $u->is_personal ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.emails.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    return "<a href='$LJ::SITEROOT/tools/emailmanage'>" . $class->ml('setting.display.emails.option') . "</a>";
}

1;
