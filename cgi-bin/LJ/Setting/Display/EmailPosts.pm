package LJ::Setting::Display::EmailPosts;
use base 'LJ::Setting';
use strict;
use warnings;

sub should_render {
    my ($class, $u) = @_;

    return $u && !$u->is_community ? 1 : 0;
}

sub label {
    my $class = shift;

    return $class->ml('setting.display.emailposts.label');
}

sub option {
    my ($class, $u, $errs, $args) = @_;

    return "<a href='$LJ::SITEROOT/tools/recent_emailposts'>" . $class->ml('setting.display.emailposts.option') . "</a>";
}

1;
