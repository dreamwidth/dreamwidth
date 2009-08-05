package LJ::Setting::Display::BanUsers;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u ? 1 : 0;
}

sub helpurl {
    my ($class, $u) = @_;

    return "banusers";
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.banusers.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    my $remote = LJ::get_remote();
    my $getextra = $remote && $remote->user ne $u->user ? "?authas=" . $u->user : "";

    my $ret = "<a href='$LJ::SITEROOT/manage/banusers$getextra'>";
    $ret .= $u->is_community ? $class->ml('setting.display.banusers.option.comm') : $class->ml('setting.display.banusers.option.self');
    $ret .= "</a>";

    return $ret;
}

1;
